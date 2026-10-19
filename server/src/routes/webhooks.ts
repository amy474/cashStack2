import type { FastifyInstance } from 'fastify';
import { basiqUserFromEvent, verifyWebhook } from '../basiq/webhooks.ts';
import { HttpError, type Ctx } from '../context.ts';

type BasiqEvent = { eventTypeId?: string; eventId?: string; links?: { eventEntity?: string } };

/// Basiq tells us when consent is revoked or expires, connections change, or
/// a user is deleted on their side. The server holds no CDR data, so there is
/// nothing to purge — but cached balances are dropped at once, a revoked
/// Basiq user is forgotten, and every event is written to the audit log.
export function webhookRoutes(app: FastifyInstance, ctx: Ctx) {
  // Signatures cover the exact bytes sent, so this route reads the body raw.
  app.register(async (scope) => {
    scope.addContentTypeParser('application/json', { parseAs: 'string', bodyLimit: 256 * 1024 }, (_req, body, done) => done(null, body));

    scope.post('/v1/webhooks/basiq', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (req, reply) => {
      const secret = ctx.config.basiq.webhookSecret;
      if (!secret) throw new HttpError(503, 'not_configured', 'Webhooks are not configured.');
      const raw = typeof req.body === 'string' ? req.body : '';
      const header = (name: string) => {
        const value = req.headers[name];
        return Array.isArray(value) ? value[0] : value;
      };
      const verdict = verifyWebhook(
        secret,
        { id: header('webhook-id'), timestamp: header('webhook-timestamp'), signature: header('webhook-signature') },
        raw,
        Math.floor(ctx.now().getTime() / 1000),
      );
      if (!verdict.ok) {
        req.log.warn({ reason: verdict.reason }, 'webhook rejected');
        throw new HttpError(401, 'bad_signature', 'Signature did not verify.');
      }

      let event: BasiqEvent;
      try {
        event = JSON.parse(raw) as BasiqEvent;
      } catch {
        throw new HttpError(400, 'invalid_request', 'Body is not JSON.');
      }
      const type = String(event.eventTypeId ?? 'unknown').slice(0, 64);

      // Each delivery id is handled once; a redelivery is just acknowledged.
      const fresh = await ctx.db.query('insert into webhook_deliveries (id, event_type) values ($1, $2) on conflict do nothing returning id', [
        header('webhook-id'),
        type,
      ]);
      if (fresh.rows.length === 0) return reply.code(204).send();

      const basiqUser = basiqUserFromEvent(event);
      const { rows } = basiqUser
        ? await ctx.db.query<{ id: string }>('select id from users where basiq_user_id = $1', [basiqUser])
        : { rows: [] };
      const user = rows[0]?.id ?? null;
      if (user) ctx.accountsCache.delete(user);
      if (user && type === 'user.deleted') {
        await ctx.db.query('update users set basiq_user_id = null where id = $1', [user]);
      }
      await ctx.audit(user, `webhook.${type}`, { eventId: event.eventId?.slice(0, 80) });
      return reply.code(204).send();
    });
  });
}
