import Fastify, { type FastifyError, type FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { ZodError } from 'zod';
import { Alerts, webhookSink } from './alerts.ts';
import { FakeBasiq } from './basiq/fake.ts';
import { BasiqError } from './basiq/types.ts';
import { HttpError, type Ctx, type Deps } from './context.ts';
import { authRoutes } from './routes/auth.ts';
import { bankRoutes } from './routes/bank.ts';
import { diagnosticsRoutes } from './routes/diagnostics.ts';
import { pageRoutes } from './routes/pages.ts';
import { statusRoutes } from './routes/status.ts';
import { webhookRoutes } from './routes/webhooks.ts';

export async function buildApp(deps: Deps, opts: { logger?: boolean } = {}): Promise<FastifyInstance> {
  const production = deps.config.env === 'production';
  const app = Fastify({
    logger: opts.logger === false ? false : {
      level: deps.config.logLevel,
      redact: { paths: ['req.headers.authorization', 'req.headers.cookie'], remove: true },
      serializers: {
        // Paths only: query strings can carry consent state.
        req: (req) => ({ method: req.method, path: req.url.split('?')[0], reqId: req.id }),
      },
    },
    bodyLimit: 16 * 1024,
    // Fly's proxy terminates TLS and appends the client to X-Forwarded-For.
    // Trusting exactly that one hop means a client can't put a made-up
    // address in front and dodge the per-IP rate limits.
    trustProxy: production ? (_address: string, hop: number) => hop < 1 : false,
  });

  const ctx: Ctx = {
    ...deps,
    now: deps.now ?? (() => new Date()),
    pollIntervalMs: deps.pollIntervalMs ?? 1500,
    accountsCache: new Map(),
    alerts: new Alerts(deps.alertSink ?? (deps.config.alertWebhookUrl ? webhookSink(deps.config.alertWebhookUrl, app.log) : undefined)),
    async audit(userId, event, detail = {}) {
      await deps.db.query('insert into audit_log (user_id, event, detail, at) values ($1, $2, $3::jsonb, $4)', [
        userId,
        event,
        JSON.stringify(detail),
        (deps.now ?? (() => new Date()))(),
      ]);
    },
  };

  await app.register(rateLimit, { global: true, max: 300, timeWindow: '1 minute' });

  app.addHook('onSend', async (_req, reply, payload) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Referrer-Policy', 'no-referrer');
    reply.header('X-Frame-Options', 'DENY');
    reply.header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'");
    if (production) reply.header('Strict-Transport-Security', 'max-age=63072000; includeSubDomains');
    return payload;
  });

  app.setErrorHandler((error: FastifyError | Error, req, reply) => {
    if (error instanceof HttpError) {
      return reply.code(error.status).send({ error: error.code, message: error.message });
    }
    if (error instanceof ZodError) {
      return reply.code(400).send({ error: 'invalid_request', message: 'Some of that request was not as expected.' });
    }
    if (error instanceof BasiqError) {
      req.log.error({ status: error.status, code: error.code, correlationId: error.correlationId }, 'basiq error');
      return reply.code(502).send({ error: 'bank_unavailable', message: "Your bank connection isn't responding right now. Try again in a minute." });
    }
    const status = (error as FastifyError).statusCode;
    if (status && status >= 400 && status < 500) {
      return reply.code(status).send({ error: status === 429 ? 'rate_limited' : 'invalid_request', message: status === 429 ? 'Slow down a little and try again.' : 'That request was not understood.' });
    }
    req.log.error({ err: error }, 'unhandled error');
    // The route and the kind of error only: messages can carry data.
    const route = `${req.method} ${req.routeOptions.url ?? 'unknown route'}`;
    ctx.alerts.notify(`error:${route}:${error.name}`, `CashStack API: ${error.name} on ${route} (request ${req.id}). Details in \`fly logs\`.`);
    return reply.code(500).send({ error: 'server_error', message: 'Something went wrong on our side.' });
  });

  app.setNotFoundHandler((_req, reply) => reply.code(404).send({ error: 'not_found', message: 'Nothing here.' }));

  // First, so its gate sits in front of every route after it.
  statusRoutes(app, ctx);
  authRoutes(app, ctx);
  bankRoutes(app, ctx);
  diagnosticsRoutes(app, ctx);
  webhookRoutes(app, ctx);
  pageRoutes(app, ctx, deps.basiq instanceof FakeBasiq && !production ? deps.basiq : undefined);

  return app;
}
