/// The parts of Basiq's v3 API the server uses, typed as loosely as Basiq is:
/// most fields can be missing, so everything that reads them copes.

export type BasiqJobStep = {
  title: string;
  status: 'pending' | 'in-progress' | 'success' | 'failed' | string;
  result?: { type?: string; code?: string; title?: string; detail?: string; url?: string } | null;
};

export type BasiqJob = {
  id: string;
  steps: BasiqJobStep[];
  links?: { self?: string; source?: string };
};

export type BasiqAccount = {
  id: string;
  name?: string;
  displayName?: string;
  accountNo?: string;
  maskedNumber?: string;
  availableFunds?: string;
  balance?: string;
  currency?: string;
  class?: { type?: string; product?: string };
  connection?: string;
  institution?: string;
  lastUpdated?: string;
  status?: string;
};

export type BasiqConnection = {
  id: string;
  status?: string;
  method?: string;
  createdDate?: string;
  expiryDate?: string;
  lastUsed?: string;
  institution?: { id?: string };
};

export type BasiqConsent = {
  id: string;
  status?: string;
  created?: string;
  expiryDate?: string;
  revoked?: string;
};

export type BasiqConnector = {
  id: string;
  method?: string;
  institution?: {
    name?: string;
    shortName?: string;
    logo?: { links?: { square?: string; full?: string }; colors?: { primary?: string } };
  };
};

export type ConsentAction = 'connect' | 'manage' | 'extend';

export interface BasiqClient {
  createUser(input: { email?: string; mobile?: string }): Promise<{ id: string }>;
  deleteUser(userId: string): Promise<void>;
  /// A CLIENT_ACCESS token bound to one Basiq user, for the consent screens.
  clientToken(userId: string): Promise<string>;
  consentUrl(input: { token: string; action: ConsentAction; state: string; connectionId?: string }): string;
  getJob(jobId: string): Promise<BasiqJob>;
  listAccounts(userId: string): Promise<BasiqAccount[]>;
  listConnections(userId: string): Promise<BasiqConnection[]>;
  deleteConnection(userId: string, connectionId: string): Promise<void>;
  refreshConnections(userId: string): Promise<string[]>;
  listConsents(userId: string): Promise<BasiqConsent[]>;
  listConnectors(): Promise<BasiqConnector[]>;
}

export class BasiqError extends Error {
  readonly status: number;
  readonly code?: string;
  readonly correlationId?: string;

  constructor(status: number, message: string, code?: string, correlationId?: string) {
    super(message);
    this.name = 'BasiqError';
    this.status = status;
    this.code = code;
    this.correlationId = correlationId;
  }
}
