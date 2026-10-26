# Claude instructions — Apolo's Loyalty

## Mission
Build a secure, elegant, mobile-first digital loyalty web app for Apolo's restaurant. There are two experiences sharing one backend: a customer-facing progress/rewards view and a staff/admin console.

## Product invariants
1. A public QR scan or customer page view MUST NEVER add a stamp.
2. Only authenticated, authorized staff can record a valid visit.
3. Customers can view their own progress and rewards, but cannot edit visits, stamps, reward balances, redemption state, roles, or loyalty rules.
4. Every stamp and redemption must be server-validated, auditable, and protected against duplicate requests.
5. A reward is redeemable once only. Use a cryptographically random, short-lived/one-time redemption token or code; never trust a client-supplied status.
6. Do not use invasive device fingerprinting. Use a random customer ID and secure session token; offer account recovery with verified phone OTP or email magic link. Explain that recovery is unavailable if no method has been linked.
7. Never expose Supabase service_role keys or other secrets in browser code, commits, logs, or client-visible errors.
8. Use least privilege, Supabase RLS, server-side authorization, input validation, rate limits where appropriate, and audit records.
9. Do not assume a database, Supabase project, hosting account, credentials, or Meta/WhatsApp setup already exists.
10. Do not claim a feature works until implemented and tested.

## Brand and UX
- Premium, minimal Greek-mythology theme inspired by Apollo; not childish or cluttered.
- Palette: navy #101A2B, gold #D6B36A, ivory #F6F0E4, white; success #287D5A; alert #B83D45.
- Suggested typography: Cormorant Garamond for display headings and Inter for UI.
- Subtle sun/laurel/geometric motifs; clear contrast, keyboard access, visible focus states, responsive layout.
- Customer journey should be simple and not force a long sign-up before showing useful information.

## Preferred stack
React + TypeScript + Vite; Supabase Auth/Postgres; server-side RPC or Edge Functions for sensitive mutations. Keep presentation, business logic, and database access separated.

## Working process
1. Inspect the repository and existing files before editing.
2. Start by reporting the architecture, schema, authorization model, risks, and implementation plan.
3. Implement in small, reviewable steps. Do not overwrite existing user work without inspecting it.
4. Add tests for authorization boundaries, duplicate visits, reward threshold, and one-time redemption.
5. Include setup instructions and an environment variable example with placeholders only.
6. Run available lint/typecheck/tests and report exactly what passed or failed.
7. Ask before choosing paid services or enabling public deployment.

## Definition of done for MVP
- Staff login and role checks.
- Customer profile access limited to the correct customer.
- Staff can record one valid visit per defined visit event without duplicates.
- Every 10 valid visits grants the configured reward according to a documented rule.
- Staff can redeem a reward exactly once; replay attempts fail safely.
- Audit trail for visits, reward issuance, redemption, and administrative changes.
- RLS and server-side checks are tested; no secrets in frontend or Git.
- Mobile-first customer interface and desktop-friendly staff console.
