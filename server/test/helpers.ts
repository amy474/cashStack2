import { createHash, randomUUID } from 'node:crypto';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWK } from 'jose';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.ts';
import { appleVerifier } from '../src/auth/apple.ts';
import { FakeBasiq } from '../src/basiq/fake.ts';
import { loadConfig, type Config } from '../src/config.ts';
import { migrate, openDatabase, type Db } from '../src/db.ts';

export const BUNDLE_ID = 'com.bokscot.cashstack';
export const WEBHOOK_SECRET = `whsec_${Buffer.from('test-webhook-secret-32-bytes-long!').toString('base64')}`;

/// A stand-in for Apple's signing key, so tests can mint identity tokens the
/// real verifier accepts — and ones it must not.
export async function fakeApple() {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk: JWK = { ...(await exportJWK(publicKey)), kid: 'test-key', alg: 'RS256', use: 'sig' };
  const keys = createLocalJWKSet({ keys: [jwk] });

  async function token(opts: { sub?: string; nonce?: string; rawNonce?: string; aud?: string; iss?: string; email?: string; expiresIn?: string; key?: CryptoKey } = {}) {
    const rawNonce = opts.rawNonce ?? randomUUID();
    const nonce = opts.nonce ?? createHash('sha256').update(rawNonce).digest('hex');
    const identityToken = await new SignJWT({ nonce, email: opts.email ?? 'someone@privaterelay.appleid.com', email_verified: 'true', is_private_email: 'true' })
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
      .setIssuer(opts.iss ?? 'https://appleid.apple.com')
      .setAudience(opts.aud ?? BUNDLE_ID)
      .setSubject(opts.sub ?? 'apple-user-1')
      .setIssuedAt()
      .setExpirationTime(opts.expiresIn ?? '5m')
      .sign(opts.key ?? privateKey);
    return { identityToken, rawNonce };
  }

  return { keys, token };
}

export type TestApp = {
  app: FastifyInstance;
  db: Db;
  basiq: FakeBasiq;
  config: Config;
  apple: Awaited<ReturnType<typeof fakeApple>>;
  clock: { now: Date; advance(ms: number): void };
  /// Every alert the server sent, in order.
  alerts: string[];
  signIn(sub?: string): Promise<{ accessToken: string; refreshToken: string; userId: string }>;
  connectBank(accessToken: string, opts?: { fail?: boolean }): Promise<{ sessionId: string; redirect: string }>;
  close(): Promise<void>;
};

export async function testApp(env: Record<string, string> = {}): Promise<TestApp> {
  const config = loadConfig({
    NODE_ENV: 'test',
    PUBLIC_URL: 'http://127.0.0.1:8080',
    BASIQ_MODE: 'fake',
    BASIQ_WEBHOOK_SECRET: WEBHOOK_SECRET,
    LOG_LEVEL: 'silent',
    ...env,
  });
  const db = await openDatabase({ memory: true });
  await migrate(db);
  const basiq = new FakeBasiq(`${config.publicUrl}/dev/fake-consent`);
  const apple = await fakeApple();
  const clock = {
    now: new Date('2026-10-19T09:00:00Z'),
    advance(ms: number) {
      this.now = new Date(this.now.getTime() + ms);
    },
  };
  const alerts: string[] = [];
  const app = await buildApp(
    { config, db, basiq, verifyApple: appleVerifier(BUNDLE_ID, apple.keys), now: () => clock.now, pollIntervalMs: 0, alertSink: (text) => { alerts.push(text); } },
    { logger: false },
  );

  async function signIn(sub = 'apple-user-1') {
    const { identityToken, rawNonce } = await apple.token({ sub });
    const res = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken, rawNonce } });
    if (res.statusCode !== 200) throw new Error(`sign in failed: ${res.statusCode} ${res.body}`);
    const body = res.json();
    return { accessToken: body.accessToken, refreshToken: body.refreshToken, userId: body.user.id };
  }

  /// The whole trip: start a consent session, "approve" on the fake consent
  /// screen, and follow Basiq's redirect back to the server.
  async function connectBank(accessToken: string, opts: { fail?: boolean } = {}) {
    const start = await app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: { action: 'connect' } });
    if (start.statusCode !== 200) throw new Error(`consent start failed: ${start.statusCode} ${start.body}`);
    const consentUrl = new URL(start.json().url);
    const approve = await app.inject({
      method: 'GET',
      url: `/dev/fake-consent/approve?token=${consentUrl.searchParams.get('token')}&state=${consentUrl.searchParams.get('state')}${opts.fail ? '&fail=1' : ''}`,
    });
    const back = new URL(approve.headers.location as string);
    const ret = await app.inject({ method: 'GET', url: back.pathname + back.search });
    return { sessionId: start.json().id, redirect: ret.headers.location as string };
  }

  return { app, db, basiq, config, apple, clock, alerts, signIn, connectBank, close: async () => { await app.close(); await db.close(); } };
}

export const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
