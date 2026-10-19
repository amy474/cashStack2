import { loadConfig } from './config.ts';
import { openDatabase } from './db.ts';

/// What's been crashing. `npm run diagnostics` (or, on Fly,
/// `fly ssh console -C "node src/diagnostics-report.ts"`) lists the last
/// week's reports grouped by build and kind; `-- 30` widens it to 30 days.
/// `-- --id 42` prints one report in full, call stack and all, ready to
/// symbolicate against that build's dSYM.

const args = process.argv.slice(2);
const config = loadConfig();
const db = await openDatabase({ url: config.databaseUrl, pgliteDir: config.pgliteDir });

try {
  const idAt = args.indexOf('--id');
  if (idAt >= 0) {
    const { rows } = await db.query<{ detail: unknown }>('select detail from diagnostics where id = $1', [Number(args[idAt + 1])]);
    console.log(rows[0] ? JSON.stringify(rows[0].detail, null, 2) : 'No report with that id.');
  } else {
    const days = Number(args[0] ?? 7);
    const { rows } = await db.query<{ app_version: string | null; app_build: string | null; kind: string; summary: string; count: string; last_seen: Date; latest_id: string }>(
      `select app_version, app_build, kind, summary, count(*) as count, max(received_at) as last_seen, max(id) as latest_id
         from diagnostics
        where received_at > now() - make_interval(days => $1)
        group by app_version, app_build, kind, summary
        order by max(received_at) desc`,
      [days],
    );
    if (!rows.length) console.log(`No crash or hang reports in the last ${days} days.`);
    for (const r of rows) {
      console.log(`${String(r.count).padStart(5)}  ${`${r.app_version ?? '?'} (${r.app_build ?? '?'})`.padEnd(12)} ${r.kind.padEnd(10)} ${r.summary.padEnd(32)} last ${r.last_seen.toISOString().slice(0, 16)}  --id ${r.latest_id}`);
    }
  }
} finally {
  await db.close();
}
