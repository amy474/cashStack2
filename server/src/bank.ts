import { setTimeout as sleep } from 'node:timers/promises';
import type { Ctx } from './context.ts';
import { HttpError } from './context.ts';
import type { BasiqAccount, BasiqConnection, BasiqConnector, BasiqJob } from './basiq/types.ts';
import { maskAccountNumber, toMinor } from './money.ts';

/// What the app is told about an account. Deliberately thin: no full account
/// number, no BSB, no holder name, no transactions — only what it takes to
/// draw the balance as cash and say which account it is.
export type AccountOut = {
  id: string;
  connectionId: string | null;
  institution: InstitutionOut;
  name: string;
  maskedNumber: string;
  type: 'transaction' | 'savings';
  availableMinor: number;
  balanceMinor: number | null;
  currency: 'AUD';
  lastUpdated: string | null;
};

export type InstitutionOut = { id: string; name: string; color: string | null };

export type ConnectionOut = {
  id: string;
  institution: InstitutionOut;
  status: string;
  expiresAt: string | null;
  lastUsed: string | null;
};

/// Money you can hold as cash: everyday and savings accounts in dollars.
/// Cards, loans and mortgages are shared by the bank but never shown.
const CASH_ACCOUNTS = new Set(['transaction', 'savings']);

export async function basiqUserId(ctx: Ctx, userId: string): Promise<string | null> {
  const { rows } = await ctx.db.query<{ basiq_user_id: string | null }>('select basiq_user_id from users where id = $1', [userId]);
  if (!rows[0]) throw new HttpError(401, 'unauthorized', 'Sign in again to continue.');
  return rows[0].basiq_user_id;
}

/// The Basiq user for this person, made the first time they connect a bank.
/// The row is locked meanwhile so two taps can't make two Basiq users.
export async function ensureBasiqUser(ctx: Ctx, userId: string): Promise<string> {
  let created = false;
  const id = await ctx.db.tx(async (t) => {
    const { rows } = await t.query<{ basiq_user_id: string | null; email: string | null }>(
      'select basiq_user_id, email from users where id = $1 for update',
      [userId],
    );
    const row = rows[0];
    if (!row) throw new HttpError(401, 'unauthorized', 'Sign in again to continue.');
    if (row.basiq_user_id) return row.basiq_user_id;
    if (!row.email) {
      throw new HttpError(409, 'email_required', 'Sign in with Apple again and share an email, so your bank connection can be set up.');
    }
    const user = await ctx.basiq.createUser({ email: row.email });
    await t.query('update users set basiq_user_id = $2 where id = $1', [userId, user.id]);
    created = true;
    return user.id;
  });
  if (created) await ctx.audit(userId, 'bank.user_created');
  return id;
}

export function institutionsById(connectors: BasiqConnector[]): Map<string, InstitutionOut> {
  const map = new Map<string, InstitutionOut>();
  for (const c of connectors) {
    // A bank can have a screen-scraping and an open-banking connector under
    // one id; either carries the same name.
    if (map.has(c.id) && c.method !== 'open-banking') continue;
    map.set(c.id, {
      id: c.id,
      name: c.institution?.shortName || c.institution?.name || c.id,
      color: /^#[0-9a-f]{6}$/i.test(c.institution?.logo?.colors?.primary ?? '') ? c.institution!.logo!.colors!.primary! : null,
    });
  }
  return map;
}

function institution(map: Map<string, InstitutionOut>, id: string | undefined): InstitutionOut {
  return (id && map.get(id)) || { id: id ?? 'unknown', name: 'Your bank', color: null };
}

export function toAccountOut(a: BasiqAccount, institutions: Map<string, InstitutionOut>): AccountOut | null {
  const type = a.class?.type ?? '';
  if (!CASH_ACCOUNTS.has(type)) return null;
  if ((a.currency ?? 'AUD') !== 'AUD') return null;
  if (a.status && a.status !== 'available') return null;
  const available = toMinor(a.availableFunds) ?? toMinor(a.balance);
  if (available === null) return null;
  return {
    id: a.id,
    connectionId: a.connection ?? null,
    institution: institution(institutions, a.institution),
    name: (a.displayName || a.name || a.class?.product || 'Account').slice(0, 60),
    maskedNumber: maskAccountNumber(a.maskedNumber, a.accountNo),
    type: type as AccountOut['type'],
    availableMinor: available,
    balanceMinor: toMinor(a.balance),
    currency: 'AUD',
    lastUpdated: a.lastUpdated ?? null,
  };
}

export function toConnectionOut(c: BasiqConnection, institutions: Map<string, InstitutionOut>): ConnectionOut {
  return {
    id: c.id,
    institution: institution(institutions, c.institution?.id),
    status: c.status ?? 'unknown',
    expiresAt: c.expiryDate ?? null,
    lastUsed: c.lastUsed ?? null,
  };
}

const ACCOUNTS_TTL_MS = 60_000;

/// Accounts are read from Basiq each time (with a minute's grace), never
/// stored here.
export async function accountsFor(ctx: Ctx, userId: string, opts: { fresh?: boolean } = {}): Promise<AccountOut[]> {
  const basiqUser = await basiqUserId(ctx, userId);
  if (!basiqUser) return [];
  const cached = ctx.accountsCache.get(userId);
  if (!opts.fresh && cached && Date.now() - cached.at < ACCOUNTS_TTL_MS) return cached.value as AccountOut[];
  const [accounts, connectors] = await Promise.all([ctx.basiq.listAccounts(basiqUser), ctx.basiq.listConnectors()]);
  const institutions = institutionsById(connectors);
  const value = accounts.map((a) => toAccountOut(a, institutions)).filter((a): a is AccountOut => a !== null);
  ctx.accountsCache.set(userId, { at: Date.now(), value });
  return value;
}

export type JobState = 'ready' | 'pending' | 'failed';

/// A connection job is done, as far as the wallet cares, once the accounts
/// are in; transactions can keep loading behind it.
export function jobState(job: BasiqJob): JobState {
  const step = (title: string) => job.steps.find((s) => s.title === title);
  if (step('verify-credentials')?.status === 'failed' || step('retrieve-accounts')?.status === 'failed') return 'failed';
  return step('retrieve-accounts')?.status === 'success' ? 'ready' : 'pending';
}

export type WaitResult = {
  status: JobState;
  failures: Array<{ title: string; detail?: string }>;
};

/// Poll jobs until each has its accounts or has failed, or time runs out.
/// Jobs that turn out to belong to someone else are dropped, so a doctored
/// redirect can't be used to peek at another person's connection.
export async function waitForJobs(ctx: Ctx, userId: string, basiqUser: string, jobIds: string[], timeoutMs: number): Promise<WaitResult> {
  const deadline = Date.now() + timeoutMs;
  const open = new Set(jobIds);
  const failures: WaitResult['failures'] = [];
  let ready = 0;
  while (open.size > 0) {
    for (const id of [...open]) {
      const job = await ctx.basiq.getJob(id);
      if (!job.links?.source?.includes(`/users/${basiqUser}/`)) {
        open.delete(id);
        continue;
      }
      const state = jobState(job);
      if (state === 'pending') continue;
      open.delete(id);
      if (state === 'ready') ready++;
      else {
        const result = job.steps.find((s) => s.status === 'failed')?.result;
        failures.push({ title: result?.title ?? 'Your bank could not be reached', detail: result?.detail });
      }
    }
    if (open.size === 0 || Date.now() + ctx.pollIntervalMs > deadline) break;
    await sleep(ctx.pollIntervalMs);
  }
  ctx.accountsCache.delete(userId);
  const status: JobState = open.size > 0 ? 'pending' : ready === 0 && failures.length > 0 ? 'failed' : 'ready';
  return { status, failures };
}
