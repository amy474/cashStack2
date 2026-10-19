import { z } from 'zod';

/// Everything the server reads from the environment, checked once at boot.
/// Production refuses to start with a development-only switch turned on, so a
/// stray variable can't open a back door.

const bool = z
  .enum(['1', '0', 'true', 'false', ''])
  .optional()
  .transform((v) => v === '1' || v === 'true');

const Env = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('127.0.0.1'),
  PORT: z.coerce.number().int().positive().default(8080),
  /// Where the app and Basiq reach this server, e.g. https://cashstack-api.fly.dev
  PUBLIC_URL: z.url().default('http://127.0.0.1:8080'),
  /// Postgres. Without it, development runs on an embedded database on disk.
  DATABASE_URL: z.string().optional(),
  PGLITE_DIR: z.string().default('.data/pglite'),

  APP_BUNDLE_ID: z.string().default('com.bokscot.cashstack'),
  APP_CALLBACK_SCHEME: z.string().regex(/^[a-z][a-z0-9+.-]*$/).default('cashstack'),

  BASIQ_MODE: z.enum(['live', 'fake']).optional(),
  BASIQ_API_KEY: z.string().optional(),
  BASIQ_API_URL: z.url().default('https://au-api.basiq.io'),
  BASIQ_CONSENT_URL: z.url().default('https://consent.basiq.io/home'),
  /// The whsec_… signing secret Basiq gives you for the webhook endpoint.
  BASIQ_WEBHOOK_SECRET: z.string().optional(),

  /// 32 random bytes, base64. Encrypts the Apple refresh tokens kept for revocation.
  DATA_KEY: z.string().optional(),

  /// Optional: lets the server revoke Apple tokens when someone deletes their account.
  APPLE_TEAM_ID: z.string().optional(),
  APPLE_KEY_ID: z.string().optional(),
  APPLE_PRIVATE_KEY: z.string().optional(),

  /// Development only: sign in without Apple.
  DEV_LOGIN: bool,
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export type Config = {
  env: 'development' | 'test' | 'production';
  host: string;
  port: number;
  publicUrl: string;
  databaseUrl?: string;
  pgliteDir: string;
  bundleId: string;
  callbackScheme: string;
  basiq: {
    mode: 'live' | 'fake';
    apiKey?: string;
    apiUrl: string;
    consentUrl: string;
    webhookSecret?: string;
  };
  dataKey: Buffer;
  apple?: { teamId: string; keyId: string; privateKey: string };
  devLogin: boolean;
  logLevel: string;
};

export function loadConfig(source: Record<string, string | undefined> = process.env): Config {
  const parsed = Env.safeParse(source);
  if (!parsed.success) {
    throw new Error(`Bad configuration: ${z.prettifyError(parsed.error)}`);
  }
  const e = parsed.data;
  const production = e.NODE_ENV === 'production';
  const mode = e.BASIQ_MODE ?? (production ? 'live' : 'fake');
  const problems: string[] = [];

  if (production) {
    if (!e.DATABASE_URL) problems.push('DATABASE_URL is required in production');
    if (mode !== 'live') problems.push('BASIQ_MODE must be live in production');
    if (e.DEV_LOGIN) problems.push('DEV_LOGIN must not be set in production');
    if (!e.PUBLIC_URL.startsWith('https://')) problems.push('PUBLIC_URL must be https in production');
    if (!e.BASIQ_WEBHOOK_SECRET) problems.push('BASIQ_WEBHOOK_SECRET is required in production');
    if (!e.DATA_KEY) problems.push('DATA_KEY is required in production');
  }
  if (mode === 'live' && !e.BASIQ_API_KEY) problems.push('BASIQ_API_KEY is required when BASIQ_MODE=live');

  let dataKey: Buffer;
  if (e.DATA_KEY) {
    dataKey = Buffer.from(e.DATA_KEY, 'base64');
    if (dataKey.length !== 32) problems.push('DATA_KEY must be 32 bytes, base64-encoded');
  } else {
    // Development: a fixed, obviously-not-secret key so restarts can still read old rows.
    dataKey = Buffer.alloc(32, 7);
  }

  const appleParts = [e.APPLE_TEAM_ID, e.APPLE_KEY_ID, e.APPLE_PRIVATE_KEY];
  if (appleParts.some(Boolean) && !appleParts.every(Boolean)) {
    problems.push('APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY go together');
  }

  if (problems.length) throw new Error(`Bad configuration:\n  - ${problems.join('\n  - ')}`);

  return {
    env: e.NODE_ENV,
    host: e.HOST,
    port: e.PORT,
    publicUrl: e.PUBLIC_URL.replace(/\/$/, ''),
    databaseUrl: e.DATABASE_URL,
    pgliteDir: e.PGLITE_DIR,
    bundleId: e.APP_BUNDLE_ID,
    callbackScheme: e.APP_CALLBACK_SCHEME,
    basiq: {
      mode,
      apiKey: e.BASIQ_API_KEY,
      apiUrl: e.BASIQ_API_URL.replace(/\/$/, ''),
      consentUrl: e.BASIQ_CONSENT_URL,
      webhookSecret: e.BASIQ_WEBHOOK_SECRET,
    },
    dataKey,
    apple: e.APPLE_TEAM_ID && e.APPLE_KEY_ID && e.APPLE_PRIVATE_KEY
      ? { teamId: e.APPLE_TEAM_ID, keyId: e.APPLE_KEY_ID, privateKey: e.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n') }
      : undefined,
    devLogin: e.DEV_LOGIN,
    logLevel: e.LOG_LEVEL,
  };
}
