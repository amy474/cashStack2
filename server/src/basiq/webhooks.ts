import { createHmac } from 'node:crypto';
import { safeEqual } from '../crypto.ts';

/// Basiq signs each delivery with HMAC-SHA256 over "<id>.<timestamp>.<raw body>",
/// keyed with the base64 part of the endpoint's whsec_ secret. The signature
/// header can carry several "v1,<base64>" entries (during secret rotation);
/// any one matching is enough. Deliveries more than five minutes off the
/// server clock are refused, which stops a captured one being replayed later.

export const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;

export type WebhookHeaders = {
  id?: string;
  timestamp?: string;
  signature?: string;
};

export type Verification = { ok: true } | { ok: false; reason: 'missing-headers' | 'stale' | 'bad-signature' };

export function signWebhook(secret: string, id: string, timestamp: string, body: string): string {
  const key = Buffer.from(secret.startsWith('whsec_') ? secret.slice(6) : secret, 'base64');
  return createHmac('sha256', key).update(`${id}.${timestamp}.${body}`).digest('base64');
}

export function verifyWebhook(secret: string, headers: WebhookHeaders, rawBody: string, nowSeconds: number): Verification {
  const { id, timestamp, signature } = headers;
  if (!id || !timestamp || !signature) return { ok: false, reason: 'missing-headers' };
  const sent = Number(timestamp);
  if (!Number.isFinite(sent) || Math.abs(nowSeconds - sent) > WEBHOOK_TOLERANCE_SECONDS) return { ok: false, reason: 'stale' };
  const expected = signWebhook(secret, id, timestamp, rawBody);
  const matched = signature
    .split(' ')
    .map((entry) => entry.split(','))
    .some(([version, sig]) => version === 'v1' && sig !== undefined && safeEqual(sig, expected));
  return matched ? { ok: true } : { ok: false, reason: 'bad-signature' };
}

/// The Basiq user a webhook is about, from links.eventEntity
/// (".../users/<id>" or ".../users/<id>/connections/<id>").
export function basiqUserFromEvent(event: { links?: { eventEntity?: string } }): string | undefined {
  return /\/users\/([A-Za-z0-9_-]+)/.exec(event.links?.eventEntity ?? '')?.[1];
}
