import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Ctx } from '../context.ts';

/// Every request from the app says which build it is (CFBundleVersion).
export const BUILD_HEADER = 'x-cashstack-build';

/// Paths the gate never closes: the status check itself, crash reports (the
/// builds being turned away are the ones whose crashes matter most), Basiq's
/// webhooks, and Basiq's redirect back from its consent screens, which comes
/// from a browser rather than the app.
const ALWAYS_OPEN = new Set(['/v1/status', '/v1/diagnostics', '/v1/webhooks/basiq', '/v1/consent/return']);

/// A build that doesn't say which it is counts as older than any minimum.
export function appBuild(req: FastifyRequest): number {
  const value = req.headers[BUILD_HEADER];
  const build = Number.parseInt(Array.isArray(value) ? (value[0] ?? '') : (value ?? ''), 10);
  return Number.isSafeInteger(build) && build >= 0 ? build : 0;
}

const UPGRADE_MESSAGE = 'This version of CashStack is out of date. Update it to keep going.';

/// Two switches that don't need a new app to flip: turn away builds older
/// than MIN_APP_BUILD (a build that mishandles data can be stopped the day
/// it's found), and turn everything away with MAINTENANCE_MESSAGE while the
/// server or Basiq is being worked on. `fly secrets set` flips either one.
export function statusRoutes(app: FastifyInstance, ctx: Ctx) {
  const { minBuild, updateUrl, maintenance } = ctx.config.app;

  app.addHook('onRequest', async (req, reply) => {
    const path = req.url.split('?')[0] ?? '';
    if (!path.startsWith('/v1/') || ALWAYS_OPEN.has(path)) return;
    if (maintenance) {
      reply.header('Retry-After', '300');
      return reply.code(503).send({ error: 'maintenance', message: maintenance });
    }
    if (appBuild(req) < minBuild) {
      return reply.code(426).send({ error: 'upgrade_required', message: UPGRADE_MESSAGE, updateUrl: updateUrl ?? null });
    }
  });

  /// What the app asks at launch and whenever it comes back to the front, so
  /// it can say "update" or "down for maintenance" before anyone signs in.
  app.get('/v1/status', async () => ({
    minBuild,
    updateUrl: updateUrl ?? null,
    maintenance: maintenance ? { message: maintenance } : null,
  }));
}
