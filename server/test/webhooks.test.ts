import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { signWebhook } from '../src/basiq/webhooks.ts';
import { bearer, testApp, WEBHOOK_SECRET, type TestApp } from './helpers.ts';

describe('Basiq webhooks', () => {
  let t: TestApp;
  before(async () => { t = await testApp(); });
  after(async () => { await t.close(); });

  const send = (body: string, opts: { id?: string; timestamp?: number; secret?: string; signature?: string } = {}) => {
    const id = opts.id ?? `msg_${Math.random().toString(36).slice(2)}`;
    const timestamp = String(opts.timestamp ?? Math.floor(t.clock.now.getTime() / 1000));
    const signature = opts.signature ?? `v1,${signWebhook(opts.secret ?? WEBHOOK_SECRET, id, timestamp, body)}`;
    return t.app.inject({
      method: 'POST',
      url: '/v1/webhooks/basiq',
      headers: { 'content-type': 'application/json', 'webhook-id': id, 'webhook-timestamp': timestamp, 'webhook-signature': signature },
      payload: body,
    });
  };

  const event = (type: string, basiqUser: string) =>
    JSON.stringify({ eventTypeId: type, eventId: 'evt_1', links: { eventEntity: `https://au-api.basiq.io/users/${basiqUser}` } });

  test('a correctly signed event is accepted and audited', async () => {
    const res = await send(event('consent.warning', 'nobody'));
    assert.equal(res.statusCode, 204);
    const audit = await t.db.query("select 1 from audit_log where event = 'webhook.consent.warning'");
    assert.equal(audit.rows.length, 1);
  });

  test('a rotated secret still verifies when any listed signature matches', async () => {
    const body = event('connection.created', 'nobody');
    const id = 'msg_rotation';
    const ts = String(Math.floor(t.clock.now.getTime() / 1000));
    const good = signWebhook(WEBHOOK_SECRET, id, ts, body);
    const res = await send(body, { id, timestamp: Number(ts), signature: `v1,bm90LXRoaXMtb25l v1,${good}` });
    assert.equal(res.statusCode, 204);
  });

  test('wrong secret, tampered body, stale timestamp or missing headers are refused', async () => {
    const body = event('consent.revoked', 'nobody');
    assert.equal((await send(body, { secret: `whsec_${Buffer.from('the-wrong-one').toString('base64')}` })).statusCode, 401);
    const id = 'msg_tamper';
    const ts = Math.floor(t.clock.now.getTime() / 1000);
    const sig = `v1,${signWebhook(WEBHOOK_SECRET, id, String(ts), body)}`;
    assert.equal((await send(body.replace('revoked', 'created'), { id, timestamp: ts, signature: sig })).statusCode, 401);
    assert.equal((await send(body, { timestamp: ts - 6 * 60 })).statusCode, 401);
    const bare = await t.app.inject({ method: 'POST', url: '/v1/webhooks/basiq', headers: { 'content-type': 'application/json' }, payload: body });
    assert.equal(bare.statusCode, 401);
  });

  test('a redelivered event is acknowledged but handled once', async () => {
    const body = event('connection.deleted', 'nobody');
    assert.equal((await send(body, { id: 'msg_dupe' })).statusCode, 204);
    assert.equal((await send(body, { id: 'msg_dupe' })).statusCode, 204);
    const audit = await t.db.query("select 1 from audit_log where event = 'webhook.connection.deleted'");
    assert.equal(audit.rows.length, 1);
  });

  test("revoked consent drops the person's cached balances at once", async () => {
    const { accessToken, userId } = await t.signIn('apple-hook');
    await t.connectBank(accessToken);
    await t.app.inject({ method: 'GET', url: '/v1/accounts', headers: bearer(accessToken) });
    const basiqUser = (await t.db.query<{ basiq_user_id: string }>('select basiq_user_id from users where id = $1', [userId])).rows[0]!.basiq_user_id;

    // Basiq empties the user on its side, then tells us.
    t.basiq.users.get(basiqUser)!.accounts = [];
    assert.equal((await send(event('consent.revoked', basiqUser))).statusCode, 204);
    const res = (await t.app.inject({ method: 'GET', url: '/v1/accounts', headers: bearer(accessToken) })).json();
    assert.deepEqual(res.accounts, []);
    const audit = await t.db.query("select 1 from audit_log where user_id = $1 and event = 'webhook.consent.revoked'", [userId]);
    assert.equal(audit.rows.length, 1);
  });

  test('user.deleted forgets the Basiq user', async () => {
    const { accessToken, userId } = await t.signIn('apple-gone');
    await t.connectBank(accessToken);
    const basiqUser = (await t.db.query<{ basiq_user_id: string }>('select basiq_user_id from users where id = $1', [userId])).rows[0]!.basiq_user_id;
    await send(event('user.deleted', basiqUser));
    const row = await t.db.query<{ basiq_user_id: string | null }>('select basiq_user_id from users where id = $1', [userId]);
    assert.equal(row.rows[0]?.basiq_user_id, null);
  });

  test('without a configured secret, webhooks are switched off rather than trusted', async () => {
    const bare = await testApp({ BASIQ_WEBHOOK_SECRET: '' });
    const res = await bare.app.inject({ method: 'POST', url: '/v1/webhooks/basiq', headers: { 'content-type': 'application/json' }, payload: '{}' });
    assert.equal(res.statusCode, 503);
    await bare.close();
  });
});

describe('every response', () => {
  test('is uncacheable and locked down', async () => {
    const t = await testApp();
    for (const url of ['/healthz', '/data-sharing', '/nowhere']) {
      const res = await t.app.inject({ method: 'GET', url });
      assert.equal(res.headers['cache-control'], 'no-store', url);
      assert.equal(res.headers['x-content-type-options'], 'nosniff', url);
      assert.equal(res.headers['x-frame-options'], 'DENY', url);
      assert.match(String(res.headers['content-security-policy']), /default-src 'none'/, url);
    }
    await t.close();
  });
});
