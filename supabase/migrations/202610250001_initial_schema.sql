-- Apolo's Loyalty initial schema.
-- RLS is enabled and no permissive client policies are added in this migration.
-- Add carefully scoped policies and server-validated RPC/Edge Functions before app integration.

create extension if not exists pgcrypto;

create type public.staff_role as enum ('admin', 'employee');
create type public.reward_status as enum ('available', 'redeemed', 'expired');
create type public.recovery_method_type as enum ('email', 'phone');

create table public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.staff_role not null default 'employee',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  display_name text,
  status text not null default 'active' check (status in ('active', 'blocked', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_recovery_methods (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  method_type public.recovery_method_type not null,
  identifier_normalized text not null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (method_type, identifier_normalized)
);

create table public.loyalty_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Apolo’s 10 visits',
  visits_required integer not null default 10 check (visits_required between 1 and 1000),
  reward_description text not null,
  is_active boolean not null default true,
  created_by uuid references public.staff_profiles(user_id) on delete set null,
  updated_by uuid references public.staff_profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index loyalty_rules_one_active_idx
  on public.loyalty_rules (is_active)
  where is_active = true;

create table public.loyalty_visits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  staff_user_id uuid not null references public.staff_profiles(user_id) on delete restrict,
  idempotency_key text not null,
  note text,
  created_at timestamptz not null default now(),
  unique (idempotency_key)
);

create index loyalty_visits_customer_created_idx
  on public.loyalty_visits (customer_id, created_at desc);

create table public.customer_rewards (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  rule_id uuid references public.loyalty_rules(id) on delete set null,
  visits_required_snapshot integer not null check (visits_required_snapshot > 0),
  reward_description_snapshot text not null,
  status public.reward_status not null default 'available',
  redemption_token_hash text unique,
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by uuid references public.staff_profiles(user_id) on delete set null,
  check (
    (status = 'redeemed' and redeemed_at is not null and redeemed_by is not null)
    or status <> 'redeemed'
  )
);

create index customer_rewards_customer_status_idx
  on public.customer_rewards (customer_id, status, issued_at desc);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_created_at_idx on public.audit_log (created_at desc);
create index audit_log_entity_idx on public.audit_log (entity_type, entity_id);

alter table public.staff_profiles enable row level security;
alter table public.customers enable row level security;
alter table public.customer_recovery_methods enable row level security;
alter table public.loyalty_rules enable row level security;
alter table public.loyalty_visits enable row level security;
alter table public.customer_rewards enable row level security;
alter table public.audit_log enable row level security;

-- Intentionally no broad policies here. Until explicit policies and server-side
-- functions are implemented, clients cannot access these tables through RLS.
-- Follow-up migration must add safe staff/customer access and atomic operations.
