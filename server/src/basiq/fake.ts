import { randomUUID } from 'node:crypto';
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

type FakeUser = {
  id: string;
  email?: string;
  connections: BasiqConnection[];
  accounts: BasiqAccount[];
  consents: BasiqConsent[];
};

type FakeJob = { id: string; userId: string; connectionId: string; polls: number; fail: boolean };

/// An in-memory stand-in for Basiq, for development and the tests. It behaves
/// the way the real thing does where the server depends on it — jobs take a
/// poll or two to finish, ids are opaque, unknown users are 404s — and serves
/// a pretend consent screen so the whole app flow runs without an API key.
/// Production refuses to start in this mode.
export class FakeBasiq implements BasiqClient {
  readonly users = new Map<string, FakeUser>();
  private readonly tokens = new Map<string, string>();
  private readonly jobs = new Map<string, FakeJob>();
  /// How many times a job reports in-progress before it finishes.
  jobPolls = 1;
  /// Calls made, for tests that care what reached "Basiq".
  readonly calls: string[] = [];

  private readonly consentPageUrl: string;

  constructor(consentPageUrl: string) {
    this.consentPageUrl = consentPageUrl;
  }

  async createUser(input: { email?: string; mobile?: string }) {
    this.calls.push('createUser');
    if (!input.email && !input.mobile) throw new BasiqError(400, 'email or mobile is required');
    const id = randomUUID();
    this.users.set(id, { id, email: input.email, connections: [], accounts: [], consents: [] });
    return { id };
  }

  async deleteUser(userId: string) {
    this.calls.push('deleteUser');
    if (!this.users.delete(userId)) throw new BasiqError(404, 'User not found');
  }

  async clientToken(userId: string) {
    this.user(userId);
    const token = `fake-client-${randomUUID()}`;
    this.tokens.set(token, userId);
    return token;
  }

  consentUrl(input: { token: string; action: ConsentAction; state: string; connectionId?: string }) {
    const url = new URL(this.consentPageUrl);
    url.searchParams.set('token', input.token);
    url.searchParams.set('action', input.action);
    url.searchParams.set('state', input.state);
    if (input.connectionId) url.searchParams.set('connectionId', input.connectionId);
    return url.toString();
  }

  async getJob(jobId: string): Promise<BasiqJob> {
    const job = this.jobs.get(jobId);
    if (!job) throw new BasiqError(404, 'Job not found');
    const done = job.polls >= this.jobPolls;
    job.polls += 1;
    const accounts = !done ? 'in-progress' : job.fail ? 'failed' : 'success';
    return {
      id: job.id,
      steps: [
        { title: 'verify-credentials', status: 'success', result: { type: 'link', url: `/users/${job.userId}/connections/${job.connectionId}` } },
        {
          title: 'retrieve-accounts',
          status: accounts,
          result: accounts === 'failed' ? { type: 'error', code: 'service-unavailable', title: 'Hooli is not responding', detail: 'Try again in a few minutes.' } : null,
        },
        { title: 'retrieve-transactions', status: 'pending', result: null },
      ],
      links: { source: `https://au-api.basiq.io/users/${job.userId}/connections/${job.connectionId}` },
    };
  }

  async listAccounts(userId: string) {
    this.calls.push('listAccounts');
    return this.user(userId).accounts;
  }

  async listConnections(userId: string) {
    return this.user(userId).connections;
  }

  async deleteConnection(userId: string, connectionId: string) {
    this.calls.push('deleteConnection');
    const user = this.user(userId);
    if (!user.connections.some((c) => c.id === connectionId)) throw new BasiqError(404, 'Connection not found');
    user.connections = user.connections.filter((c) => c.id !== connectionId);
    user.accounts = user.accounts.filter((a) => a.connection !== connectionId);
  }

  async refreshConnections(userId: string) {
    this.calls.push('refreshConnections');
    const user = this.user(userId);
    return user.connections.map((c) => this.addJob(user.id, c.id, false));
  }

  async listConsents(userId: string) {
    return this.user(userId).consents;
  }

  async listConnectors(): Promise<BasiqConnector[]> {
    return [
      {
        id: 'AU00000',
        method: 'open-banking',
        institution: { name: 'Hooli Bank', shortName: 'Hooli', logo: { colors: { primary: '#5B2EFF' } } },
      },
    ];
  }

  // MARK: The pretend consent screen

  /// Who a consent-screen token belongs to, or undefined if it's not one of ours.
  userForToken(token: string): string | undefined {
    return this.tokens.get(token);
  }

  /// What pressing "Share" does: connect Hooli with an everyday account, a
  /// savings account, and two the wallet should ignore.
  approve(token: string, options: { fail?: boolean } = {}): { jobId: string } {
    const userId = this.tokens.get(token);
    if (!userId) throw new BasiqError(401, 'Unknown consent token');
    this.tokens.delete(token);
    const user = this.user(userId);
    const connectionId = randomUUID().slice(0, 8);
    const now = new Date();
    const expiry = new Date(now.getTime() + 365 * 86_400_000).toISOString();
    user.connections.push({
      id: connectionId,
      status: 'active',
      method: 'openbanking',
      createdDate: now.toISOString(),
      expiryDate: expiry,
      lastUsed: now.toISOString(),
      institution: { id: 'AU00000' },
    });
    if (!user.consents.some((c) => c.status === 'active')) {
      user.consents.push({ id: randomUUID(), status: 'active', created: now.toISOString(), expiryDate: expiry });
    }
    const n = user.connections.length;
    const account = (suffix: string, fields: Partial<BasiqAccount>): BasiqAccount => ({
      id: `${connectionId}-${suffix}`,
      connection: connectionId,
      institution: 'AU00000',
      currency: 'AUD',
      status: 'available',
      lastUpdated: now.toISOString(),
      ...fields,
    });
    if (!options.fail) {
      user.accounts.push(
        account('everyday', { name: n > 1 ? `Everyday ${n}` : 'Everyday', accountNo: '063000 1234 1965', availableFunds: '1284.35', balance: '1290.10', class: { type: 'transaction', product: 'Hooli Everyday' } }),
        account('saver', { name: 'Bonus Saver', maskedNumber: 'xxxx-xxxx-8802', availableFunds: '5020.00', balance: '5020.00', class: { type: 'savings', product: 'Hooli Bonus Saver' } }),
        account('card', { name: 'Platinum Card', accountNo: '5520000000004417', availableFunds: '8000.00', balance: '-412.50', class: { type: 'credit-card' } }),
        account('home', { name: 'Home Loan', accountNo: '600000157441965', availableFunds: '0.00', balance: '-412000.00', class: { type: 'mortgage' } }),
      );
    }
    return { jobId: this.addJob(userId, connectionId, Boolean(options.fail)) };
  }

  private addJob(userId: string, connectionId: string, fail: boolean) {
    const id = randomUUID();
    this.jobs.set(id, { id, userId, connectionId, polls: 0, fail });
    return id;
  }

  private user(userId: string): FakeUser {
    const user = this.users.get(userId);
    if (!user) throw new BasiqError(404, 'User not found');
    return user;
  }
}
