import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { Alerts } from '../src/alerts.ts';
import { summarise } from '../src/routes/diagnostics.ts';
import { testApp } from './helpers.ts';

/// The shape MetricKit's MXDiagnosticPayload.jsonRepresentation() produces,
/// trimmed to what matters here.
const crash = (overrides: Record<string, unknown> = {}) => ({
  version: '1.0.0',
  callStackTree: { callStackPerThread: true, callStacks: [{ threadAttributed: true, callStackRootFrames: [{ binaryUUID: 'A1B2', offsetIntoBinaryTextSegment: 1234, binaryName: 'CashStack', address: 4300000000, sampleCount: 1 }] }] },
  diagnosticMetaData: {
    appVersion: '0.2', appBuildVersion: '14', osVersion: 'iPhone OS 26.0 (23A341)', deviceType: 'iPhone17,1',
    regionFormat: 'AU', platformArchitecture: 'arm64e', exceptionType: 6, exceptionCode: 1, signal: 5,
    ...overrides,
  },
});
const hang = { callStackTree: {}, diagnosticMetaData: { appVersion: '0.2', appBuildVersion: '14', hangDuration: '2.4 sec' } };

describe('crash reports', () => {
  test('are stored one row per diagnostic, with nothing tying them to a person', async () => {
    const t = await testApp();
    const res = await t.app.inject({
      method: 'POST',
      url: '/v1/diagnostics',
      payload: { timeStampBegin: '2026-10-19 09:00', crashDiagnostics: [crash()], hangDiagnostics: [hang] },
    });
    assert.equal(res.statusCode, 202);
    assert.deepEqual(res.json(), { received: 2 });

    const { rows } = await t.db.query<{ kind: string; app_build: string; device_type: string | null; summary: string; detail: { callStackTree: unknown } }>(
      'select kind, app_build, device_type, summary, detail from diagnostics order by kind',
    );
    assert.deepEqual(rows.map((r) => [r.kind, r.app_build, r.summary]), [
      ['crash', '14', 'EXC_BREAKPOINT (SIGTRAP)'],
      ['hang', '14', '2.4 sec hang'],
    ]);
    assert.ok(rows[0]!.detail.callStackTree, 'the call stack is kept for symbolicating');
    const columns = (await t.db.query<{ column_name: string }>("select column_name from information_schema.columns where table_name = 'diagnostics'")).rows.map((r) => r.column_name);
    assert.ok(!columns.some((c) => /user|ip|email/.test(c)), `no identifying columns: ${columns}`);
    await t.close();
  });

  test('alert once per kind of crash, not once per crash', async () => {
    const t = await testApp();
    for (let i = 0; i < 3; i++) {
      await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { crashDiagnostics: [crash()] } });
    }
    await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { crashDiagnostics: [crash({ exceptionType: 1, signal: 11 })] } });
    await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { hangDiagnostics: [hang] } });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(t.alerts.length, 2, t.alerts.join('\n'));
    assert.match(t.alerts[0]!, /CashStack `0\.2 \(14\)` crashed: `EXC_BREAKPOINT \(SIGTRAP\)` on `iPhone17,1`/);
    assert.match(t.alerts[1]!, /EXC_BAD_ACCESS \(SIGSEGV\)/);
    await t.close();
  });

  test("can't put links, mentions or terminal escapes into alerts or the report", async () => {
    const t = await testApp();
    const res = await t.app.inject({
      method: 'POST',
      url: '/v1/diagnostics',
      payload: { crashDiagnostics: [{ diagnosticMetaData: {
        appVersion: '<!channel>', deviceType: '<https://evil.example|Sign in>', osVersion: '`x` & y',
        terminationReason: 'boom\u001b]52;c;cm0gLXJmIH4=\u0007',
      } }] },
    });
    assert.equal(res.statusCode, 202);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(t.alerts.length, 1);
    assert.ok(!/[<>&\u001b\u0007]/.test(t.alerts[0]!), t.alerts[0]!);
    assert.equal(t.alerts[0]!.split('`').length, 11, 'each outside value stays in its own code span');
    const { rows } = await t.db.query<{ summary: string }>('select summary from diagnostics');
    assert.ok(!/[\u0000-\u001f]/.test(rows[0]!.summary), 'no control characters reach the terminal report');
    await t.close();
  });

  test('stop being stored past a daily ceiling', async () => {
    const t = await testApp();
    await t.db.query(
      `insert into diagnostics (kind, summary, detail, received_at)
       select 'hang', 'hang', '{}'::jsonb, $1 from generate_series(1, 2000)`,
      [t.clock.now],
    );
    const res = await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { hangDiagnostics: [hang] } });
    assert.equal(res.statusCode, 429, 'the app keeps the report and tries again later');
    t.clock.advance(86_400_000 + 1);
    const later = await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { hangDiagnostics: [hang] } });
    assert.equal(later.statusCode, 202);
    await t.close();
  });

  test('are dropped after 90 days', async () => {
    const t = await testApp();
    await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { crashDiagnostics: [crash()] } });
    t.clock.advance(91 * 86_400_000);
    await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload: { hangDiagnostics: [hang] } });
    const { rows } = await t.db.query<{ kind: string }>('select kind from diagnostics');
    assert.deepEqual(rows.map((r) => r.kind), ['hang']);
    await t.close();
  });

  test('refuse anything that is not a report', async () => {
    const t = await testApp();
    for (const payload of [[1, 2, 3], { crashDiagnostics: 'boom' }, { crashDiagnostics: Array.from({ length: 51 }, () => crash()) }]) {
      const res = await t.app.inject({ method: 'POST', url: '/v1/diagnostics', payload });
      assert.equal(res.statusCode, 400, JSON.stringify(payload).slice(0, 60));
    }
    await t.close();
  });

  test('name the common crashes in words', () => {
    assert.equal(summarise('crash', { exceptionType: 1, signal: 11 }), 'EXC_BAD_ACCESS (SIGSEGV)');
    assert.equal(summarise('crash', { exceptionType: 10, signal: 6 }), 'EXC_CRASH (SIGABRT)');
    assert.equal(summarise('crash', { signal: 9 }), 'SIGKILL');
    assert.equal(summarise('crash', { terminationReason: 'Namespace RUNNINGBOARD, Code 0xdead10cc' }), 'Namespace RUNNINGBOARD, Code 0xdead10cc');
    assert.equal(summarise('crash'), 'crash');
    assert.equal(summarise('cpu'), 'too much CPU');
  });
});

describe('server errors', () => {
  test('alert with the route and the kind of error, never the message', async () => {
    const t = await testApp();
    t.app.get('/v1/boom', async () => {
      throw new TypeError('balance for jane@example.com was undefined');
    });
    const res = await t.app.inject({ method: 'GET', url: '/v1/boom' });
    assert.equal(res.statusCode, 500);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(t.alerts.length, 1);
    assert.match(t.alerts[0]!, /TypeError on GET \/v1\/boom/);
    assert.ok(!t.alerts[0]!.includes('jane'), 'the message stays out of the alert');
    await t.close();
  });
});

describe('alerts', () => {
  test('stay quiet for an hour after each kind of problem', async () => {
    const sent: string[] = [];
    let now = 0;
    const alerts = new Alerts((text) => { sent.push(text); }, () => now);
    alerts.notify('a', 'first');
    alerts.notify('a', 'again');
    alerts.notify('b', 'other');
    now += 60 * 60_000;
    alerts.notify('a', 'an hour later');
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(sent, ['first', 'other', 'an hour later']);
  });

  test('however many kinds of problem there are, only so many go out an hour', async () => {
    const sent: string[] = [];
    let now = 0;
    const alerts = new Alerts((text) => { sent.push(text); }, () => now, 60 * 60_000, 3);
    for (let i = 0; i < 10; i++) alerts.notify(`kind-${i}`, `alert ${i}`);
    now += 60 * 60_000;
    alerts.notify('kind-late', 'an hour later');
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(sent, ['alert 0', 'alert 1', 'alert 2', 'an hour later']);
  });

  test('go nowhere without a webhook', () => {
    assert.doesNotThrow(() => new Alerts(undefined).notify('a', 'nobody hears this'));
  });
});
