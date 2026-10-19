import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT, type JWTVerifyGetKey } from 'jose';
import { sha256 } from '../crypto.ts';

const APPLE_ISSUER = 'https://appleid.apple.com';

export type AppleIdentity = {
  /// Apple's stable id for this person in this app.
  sub: string;
  email?: string;
  privateRelay: boolean;
};

export type AppleVerifier = (identityToken: string, rawNonce: string) => Promise<AppleIdentity>;

export class AppleAuthError extends Error {}

/// Checks a Sign in with Apple identity token: signed by one of Apple's
/// current keys, issued for this app, unexpired, and carrying the hash of the
/// nonce the app made for this sign-in. The nonce check is what stops a token
/// lifted from one sign-in being replayed into another.
export function appleVerifier(bundleId: string, keys: JWTVerifyGetKey = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`))): AppleVerifier {
  return async (identityToken, rawNonce) => {
    let payload;
    try {
      ({ payload } = await jwtVerify(identityToken, keys, {
        issuer: APPLE_ISSUER,
        audience: bundleId,
        algorithms: ['RS256'],
        maxTokenAge: '10m',
      }));
    } catch {
      throw new AppleAuthError('Identity token did not verify');
    }
    if (typeof payload.sub !== 'string' || !payload.sub) throw new AppleAuthError('Identity token has no subject');
    if (typeof payload.nonce !== 'string' || payload.nonce !== sha256(rawNonce)) {
      throw new AppleAuthError('Identity token nonce does not match');
    }
    const emailVerified = payload.email_verified === true || payload.email_verified === 'true';
    return {
      sub: payload.sub,
      email: typeof payload.email === 'string' && emailVerified ? payload.email : undefined,
      privateRelay: payload.is_private_email === true || payload.is_private_email === 'true',
    };
  };
}

/// Apple asks apps to revoke a person's Sign in with Apple tokens when they
/// delete their account. That needs a refresh token, which comes from swapping
/// the one-time authorisation code at sign-in. Both calls authenticate with a
/// short-lived client secret signed by the team's Sign in with Apple key.
export type AppleKeyConfig = { teamId: string; keyId: string; privateKey: string; bundleId: string };

export class AppleTokens {
  private readonly cfg: AppleKeyConfig;
  private readonly fetchFn: typeof fetch;

  constructor(cfg: AppleKeyConfig, fetchFn: typeof fetch = fetch) {
    this.cfg = cfg;
    this.fetchFn = fetchFn;
  }

  private async clientSecret(): Promise<string> {
    const key = await importPKCS8(this.cfg.privateKey, 'ES256');
    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.cfg.keyId })
      .setIssuer(this.cfg.teamId)
      .setSubject(this.cfg.bundleId)
      .setAudience(APPLE_ISSUER)
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(key);
  }

  /// The refresh token for this sign-in, or undefined if Apple wouldn't give one.
  async exchange(authorizationCode: string): Promise<string | undefined> {
    const res = await this.fetchFn(`${APPLE_ISSUER}/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.cfg.bundleId,
        client_secret: await this.clientSecret(),
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return undefined;
    const body = (await res.json()) as { refresh_token?: string };
    return body.refresh_token;
  }

  async revoke(refreshToken: string): Promise<boolean> {
    const res = await this.fetchFn(`${APPLE_ISSUER}/auth/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.cfg.bundleId,
        client_secret: await this.clientSecret(),
        token: refreshToken,
        token_type_hint: 'refresh_token',
      }),
      signal: AbortSignal.timeout(10_000),
    });
    return res.ok;
  }
}
