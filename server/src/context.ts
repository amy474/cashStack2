import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Config } from './config.ts';
import type { Db } from './db.ts';
import type { BasiqClient } from './basiq/types.ts';
import type { AppleTokens, AppleVerifier } from './auth/apple.ts';
import { authenticate, type Authenticated } from './auth/sessions.ts';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: Authenticated;
  }
}

/// Everything a route needs, passed in rather than imported, so the tests can
/// build the same app around an embedded database, a fake Basiq and a clock.
export type Deps = {
  config: Config;
  db: Db;
  basiq: BasiqClient;
  verifyApple: AppleVerifier;
  appleTokens?: AppleTokens;
  now?: () => Date;
  /// Pause between job polls. Tests set it to zero.
  pollIntervalMs?: number;
};

export type Ctx = Required<Pick<Deps, 'now' | 'pollIntervalMs'>> & Deps & {
  audit(userId: string | null, event: string, detail?: Record<string, unknown>): Promise<void>;
  accountsCache: Map<string, { at: number; value: unknown }>;
};

export class HttpError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/// preHandler for every route that acts as a signed-in person.
export function requireUser(ctx: Ctx) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization ?? '';
    const match = /^Bearer ([A-Za-z0-9_-]{8,200})$/.exec(header);
    const auth = match?.[1] ? await authenticate(ctx.db, match[1], ctx.now()) : undefined;
    if (!auth) {
      reply.header('WWW-Authenticate', 'Bearer');
      throw new HttpError(401, 'unauthorized', 'Sign in again to continue.');
    }
    req.auth = auth;
  };
}

export function userId(req: FastifyRequest): string {
  if (!req.auth) throw new HttpError(401, 'unauthorized', 'Sign in again to continue.');
  return req.auth.userId;
}
