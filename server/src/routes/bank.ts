import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { accountsFor, basiqUserId, ensureBasiqUser, institutionsById, toConnectionOut, waitForJobs } from '../bank.ts';
import { BasiqError } from '../basiq/types.ts';
import { open, randomToken, sha256 } from '../crypto.ts';
import { HttpError, requireUser, userId, type Ctx } from '../context.ts';

const BASIQ_ID = /^[A-Za-z0-9_-]{1,128}$/;
const CONSENT_TTL_MS = 20 * 60_000;
/// Basiq refreshes connected banks itself every day; a manual refresh is for
/// "I just got paid", and is held to one per quarter hour.
const MANUAL_REFRESH_EVERY_MS = 15 * 60_000;

const StartConsent = z.object({
  action: z.enum(['connect', 'manage', 'extend']).default('connect'),
  connectionId: z.string().regex(BASIQ_ID).optional(),
});

const ConsentReturn = z.object({
  state: z.string().min(8).max(200),
  jobIds: z.string().max(2000).optional(),
  jobId: z.string().max(200).optional(),
});

const IdParam = z.object({ id: z.uuid() });
const ConnectionParam = z.object({ id: z.string().regex(BASIQ_ID) });

/// Per-person limits, keyed on the bearer token since the limiter runs before
/// the token is checked.
const perPerson = (max: number) => ({
  rateLimit: { max, timeWindow: '1 minute', keyGenerator: (req: FastifyRequest) => sha256(req.headers.authorization ?? req.ip) },
});

export function bankRoutes(app: FastifyInstance, ctx: Ctx) {
  const signedIn = { preHandler: requireUser(ctx) };

  // MARK: Me

  app.get('/v1/me', signedIn, async (req) => {
    const { rows } = await ctx.db.query<{ id: string; email: string | null; created_at: Date; basiq_user_id: string | null }>(
      'select id, email, created_at, basiq_user_id from users where id = $1',
      [userId(req)],
    );
    const user = rows[0];
    if (!user) throw new HttpError(401, 'unauthorized', 'Sign in again to continue.');

    let consent: { status: string; expiresAt: string | null } | null = null;
    let bankReachable = true;
    if (user.basiq_user_id) {
      try {
        const active = (await ctx.basiq.listConsents(user.basiq_user_id))
          .filter((c) => c.status === 'active')
          .sort((a, b) => (b.expiryDate ?? '').localeCompare(a.expiryDate ?? ''))[0];
        consent = active ? { status: 'active', expiresAt: active.expiryDate ?? null } : null;
      } catch (error) {
        req.log.warn({ err: error }, 'could not read consents');
        bankReachable = false;
      }
    }
    return {
      id: user.id,
      email: user.email,
      createdAt: new Date(user.created_at).toISOString(),
      bank: { linked: Boolean(user.basiq_user_id), reachable: bankReachable, consent },
    };
  });

  /// Delete the account and everything behind it: the Basiq user (which takes
  /// every bank connection and all the data Basiq holds with it), the Apple
  /// sign-in, and every row here. If Basiq can't be reached nothing is
  /// deleted, so the person can simply try again.
  app.delete('/v1/me', signedIn, async (req, reply) => {
    const id = userId(req);
    const { rows } = await ctx.db.query<{ basiq_user_id: string | null; apple_refresh_token_sealed: string | null }>(
      'select basiq_user_id, apple_refresh_token_sealed from users where id = $1',
      [id],
    );
    const user = rows[0];
    if (!user) return reply.code(204).send();

    if (user.basiq_user_id) {
      try {
        await ctx.basiq.deleteUser(user.basiq_user_id);
      } catch (error) {
        if (!(error instanceof BasiqError && error.status === 404)) {
          throw new HttpError(502, 'bank_unavailable', "We couldn't reach the bank connection service, so nothing was deleted. Try again in a minute.");
        }
      }
    }
    if (ctx.appleTokens && user.apple_refresh_token_sealed) {
      try {
        await ctx.appleTokens.revoke(open(user.apple_refresh_token_sealed, ctx.config.dataKey));
      } catch (error) {
        req.log.warn({ err: error }, 'apple revoke failed');
      }
    }
    await ctx.db.query('delete from users where id = $1', [id]);
    ctx.accountsCache.delete(id);
    await ctx.audit(id, 'account.deleted', { hadBank: Boolean(user.basiq_user_id) });
    return reply.code(204).send();
  });

  // MARK: Consent

  /// Start a trip through Basiq's consent screens. The app opens the URL in a
  /// system web sheet; Basiq sends the browser back to /v1/consent/return.
  app.post('/v1/consent/sessions', { ...signedIn, config: perPerson(10) }, async (req) => {
    const body = StartConsent.parse(req.body ?? {});
    const id = userId(req);
    const basiqUser = await ensureBasiqUser(ctx, id);
    const state = randomToken('cst', 24);
    const sessionId = randomUUID();
    const now = ctx.now();
    await ctx.db.query(
      `insert into consent_sessions (id, user_id, state_hash, action, created_at, expires_at)
       values ($1, $2, $3, $4, $5, $6)`,
      [sessionId, id, sha256(state), body.action, now, new Date(now.getTime() + CONSENT_TTL_MS)],
    );
    const token = await ctx.basiq.clientToken(basiqUser);
    await ctx.audit(id, 'consent.started', { action: body.action });
    return {
      id: sessionId,
      url: ctx.basiq.consentUrl({ token, action: body.action, state, connectionId: body.connectionId }),
      callbackScheme: ctx.config.callbackScheme,
    };
  });

  /// Basiq's redirect lands here. The state is spent on first use and only
  /// the session id goes on to the app — no tokens in the custom-scheme URL,
  /// which any app could register.
  app.get('/v1/consent/return', async (req, reply) => {
    const back = (query: string) => reply.redirect(`${ctx.config.callbackScheme}://consent/complete?${query}`, 302);
    const parsed = ConsentReturn.safeParse(req.query);
    if (!parsed.success) return back('error=invalid');
    const { state, jobIds, jobId } = parsed.data;
    const jobs = [...new Set([...(jobIds ?? '').split(','), jobId ?? ''])].filter((j) => BASIQ_ID.test(j)).slice(0, 10);
    const now = ctx.now();
    const { rows } = await ctx.db.query<{ id: string; user_id: string }>(
      `update consent_sessions set returned_at = $2, job_ids = $3::jsonb
       where state_hash = $1 and returned_at is null and expires_at > $2
       returning id, user_id`,
      [sha256(state), now, JSON.stringify(jobs)],
    );
    const session = rows[0];
    if (!session) return back('error=expired');
    await ctx.audit(session.user_id, 'consent.returned', { jobs: jobs.length });
    return back(`session=${session.id}`);
  });

  /// After the web sheet closes: wait for the new connections' accounts to
  /// arrive (Basiq fetches them in the background), then hand them over.
  /// Each call can poll Basiq for up to 25 seconds, so it has its own limit;
  /// the app makes at most four in a row.
  app.post('/v1/consent/sessions/:id/wait', { ...signedIn, config: perPerson(8) }, async (req) => {
    const { id: sessionId } = IdParam.parse(req.params);
    const id = userId(req);
    const { rows } = await ctx.db.query<{ job_ids: string[]; returned_at: Date | null; action: string }>(
      'select job_ids, returned_at, action from consent_sessions where id = $1 and user_id = $2',
      [sessionId, id],
    );
    const session = rows[0];
    if (!session) throw new HttpError(404, 'not_found', 'That bank connection attempt has expired.');
    if (!session.returned_at) return { status: 'cancelled', failures: [], accounts: await accountsFor(ctx, id) };

    const basiqUser = await basiqUserId(ctx, id);
    const jobs = Array.isArray(session.job_ids) ? session.job_ids : [];
    // Connecting always yields a job; coming back without one means they
    // backed out of Basiq's screens. Manage and extend have no jobs anyway.
    if (session.action === 'connect' && jobs.length === 0) {
      await ctx.db.query("update consent_sessions set outcome = 'cancelled' where id = $1", [sessionId]);
      return { status: 'cancelled', failures: [], accounts: await accountsFor(ctx, id) };
    }
    const result = basiqUser && jobs.length
      ? await waitForJobs(ctx, id, basiqUser, jobs, 25_000)
      : { status: 'ready' as const, failures: [] };
    await ctx.db.query('update consent_sessions set outcome = $2 where id = $1', [sessionId, result.status]);
    await ctx.audit(id, 'consent.completed', { status: result.status, jobs: jobs.length });
    return { ...result, accounts: await accountsFor(ctx, id, { fresh: true }) };
  });

  // MARK: Accounts and connections

  app.get('/v1/accounts', signedIn, async (req) => {
    return { accounts: await accountsFor(ctx, userId(req)), fetchedAt: ctx.now().toISOString() };
  });

  app.post('/v1/accounts/refresh', { ...signedIn, config: perPerson(6) }, async (req) => {
    const id = userId(req);
    const now = ctx.now();
    const { rows } = await ctx.db.query<{ basiq_user_id: string | null }>(
      `update users set last_bank_refresh_at = $2
       where id = $1 and basiq_user_id is not null
         and (last_bank_refresh_at is null or last_bank_refresh_at < $3)
       returning basiq_user_id`,
      [id, now, new Date(now.getTime() - MANUAL_REFRESH_EVERY_MS)],
    );
    const basiqUser = rows[0]?.basiq_user_id;
    let refreshed = false;
    if (basiqUser) {
      const jobs = await ctx.basiq.refreshConnections(basiqUser);
      await waitForJobs(ctx, id, basiqUser, jobs, 20_000);
      refreshed = true;
    }
    return { accounts: await accountsFor(ctx, id, { fresh: true }), refreshed, fetchedAt: ctx.now().toISOString() };
  });

  app.get('/v1/connections', signedIn, async (req) => {
    const basiqUser = await basiqUserId(ctx, userId(req));
    if (!basiqUser) return { connections: [] };
    const [connections, connectors] = await Promise.all([ctx.basiq.listConnections(basiqUser), ctx.basiq.listConnectors()]);
    const institutions = institutionsById(connectors);
    return { connections: connections.map((c) => toConnectionOut(c, institutions)) };
  });

  /// Stop sharing one bank. Basiq deletes the connection and the data it
  /// fetched through it.
  app.delete('/v1/connections/:id', signedIn, async (req, reply) => {
    const { id: connectionId } = ConnectionParam.parse(req.params);
    const id = userId(req);
    const basiqUser = await basiqUserId(ctx, id);
    if (!basiqUser) throw new HttpError(404, 'not_found', 'That bank is not connected.');
    try {
      await ctx.basiq.deleteConnection(basiqUser, connectionId);
    } catch (error) {
      if (error instanceof BasiqError && error.status === 404) throw new HttpError(404, 'not_found', 'That bank is not connected.');
      throw error;
    }
    ctx.accountsCache.delete(id);
    await ctx.audit(id, 'connection.deleted', { connectionId });
    return reply.code(204).send();
  });
}
