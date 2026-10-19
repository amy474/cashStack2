import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AppleAuthError } from '../auth/apple.ts';
import { issueSession, revokeFamily, rotate } from '../auth/sessions.ts';
import { seal, sha256 } from '../crypto.ts';
import { HttpError, requireUser, type Ctx } from '../context.ts';

const AppleSignIn = z.object({
  identityToken: z.string().min(20).max(8192),
  /// The nonce the app generated; Apple saw only its SHA-256.
  rawNonce: z.string().min(16).max(128),
  authorizationCode: z.string().max(2048).optional(),
  device: z.string().max(80).optional(),
});

const Refresh = z.object({ refreshToken: z.string().min(8).max(200) });

const DevSignIn = z.object({ name: z.string().regex(/^[a-z0-9-]{1,32}$/).default('developer') });

/// Signing in is the most-guessed door, so it gets its own tight limit.
const authLimit = { rateLimit: { max: 20, timeWindow: '1 minute' } };

export function authRoutes(app: FastifyInstance, ctx: Ctx) {
  app.post('/v1/auth/apple', { config: authLimit }, async (req) => {
    const body = AppleSignIn.parse(req.body);
    let identity;
    try {
      identity = await ctx.verifyApple(body.identityToken, body.rawNonce);
    } catch (error) {
      if (error instanceof AppleAuthError) throw new HttpError(401, 'apple_rejected', 'Sign in with Apple did not go through. Try again.');
      throw error;
    }

    const now = ctx.now();
    const { id, isNew } = await ctx.db.tx(async (t) => {
      const existing = await t.query<{ id: string }>('select id from users where apple_sub = $1 for update', [identity.sub]);
      if (existing.rows[0]) {
        if (identity.email) await t.query('update users set email = $2 where id = $1', [existing.rows[0].id, identity.email]);
        return { id: existing.rows[0].id, isNew: false };
      }
      const id = randomUUID();
      await t.query('insert into users (id, apple_sub, email, created_at) values ($1, $2, $3, $4)', [id, identity.sub, identity.email ?? null, now]);
      return { id, isNew: true };
    });

    // Keep what's needed to revoke this sign-in if they delete their account.
    // A failure here mustn't stop them signing in.
    if (ctx.appleTokens && body.authorizationCode) {
      try {
        const refresh = await ctx.appleTokens.exchange(body.authorizationCode);
        if (refresh) await ctx.db.query('update users set apple_refresh_token_sealed = $2 where id = $1', [id, seal(refresh, ctx.config.dataKey)]);
      } catch (error) {
        req.log.warn({ err: error }, 'apple code exchange failed');
      }
    }

    const tokens = await issueSession(ctx.db, id, now, { device: body.device });
    await ctx.audit(id, isNew ? 'auth.signup' : 'auth.signin', { method: 'apple' });
    return { ...tokens, user: { id, isNew } };
  });

  // Development only: a stable, named user without Apple in the way.
  if (ctx.config.devLogin && ctx.config.env !== 'production') {
    app.post('/v1/auth/dev', { config: authLimit }, async (req) => {
      const { name } = DevSignIn.parse(req.body ?? {});
      const now = ctx.now();
      const found = await ctx.db.query<{ id: string }>('select id from users where dev_key = $1', [name]);
      let id = found.rows[0]?.id;
      const isNew = !id;
      if (!id) {
        id = randomUUID();
        await ctx.db.query('insert into users (id, dev_key, email, created_at) values ($1, $2, $3, $4)', [id, name, `${name}@example.com`, now]);
      }
      const tokens = await issueSession(ctx.db, id, now, { device: 'dev' });
      await ctx.audit(id, 'auth.signin', { method: 'dev' });
      return { ...tokens, user: { id, isNew } };
    });
  }

  app.post('/v1/auth/refresh', { config: authLimit }, async (req) => {
    const { refreshToken } = Refresh.parse(req.body);
    const outcome = await rotate(ctx.db, refreshToken, ctx.now());
    if (!outcome.ok) {
      if (outcome.reason === 'reused') {
        req.log.warn({ tokenHash: sha256(refreshToken).slice(0, 12) }, 'refresh token reused; family revoked');
        await ctx.audit(null, 'auth.refresh_reuse', { tokenHash: sha256(refreshToken).slice(0, 12) });
      }
      throw new HttpError(401, 'session_expired', 'Sign in again to continue.');
    }
    return outcome.tokens;
  });

  app.post('/v1/auth/logout', { preHandler: requireUser(ctx) }, async (req, reply) => {
    const auth = req.auth!;
    await revokeFamily(ctx.db, auth.familyId, ctx.now(), 'logout');
    await ctx.audit(auth.userId, 'auth.signout');
    return reply.code(204).send();
  });
}
