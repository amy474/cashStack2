import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { FakeBasiq } from '../basiq/fake.ts';
import type { Ctx } from '../context.ts';

const page = (title: string, body: string) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  :root { color-scheme: light; }
  body { margin: 0; background: #fff; color: #000; font: 16px/1.5 -apple-system, system-ui, sans-serif; }
  main { max-width: 560px; margin: 0 auto; padding: 32px 20px 48px; }
  h1 { font-size: 28px; line-height: 1.15; margin: 0 0 8px; }
  h2 { font-size: 13px; letter-spacing: .14em; text-transform: uppercase; margin: 32px 0 8px; }
  p, li { color: rgba(0,0,0,.72); }
  ol { padding-left: 20px; }
  .rule { border: 0; border-top: 1px solid #000; margin: 24px 0; }
  .button { display: block; text-align: center; padding: 15px; border-radius: 100px; text-decoration: none; margin-top: 12px; border: 1px solid #000; }
  .primary { background: #000; color: #fff; }
  .ghost { color: #000; }
  .tag { display: inline-block; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; border: 1px solid #000; border-radius: 100px; padding: 2px 10px; }
</style></head><body><main>${body}</main></body></html>`;

/// The public page Basiq's consent screen links to as the "Manage Consent
/// URL", and that the app links to from its data-sharing settings.
const dataSharing = page(
  'Managing your data sharing · CashStack',
  `<h1>Managing your data sharing</h1>
<p>CashStack shows the balance of the bank accounts you choose as notes and coins. It reads balances and account details through Basiq, an accredited data recipient under Australia's Consumer Data Right. CashStack cannot move money and never sees your bank password.</p>
<hr class="rule">
<h2>Stop sharing one bank</h2>
<ol><li>Open CashStack and tap the account name at the top.</li><li>Under <b>Data sharing</b>, find the bank and tap <b>Stop sharing</b>.</li></ol>
<h2>Review or withdraw all consent</h2>
<ol><li>In the same place, tap <b>Manage data sharing</b>.</li><li>You'll see what you agreed to share, until when, and can withdraw it.</li></ol>
<h2>From your bank</h2>
<p>Every bank that takes part in the Consumer Data Right has a data-sharing dashboard in its app or internet banking. Stopping sharing there works too.</p>
<h2>Delete everything</h2>
<p>In CashStack, open accounts and tap <b>Delete my account and data</b>. This deletes your CashStack account, your bank connections, and the data Basiq holds for CashStack.</p>
<h2>When sharing stops</h2>
<p>CashStack does not store your balances or transactions; it reads them when you open the app. When sharing stops, the wallet simply has nothing to show for that bank.</p>`,
);

const FakeConsentQuery = z.object({
  token: z.string().max(200),
  state: z.string().max(200),
  action: z.string().max(20).optional(),
});

export function pageRoutes(app: FastifyInstance, ctx: Ctx, fake?: FakeBasiq) {
  app.get('/healthz', async () => ({ ok: true }));

  app.get('/data-sharing', async (_req, reply) => reply.type('text/html; charset=utf-8').send(dataSharing));

  if (!fake) return;

  // MARK: The pretend consent screen (fake mode only)

  const returnUrl = (state: string, jobIds?: string) => {
    const url = new URL(`${ctx.config.publicUrl}/v1/consent/return`);
    url.searchParams.set('state', state);
    if (jobIds) url.searchParams.set('jobIds', jobIds);
    return url.toString();
  };

  app.get('/dev/fake-consent', async (req, reply) => {
    const q = FakeConsentQuery.safeParse(req.query);
    if (!q.success || !fake.userForToken(q.data.token)) return reply.code(400).type('text/html; charset=utf-8').send(page('Expired', '<h1>This link has expired</h1>'));
    const params = new URLSearchParams({ token: q.data.token, state: q.data.state });
    const manage = q.data.action === 'manage';
    return reply.type('text/html; charset=utf-8').send(
      page(
        'Connect Hooli · Basiq sandbox',
        `<span class="tag">Fake Basiq · development</span>
<h1 style="margin-top:16px">${manage ? 'Your data sharing' : 'Share your Hooli accounts with CashStack'}</h1>
<p>${manage ? 'In the real app this is Basiq’s consent dashboard, where people review and withdraw consent.' : 'In the real app this is Basiq’s consent screen, then your bank’s own login. Here it connects a pretend Hooli bank.'}</p>
<hr class="rule">
${manage ? '' : `<p><b>CashStack will see</b><br>Account names, numbers and balances.</p><p><b>For</b><br>12 months, or until you stop sharing.</p>`}
${manage ? '' : `<a class="button primary" id="share" href="/dev/fake-consent/approve?${params}">Share</a>`}
${manage ? '' : `<a class="button ghost" id="fail" href="/dev/fake-consent/approve?${params}&fail=1">Share, but the bank is down</a>`}
<a class="button ghost" id="done" href="${returnUrl(q.data.state)}">${manage ? 'Done' : 'Cancel'}</a>`,
      ),
    );
  });

  app.get('/dev/fake-consent/approve', async (req, reply) => {
    const q = FakeConsentQuery.extend({ fail: z.literal('1').optional() }).safeParse(req.query);
    if (!q.success || !fake.userForToken(q.data.token)) return reply.code(400).send({ error: 'expired' });
    const { jobId } = fake.approve(q.data.token, { fail: q.data.fail === '1' });
    return reply.redirect(returnUrl(q.data.state, jobId), 302);
  });
}
