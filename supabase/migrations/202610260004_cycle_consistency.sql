-- Fix cycle progression: a redeemed reward starts the next cycle.
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
  v_latest_reward public.customer_rewards;
  v_override boolean := nullif(trim(coalesce(p_override_reason, '')), '') is not null;
begin
  v_role := private.require_staff();
  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null then raise exception using errcode = '22023', message = 'idempotency_key_required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text, 817263));

  select * into v_existing from public.loyalty_visits where idempotency_key = p_idempotency_key limit 1;
  if found then
    if v_existing.customer_id <> p_customer_id then raise exception using errcode = '23505', message = 'idempotency_conflict'; end if;
    select * into v_reward from public.customer_rewards where customer_id = p_customer_id and cycle_number = v_existing.cycle_number order by issued_at desc limit 1;
    return jsonb_build_object('ok', true, 'duplicate', true, 'visit_id', v_existing.id, 'visit_reference', v_existing.visit_reference,
      'cycle_number', v_existing.cycle_number,
      'visits_in_cycle', (select count(*) from public.loyalty_visits where customer_id = p_customer_id and cycle_number = v_existing.cycle_number and reversal_of is null),
      'reward_id', v_reward.id, 'reward_status', v_reward.status,
      'reward_code', case when v_reward.id is null then null else 'APOLO-' || upper(replace(v_reward.id::text, '-', '')) end);
  end if;

  select * into v_customer from public.customers where id = p_customer_id and status = 'active' for update;
  if not found then raise exception using errcode = 'P0001', message = 'customer_not_found'; end if;
  select * into v_rule from public.loyalty_rules where is_active = true limit 1;
  if v_rule.id is null then raise exception using errcode = 'P0001', message = 'active_loyalty_rule_missing'; end if;

  select * into v_reward from public.customer_rewards where customer_id = p_customer_id and status = 'available' order by issued_at desc limit 1;
  if v_reward.id is not null then raise exception using errcode = 'P0001', message = 'reward_pending'; end if;

  select * into v_latest_reward from public.customer_rewards where customer_id = p_customer_id order by cycle_number desc, issued_at desc limit 1;
  v_cycle := case when v_latest_reward.id is null then 1 else v_latest_reward.cycle_number + 1 end;

  select max(created_at) into v_last_visit from public.loyalty_visits where customer_id = p_customer_id and cycle_number = v_cycle and reversal_of is null;
  if v_last_visit is not null and v_last_visit > now() - interval '12 hours' and not v_override then raise exception using errcode = 'P0001', message = 'visit_too_soon'; end if;
  if v_override and v_role not in ('admin', 'manager') then raise exception using errcode = '42501', message = 'override_requires_manager'; end if;

  insert into public.loyalty_visits(customer_id, staff_user_id, idempotency_key, note, cycle_number)
  values (p_customer_id, auth.uid(), trim(p_idempotency_key), nullif(trim(p_note), ''), v_cycle)
  returning * into v_visit;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'visit_recorded', 'loyalty_visit', v_visit.id::text, jsonb_build_object('customer_id', p_customer_id, 'cycle_number', v_cycle, 'override', v_override, 'override_reason', nullif(trim(p_override_reason), '')));

  select count(*)::integer into v_count from public.loyalty_visits where customer_id = p_customer_id and cycle_number = v_cycle and reversal_of is null;

  if v_count >= v_rule.visits_required then
    insert into public.customer_rewards(customer_id, rule_id, visits_required_snapshot, reward_description_snapshot, status, cycle_number, redemption_token_hash)
    values (p_customer_id, v_rule.id, v_rule.visits_required, v_rule.reward_description, 'available', v_cycle,
      encode(digest(('reward:' || gen_random_uuid()::text), 'sha256'), 'hex'))
    returning * into v_reward;
    insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
    values (auth.uid(), 'reward_issued', 'customer_reward', v_reward.id::text, jsonb_build_object('customer_id', p_customer_id, 'cycle_number', v_cycle, 'visits_required', v_rule.visits_required));
  end if;

  return jsonb_build_object('ok', true, 'duplicate', false, 'visit_id', v_visit.id, 'visit_reference', v_visit.visit_reference,
    'cycle_number', v_cycle, 'visits_in_cycle', v_count, 'visits_required', v_rule.visits_required,
    'reward_id', v_reward.id, 'reward_status', v_reward.status,
    'reward_code', case when v_reward.id is null then null else 'APOLO-' || upper(replace(v_reward.id::text, '-', '')) end,
    'reward_description', v_reward.reward_description_snapshot);
end;
$$;
revoke all on function public.record_visit(uuid, text, text, text) from public;
grant execute on function public.record_visit(uuid, text, text, text) to authenticated;

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
  v_latest_reward public.customer_rewards;
  v_cycle integer := 1;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  select * into v_customer from public.customers where auth_user_id = auth.uid() and status = 'active' limit 1;
  if not found then raise exception using errcode = 'P0001', message = 'customer_profile_missing'; end if;
  select * into v_rule from public.loyalty_rules where is_active = true limit 1;
  select * into v_reward from public.customer_rewards where customer_id = v_customer.id and status = 'available' order by issued_at desc limit 1;
  select * into v_latest_reward from public.customer_rewards where customer_id = v_customer.id order by cycle_number desc, issued_at desc limit 1;
  v_cycle := case when v_reward.id is not null then v_reward.cycle_number when v_latest_reward.id is null then 1 else v_latest_reward.cycle_number + 1 end;
  select count(*)::integer into v_count from public.loyalty_visits where customer_id = v_customer.id and cycle_number = v_cycle and reversal_of is null;

  return jsonb_build_object('customer', jsonb_build_object('id', v_customer.id, 'display_name', v_customer.display_name),
    'cycle_number', v_cycle, 'visits_in_cycle', v_count, 'visits_required', v_rule.visits_required,
    'reward', case when v_reward.id is null then null else jsonb_build_object('id', v_reward.id, 'description', v_reward.reward_description_snapshot,
      'status', v_reward.status, 'issued_at', v_reward.issued_at, 'code', 'APOLO-' || upper(replace(v_reward.id::text, '-', '')),
      'qr_payload', 'apolos://reward/' || v_reward.id::text) end);
end;
$$;
revoke all on function public.get_customer_dashboard() from public;
grant execute on function public.get_customer_dashboard() to authenticated;

-- A reward must not remain usable after a manager reverses a visit from its cycle.
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
  v_reward public.customer_rewards;
begin
  v_role := private.require_staff();
  if v_role not in ('admin', 'manager') then raise exception using errcode = '42501', message = 'manager_access_required'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception using errcode = '22023', message = 'reversal_reason_required'; end if;
  select * into v_original from public.loyalty_visits where id = p_visit_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'visit_not_found'; end if;
  if v_original.reversal_of is not null then raise exception using errcode = 'P0001', message = 'cannot_reverse_reversal'; end if;
  if exists (select 1 from public.loyalty_visits where reversal_of = p_visit_id) then raise exception using errcode = 'P0001', message = 'visit_already_reversed'; end if;
  select * into v_reward from public.customer_rewards where customer_id = v_original.customer_id and cycle_number = v_original.cycle_number and status = 'available' limit 1;
  if v_reward.id is not null then raise exception using errcode = 'P0001', message = 'cannot_reverse_with_pending_reward'; end if;

  insert into public.loyalty_visits(customer_id, staff_user_id, idempotency_key, note, cycle_number, reversal_of)
  values (v_original.customer_id, auth.uid(), 'REV-' || v_original.id::text, trim(p_reason), v_original.cycle_number, v_original.id)
  returning * into v_reversal;
  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'visit_reversed', 'loyalty_visit', v_original.id::text, jsonb_build_object('reversal_id', v_reversal.id, 'reason', trim(p_reason), 'customer_id', v_original.customer_id));
  return jsonb_build_object('ok', true, 'original_visit_id', v_original.id, 'reversal_visit_id', v_reversal.id);
end;
$$;
revoke all on function public.reverse_visit(uuid, text) from public;
grant execute on function public.reverse_visit(uuid, text) to authenticated;
