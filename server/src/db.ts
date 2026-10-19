import { readdir, readFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import pg from 'pg';

/// The narrow slice of Postgres the server uses. Production talks to a real
/// Postgres through `pg`; development and the tests run the same SQL on an
/// embedded Postgres (PGlite), so there is one dialect and no mocks.
export interface Db {
  query<T = Record<string, unknown>>(text: string, params?: unknown[]): Promise<{ rows: T[] }>;
  /// Run several statements as one unit. Nested calls join the outer one.
  tx<T>(fn: (db: Db) => Promise<T>): Promise<T>;
  exec(sql: string): Promise<void>;
  close(): Promise<void>;
}

export async function openDatabase(opts: { url?: string; pgliteDir?: string; memory?: boolean }): Promise<Db> {
  if (opts.url) return postgres(opts.url);
  return embedded(opts.memory ? undefined : opts.pgliteDir);
}

function postgres(url: string): Db {
  const pool = new pg.Pool({ connectionString: url, max: 10, idleTimeoutMillis: 30_000 });

  const wrap = (client: pg.PoolClient): Db => ({
    query: async (text, params) => ({ rows: (await client.query(text, params)).rows }),
    tx: (fn) => fn(wrap(client)),
    exec: async (sql) => { await client.query(sql); },
    close: async () => {},
  });

  return {
    query: async (text, params) => ({ rows: (await pool.query(text, params)).rows }),
    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query('begin');
        const result = await fn(wrap(client));
        await client.query('commit');
        return result;
      } catch (error) {
        await client.query('rollback').catch(() => {});
        throw error;
      } finally {
        client.release();
      }
    },
    exec: async (sql) => { await pool.query(sql); },
    close: () => pool.end(),
  };
}

async function embedded(dir?: string): Promise<Db> {
  // Only development and the tests ever get here; production has DATABASE_URL.
  const { PGlite } = await import('@electric-sql/pglite');
  if (dir) await mkdir(dir, { recursive: true });
  const lite = new PGlite(dir);

  type Queryable = { query: (text: string, params?: unknown[]) => Promise<{ rows: unknown[] }>; exec: (sql: string) => Promise<unknown> };
  const wrap = (q: Queryable, inTx: boolean): Db => ({
    query: async <T>(text: string, params?: unknown[]) => ({ rows: (await q.query(text, params)).rows as T[] }),
    tx: (fn) => (inTx ? fn(wrap(q, true)) : lite.transaction((t) => fn(wrap(t as Queryable, true)))),
    exec: async (sql) => { await q.exec(sql); },
    close: () => lite.close(),
  });
  return wrap(lite as unknown as Queryable, false);
}

/// Apply every migration in ./migrations that hasn't been applied, in name order.
export async function migrate(db: Db, dir = join(import.meta.dirname, '..', 'migrations')): Promise<string[]> {
  await db.exec(`create table if not exists schema_migrations (
    version text primary key,
    applied_at timestamptz not null default now()
  )`);
  const done = new Set((await db.query<{ version: string }>('select version from schema_migrations')).rows.map((r) => r.version));
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  const applied: string[] = [];
  for (const file of files) {
    if (done.has(file)) continue;
    const sql = await readFile(join(dir, file), 'utf8');
    await db.tx(async (t) => {
      await t.exec(sql);
      await t.query('insert into schema_migrations (version) values ($1)', [file]);
    });
    applied.push(file);
  }
  return applied;
}
