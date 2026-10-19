import { loadConfig } from './config.ts';
import { migrate, openDatabase } from './db.ts';

/// `npm run migrate` — Fly runs this as the release command on every deploy.
const config = loadConfig();
const db = await openDatabase({ url: config.databaseUrl, pgliteDir: config.pgliteDir });
const applied = await migrate(db);
console.log(applied.length ? `Applied ${applied.join(', ')}` : 'Database is up to date');
await db.close();
