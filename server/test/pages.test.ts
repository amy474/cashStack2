import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { PUBLIC_PAGES, renderPublicPage, type Details } from '../src/routes/pages.ts';
import { testApp } from './helpers.ts';

const filled: Details = { business: 'Example Pty Ltd', abn: '12 345 678 901', email: 'help@example.com', address: '1 George St, Sydney NSW 2000', state: 'New South Wales' };
const blank: Details = { business: '', abn: '', email: '', address: '', state: '' };

describe('policies and help', () => {
  test('are served as pages that lead to each other', async () => {
    const t = await testApp();
    for (const { path } of [...PUBLIC_PAGES, { path: '/data-sharing' }]) {
      const res = await t.app.inject({ method: 'GET', url: path });
      assert.equal(res.statusCode, 200, path);
      assert.match(String(res.headers['content-type']), /^text\/html/, path);
      assert.match(res.body, /<h1>/, path);
      for (const other of PUBLIC_PAGES) assert.ok(res.body.includes(`href="${other.path}"`), `${path} links to ${other.path}`);
      assert.ok(!res.body.includes('<!--'), `${path} keeps its editing notes to itself`);
    }
    await t.close();
  });

  test('only link to pages that exist', async () => {
    const t = await testApp();
    for (const { path } of PUBLIC_PAGES) {
      const body = (await t.app.inject({ method: 'GET', url: path })).body;
      for (const [, href] of body.matchAll(/href="(\/[^"#?]*)/g)) {
        const res = await t.app.inject({ method: 'GET', url: href! });
        assert.equal(res.statusCode, 200, `${path} links to ${href}`);
      }
    }
    await t.close();
  });

  test('fill in the business details, with the email as a link', () => {
    const { body, gaps } = renderPublicPage('<p>{{business}} (ABN {{abn}}). Write to {{email}}.</p>', filled);
    assert.deepEqual(gaps, []);
    assert.ok(body.includes('Example Pty Ltd (ABN 12 345 678 901)'));
    assert.ok(body.includes('<a href="mailto:help@example.com">help@example.com</a>'));
    assert.ok(!body.includes('Draft'));
  });

  test('escape the details rather than trusting them as HTML', () => {
    const { body } = renderPublicPage('<p>{{business}}</p>', { ...filled, business: 'A & B <Pty> Ltd' });
    assert.ok(body.includes('A &amp; B &lt;Pty&gt; Ltd'));
  });

  test('mark blank details and [[gaps]] as a draft', () => {
    const { body, gaps } = renderPublicPage('<!-- note -->\n<p>{{business}} keeps records for [[six years]].</p>', blank);
    assert.deepEqual(gaps, ['business name', 'six years']);
    assert.ok(body.startsWith('<p class="draft">'));
    assert.ok(body.includes('<mark>business name</mark> keeps records for <mark>six years</mark>'));
    assert.ok(!body.includes('note'));
  });

  test('refuse a detail that does not exist, so a typo fails at boot', () => {
    assert.throws(() => renderPublicPage('<p>{{bussiness}}</p>', filled), /unknown detail/);
  });
});
