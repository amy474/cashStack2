# Going live

Everything in the repo runs end to end today against a fake Basiq. Moving real
people's banks onto it takes accounts, agreements and keys that only the
business can hold. This is that list, in order.

## 1. Basiq — sandbox first

1. Sign up at [dashboard.basiq.io](https://dashboard.basiq.io) and create an
   application. Create an API key and keep it somewhere safe; it is shown once.
2. In the dashboard's **Customise UI**:
   - **Redirect URL**: `https://<your-api>/v1/consent/return`
     (`https://cashstack-api.fly.dev/v1/consent/return` with the default `fly.toml`).
   - **Manage Consent URL**: `https://<your-api>/data-sharing` — the public page
     the server already serves, explaining how to stop sharing.
   - Set **Hooli OB (AU00000)** to `open-banking` to test the real CDR flow.
     Basiq's test credentials for it are on their
     [testing page](https://api.basiq.io/reference/testing).
3. **Consent policy**: CashStack only uses account names, the last four digits
   and balances. Ask for the narrowest data clusters Basiq will allow
   (account name, type and balance; account numbers and features). Transactions
   are not needed.
4. **Webhooks**: create one pointing at `https://<your-api>/v1/webhooks/basiq`
   for `consent.revoked`, `consent.expired`, `consent.warning`,
   `connection.created`, `connection.deleted`, `connection.invalidated` and
   `user.deleted`. Copy its `whsec_…` signing secret.
5. Try it locally against the sandbox:

   ```bash
   cd server && BASIQ_MODE=live BASIQ_API_KEY=… BASIQ_WEBHOOK_SECRET=whsec_… DEV_LOGIN=1 npm run dev
   ```

   Basiq can't redirect back to `127.0.0.1`, so for the full round trip use the
   deployed API (step 3) or a tunnel, and point a Debug build at it with
   `-apiBaseURL https://…`.

## 2. Consumer Data Right — the agreement

CashStack doesn't hold its own CDR accreditation; it receives data as Basiq's
**CDR representative**. Before any real customer connects:

- Sign Basiq's CDR representative arrangement. Basiq's onboarding team walks
  through the obligations; their go-live checklist asks for a UX review too.
- Finish the **CDR policy**, **privacy policy** and **terms**. Drafts are in
  `server/pages` and already served at `/cdr-policy`, `/privacy` and `/terms`;
  `/support` is the help page. Fill in `server/pages/details.json` (business
  name, ABN, support email, postal address, state), then work through every
  highlighted `[[…]]` gap — several are questions for Basiq — and have a
  lawyer read all three. Until nothing is highlighted, each page carries a
  **Draft** notice and the server logs `public pages still have gaps to fill`
  at startup.
- Remove the sandbox test users from the Basiq app before production is
  switched on — they become billable.

What the build already does towards those obligations:

| Obligation | Where |
|---|---|
| Explain what's shared, with whom, and how to stop, before consent | `ConnectStep` in `Onboarding/OnboardingFlow.swift` |
| Let people withdraw consent in the app | Accounts › Data sharing: **Stop sharing**, **Manage data sharing** (Basiq's dashboard, `action=manage`) |
| Prompt before consent expires | **Extend sharing** appears in the last 30 days (`action=extend`) |
| Delete data when consent ends | Nothing to delete: balances are read on demand and never stored. Webhooks drop cached balances at once. |
| Delete everything on request | **Delete my account and data** deletes the Basiq user (all connections and data) and every row on our side |
| Keep records | `audit_log` — ids and events only, retained after deletion |
| Data minimisation | The server sends the app account name, last four digits and balances; cards, loans and mortgages are filtered out |

## 3. Fly.io, Sydney

```bash
cd server
fly launch --no-deploy --copy-config      # takes the app name from fly.toml
fly postgres create --region syd          # or Fly Managed Postgres / any Postgres in Sydney
fly postgres attach <db-app-name>         # sets DATABASE_URL
fly secrets set \
  BASIQ_API_KEY=… \
  BASIQ_WEBHOOK_SECRET=whsec_… \
  DATA_KEY=$(openssl rand -base64 32)
fly deploy                                # runs migrations, then rolls out
```

The server refuses to start in production without `DATABASE_URL`,
`BASIQ_WEBHOOK_SECRET` and `DATA_KEY`, with `BASIQ_MODE` anything but `live`,
or with `DEV_LOGIN` set. If you pick another app name, change `PUBLIC_URL` in
`fly.toml` and `CASHSTACK_API_URL` (Release) in the Xcode project to match.

## 4. Apple

1. **Sign in with Apple**: the entitlement is in `Config/CashStack.entitlements`.
   Automatic signing adds the capability to the App ID on the next device build.
2. **Token revocation on account deletion** (App Store guideline 5.1.1(v)):
   in Certificates, Identifiers & Profiles create a **Sign in with Apple key**,
   then:

   ```bash
   fly secrets set APPLE_TEAM_ID=URYQTTYR57 APPLE_KEY_ID=… APPLE_PRIVATE_KEY="$(cat AuthKey_….p8)"
   ```

   Without it, sign-in works, but deleting an account can't revoke the
   Sign in with Apple grant.
3. **Private email relay**: most people hide their email, and Basiq gets the
   relay address. If Basiq emails consumers (CDR receipts, consent notices),
   register Basiq's sending domain under **Sign in with Apple for Email
   Communication**, or those emails won't arrive. Ask Basiq which domain.
4. **App Privacy**: declare *Financial Info* (account balances), *Contact
   Info → Email Address* and *Identifiers → User ID*, each linked to the user
   and used for app functionality. No tracking. These answers have to match
   `CashStack/PrivacyInfo.xcprivacy`, which the upload is checked against; if
   the app starts collecting something new, change both.
5. **App Store listing**: Privacy Policy URL
   `https://cashstack-api.fly.dev/privacy`, Support URL
   `https://cashstack-api.fly.dev/support`.
6. **App Review**: reviewers can't connect a bank. Point them at
   **Try it with pretend money** in the review notes.

## 5. Before the first real customer

- [ ] Sandbox round trip on a device: sign in with Apple, Face ID, connect
      Hooli OB, pick the account, pay at the till, stop sharing, delete account.
- [ ] Basiq webhook delivery stats show 2xx (dashboard, or
      `GET /notifications/webhooks/{id}/stats`).
- [ ] `fly logs` show no `unhandled error` lines, and no tokens or query strings.
- [ ] Basiq production switched on; sandbox users removed.
- [ ] Policies finished and reviewed: no **Draft** notice on `/privacy`,
      `/cdr-policy`, `/terms` or `/support`, and no
      `public pages still have gaps to fill` line in `fly logs`.
- [ ] Privacy Policy and Support URLs set in App Store Connect.

## What this release does not do

- **Move money.** Paying at the till and the jars are practice on the real
  balance. Real payments would need a PayTo/NPP partner (Zepto, Monoova,
  Azupay) and licensing advice.
- **Big balances.** Every note is a physics body, so a large savings balance
  makes a very large pile. Bundling above some count is the fix; it isn't
  built yet.
- **Bank app hand-off.** Some banks' CDR login can jump to their own app.
  The consent sheet is a private web session, so that hand-off may fall back
  to the bank's web login. Test with the banks your users have.
