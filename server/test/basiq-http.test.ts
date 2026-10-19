import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpBasiqClient } from '../src/basiq/http.ts';
import { BasiqError } from '../src/basiq/types.ts';

type Call = { url: string; method: string; headers: Record<string, string>; body?: string };

/// A scripted Basiq: each request is recorded and answered by the first
/// handler whose path matches.
function stub(routes: Array<[RegExp, (call: Call, n: number) => Response]>) {
  const calls: Call[] = [];
  const counts = new Map<RegExp, number>();
  const fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    const call: Call = { url: String(input), method: init?.method ?? 'GET', headers: init?.headers as Record<string, string>, body: init?.body as string | undefined };
    calls.push(call);
    for (const [pattern, handler] of routes) {
      if (pattern.test(new URL(call.url).pathname)) {
        const n = counts.get(pattern) ?? 0;
        counts.set(pattern, n + 1);
        return handler(call, n);
      }
    }
    return new Response('{}', { status: 404 });
  }) as typeof fetch;
  return { calls, fetchFn };
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const tokenRoute: [RegExp, (call: Call, n: number) => Response] = [/^\/token$/, (_c, n) => json({ access_token: `server-token-${n}`, expires_in: 3600 })];

test('the API key goes verbatim in Basic auth, and one server token serves many calls', async () => {
  const { calls, fetchFn } = stub([tokenRoute, [/\/users\/u1\/accounts$/, () => json({ data: [{ id: 'a1' }] })]]);
  let now = 0;
  const client = new HttpBasiqClient({ apiKey: 'key-as-issued==', apiUrl: 'https://au-api.basiq.io', consentUrl: 'https://consent.basiq.io/home', fetch: fetchFn, now: () => now });

  await Promise.all([client.listAccounts('u1'), client.listAccounts('u1'), client.listAccounts('u1')]);
  const tokenCalls = calls.filter((c) => c.url.endsWith('/token'));
  assert.equal(tokenCalls.length, 1);
  assert.equal(tokenCalls[0]!.headers.Authorization, 'Basic key-as-issued==');
  assert.equal(tokenCalls[0]!.headers['basiq-version'], '3.0');
  assert.equal(tokenCalls[0]!.body, 'scope=SERVER_ACCESS');
  assert.equal(calls.find((c) => c.url.endsWith('/accounts'))!.headers.Authorization, 'Bearer server-token-0');

  // With under ten minutes left, the next call renews first.
  now = 51 * 60_000;
  await client.listAccounts('u1');
  assert.equal(calls.filter((c) => c.url.endsWith('/token')).length, 2);
});

test('client tokens are bound to the user', async () => {
  const { calls, fetchFn } = stub([tokenRoute]);
  const client = new HttpBasiqClient({ apiKey: 'k', apiUrl: 'https://au-api.basiq.io', consentUrl: 'https://consent.basiq.io/home', fetch: fetchFn });
  await client.clientToken('user-42');
  assert.equal(calls[0]!.body, 'scope=CLIENT_ACCESS&userId=user-42');
  const url = new URL(client.consentUrl({ token: 'tok', action: 'connect', state: 'cst_x' }));
  assert.equal(url.origin + url.pathname, 'https://consent.basiq.io/home');
  assert.equal(url.searchParams.get('action'), 'connect');
});

test('reads retry through a brief outage; writes are never repeated', async () => {
  const { calls, fetchFn } = stub([
    tokenRoute,
    [/\/jobs\/j1$/, (_c, n) => (n < 2 ? json({}, 503) : json({ id: 'j1', steps: [] }))],
    [/\/users$/, () => json({}, 503)],
  ]);
  const client = new HttpBasiqClient({ apiKey: 'k', apiUrl: 'https://au-api.basiq.io', consentUrl: 'https://consent.basiq.io/home', fetch: fetchFn });
  const job = await client.getJob('j1');
  assert.equal(job.id, 'j1');
  assert.equal(calls.filter((c) => c.url.endsWith('/jobs/j1')).length, 3);

  await assert.rejects(client.createUser({ email: 'a@b.co' }), (e: unknown) => e instanceof BasiqError && e.status === 503);
  assert.equal(calls.filter((c) => c.url.endsWith('/users')).length, 1);
});

test("Basiq's error body comes through as a BasiqError, and a revoked token is renewed once", async () => {
  const { calls, fetchFn } = stub([
    tokenRoute,
    [/\/users\/u1\/connections$/, (call) =>
      call.headers.Authorization === 'Bearer server-token-0'
        ? json({ correlationId: 'corr-1', data: [{ code: 'unauthorized-access', title: 'Unauthorized' }] }, 401)
        : json({ data: [] })],
    [/\/users\/u2\/connections$/, () => json({ correlationId: 'corr-2', data: [{ code: 'resource-not-found', detail: 'User not found' }] }, 404)],
  ]);
  const client = new HttpBasiqClient({ apiKey: 'k', apiUrl: 'https://au-api.basiq.io', consentUrl: 'https://consent.basiq.io/home', fetch: fetchFn });
  assert.deepEqual(await client.listConnections('u1'), []);
  assert.equal(calls.filter((c) => c.url.endsWith('/token')).length, 2);

  await assert.rejects(client.listConnections('u2'), (e: unknown) =>
    e instanceof BasiqError && e.status === 404 && e.code === 'resource-not-found' && e.correlationId === 'corr-2' && e.message === 'User not found');
});

test('ids that would bend the URL path are refused before any request', async () => {
  const { calls, fetchFn } = stub([tokenRoute]);
  const client = new HttpBasiqClient({ apiKey: 'k', apiUrl: 'https://au-api.basiq.io', consentUrl: 'https://consent.basiq.io/home', fetch: fetchFn });
  await assert.rejects(client.deleteConnection('u1', '../../users/u2'), BasiqError);
  assert.equal(calls.filter((c) => c.url.includes('/connections')).length, 0);
});
