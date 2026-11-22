-- Staging candidate. Do not deploy until expiry scheduling and old-client
-- behaviour have been verified against a managed staging project.
begin;

-- Blocks apply to direct chats only; group members can continue speaking and
-- reading within their shared group. Membership/RLS remains authoritative.
create or replace function public.tg_messages_block_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  peer uuid;
  conversation_kind text;
begin
  select c.kind into conversation_kind
    from public.conversations c where c.id = new.conversation_id;
  if conversation_kind = 'direct' then
    select m.user_id into peer
      from public.conversation_members m
     where m.conversation_id = new.conversation_id
       and m.user_id <> new.sender_id
     limit 1;
    if peer is not null and public.pulse_is_blocked(new.sender_id, peer) then
      raise exception 'blocked' using errcode = '42501',
        hint = 'Messages between these accounts are switched off.';
    end if;
  end if;
  return new;
end;
$$;

-- Boolean switches and explicit enum restrictions both work on INSERT. On
-- conflicting INSERT, a restrictive status wins; suspended=true with the
-- default active enum becomes a temporary suspension. UPDATE stays compatible
-- with the existing precedence rules.
create or replace function public.sync_account_suspension()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_from_status boolean := (coalesce(new.status::text, 'active') <> 'active');
begin
  if tg_op = 'INSERT' then
    if v_from_status then
      new.suspended := true;
    elsif coalesce(new.suspended, false) then
      new.status := 'suspended'::public.account_status_value;
      new.suspended := true;
    else
      new.suspended := false;
    end if;
  elsif new.suspended is distinct from old.suspended then
    new.status := case when new.suspended
      then 'suspended'::public.account_status_value
      else 'active'::public.account_status_value end;
  elsif new.status is distinct from old.status then
    new.suspended := v_from_status;
  end if;
  if new.suspended then
    if tg_op = 'INSERT' then
      new.starts_at := now();
    elsif not old.suspended then
      new.starts_at := now();
    end if;
  end if;
  if new.case_code is null then
    new.case_code := 'PULSE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9));
  end if;
  return new;
end;
$$;

-- Temporary suspensions only: an expiry does not automatically release bans
-- or reviews. Use the database clock; status=active is always active.
create or replace function public.is_account_active(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select a.status = 'active'
         or (a.status = 'suspended' and a.ends_at is not null and a.ends_at <= now())
       from public.account_status a where a.user_id = p_user),
    true
  );
$$;

-- This job must be invoked by a trusted scheduler. A separate deployment
-- step must establish and verify that scheduler; defining this function alone
-- does NOT update expired rows automatically or support old clients.
create or replace function public.release_expired_suspensions()
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n bigint;
begin
  update public.account_status
     set status = 'active', suspended = false, ends_at = null
   where status = 'suspended' and ends_at is not null and ends_at <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.release_expired_suspensions() from public, anon, authenticated;
grant execute on function public.release_expired_suspensions() to service_role;

commit;
