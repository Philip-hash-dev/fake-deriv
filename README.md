# TaskNest

TaskNest is a front-end and database-schema foundation for a task marketplace using KES.

## Current status: not live

This project does **not** yet have a deployed backend, configured sign-in, payment endpoints, provider webhooks, withdrawal processing, or owner dashboard. It cannot accept money, publish tasks, or pay anyone. The interface intentionally shows no sample balances or rewards and disables money actions.

The agreed product rules are:

- KES 50–200 top-ups are optional. They must never unlock tasks or withdrawals and must remain the user's own withdrawable or refundable funds.
- Tasks and reward amounts stay unpublished until a reward budget is funded and verified independently of user top-ups. The funding model is still undecided, so no task or reward data is seeded.
- Withdrawal decisions require a reason, are due within seven days, and must support an appeal.
- Stripe and M-Pesa are planned but not connected. Merchant accounts are not yet set up.

## Supabase schema foundation

`supabase/migrations/20261031000000_tasknest_financial_foundation.sql` defines private-by-default tables for profiles, funded reward campaigns, tasks, submissions, optional top-ups, an immutable-style wallet ledger, withdrawals, and withdrawal audit records. Row-level security lets signed-in users read only their own account and financial records; clients are not granted write access to financial or review tables. Tasks are readable only when published and associated with a funded campaign.

This migration is **not a complete payment or payout implementation**. Do not connect a live frontend or collect funds based on this schema alone. Before launch, implement and test authenticated server endpoints, provider signature verification and idempotency, ledger-safe balance reservations, owner-only decisions, payout reconciliation, appeal handling, and operational monitoring. Keep Supabase service-role and payment-provider secrets exclusively in server-side deployment secrets.

## Configure sign-in and sign-up

The app includes email/password sign-in and sign-up through Supabase Auth. To enable it:

1. Create a Supabase project and configure email authentication and the email-confirmation policy you want.
2. In `index.html`, set `SUPABASE_URL` to your project URL and `SUPABASE_ANON_KEY` to the project's **publishable/anon client key**. The browser client key is public by design; database access must remain protected by row-level security.
3. Serve the app from your HTTPS deployment and add that origin to Supabase's allowed redirect/site URLs. Do not rely on `file://` for deployed authentication.
4. Run the SQL migration in the Supabase SQL editor or using the Supabase CLI. Test sign-up, email confirmation, sign-in, session persistence, and sign-out.

Never put a Supabase **service-role** key, payment secret, or webhook secret in `index.html`. The current owner setup is not configured; new accounts do not become owners automatically. This frontend does not yet include password reset, an owner dashboard, or live balance/withdrawal operations.

## Required before launch

1. Decide and document the independent task-reward funding source and refund terms.
2. Set up Supabase and Vercel projects, then configure the owner identity securely in the backend.
3. Complete merchant onboarding and test Stripe and M-Pesa in their provider sandboxes.
4. Implement server-side payment creation, verified webhooks, wallet accounting, withdrawal approval/rejection with reasons, seven-day monitoring, and appeals.
5. Test security, duplicate callbacks, payment reversals, insufficient balances, owner authorization, and payout failures before enabling live money.

Never put passwords, API keys, webhook secrets, or service-role keys in browser code, this repository, or chat.
