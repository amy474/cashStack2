import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { bearer, testApp, type TestApp } from './helpers.ts';

describe('connecting a bank', () => {
  let t: TestApp;
  before(async () => { t = await testApp(); });
  after(async () => { await t.close(); });

  test('a consent session points at Basiq with a client token, the action and a fresh state', async () => {
    const { accessToken } = await t.signIn('apple-consent');
    const res = await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: { action: 'connect' } });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.callbackScheme, 'cashstack');
    const url = new URL(body.url);
    assert.match(url.searchParams.get('token') ?? '', /^fake-client-/);
    assert.equal(url.searchParams.get('action'), 'connect');
    assert.match(url.searchParams.get('state') ?? '', /^cst_/);
    // Only the hash of the state is kept.
    const stored = await t.db.query<{ state_hash: string }>('select state_hash from consent_sessions where id = $1', [body.id]);
    assert.notEqual(stored.rows[0]?.state_hash, url.searchParams.get('state'));
  });

  test('the Basiq user is made once, however many times they start', async () => {
    const { accessToken } = await t.signIn('apple-once');
    const before = t.basiq.calls.filter((c) => c === 'createUser').length;
    await Promise.all([1, 2, 3].map(() => t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: {} })));
    assert.equal(t.basiq.calls.filter((c) => c === 'createUser').length - before, 1);
  });

  test('the redirect back hands the app a session id and nothing else, once', async () => {
    const { accessToken } = await t.signIn('apple-return');
    const start = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: {} })).json();
    const state = new URL(start.url).searchParams.get('state');
    const first = await t.app.inject({ method: 'GET', url: `/v1/consent/return?state=${state}&jobIds=abc,def` });
    assert.equal(first.statusCode, 302);
    assert.equal(first.headers.location, `cashstack://consent/complete?session=${start.id}`);
    const replay = await t.app.inject({ method: 'GET', url: `/v1/consent/return?state=${state}` });
    assert.equal(replay.headers.location, 'cashstack://consent/complete?error=expired');
    const junk = await t.app.inject({ method: 'GET', url: '/v1/consent/return?state=cst_made-up-value' });
    assert.equal(junk.headers.location, 'cashstack://consent/complete?error=expired');
    const missing = await t.app.inject({ method: 'GET', url: '/v1/consent/return' });
    assert.equal(missing.headers.location, 'cashstack://consent/complete?error=invalid');
  });

  test('a consent session goes stale after twenty minutes', async () => {
    const { accessToken } = await t.signIn('apple-stale');
    const start = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: {} })).json();
    t.clock.advance(20 * 60_000 + 1);
    const res = await t.app.inject({ method: 'GET', url: `/v1/consent/return?state=${new URL(start.url).searchParams.get('state')}` });
    assert.equal(res.headers.location, 'cashstack://consent/complete?error=expired');
  });

  test('after consent, the cash accounts arrive — and only those, in cents, masked', async () => {
    const { accessToken } = await t.signIn('apple-accounts');
    const { sessionId, redirect } = await t.connectBank(accessToken);
    assert.equal(redirect, `cashstack://consent/complete?session=${sessionId}`);
    const res = await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${sessionId}/wait`, headers: bearer(accessToken) });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.status, 'ready');
    assert.deepEqual(body.accounts.map((a: { name: string }) => a.name), ['Everyday', 'Bonus Saver']);
    const [everyday, saver] = body.accounts;
    assert.equal(everyday.availableMinor, 128435);
    assert.equal(everyday.balanceMinor, 129010);
    assert.equal(everyday.maskedNumber, '•••• 1965');
    assert.equal(everyday.type, 'transaction');
    assert.deepEqual(everyday.institution, { id: 'AU00000', name: 'Hooli', color: '#5B2EFF' });
    assert.equal(saver.maskedNumber, '•••• 8802');
    // Nothing that identifies the account beyond the last four digits.
    assert.doesNotMatch(JSON.stringify(body), /063000|1234 1965|600000157441965/);
  });

  test('a bank that fails says so', async () => {
    const { accessToken } = await t.signIn('apple-fail');
    const { sessionId } = await t.connectBank(accessToken, { fail: true });
    const body = (await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${sessionId}/wait`, headers: bearer(accessToken) })).json();
    assert.equal(body.status, 'failed');
    assert.equal(body.failures[0].title, 'Hooli is not responding');
    assert.deepEqual(body.accounts, []);
  });

  test("nobody can wait on someone else's consent session", async () => {
    const owner = await t.signIn('apple-owner');
    const other = await t.signIn('apple-other');
    const { sessionId } = await t.connectBank(owner.accessToken);
    const res = await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${sessionId}/wait`, headers: bearer(other.accessToken) });
    assert.equal(res.statusCode, 404);
  });

  test("a doctored redirect can't pull in someone else's job", async () => {
    const victim = await t.signIn('apple-victim');
    const attacker = await t.signIn('apple-attacker');
    // The victim connects; the attacker learns the job id somehow.
    const victimStart = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(victim.accessToken), payload: {} })).json();
    const victimUrl = new URL(victimStart.url);
    const { jobId } = t.basiq.approve(victimUrl.searchParams.get('token')!);
    // The attacker returns from their own consent trip with the victim's job id.
    const mine = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(attacker.accessToken), payload: {} })).json();
    await t.app.inject({ method: 'GET', url: `/v1/consent/return?state=${new URL(mine.url).searchParams.get('state')}&jobIds=${jobId}` });
    const body = (await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${mine.id}/wait`, headers: bearer(attacker.accessToken) })).json();
    assert.equal(body.status, 'ready');
    assert.deepEqual(body.accounts, []);
    assert.deepEqual(body.failures, []);
  });

  test("backing out of Basiq's screens comes back as a cancel", async () => {
    const { accessToken } = await t.signIn('apple-backout');
    const start = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: {} })).json();
    await t.app.inject({ method: 'GET', url: `/v1/consent/return?state=${new URL(start.url).searchParams.get('state')}` });
    const body = (await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${start.id}/wait`, headers: bearer(accessToken) })).json();
    assert.equal(body.status, 'cancelled');
  });

  test('closing the sheet before Basiq redirects is a cancel, not an error', async () => {
    const { accessToken } = await t.signIn('apple-cancel');
    const start = (await t.app.inject({ method: 'POST', url: '/v1/consent/sessions', headers: bearer(accessToken), payload: {} })).json();
    const body = (await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${start.id}/wait`, headers: bearer(accessToken) })).json();
    assert.equal(body.status, 'cancelled');
  });
});

describe('accounts and connections', () => {
  let t: TestApp;
  before(async () => { t = await testApp(); });
  after(async () => { await t.close(); });

  test('no bank yet means no accounts, without making a Basiq user', async () => {
    const { accessToken } = await t.signIn('apple-empty');
    const res = await t.app.inject({ method: 'GET', url: '/v1/accounts', headers: bearer(accessToken) });
    assert.deepEqual(res.json().accounts, []);
    assert.equal(t.basiq.calls.includes('createUser'), false);
    const me = (await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).json();
    assert.equal(me.bank.linked, false);
  });

  test('connections list with their expiry, and stopping one takes its accounts away', async () => {
    const { accessToken } = await t.signIn('apple-conn');
    const { sessionId } = await t.connectBank(accessToken);
    await t.app.inject({ method: 'POST', url: `/v1/consent/sessions/${sessionId}/wait`, headers: bearer(accessToken) });

    const me = (await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) })).json();
    assert.equal(me.bank.linked, true);
    assert.equal(me.bank.consent.status, 'active');

    const { connections } = (await t.app.inject({ method: 'GET', url: '/v1/connections', headers: bearer(accessToken) })).json();
    assert.equal(connections.length, 1);
    assert.equal(connections[0].institution.name, 'Hooli');
    assert.ok(connections[0].expiresAt);

    const del = await t.app.inject({ method: 'DELETE', url: `/v1/connections/${connections[0].id}`, headers: bearer(accessToken) });
    assert.equal(del.statusCode, 204);
    const after = (await t.app.inject({ method: 'GET', url: '/v1/accounts', headers: bearer(accessToken) })).json();
    assert.deepEqual(after.accounts, []);
    const again = await t.app.inject({ method: 'DELETE', url: `/v1/connections/${connections[0].id}`, headers: bearer(accessToken) });
    assert.equal(again.statusCode, 404);
  });

  test('connection ids that are not ids are refused before reaching Basiq', async () => {
    const { accessToken } = await t.signIn('apple-path');
    const res = await t.app.inject({ method: 'DELETE', url: '/v1/connections/..%2F..%2Fusers', headers: bearer(accessToken) });
    assert.equal(res.statusCode, 400);
  });

  test('a manual refresh runs at most once every fifteen minutes', async () => {
    const { accessToken } = await t.signIn('apple-refresh');
    await t.connectBank(accessToken);
    const count = () => t.basiq.calls.filter((c) => c === 'refreshConnections').length;
    const start = count();
    const first = (await t.app.inject({ method: 'POST', url: '/v1/accounts/refresh', headers: bearer(accessToken) })).json();
    assert.equal(first.refreshed, true);
    assert.equal(first.accounts.length, 2);
    const second = (await t.app.inject({ method: 'POST', url: '/v1/accounts/refresh', headers: bearer(accessToken) })).json();
    assert.equal(second.refreshed, false);
    assert.equal(count() - start, 1);
    t.clock.advance(15 * 60_000 + 1);
    // The access token has lapsed by now too; signing in again is the same person.
    const later = await t.signIn('apple-refresh');
    assert.equal((await t.app.inject({ method: 'POST', url: '/v1/accounts/refresh', headers: bearer(later.accessToken) })).json().refreshed, true);
  });
});

describe('deleting an account', () => {
  test('removes the Basiq user, every session and every row — but keeps the audit trail', async () => {
    const t = await testApp();
    const { accessToken, refreshToken, userId } = await t.signIn('apple-delete');
    await t.connectBank(accessToken);
    const basiqUser = (await t.db.query<{ basiq_user_id: string }>('select basiq_user_id from users where id = $1', [userId])).rows[0]!.basiq_user_id;

    const res = await t.app.inject({ method: 'DELETE', url: '/v1/me', headers: bearer(accessToken) });
    assert.equal(res.statusCode, 204);
    assert.equal(t.basiq.users.has(basiqUser), false);
    assert.equal((await t.db.query('select 1 from users where id = $1', [userId])).rows.length, 0);
    assert.equal((await t.db.query('select 1 from sessions where user_id = $1', [userId])).rows.length, 0);
    assert.equal((await t.db.query('select 1 from consent_sessions where user_id = $1', [userId])).rows.length, 0);
    assert.equal((await t.app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } })).statusCode, 401);
    const audit = await t.db.query("select 1 from audit_log where user_id = $1 and event = 'account.deleted'", [userId]);
    assert.equal(audit.rows.length, 1);
    await t.close();
  });

  test('keeps everything if Basiq cannot be reached, so it can be retried', async () => {
    const t = await testApp();
    const { accessToken, userId } = await t.signIn('apple-retry');
    await t.connectBank(accessToken);
    t.basiq.deleteUser = async () => { throw new (await import('../src/basiq/types.ts')).BasiqError(503, 'down'); };
    const res = await t.app.inject({ method: 'DELETE', url: '/v1/me', headers: bearer(accessToken) });
    assert.equal(res.statusCode, 502);
    assert.equal((await t.db.query('select 1 from users where id = $1', [userId])).rows.length, 1);
    await t.close();
  });
});
