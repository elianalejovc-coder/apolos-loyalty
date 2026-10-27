# Supabase setup — Apolo’s Loyalty

## What is already in the repository

The repo now contains the Supabase local configuration, ordered migrations, seed data, pgTAP tests, and a React client that calls only the approved RPCs for sensitive operations.

Supabase migrations are applied in timestamp order. The local stack is reproducible with `supabase db reset`, which applies all migrations and then `seed.sql`.

## 1. Local development

Requirements:

- Node.js 20+
- Docker Desktop on Windows/Linux (or another Docker-compatible runtime)
- Git

From the repository root:

```bash
npm install
npx supabase start
npx supabase status
```

Copy the local Project URL and publishable key from `supabase status` into `.env.local`:

```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Then:

```bash
npm run dev
```

Open the Vite URL shown in the terminal. Local Auth email messages are captured by Mailpit; the URL is shown by `supabase status`.

## 2. Recreate the database from scratch

```bash
npm run supabase:reset
npm run supabase:test
```

The test suite is in `supabase/tests/loyalty_operations.sql` and uses pgTAP.

## 3. First administrator

The application cannot safely guess who should be an administrator.

1. Start the local app.
2. Sign in with your email using the magic link.
3. Until a staff profile exists, use the SQL editor in local Studio to call the one-time bootstrap function for your signed-in user, or use the SQL command below after replacing the UUID with your authenticated user ID:

```sql
select public.bootstrap_first_admin('Nombre del administrador');
```

The function can only succeed while `staff_profiles` is empty and requires an authenticated user.

For hosted production, create the first Auth user in Authentication > Users, sign in, and run the bootstrap RPC while authenticated.

## 4. Add staff

Create the employee/manager's Auth account first. Then an admin can create the corresponding `staff_profiles` row with:

```sql
select public.create_staff_profile(
  '<AUTH-USER-UUID>',
  'Nombre del empleado',
  'employee'
);
```

Allowed roles:

- `admin`: full staff administration and operational overrides.
- `manager`: operational overrides and visit reversals; cannot manage staff roles.
- `employee`: search customers, record valid visits, redeem rewards.

All sensitive mutations are server-side RPCs. The browser never receives a service-role key.

## 5. Hosted Supabase project

Create a Supabase project first. This repository cannot create the hosted project automatically because project provisioning requires the owner's Supabase account and billing/organization context.

After creating it:

```bash
npx supabase login
npx supabase link --project-ref <PROJECT-REF>
npx supabase db push
```

Before production, verify the remote Postgres major version with:

```sql
show server_version;
```

If the remote major version differs from the local value in `supabase/config.toml`, change `db.major_version` to match it before using the local stack.

## 6. Hosted Auth

For production customer login, configure the real Site URL and redirect URL in Supabase Authentication settings. Email magic links require email delivery configuration; the built-in hosted sender is intended for trying the product, not production volume.

Do not enable test OTPs or local-only settings in production.

## 7. Environment variables

Only these browser variables belong in `.env.local`:

```env
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Never commit `.env.local`. Never place a secret/service-role key in a `VITE_` variable.

## 8. QR behavior

The public loyalty QR must point to the customer web experience only. Scanning it does **not** create a visit.

A reward QR is generated only after the server issues a reward. The payload identifies that one reward. Redemption is server-side and changes the reward from `available` to `redeemed` atomically, so it cannot be redeemed twice.

## 9. Production checklist

Before publishing:

- [ ] Remote Supabase project created.
- [ ] `supabase db push` completes without manual SQL drift.
- [ ] `supabase migration list` is synchronized.
- [ ] RLS and table grants verified.
- [ ] First admin created.
- [ ] Employee and manager accounts tested.
- [ ] Customer magic-link recovery tested on a second device/browser.
- [ ] Duplicate visit/idempotency behavior tested.
- [ ] 12-hour duplicate-visit window tested.
- [ ] Manager/admin override tested and audited.
- [ ] Reward issuance at visit 10 tested.
- [ ] Reward redemption twice tested; second attempt must fail.
- [ ] No service-role/secret key appears in frontend source or GitHub.
- [ ] Production email delivery configured.
- [ ] Public QR verified to be read-only.

## Important limitation

This repository contains the complete **configuration and migration workflow** for Supabase, but it cannot create or link your private hosted Supabase project from GitHub alone. The project owner must create/link that hosted project and provide the project ref locally. Once linked, the migrations are the source of truth and `supabase db push` applies them in order.
