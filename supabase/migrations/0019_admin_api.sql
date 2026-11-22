-- RECONSTRUCTED STAGING CANDIDATE, not the lost original. Do not deploy until
-- security review, managed staging tests and migration-history reconciliation.
begin;
alter table public.pulse_user_controls add column if not exists can_start_calls boolean not null default true;

-- This lock protects both actor authorization and target protection from
-- concurrent changes to the trusted allowlist for the duration of a mutation.
create or replace function public.pulse_admin_set_user_control(p_user uuid,p_control text,p_enabled boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid();
begin
  lock table public.pulse_admin_accounts in share mode;
  if not public.pulse_is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  if p_enabled is null or p_control is null or p_control not in ('send_messages','start_calls','change_profile_photo') then raise exception 'invalid_control' using errcode='22023'; end if;
  if not exists(select 1 from auth.users where id=p_user) then raise exception 'user_not_found' using errcode='P0002'; end if;
  if exists(select 1 from public.pulse_admin_accounts where user_id=p_user and enabled) then raise exception 'admin_target_protected' using errcode='42501'; end if;
  insert into public.pulse_user_controls(user_id,updated_by) values(p_user,actor) on conflict(user_id) do nothing;
  update public.pulse_user_controls set
    can_send_messages=case when p_control='send_messages' then p_enabled else can_send_messages end,
    can_start_calls=case when p_control='start_calls' then p_enabled else can_start_calls end,
    can_change_profile_photo=case when p_control='change_profile_photo' then p_enabled else can_change_profile_photo end,
    updated_at=now(),updated_by=actor where user_id=p_user;
  insert into public.pulse_admin_audit(actor_id,target_id,action,change) values(actor,p_user,'user_control',jsonb_build_object('control',p_control,'enabled',p_enabled));
end $$;
revoke all on function public.pulse_admin_set_user_control(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.pulse_admin_set_user_control(uuid,text,boolean) to authenticated;

create or replace function public.pulse_admin_list_users(p_query text default '',p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,email text,display_name text,status text,ends_at timestamptz,can_send_messages boolean,can_start_calls boolean,can_change_profile_photo boolean)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.pulse_is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  if p_query is null or length(p_query)>100 or p_limit is null or p_limit<1 or p_limit>100 or p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'invalid_search' using errcode='22023'; end if;
  return query select u.id,coalesce(u.email::text,''),coalesce(p.display_name,''),coalesce(s.status::text,'active'),s.ends_at,
    coalesce(c.can_send_messages,true),coalesce(c.can_start_calls,true),coalesce(c.can_change_profile_photo,true)
    from auth.users u left join public.profiles p on p.id=u.id
    left join public.account_status s on s.user_id=u.id left join public.pulse_user_controls c on c.user_id=u.id
    where position(lower(btrim(p_query)) in lower(coalesce(u.email::text,'')||' '||coalesce(p.display_name,'')||' '||coalesce(p.username,'')))>0
    order by lower(coalesce(p.display_name,'')),u.id limit p_limit offset p_offset;
end $$;
revoke all on function public.pulse_admin_list_users(text,integer,integer) from public,anon,authenticated;
grant execute on function public.pulse_admin_list_users(text,integer,integer) to authenticated;

create or replace function public.pulse_admin_set_suspension(p_user uuid,p_suspend boolean,p_ends_at timestamptz default null,p_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); current_status public.account_status_value;
begin
  lock table public.pulse_admin_accounts in share mode;
  if not public.pulse_is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  if p_suspend is null or (p_suspend and p_ends_at is not null and p_ends_at<=now()) or (not p_suspend and p_ends_at is not null) or length(coalesce(p_reason,''))>500 then raise exception 'invalid_suspension' using errcode='22023'; end if;
  if not exists(select 1 from auth.users where id=p_user) then raise exception 'user_not_found' using errcode='P0002'; end if;
  if exists(select 1 from public.pulse_admin_accounts where user_id=p_user and enabled) then raise exception 'admin_target_protected' using errcode='42501'; end if;
  insert into public.account_status(user_id) values(p_user) on conflict(user_id) do nothing;
  select s.status into current_status from public.account_status s where s.user_id=p_user for update;
  if current_status not in ('active','suspended') then raise exception 'restricted_status_protected' using errcode='42501'; end if;
  update public.account_status set status=case when p_suspend then 'suspended'::public.account_status_value else 'active'::public.account_status_value end,
    starts_at=case when p_suspend then now() else starts_at end,
    ends_at=case when p_suspend then p_ends_at else null end,
    reason_text=case when p_suspend then p_reason else null end, updated_by=actor
  where user_id=p_user;
  insert into public.pulse_admin_audit(actor_id,target_id,action,change) values(actor,p_user,'account_suspension',jsonb_build_object('suspended',p_suspend,'ends_at',p_ends_at));
end $$;
revoke all on function public.pulse_admin_set_suspension(uuid,boolean,timestamptz,text) from public,anon,authenticated;
grant execute on function public.pulse_admin_set_suspension(uuid,boolean,timestamptz,text) to authenticated;

-- Only normal new call records, not incoming calls, existing calls or force audio.
create or replace function public.pulse_guard_call_start()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is not null and new.caller_id=auth.uid() and not coalesce((select can_start_calls from public.pulse_user_controls where user_id=auth.uid()),true) then
    raise exception 'call_start_disabled' using errcode='PCTRL';
  end if;
  return new;
end $$;
revoke all on function public.pulse_guard_call_start() from public,anon,authenticated;
drop trigger if exists pulse_call_start_control on public.calls;
create trigger pulse_call_start_control before insert on public.calls for each row execute function public.pulse_guard_call_start();
commit;
