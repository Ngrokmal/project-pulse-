-- Staging candidate only: establishes a server-authoritative admin foundation.
-- Intentionally no bootstrap admin; assignment requires a trusted operator.
-- It does not claim to cover external uploads or all feature surfaces.
begin;

create table if not exists public.pulse_admin_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  enabled boolean not null default true
);
alter table public.pulse_admin_accounts enable row level security;
revoke all on table public.pulse_admin_accounts from public, anon, authenticated;

create table if not exists public.pulse_user_controls (
  user_id uuid primary key references auth.users(id) on delete cascade,
  can_send_messages boolean not null default true,
  can_change_profile_photo boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.pulse_user_controls enable row level security;
revoke all on table public.pulse_user_controls from public, anon, authenticated;

create table if not exists public.pulse_admin_audit (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  target_id uuid references auth.users(id) on delete set null,
  action text not null,
  change jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.pulse_admin_audit enable row level security;
revoke all on table public.pulse_admin_audit from public, anon, authenticated;

create table if not exists public.pulse_error_messages (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{2,63}$'),
  message text not null check (char_length(btrim(message)) between 1 and 500),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.pulse_error_messages enable row level security;
revoke all on table public.pulse_error_messages from public, anon, authenticated;

create or replace function public.pulse_is_admin()
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select auth.uid() is not null and public.is_account_active(auth.uid())
    and exists(select 1 from public.pulse_admin_accounts a where a.user_id=auth.uid() and a.enabled);
$$;
revoke all on function public.pulse_is_admin() from public, anon, authenticated;
grant execute on function public.pulse_is_admin() to authenticated;

-- Only hard-coded feature keys are accepted; client cannot change membership.
create or replace function public.pulse_admin_set_user_control(p_user uuid, p_control text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid := auth.uid();
begin
  if not public.pulse_is_admin() then
    raise exception 'admin_required' using errcode='42501';
  end if;
  if p_enabled is null or p_control is null or p_control not in ('send_messages','change_profile_photo') then
    raise exception 'invalid_control' using errcode='22023';
  end if;
  if not exists(select 1 from auth.users where id=p_user) then
    raise exception 'user_not_found' using errcode='P0002';
  end if;
  insert into public.pulse_user_controls(user_id, updated_by) values(p_user,v_actor)
  on conflict(user_id) do nothing;
  if p_control='send_messages' then
    update public.pulse_user_controls set can_send_messages=p_enabled, updated_at=now(),updated_by=v_actor where user_id=p_user;
  else
    update public.pulse_user_controls set can_change_profile_photo=p_enabled, updated_at=now(),updated_by=v_actor where user_id=p_user;
  end if;
  insert into public.pulse_admin_audit(actor_id,target_id,action,change)
    values(v_actor,p_user,'user_control',jsonb_build_object('control',p_control,'enabled',p_enabled));
end;
$$;
revoke all on function public.pulse_admin_set_user_control(uuid,text,boolean) from public, anon, authenticated;
grant execute on function public.pulse_admin_set_user_control(uuid,text,boolean) to authenticated;

create or replace function public.pulse_admin_set_error_message(p_code text, p_message text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.pulse_is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{2,63}$' or p_message is null or char_length(btrim(p_message)) not between 1 and 500 then
    raise exception 'invalid_error_message' using errcode='22023';
  end if;
  insert into public.pulse_error_messages(code,message,updated_at,updated_by)
    values(p_code,btrim(p_message),now(),auth.uid())
    on conflict(code) do update set message=excluded.message,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
  insert into public.pulse_admin_audit(actor_id,action,change)
    values(auth.uid(),'error_message',jsonb_build_object('code',p_code));
end;
$$;
revoke all on function public.pulse_admin_set_error_message(text,text) from public, anon, authenticated;
grant execute on function public.pulse_admin_set_error_message(text,text) to authenticated;

create or replace function public.pulse_error_message(p_code text)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select e.message from public.pulse_error_messages e where e.code=p_code and auth.uid() is not null;
$$;
revoke all on function public.pulse_error_message(text) from public, anon, authenticated;
grant execute on function public.pulse_error_message(text) to authenticated;

create or replace function public.pulse_guard_admin_controls()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid:=auth.uid(); v_allowed boolean;
begin
  -- Maintenance/service jobs without an end-user JWT are not treated as a user.
  if v_uid is null then return new; end if;
  if tg_table_name='messages' and tg_op='INSERT' then
    select coalesce((select can_send_messages from public.pulse_user_controls where user_id=v_uid),true) into v_allowed;
    if not v_allowed then raise exception 'message_send_disabled' using errcode='PCTRL'; end if;
  elsif tg_table_name='profiles' and tg_op='UPDATE' and new.id=v_uid
        and new.avatar_url is distinct from old.avatar_url then
    select coalesce((select can_change_profile_photo from public.pulse_user_controls where user_id=v_uid),true) into v_allowed;
    if not v_allowed then raise exception 'profile_photo_change_disabled' using errcode='PCTRL'; end if;
  end if;
  return new;
end;
$$;
revoke all on function public.pulse_guard_admin_controls() from public, anon, authenticated;
drop trigger if exists pulse_message_control on public.messages;
create trigger pulse_message_control before insert on public.messages for each row execute function public.pulse_guard_admin_controls();
drop trigger if exists pulse_profile_photo_control on public.profiles;
create trigger pulse_profile_photo_control before update on public.profiles for each row execute function public.pulse_guard_admin_controls();

commit;
