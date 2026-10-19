-- CashStack keeps as little as it can. No balances, account numbers or
-- transactions are stored here: they stay with Basiq and are read on demand,
-- so withdrawing consent leaves nothing behind on this side to clean up.

create table users (
  id uuid primary key,
  -- Apple's stable identifier for this person in this app.
  apple_sub text unique,
  -- Only for development sign-in; never set in production.
  dev_key text unique,
  -- From Sign in with Apple. Often a private relay address. Given to Basiq,
  -- which needs an email or mobile to create its user.
  email text,
  basiq_user_id text unique,
  -- AES-256-GCM sealed. Lets account deletion revoke the Apple sign-in.
  apple_refresh_token_sealed text,
  last_bank_refresh_at timestamptz,
  created_at timestamptz not null default now()
);

-- One row per issued token pair. Refreshing replaces the row with a new one in
-- the same family; presenting a refresh token that was already replaced means
-- it leaked, so the whole family is revoked.
create table sessions (
  id uuid primary key,
  user_id uuid not null references users (id) on delete cascade,
  family_id uuid not null,
  access_hash text not null unique,
  access_expires_at timestamptz not null,
  refresh_hash text not null unique,
  refresh_expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  device text,
  created_at timestamptz not null default now()
);
create index sessions_family on sessions (family_id);
create index sessions_user on sessions (user_id);

-- A trip through Basiq's consent screens. The state value is single-use and
-- short-lived; only its hash is kept.
create table consent_sessions (
  id uuid primary key,
  user_id uuid not null references users (id) on delete cascade,
  state_hash text not null unique,
  action text not null,
  job_ids jsonb not null default '[]',
  outcome text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  returned_at timestamptz
);
create index consent_sessions_user on consent_sessions (user_id);

-- Webhook ids already handled, so a redelivery is acknowledged, not re-run.
create table webhook_deliveries (
  id text primary key,
  event_type text,
  received_at timestamptz not null default now()
);

-- What happened, when, to whom — ids only, never financial data. Kept after
-- an account is deleted (no foreign key) as the record CDR expects.
create table audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  event text not null,
  detail jsonb not null default '{}',
  at timestamptz not null default now()
);
create index audit_log_user on audit_log (user_id, at);
