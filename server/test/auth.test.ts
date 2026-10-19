import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair } from 'jose';
import { bearer, testApp, type TestApp } from './helpers.ts';

describe('signing in', () => {
  let t: TestApp;
  before(async () => { t = await testApp(); });
  after(async () => { await t.close(); });

  test('Sign in with Apple creates a user once and signs them in after that', async () => {
    const first = await t.apple.token({ sub: 'apple-a' });
    const a = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload: first });
    assert.equal(a.statusCode, 200);
    assert.equal(a.json().user.isNew, true);
    assert.match(a.json().accessToken, /^csa_/);
    assert.match(a.json().refreshToken, /^csr_/);
    assert.equal(a.json().expiresIn, 900);

    const again = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload: await t.apple.token({ sub: 'apple-a' }) });
    assert.equal(again.json().user.id, a.json().user.id);
    assert.equal(again.json().user.isNew, false);
  });

  test('tokens are stored only as hashes', async () => {
    const { accessToken, refreshToken } = await t.signIn('apple-hash');
    const { rows } = await t.db.query<{ access_hash: string; refresh_hash: string }>('select access_hash, refresh_hash from sessions');
    for (const row of rows) {
      assert.notEqual(row.access_hash, accessToken);
      assert.notEqual(row.refresh_hash, refreshToken);
      assert.match(row.access_hash, /^[0-9a-f]{64}$/);
    }
  });

  test('an identity token and nonce work once; presented again they are refused', async () => {
    const payload = await t.apple.token({ sub: 'apple-replay' });
    const first = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload });
    assert.equal(first.statusCode, 200);
    const again = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload });
    assert.equal(again.statusCode, 401);
    assert.equal(again.json().error, 'apple_rejected');
    const sessions = await t.db.query("select s.id from sessions s join users u on u.id = s.user_id where u.apple_sub = 'apple-replay'");
    assert.equal(sessions.rows.length, 1, 'the replay got no session');
  });

  test('identity tokens that are not exactly right are refused', async () => {
    const { privateKey: stranger } = await generateKeyPair('RS256');
    const bad = [
      { ...(await t.apple.token()), rawNonce: 'a-different-nonce-entirely' },
      await t.apple.token({ aud: 'com.someone.else' }),
      await t.apple.token({ iss: 'https://evil.example.com' }),
      await t.apple.token({ expiresIn: '-1m' }),
      await t.apple.token({ key: stranger }),
    ];
    for (const payload of bad) {
      const res = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload });
      assert.equal(res.statusCode, 401, JSON.stringify(payload).slice(0, 60));
      assert.equal(res.json().error, 'apple_rejected');
    }
  });

  test('malformed bodies are a 400 that gives nothing away', async () => {
    const res = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: 'x' } });
    assert.equal(res.statusCode, 400);
    assert.deepEqual(Object.keys(res.json()).sort(), ['error', 'message']);
  });

  test('development sign-in does not exist unless switched on', async () => {
    const res = await t.app.inject({ method: 'POST', url: '/v1/auth/dev', payload: {} });
    assert.equal(res.statusCode, 404);
  });
});

describe('sessions', () => {
  let t: TestApp;
  before(async () => { t = await testApp(); });
  after(async () => { await t.close(); });

  test('every account route needs a valid access token', async () => {
    for (const [method, url] of [['GET', '/v1/me'], ['DELETE', '/v1/me'], ['GET', '/v1/accounts'], ['POST', '/v1/accounts/refresh'], ['GET', '/v1/connections'], ['POST', '/v1/consent/sessions'], ['POST', '/v1/auth/logout']] as const) {
      const none = await t.app.inject({ method, url });
      assert.equal(none.statusCode, 401, `${method} ${url}`);
      const forged = await t.app.inject({ method, url, headers: bearer('csa_not-a-real-token-at-all') });
      assert.equal(forged.statusCode, 401, `${method} ${url} forged`);
    }
  });

  test('access tokens expire after fifteen minutes', async () => {
    const { accessToken } = await t.signIn('apple-expiry');
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).statusCode, 200);
    t.clock.advance(15 * 60_000 + 1);
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).statusCode, 401);
  });

  test('refreshing swaps both tokens and kills the old pair', async () => {
    const { accessToken, refreshToken } = await t.signIn('apple-rotate');
    const res = await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } });
    assert.equal(res.statusCode, 200);
    const next = res.json();
    assert.notEqual(next.refreshToken, refreshToken);
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).statusCode, 401);
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(next.accessToken) })).statusCode, 200);
  });

  test('a refresh token used twice revokes the whole sign-in', async () => {
    const { refreshToken } = await t.signIn('apple-reuse');
    const legit = (await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } })).json();
    // Someone replays the old one…
    const replay = await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } });
    assert.equal(replay.statusCode, 401);
    // …so the legitimate descendant is dead too.
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(legit.accessToken) })).statusCode, 401);
    assert.equal((await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: legit.refreshToken } })).statusCode, 401);
    const audit = await t.db.query("select 1 from audit_log where event = 'auth.refresh_reuse'");
    assert.equal(audit.rows.length, 1);
  });

  test('refresh tokens expire after sixty days', async () => {
    const { refreshToken } = await t.signIn('apple-long');
    t.clock.advance(60 * 86_400_000 + 1);
    assert.equal((await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } })).statusCode, 401);
  });

  test('signing out ends the session everywhere it was refreshed to', async () => {
    const { accessToken, refreshToken } = await t.signIn('apple-out');
    const res = await t.app.inject({ method: 'POST', url: '/v1/auth/logout', headers: bearer(accessToken) });
    assert.equal(res.statusCode, 204);
    assert.equal((await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).statusCode, 401);
    assert.equal((await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } })).statusCode, 401);
  });
});

describe('development sign-in', () => {
  test('works when switched on, and production refuses to start with it', async () => {
    const t = await testApp({ DEV_LOGIN: '1' });
    const res = await t.app.inject({ method: 'POST', url: '/v1/auth/dev', payload: { name: 'amy' } });
    assert.equal(res.statusCode, 200);
    await t.close();

    const { loadConfig } = await import('../src/config.ts');
    assert.throws(() => loadConfig({
      NODE_ENV: 'production', DEV_LOGIN: '1', DATABASE_URL: 'postgres://x', BASIQ_API_KEY: 'k',
      PUBLIC_URL: 'https://api.example.com', BASIQ_WEBHOOK_SECRET: 'whsec_x', DATA_KEY: Buffer.alloc(32).toString('base64'),
    }), /DEV_LOGIN/);
    assert.throws(() => loadConfig({ NODE_ENV: 'production', BASIQ_MODE: 'fake' }), /BASIQ_MODE must be live/);
  });
});
