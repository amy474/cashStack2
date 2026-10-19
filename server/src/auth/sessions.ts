import { randomUUID } from 'node:crypto';
import type { Db } from '../db.ts';
import { randomToken, sha256 } from '../crypto.ts';

/// Sessions are opaque random tokens, stored only as hashes, so a database
/// leak hands nobody a working session and any session can be killed on the
/// spot. The access token is short; the refresh token is rotated on every use.

export const ACCESS_TTL_MS = 15 * 60_000;
export const REFRESH_TTL_MS = 60 * 86_400_000;

export type TokenPair = {
  accessToken: string;
  refreshToken: string;
  /// Seconds until the access token expires.
  expiresIn: number;
};

export type Authenticated = { userId: string; sessionId: string; familyId: string };

export async function issueSession(db: Db, userId: string, now: Date, opts: { familyId?: string; device?: string } = {}): Promise<TokenPair> {
  const accessToken = randomToken('csa');
  const refreshToken = randomToken('csr');
  await db.query(
    `insert into sessions (id, user_id, family_id, access_hash, access_expires_at, refresh_hash, refresh_expires_at, device, created_at)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      randomUUID(),
      userId,
      opts.familyId ?? randomUUID(),
      sha256(accessToken),
      new Date(now.getTime() + ACCESS_TTL_MS),
      sha256(refreshToken),
      new Date(now.getTime() + REFRESH_TTL_MS),
      opts.device?.slice(0, 80) ?? null,
      now,
    ],
  );
  return { accessToken, refreshToken, expiresIn: ACCESS_TTL_MS / 1000 };
}

export async function authenticate(db: Db, accessToken: string, now: Date): Promise<Authenticated | undefined> {
  const { rows } = await db.query<{ id: string; user_id: string; family_id: string }>(
    `select id, user_id, family_id from sessions
     where access_hash = $1 and access_expires_at > $2 and revoked_at is null`,
    [sha256(accessToken), now],
  );
  const row = rows[0];
  return row && { userId: row.user_id, sessionId: row.id, familyId: row.family_id };
}

export type RefreshOutcome =
  | { ok: true; userId: string; tokens: TokenPair }
  | { ok: false; reason: 'unknown' | 'expired' | 'revoked' | 'reused' };

/// Swap a refresh token for a new pair. The old pair stops working at once.
/// A refresh token that has already been swapped is a sign it was copied, so
/// every session descended from the same sign-in is revoked with it.
export async function rotate(db: Db, refreshToken: string, now: Date): Promise<RefreshOutcome> {
  return db.tx(async (t) => {
    const { rows } = await t.query<{ id: string; user_id: string; family_id: string; refresh_expires_at: Date; revoked_reason: string | null; device: string | null }>(
      `select id, user_id, family_id, refresh_expires_at, revoked_reason, device from sessions
       where refresh_hash = $1 for update`,
      [sha256(refreshToken)],
    );
    const row = rows[0];
    if (!row) return { ok: false, reason: 'unknown' } as const;
    if (row.revoked_reason === 'rotated') {
      await revokeFamily(t, row.family_id, now, 'reuse');
      return { ok: false, reason: 'reused' } as const;
    }
    if (row.revoked_reason) return { ok: false, reason: 'revoked' } as const;
    if (new Date(row.refresh_expires_at) <= now) return { ok: false, reason: 'expired' } as const;

    await t.query(`update sessions set revoked_at = $2, revoked_reason = 'rotated' where id = $1`, [row.id, now]);
    const tokens = await issueSession(t, row.user_id, now, { familyId: row.family_id, device: row.device ?? undefined });
    return { ok: true, userId: row.user_id, tokens } as const;
  });
}

export async function revokeFamily(db: Db, familyId: string, now: Date, reason: string): Promise<void> {
  await db.query(
    `update sessions set revoked_at = $2, revoked_reason = $3
     where family_id = $1 and revoked_at is null`,
    [familyId, now, reason],
  );
}
