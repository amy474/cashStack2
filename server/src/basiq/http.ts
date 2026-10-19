import { setTimeout as sleep } from 'node:timers/promises';
import {
  BasiqError,
  type BasiqAccount,
  type BasiqClient,
  type BasiqConnection,
  type BasiqConnector,
  type BasiqConsent,
  type BasiqJob,
  type ConsentAction,
} from './types.ts';

type Options = {
  apiKey: string;
  apiUrl: string;
  consentUrl: string;
  fetch?: typeof fetch;
  now?: () => number;
};

type List<T> = { data?: T[] };

/// Basiq v3 over HTTPS. The API key never leaves this class: it is swapped
/// for an hour-long SERVER_ACCESS token, which is cached and shared by every
/// request rather than minted per call, as Basiq asks.
export class HttpBasiqClient implements BasiqClient {
  private readonly opts: Required<Omit<Options, 'fetch' | 'now'>>;
  private readonly fetch: typeof fetch;
  private readonly now: () => number;
  private serverToken?: { value: string; expiresAt: number };
  private pendingToken?: Promise<string>;
  private connectors?: { value: BasiqConnector[]; expiresAt: number };

  constructor(options: Options) {
    this.opts = { apiKey: options.apiKey, apiUrl: options.apiUrl, consentUrl: options.consentUrl };
    this.fetch = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
  }

  // MARK: Tokens

  private async token(scope: 'SERVER_ACCESS' | 'CLIENT_ACCESS', userId?: string) {
    const form = new URLSearchParams({ scope });
    if (userId) form.set('userId', userId);
    const res = await this.send('POST', '/token', {
      // The key is used verbatim — Basiq's Basic auth is not base64(user:pass).
      headers: { Authorization: `Basic ${this.opts.apiKey}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
    });
    const body = (await res.json()) as { access_token?: string; expires_in?: number };
    if (!body.access_token) throw new BasiqError(502, 'Basiq returned no token');
    return { value: body.access_token, expiresIn: body.expires_in ?? 3600 };
  }

  private async serverAccess(): Promise<string> {
    // Renew with ten minutes to spare; concurrent callers share one request.
    if (this.serverToken && this.serverToken.expiresAt - this.now() > 10 * 60_000) return this.serverToken.value;
    this.pendingToken ??= this.token('SERVER_ACCESS')
      .then((t) => {
        this.serverToken = { value: t.value, expiresAt: this.now() + t.expiresIn * 1000 };
        return t.value;
      })
      .finally(() => {
        this.pendingToken = undefined;
      });
    return this.pendingToken;
  }

  async clientToken(userId: string): Promise<string> {
    return (await this.token('CLIENT_ACCESS', userId)).value;
  }

  consentUrl(input: { token: string; action: ConsentAction; state: string; connectionId?: string }): string {
    const url = new URL(this.opts.consentUrl);
    url.searchParams.set('token', input.token);
    url.searchParams.set('action', input.action);
    url.searchParams.set('state', input.state);
    if (input.connectionId) url.searchParams.set('connectionId', input.connectionId);
    return url.toString();
  }

  // MARK: Resources

  async createUser(input: { email?: string; mobile?: string }) {
    const body = await this.call<{ id: string }>('POST', '/users', input);
    return { id: body.id };
  }

  async deleteUser(userId: string) {
    await this.call('DELETE', `/users/${seg(userId)}`);
  }

  getJob(jobId: string) {
    return this.call<BasiqJob>('GET', `/jobs/${seg(jobId)}`);
  }

  async listAccounts(userId: string) {
    return (await this.call<List<BasiqAccount>>('GET', `/users/${seg(userId)}/accounts`)).data ?? [];
  }

  async listConnections(userId: string) {
    return (await this.call<List<BasiqConnection>>('GET', `/users/${seg(userId)}/connections`)).data ?? [];
  }

  async deleteConnection(userId: string, connectionId: string) {
    await this.call('DELETE', `/users/${seg(userId)}/connections/${seg(connectionId)}`);
  }

  async refreshConnections(userId: string) {
    const body = await this.call<List<{ id: string }>>('POST', `/users/${seg(userId)}/connections/refresh`);
    return (body.data ?? []).map((job) => job.id);
  }

  async listConsents(userId: string) {
    return (await this.call<List<BasiqConsent>>('GET', `/users/${seg(userId)}/consents`)).data ?? [];
  }

  async listConnectors() {
    // Institution names and logos change rarely; six hours is plenty fresh.
    if (this.connectors && this.connectors.expiresAt > this.now()) return this.connectors.value;
    const value = (await this.call<List<BasiqConnector>>('GET', '/connectors')).data ?? [];
    this.connectors = { value, expiresAt: this.now() + 6 * 3600_000 };
    return value;
  }

  // MARK: Transport

  private async call<T = unknown>(method: string, path: string, json?: unknown): Promise<T> {
    let token = await this.serverAccess();
    let res: Response;
    try {
      res = await this.send(method, path, {
        headers: { Authorization: `Bearer ${token}`, ...(json ? { 'Content-Type': 'application/json' } : {}) },
        body: json ? JSON.stringify(json) : undefined,
      });
    } catch (error) {
      // A token revoked early (key rotated in the dashboard) gets one retry.
      if (!(error instanceof BasiqError) || error.status !== 401) throw error;
      this.serverToken = undefined;
      token = await this.serverAccess();
      res = await this.send(method, path, {
        headers: { Authorization: `Bearer ${token}`, ...(json ? { 'Content-Type': 'application/json' } : {}) },
        body: json ? JSON.stringify(json) : undefined,
      });
    }
    if (res.status === 204) return undefined as T;
    const text = await res.text();
    return (text ? JSON.parse(text) : undefined) as T;
  }

  private async send(method: string, path: string, init: { headers: Record<string, string>; body?: string }): Promise<Response> {
    // Reads are safe to repeat; anything that changes state is sent once.
    const attempts = method === 'GET' ? 3 : 1;
    let lastError: unknown;
    for (let attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await sleep(300 * 3 ** (attempt - 1));
      try {
        const res = await this.fetch(`${this.opts.apiUrl}${path}`, {
          method,
          headers: { Accept: 'application/json', 'basiq-version': '3.0', ...init.headers },
          body: init.body,
          signal: AbortSignal.timeout(15_000),
        });
        if (res.ok) return res;
        const error = await toError(res);
        if (![429, 502, 503, 504].includes(res.status)) throw error;
        lastError = error;
        const retryAfter = Number(res.headers.get('retry-after'));
        if (retryAfter > 0 && retryAfter <= 5) await sleep(retryAfter * 1000);
      } catch (error) {
        if (error instanceof BasiqError && ![429, 502, 503, 504].includes(error.status)) throw error;
        lastError = error;
      }
    }
    if (lastError instanceof BasiqError) throw lastError;
    throw new BasiqError(503, 'Basiq is unreachable');
  }
}

/// Ids go into URL paths, so anything that isn't plainly an id is refused
/// rather than escaped into something surprising.
function seg(id: string): string {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new BasiqError(400, 'Malformed identifier');
  return id;
}

async function toError(res: Response): Promise<BasiqError> {
  let message = `Basiq responded ${res.status}`;
  let code: string | undefined;
  let correlationId: string | undefined;
  try {
    const body = (await res.json()) as { correlationId?: string; data?: Array<{ code?: string; title?: string; detail?: string }> };
    const first = body.data?.[0];
    message = first?.detail || first?.title || message;
    code = first?.code;
    correlationId = body.correlationId;
  } catch {
    // Not JSON; the status says enough.
  }
  return new BasiqError(res.status, message, code, correlationId);
}
