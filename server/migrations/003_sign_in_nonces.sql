-- Each Sign in with Apple nonce is good for one sign-in. An identity token
-- lives ten minutes; without this, one copied off the wire together with its
-- nonce could be presented again in that time to get a second session.
-- Rows older than the token lifetime are cleared as new ones arrive.
create table used_sign_in_nonces (
  nonce_hash text primary key,
  used_at timestamptz not null
);
create index used_sign_in_nonces_used on used_sign_in_nonces (used_at);
