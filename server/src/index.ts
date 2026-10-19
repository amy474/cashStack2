import { buildApp } from './app.ts';
import { AppleTokens, appleVerifier } from './auth/apple.ts';
import { FakeBasiq } from './basiq/fake.ts';
import { HttpBasiqClient } from './basiq/http.ts';
import type { BasiqClient } from './basiq/types.ts';
import { loadConfig } from './config.ts';
import { migrate, openDatabase } from './db.ts';

const config = loadConfig();
const db = await openDatabase({ url: config.databaseUrl, pgliteDir: config.pgliteDir });

// Production migrates in Fly's release step, before new machines start.
// Development has nobody else to do it.
if (config.env !== 'production') await migrate(db);

const basiq: BasiqClient = config.basiq.mode === 'live'
  ? new HttpBasiqClient({ apiKey: config.basiq.apiKey!, apiUrl: config.basiq.apiUrl, consentUrl: config.basiq.consentUrl })
  : new FakeBasiq(`${config.publicUrl}/dev/fake-consent`);

const app = await buildApp({
  config,
  db,
  basiq,
  verifyApple: appleVerifier(config.bundleId),
  appleTokens: config.apple ? new AppleTokens({ ...config.apple, bundleId: config.bundleId }) : undefined,
});

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  await app.close();
  await db.close();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

await app.listen({ host: config.host, port: config.port });
app.log.info({ basiq: config.basiq.mode, devLogin: config.devLogin, publicUrl: config.publicUrl }, 'cashstack api ready');
