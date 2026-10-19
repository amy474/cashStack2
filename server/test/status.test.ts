import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { bearer, testApp } from './helpers.ts';

const build = (n: number) => ({ 'x-cashstack-build': String(n) });

describe('turning old builds away', () => {
  test('lets every build in until a minimum is set', async () => {
    const t = await testApp();
    const { accessToken } = await t.signIn();
    const res = await t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(accessToken) });
    assert.equal(res.statusCode, 200);
    await t.close();
  });

  test('tells a build below the minimum to update, before it can sign in', async () => {
    const t = await testApp({ MIN_APP_BUILD: '7', APP_UPDATE_URL: 'itms-apps://apps.apple.com/app/id123' });
    const old = await t.app.inject({ method: 'POST', url: '/v1/auth/apple', headers: build(6), payload: {} });
    assert.equal(old.statusCode, 426);
    assert.deepEqual(old.json(), {
      error: 'upgrade_required',
      message: 'This version of CashStack is out of date. Update it to keep going.',
      updateUrl: 'itms-apps://apps.apple.com/app/id123',
    });
    const current = await t.app.inject({ method: 'GET', url: '/v1/me', headers: build(7) });
    assert.equal(current.statusCode, 401, 'build 7 gets as far as asking for a token');
    await t.close();
  });

  test('counts a request that does not say its build as too old', async () => {
    const t = await testApp({ MIN_APP_BUILD: '2' });
    for (const headers of [{}, { 'x-cashstack-build': 'latest' }, { 'x-cashstack-build': '-4' }]) {
      const res = await t.app.inject({ method: 'GET', url: '/v1/me', headers });
      assert.equal(res.statusCode, 426, JSON.stringify(headers));
    }
    await t.close();
  });

  test('keeps status, crash reports, webhooks, the consent redirect and the public pages open', async () => {
    const t = await testApp({ MIN_APP_BUILD: '99', MAINTENANCE_MESSAGE: 'Back soon.' });
    const open = [
      ['GET', '/v1/status'],
      ['POST', '/v1/diagnostics'],
      ['POST', '/v1/webhooks/basiq'],
      ['GET', '/v1/consent/return?state=whatever-state'],
      ['GET', '/privacy'],
      ['GET', '/healthz'],
    ] as const;
    for (const [method, url] of open) {
      const res = await t.app.inject({ method, url, payload: method === 'POST' ? {} : undefined });
      assert.ok(![426, 503].includes(res.statusCode), `${method} ${url} answered ${res.statusCode}`);
    }
    await t.close();
  });
});

describe('maintenance', () => {
  test('turns every app request away with the message, even from a current build', async () => {
    const t = await testApp({ MAINTENANCE_MESSAGE: "We're upgrading CashStack. Back by 9pm." });
    const res = await t.app.inject({ method: 'GET', url: '/v1/accounts', headers: build(50) });
    assert.equal(res.statusCode, 503);
    assert.equal(res.headers['retry-after'], '300');
    assert.deepEqual(res.json(), { error: 'maintenance', message: "We're upgrading CashStack. Back by 9pm." });
    await t.close();
  });

  test('an empty message leaves the app working', async () => {
    const t = await testApp({ MAINTENANCE_MESSAGE: '  ' });
    const status = await t.app.inject({ method: 'GET', url: '/v1/status' });
    assert.equal(status.json().maintenance, null);
    await t.close();
  });
});

describe('the status check', () => {
  test('says what the app needs to know before anyone signs in', async () => {
    const t = await testApp({ MIN_APP_BUILD: '3', APP_UPDATE_URL: 'https://testflight.apple.com/join/abc', MAINTENANCE_MESSAGE: 'Back soon.' });
    const res = await t.app.inject({ method: 'GET', url: '/v1/status' });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { minBuild: 3, updateUrl: 'https://testflight.apple.com/join/abc', maintenance: { message: 'Back soon.' } });
    await t.close();
  });

  test('defaults to letting everything through', async () => {
    const t = await testApp();
    assert.deepEqual((await t.app.inject({ method: 'GET', url: '/v1/status' })).json(), { minBuild: 0, updateUrl: null, maintenance: null });
    await t.close();
  });
});
