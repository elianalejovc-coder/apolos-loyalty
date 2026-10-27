begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

select ok(to_regclass('public.staff_profiles') is not null, 'staff_profiles exists');
select ok(to_regclass('public.customers') is not null, 'customers exists');
select ok(to_regclass('public.loyalty_visits') is not null, 'loyalty_visits exists');
select ok(to_regclass('public.customer_rewards') is not null, 'customer_rewards exists');
select ok(to_regclass('public.audit_log') is not null, 'audit_log exists');
select has_column('public.loyalty_visits', 'cycle_number', 'visits have cycle_number');
select has_column('public.loyalty_visits', 'idempotency_key', 'visits have idempotency_key');
select has_column('public.loyalty_visits', 'reversal_of', 'visits have reversal_of');
select has_column('public.customer_rewards', 'cycle_number', 'rewards have cycle_number');
select function_returns('public.record_visit', ARRAY['uuid','text','text','text'], 'jsonb');
select function_returns('public.redeem_reward', ARRAY['uuid'], 'jsonb');
select function_returns('public.reverse_visit', ARRAY['uuid','text'], 'jsonb');
select function_returns('public.get_customer_dashboard', ARRAY[]::text[], 'jsonb');
select is_definer('public.record_visit(uuid,text,text,text)', 'record_visit is security definer');
select is_definer('public.redeem_reward(uuid)', 'redeem_reward is security definer');
select ok(not has_table_privilege('authenticated', 'public.loyalty_visits', 'INSERT'), 'authenticated cannot directly insert visits');
select ok(not has_table_privilege('authenticated', 'public.customer_rewards', 'UPDATE'), 'authenticated cannot directly update rewards');
select ok(not has_table_privilege('anon', 'public.customers', 'SELECT'), 'anon cannot directly read customers');

select * from finish();
rollback;
