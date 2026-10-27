-- Local development seed. No real customer/staff data is included.
-- The active loyalty rule is also created by the operational migration; this keeps
-- reset/start deterministic if the migration was applied to an empty database.
insert into public.loyalty_rules(name, visits_required, reward_description, is_active)
select 'Apolo’s 10 visits', 10, 'Recompensa por 10 visitas', true
where not exists (select 1 from public.loyalty_rules where is_active = true);
