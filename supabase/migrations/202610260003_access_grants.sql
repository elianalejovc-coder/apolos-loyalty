-- RLS policies are paired with explicit table grants. Grants limit the operation;
-- policies limit which rows are visible.
grant select on public.staff_profiles to authenticated;
grant select on public.customers to authenticated;
grant select on public.customer_recovery_methods to authenticated;
grant select on public.loyalty_visits to authenticated;
grant select on public.customer_rewards to authenticated;

revoke all on public.loyalty_rules from anon, authenticated;
revoke all on public.audit_log from anon, authenticated;
