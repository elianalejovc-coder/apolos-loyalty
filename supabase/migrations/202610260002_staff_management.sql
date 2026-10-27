-- Staff management. Admin-only mutations plus a one-time first-admin bootstrap.

create or replace function public.bootstrap_first_admin(p_display_name text)
returns public.staff_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.staff_profiles;
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  if v_name is null then raise exception using errcode = '22023', message = 'display_name_required'; end if;
  if exists (select 1 from public.staff_profiles) then raise exception using errcode = '42501', message = 'bootstrap_already_completed'; end if;

  insert into public.staff_profiles(user_id, display_name, role, is_active)
  values (auth.uid(), v_name, 'admin', true)
  returning * into v_profile;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'first_admin_bootstrapped', 'staff_profile', auth.uid()::text, jsonb_build_object('display_name', v_name));

  return v_profile;
end;
$$;
revoke all on function public.bootstrap_first_admin(text) from public;
grant execute on function public.bootstrap_first_admin(text) to authenticated;

create or replace function public.list_staff_profiles()
returns table(user_id uuid, display_name text, role public.staff_role, is_active boolean, created_at timestamptz, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare v_role public.staff_role;
begin
  v_role := private.require_staff();
  if v_role <> 'admin' then raise exception using errcode = '42501', message = 'admin_access_required'; end if;
  return query select sp.user_id, sp.display_name, sp.role, sp.is_active, sp.created_at, sp.updated_at
  from public.staff_profiles sp order by sp.created_at;
end;
$$;
revoke all on function public.list_staff_profiles() from public;
grant execute on function public.list_staff_profiles() to authenticated;

create or replace function public.create_staff_profile(p_user_id uuid, p_display_name text, p_role public.staff_role default 'employee')
returns public.staff_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile public.staff_profiles; v_role public.staff_role;
begin
  v_role := private.require_staff();
  if v_role <> 'admin' then raise exception using errcode = '42501', message = 'admin_access_required'; end if;
  if nullif(trim(coalesce(p_display_name, '')), '') is null then raise exception using errcode = '22023', message = 'display_name_required'; end if;
  if p_role not in ('admin','manager','employee') then raise exception using errcode = '22023', message = 'invalid_staff_role'; end if;
  if not exists (select 1 from auth.users where id = p_user_id) then raise exception using errcode = 'P0001', message = 'auth_user_not_found'; end if;

  insert into public.staff_profiles(user_id, display_name, role, is_active)
  values (p_user_id, trim(p_display_name), p_role, true)
  returning * into v_profile;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'staff_created', 'staff_profile', p_user_id::text, jsonb_build_object('role', p_role, 'display_name', trim(p_display_name)));
  return v_profile;
end;
$$;
revoke all on function public.create_staff_profile(uuid, text, public.staff_role) from public;
grant execute on function public.create_staff_profile(uuid, text, public.staff_role) to authenticated;

create or replace function public.update_staff_profile(p_user_id uuid, p_display_name text default null, p_role public.staff_role default null, p_is_active boolean default null)
returns public.staff_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile public.staff_profiles; v_actor_role public.staff_role;
begin
  v_actor_role := private.require_staff();
  if v_actor_role <> 'admin' then raise exception using errcode = '42501', message = 'admin_access_required'; end if;
  if p_user_id = auth.uid() and p_is_active = false then raise exception using errcode = '22023', message = 'cannot_deactivate_self'; end if;

  update public.staff_profiles
  set display_name = coalesce(nullif(trim(p_display_name), ''), display_name),
      role = coalesce(p_role, role),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;
  if v_profile.user_id is null then raise exception using errcode = 'P0001', message = 'staff_not_found'; end if;

  insert into public.audit_log(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'staff_updated', 'staff_profile', p_user_id::text,
          jsonb_build_object('display_name', p_display_name, 'role', p_role, 'is_active', p_is_active));
  return v_profile;
end;
$$;
revoke all on function public.update_staff_profile(uuid, text, public.staff_role, boolean) from public;
grant execute on function public.update_staff_profile(uuid, text, public.staff_role, boolean) to authenticated;
