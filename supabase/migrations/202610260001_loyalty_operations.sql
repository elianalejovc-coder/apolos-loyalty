-- Apolo's Loyalty operational layer.
-- Builds on 202610250001_initial_schema.sql.
-- Sensitive work is performed by SECURITY DEFINER functions with explicit role checks.
-- Customer/staff table access stays constrained by RLS; operational mutations go through RPC.

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

create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_staff_role() is not null;
$$;

revoke all on function private.is_staff() from public;
grant execute on function private.is_staff() to authenticated;

create or replace function private.require_staff()
returns public.staff_role
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role public.staff_role;
begin
  v_role := private.current_staff_role();
  if v_role is null then
    raise exception using errcode = '42501', message = 'staff_access_required';
  end if;
  return v_role;
end;
$$;

revoke all on function private.require_staff() from public;
grant execute on function private.require_staff() to authenticated;

create or replace function private.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id from public.customers c
  where c.auth_user_id = (select auth.uid()) and c.status = 'active'
  limit 1;
$$;

revoke all on function private.current_customer_id() from public;
grant execute on function private.current_customer_id() to authenticated;

-- Customer account bootstrap. This creates a customer row only for the currently authenticated user.
create or replace function public.ensure_customer_profile(p_display_name text default null)
returns public.customers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer public.customers;
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select * into v_customer
  from public.customers
  where auth_user_id = auth.uid()
  limit 1;

  if found then
    return v_customer;
  end if;

  insert into public.customers(auth_user_id, display_name)
  values (auth.uid(), v_name)
  returning * into v_customer;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'customer_profile_created', 'customer', v_customer.id::text, jsonb_build_object('source', 'customer_app'));

  return v_customer;
end;
$$;

revoke all on function public.ensure_customer_profile(text) from public;
grant execute on function public.ensure_customer_profile(text) to authenticated;

-- Staff-only customer search. It never exposes recovery identifiers.
create or replace function public.search_customers(p_search text default '')
returns table (
  customer_id uuid,
  display_name text,
  status text,
  cycle_number integer,
  visits_in_cycle integer,
  visits_required integer,
  reward_id uuid,
  reward_status public.reward_status,
  reward_description text,
  issued_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.staff_role;
  v_rule public.loyalty_rules;
  v_term text := lower(trim(coalesce(p_search, '')));
begin
  v_role := private.require_staff();
  select * into v_rule from public.loyalty_rules where is_active = true limit 1;
  if v_rule.id is null then
    raise exception using errcode = 'P0001', message = 'active_loyalty_rule_missing';
  end if;

  return query
  with matching as (
    select c.*
    from public.customers c
    where c.status <> 'deleted'
      and (v_term = '' or lower(coalesce(c.display_name, '')) like '%' || v_term || '%' or c.id::text = v_term)
    order by c.created_at desc
    limit 50
  ), latest_reward as (
    select distinct on (cr.customer_id) cr.*
    from public.customer_rewards cr
    join matching m on m.id = cr.customer_id
    order by cr.customer_id, cr.cycle_number desc, cr.issued_at desc
  ), cycles as (
    select m.id,
      case when lr.id is null then 1
           when lr.status = 'available' then lr.cycle_number
           else lr.cycle_number + 1 end as cycle_no
    from matching m left join latest_reward lr on lr.customer_id = m.id
  )
  select m.id,
         m.display_name,
         m.status,
         cy.cycle_no,
         count(lv.id)::integer,
         v_rule.visits_required,
         lr.id,
         lr.status,
         lr.reward_description_snapshot,
         lr.issued_at
  from matching m
  join cycles cy on cy.id = m.id
  left join loyalty_visits lv on lv.customer_id = m.id and lv.cycle_number = cy.cycle_no and lv.reversal_of is null
  left join latest_reward lr on lr.customer_id = m.id and lr.status = 'available'
  group by m.id, m.display_name, m.status, cy.cycle_no, v_rule.visits_required, lr.id, lr.status, lr.reward_description_snapshot, lr.issued_at
  order by m.display_name nulls last, m.created_at desc;
end;
$$;

revoke all on function public.search_customers(text) from public;
grant execute on function public.search_customers(text) to authenticated;

-- Atomic visit registration. A per-customer advisory transaction lock prevents concurrent double credits.
create or replace function public.record_visit(
  p_customer_id uuid,
  p_idempotency_key text,
  p_note text default null,
  p_override_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.staff_role;
  v_customer public.customers;
  v_rule public.loyalty_rules;
  v_existing public.loyalty_visits;
  v_last_visit timestamptz;
  v_cycle integer;
  v_count integer;
  v_visit public.loyalty_visits;
  v_reward public.customer_rewards;
  v_code text;
  v_override boolean := nullif(trim(coalesce(p_override_reason, '')), '') is not null;
begin
  v_role := private.require_staff();

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text, 817263));

  select * into v_existing from public.loyalty_visits where idempotency_key = p_idempotency_key limit 1;
  if found then
    if v_existing.customer_id <> p_customer_id then
      raise exception using errcode = '23505', message = 'idempotency_conflict';
    end if;
    select * into v_reward from public.customer_rewards
      where customer_id = p_customer_id and cycle_number = v_existing.cycle_number
      order by issued_at desc limit 1;
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'visit_id', v_existing.id,
      'visit_reference', v_existing.visit_reference,
      'cycle_number', v_existing.cycle_number,
      'visits_in_cycle', (select count(*) from public.loyalty_visits where customer_id = p_customer_id and cycle_number = v_existing.cycle_number and reversal_of is null),
      'reward_id', v_reward.id,
      'reward_status', v_reward.status,
      'reward_code', case when v_reward.id is null then null else 'APOLO-' || upper(replace(v_reward.id::text, '-', '')) end
    );
  end if;

  select * into v_customer from public.customers where id = p_customer_id and status = 'active' for update;
  if not found then raise exception using errcode = 'P0001', message = 'customer_not_found'; end if;

  select * into v_rule from public.loyalty_rules where is_active = true limit 1;
  if v_rule.id is null then raise exception using errcode = 'P0001', message = 'active_loyalty_rule_missing'; end if;

  select * into v_reward from public.customer_rewards
    where customer_id = p_customer_id and status = 'available'
    order by issued_at desc limit 1;
  if v_reward.id is not null then
    raise exception using errcode = 'P0001', message = 'reward_pending';
  end if;

  select coalesce(max(cycle_number), 1) into v_cycle from public.loyalty_visits where customer_id = p_customer_id;
  if not exists (select 1 from public.loyalty_visits where customer_id = p_customer_id and cycle_number = v_cycle and reversal_of is null) then
    v_cycle := greatest(v_cycle, 1);
  end if;

  select max(created_at) into v_last_visit
  from public.loyalty_visits
  where customer_id = p_customer_id and cycle_number = v_cycle and reversal_of is null;

  if v_last_visit is not null and v_last_visit > now() - interval '12 hours' and not v_override then
    raise exception using errcode = 'P0001', message = 'visit_too_soon';
  end if;

  if v_override and v_role not in ('admin', 'manager') then
    raise exception using errcode = '42501', message = 'override_requires_manager';
  end if;

  insert into public.loyalty_visits(customer_id, staff_user_id, idempotency_key, note, cycle_number)
  values (p_customer_id, auth.uid(), trim(nullif(p_idempotency_key, '')), nullif(trim(p_note), ''), v_cycle)
  returning * into v_visit;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'visit_recorded', 'loyalty_visit', v_visit.id::text,
          jsonb_build_object('customer_id', p_customer_id, 'cycle_number', v_cycle, 'override', v_override, 'override_reason', nullif(trim(p_override_reason), '')));

  select count(*)::integer into v_count
  from public.loyalty_visits
  where customer_id = p_customer_id and cycle_number = v_cycle and reversal_of is null;

  if v_count >= v_rule.visits_required then
    v_code := 'APOLO-' || upper(replace(gen_random_uuid()::text, '-', ''));
    insert into public.customer_rewards(customer_id, rule_id, visits_required_snapshot, reward_description_snapshot, status, cycle_number, redemption_token_hash)
    values (p_customer_id, v_rule.id, v_rule.visits_required, v_rule.reward_description, 'available', v_cycle,
            encode(digest(v_code, 'sha256'), 'hex'))
    returning * into v_reward;

    -- The customer-facing QR payload is the unique reward UUID. The stored token hash
    -- remains available for future token-based redemption hardening without exposing a secret.
    insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
    values (auth.uid(), 'reward_issued', 'customer_reward', v_reward.id::text,
            jsonb_build_object('customer_id', p_customer_id, 'cycle_number', v_cycle, 'visits_required', v_rule.visits_required));
  end if;

  return jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'visit_id', v_visit.id,
    'visit_reference', v_visit.visit_reference,
    'cycle_number', v_cycle,
    'visits_in_cycle', v_count,
    'visits_required', v_rule.visits_required,
    'reward_id', v_reward.id,
    'reward_status', v_reward.status,
    'reward_code', case when v_reward.id is null then null else 'APOLO-' || upper(replace(v_reward.id::text, '-', '')) end,
    'reward_description', v_reward.reward_description_snapshot
  );
end;
$$;

revoke all on function public.record_visit(uuid, text, text, text) from public;
grant execute on function public.record_visit(uuid, text, text, text) to authenticated;

create or replace function public.redeem_reward(p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.staff_role;
  v_reward public.customer_rewards;
begin
  v_role := private.require_staff();

  select * into v_reward from public.customer_rewards where id = p_reward_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'reward_not_found'; end if;
  if v_reward.status <> 'available' then raise exception using errcode = 'P0001', message = 'reward_already_redeemed'; end if;

  update public.customer_rewards
  set status = 'redeemed', redeemed_at = now(), redeemed_by = auth.uid()
  where id = p_reward_id and status = 'available'
  returning * into v_reward;

  if v_reward.id is null then raise exception using errcode = 'P0001', message = 'reward_already_redeemed'; end if;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'reward_redeemed', 'customer_reward', p_reward_id::text,
          jsonb_build_object('customer_id', v_reward.customer_id, 'cycle_number', v_reward.cycle_number));

  return jsonb_build_object('ok', true, 'reward_id', v_reward.id, 'status', v_reward.status, 'redeemed_at', v_reward.redeemed_at);
end;
$$;

revoke all on function public.redeem_reward(uuid) from public;
grant execute on function public.redeem_reward(uuid) to authenticated;

create or replace function public.reverse_visit(p_visit_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.staff_role;
  v_original public.loyalty_visits;
  v_reversal public.loyalty_visits;
begin
  v_role := private.require_staff();
  if v_role not in ('admin', 'manager') then raise exception using errcode = '42501', message = 'manager_access_required'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception using errcode = '22023', message = 'reversal_reason_required'; end if;

  select * into v_original from public.loyalty_visits where id = p_visit_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'visit_not_found'; end if;
  if v_original.reversal_of is not null then raise exception using errcode = 'P0001', message = 'cannot_reverse_reversal'; end if;
  if exists (select 1 from public.loyalty_visits where reversal_of = p_visit_id) then raise exception using errcode = 'P0001', message = 'visit_already_reversed'; end if;

  insert into public.loyalty_visits(customer_id, staff_user_id, idempotency_key, note, cycle_number, reversal_of)
  values (v_original.customer_id, auth.uid(), 'REV-' || v_original.id::text, trim(p_reason), v_original.cycle_number, v_original.id)
  returning * into v_reversal;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'visit_reversed', 'loyalty_visit', v_original.id::text,
          jsonb_build_object('reversal_id', v_reversal.id, 'reason', trim(p_reason), 'customer_id', v_original.customer_id));

  return jsonb_build_object('ok', true, 'original_visit_id', v_original.id, 'reversal_visit_id', v_reversal.id);
end;
$$;

revoke all on function public.reverse_visit(uuid, text) from public;
grant execute on function public.reverse_visit(uuid, text) to authenticated;

-- Customer dashboard. It returns only the currently authenticated customer's data.
create or replace function public.get_customer_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer public.customers;
  v_rule public.loyalty_rules;
  v_reward public.customer_rewards;
  v_cycle integer := 1;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  select * into v_customer from public.customers where auth_user_id = auth.uid() and status = 'active' limit 1;
  if not found then raise exception using errcode = 'P0001', message = 'customer_profile_missing'; end if;
  select * into v_rule from public.loyalty_rules where is_active = true limit 1;
  select * into v_reward from public.customer_rewards where customer_id = v_customer.id and status = 'available' order by issued_at desc limit 1;
  select coalesce(max(cycle_number), 1) into v_cycle from public.loyalty_visits where customer_id = v_customer.id;
  if v_reward.id is not null then v_cycle := v_reward.cycle_number; end if;
  if v_reward.id is null then
    select count(*)::integer into v_count from public.loyalty_visits where customer_id = v_customer.id and cycle_number = v_cycle and reversal_of is null;
  else
    v_count := v_rule.visits_required;
  end if;

  return jsonb_build_object(
    'customer', jsonb_build_object('id', v_customer.id, 'display_name', v_customer.display_name),
    'cycle_number', v_cycle,
    'visits_in_cycle', v_count,
    'visits_required', v_rule.visits_required,
    'reward', case when v_reward.id is null then null else jsonb_build_object(
      'id', v_reward.id,
      'description', v_reward.reward_description_snapshot,
      'status', v_reward.status,
      'issued_at', v_reward.issued_at,
      'code', 'APOLO-' || upper(replace(v_reward.id::text, '-', '')),
      'qr_payload', 'apolos://reward/' || v_reward.id::text
    ) end
  );
end;
$$;

revoke all on function public.get_customer_dashboard() from public;
grant execute on function public.get_customer_dashboard() to authenticated;

-- RLS: authenticated customers can read only their own profile/history; staff gets no broad table access.
create policy customer_self_select on public.customers
  for select to authenticated
  using (auth_user_id = (select auth.uid()));

create policy customer_recovery_self_select on public.customer_recovery_methods
  for select to authenticated
  using (customer_id = private.current_customer_id());

create policy customer_visits_self_select on public.loyalty_visits
  for select to authenticated
  using (customer_id = private.current_customer_id());

create policy customer_rewards_self_select on public.customer_rewards
  for select to authenticated
  using (customer_id = private.current_customer_id());

create policy staff_profile_self_select on public.staff_profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Admin/manager staff listing is intentionally deferred to a scoped RPC in the staff-management migration.
-- No direct insert/update/delete policies are granted to authenticated users.

-- Audit is intentionally append-only through SECURITY DEFINER operations; clients cannot select it directly.
revoke all on public.audit_log from anon, authenticated;
revoke all on public.loyalty_visits from anon, authenticated;
revoke all on public.customer_rewards from anon, authenticated;
revoke all on public.customers from anon, authenticated;
revoke all on public.customer_recovery_methods from anon, authenticated;
revoke all on public.loyalty_rules from anon, authenticated;
revoke all on public.staff_profiles from anon, authenticated;

-- Seed the active rule if this is a new database.
insert into public.loyalty_rules(name, visits_required, reward_description, is_active)
select 'Apolo’s 10 visits', 10, 'Recompensa por 10 visitas', true
where not exists (select 1 from public.loyalty_rules where is_active = true);
