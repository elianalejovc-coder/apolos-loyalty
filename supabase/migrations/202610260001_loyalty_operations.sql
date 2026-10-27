-- Apolo's Loyalty operational layer.
-- Builds on 202610250001_initial_schema.sql.
-- Sensitive work is performed by SECURITY DEFINER helpers in private schema,
-- with small authenticated wrappers exposed through public RPC.

create schema if not exists private;

alter type public.staff_role add value if not exists 'manager';

alter table public.customers
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create unique index if not exists customers_auth_user_id_uidx
  on public.customers(auth_user_id)
  where auth_user_id is not null;

alter table public.loyalty_visits
  add column if not exists cycle_number integer not null default 1 check (cycle_number > 0),
  add column if not exists visit_reference text not null default ('VIS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
  add column if not exists reversal_of uuid references public.loyalty_visits(id) on delete restrict;

create unique index if not exists loyalty_visits_reference_uidx
  on public.loyalty_visits(visit_reference);

create unique index if not exists loyalty_visits_reversal_uidx
  on public.loyalty_visits(reversal_of)
  where reversal_of is not null;

alter table public.customer_rewards
  add column if not exists cycle_number integer not null default 1 check (cycle_number > 0);

create unique index if not exists customer_rewards_one_available_idx
  on public.customer_rewards(customer_id)
  where status = 'available';

create index if not exists loyalty_visits_customer_cycle_idx
  on public.loyalty_visits(customer_id, cycle_number, created_at desc);

create or replace function private.current_staff_role()
returns public.staff_role
language sql
stable
security definer
set search_path = ''
as $$
  select sp.role
  from public.staff_profiles sp
  where sp.user_id = (select auth.uid())
    and sp.is_active = true
  limit 1;
$$;

revoke all on function private.current_staff_role() from public;
grant execute on function private.current_staff_role() to authenticated;

after? 
