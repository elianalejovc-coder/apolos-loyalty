# Architecture and Security

## Proposed architecture
- Frontend: React + TypeScript + Vite.
- Identity and data: Supabase Auth + PostgreSQL.
- Sensitive mutations: PostgreSQL functions (RPC) or Supabase Edge Functions, with authorization and validation on the server.
- Hosting: choose after the MVP runs locally; Vercel is one option.
- QR code: static URL to the customer entry route; scanning is read-only.

## Logical data model
- `staff_profiles`: auth user ID, display name, role (admin/employee), active status.
- `customers`: random UUID, display name if needed, created_at, status.
- `customer_recovery_methods`: customer ID, method type, verified identifier reference, verified_at; minimize exposure of raw identifiers.
- `loyalty_visits`: customer ID, staff user ID, qualifying event/idempotency key, created_at; unique constraint prevents duplicate event stamps.
- `loyalty_rules`: visits_required, reward description, active state, updated_by, timestamps.
- `customer_rewards`: customer ID, rule snapshot, status (available/redeemed/expired), issued_at, redeemed_at, redeemed_by; one-time token stored hashed where appropriate.
- `audit_log`: actor, action, entity type/ID, timestamp, and minimal metadata; avoid logging secrets or unnecessary personal data.

## Security boundaries
- Enable RLS on every table exposed through Supabase APIs.
- Default to deny. Add explicit policies only after defining exact user roles and row ownership.
- Public/anonymous users must not be able to list customers, visits, rewards, staff, or audit entries.
- Customers must not be able to insert/update/delete visits or rewards.
- Staff operations must verify authenticated identity, active staff profile, role, and input on the server.
- Prefer narrowly scoped RPC/Edge Functions for registering visits and redeeming rewards. Perform each state transition atomically.
- Never expose the service_role key in frontend code.
- Rate-limit public recovery endpoints and avoid revealing whether an email/phone is registered.
- Use short-lived or one-time redemption tokens; store token hashes where feasible.
- Use unique constraints and transaction-safe logic for idempotency and reward issuance.
- Add tests for cross-customer access, unauthenticated calls, duplicate visit attempts, threshold races, and repeated redemption.

## Initial migration note
The first migration will create core tables and enable RLS without permissive client policies. This is intentionally secure-by-default; access policies and RPC functions must be designed and tested before the app is connected.

## Environment variables
Only public Supabase URL and anon/publishable key belong in a browser environment, e.g. `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Server secrets must be stored only in the relevant hosting/Supabase secret manager and never committed.
