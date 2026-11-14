-- =============================================================================
-- 0006_groups.sql — group conversations, roles, membership rules (§7)
--
-- Design notes
--  • A group is a `conversations` row with kind='group' plus a title. Direct
--    chats are untouched: every existing policy keeps working because they are
--    membership-based, not kind-based.
--  • Roles live on `conversation_members`: owner (exactly at least one), admin,
--    member. Clients can never write roles directly — the RPCs below are the only
--    way, so "who may add/remove/rename" is decided in SQL, not in the app.
--  • The owner cannot be removed and the last owner cannot leave without
--    transferring ownership, so no group can ever be stranded.
--  • Limits: 32 members per group, title 1..60 chars.
-- =============================================================================

begin;

alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations
  add constraint conversations_kind_check check (kind in ('direct', 'group'));

alter table public.conversations
  add column if not exists title text
    check (title is null or char_length(btrim(title)) between 1 and 60);
alter table public.conversations
  add column if not exists avatar_url text
                        check (avatar_url is null or avatar_url like 'https://res.cloudinary.com/%');

alter table public.conversation_members
  add column if not exists role text not null default 'member'
    check (role in ('owner', 'admin', 'member'));

create index if not exists conversation_members_role_idx
  on public.conversation_members (conversation_id, role);

-- ------------------------------------------------------------------- helpers
create or replace function public.is_group_member(p_conversation uuid, p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation and m.user_id = p_user
  );
$$;

create or replace function public.group_role(p_conversation uuid, p_user uuid default auth.uid())
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.role from public.conversation_members m
  where m.conversation_id = p_conversation and m.user_id = p_user;
$$;

create or replace function public.is_group_admin(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.group_role(p_conversation) in ('owner', 'admin'), false);
$$;

revoke all on function public.is_group_member(uuid, uuid) from public, anon;
revoke all on function public.group_role(uuid, uuid) from public, anon;
revoke all on function public.is_group_admin(uuid) from public, anon;
grant execute on function public.is_group_member(uuid, uuid) to authenticated, service_role;
grant execute on function public.group_role(uuid, uuid) to authenticated, service_role;
grant execute on function public.is_group_admin(uuid) to authenticated, service_role;

-- --------------------------------------------------------------- create_group
create or replace function public.create_group(p_title text, p_members uuid[])
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := auth.uid();
  v_title   text := btrim(coalesce(p_title, ''));
  v_members uuid[];
  v_conv    uuid;
  v_missing integer;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.is_account_active(v_me) then
    raise exception 'account_not_active' using errcode = '42501';
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 60 then
    raise exception 'invalid_title' using errcode = '22023';
  end if;

  -- de-duplicate, drop the caller, keep the order stable
  select array_agg(distinct m) into v_members
    from unnest(coalesce(p_members, '{}'::uuid[])) as m
   where m is not null and m <> v_me;

  if coalesce(array_length(v_members, 1), 0) < 1 then
    raise exception 'group_needs_members' using errcode = '22023';
  end if;
  if array_length(v_members, 1) > 31 then
    raise exception 'group_too_large' using errcode = '22023';
  end if;

  select count(*) into v_missing
    from unnest(v_members) as m
   where not exists (select 1 from public.profiles p where p.id = m);
  if v_missing > 0 then
    raise exception 'member_not_found' using errcode = '23503';
  end if;

  insert into public.conversations (kind, title, created_by)
  values ('group', v_title, v_me)
  returning id into v_conv;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (v_conv, v_me, 'owner');

  insert into public.conversation_members (conversation_id, user_id, role)
  select v_conv, m, 'member' from unnest(v_members) as m;

  return v_conv;
end $$;

revoke all on function public.create_group(text, uuid[]) from public, anon;
grant execute on function public.create_group(text, uuid[]) to authenticated;

-- ------------------------------------------------------------ add/remove/role
create or replace function public.add_group_member(p_conversation uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  if not public.is_group_admin(p_conversation) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_user is null then
    raise exception 'invalid_member' using errcode = '22023';
  end if;
  if exists (select 1 from public.conversation_members m
              where m.conversation_id = p_conversation and m.user_id = p_user) then
    return; -- idempotent
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user) then
    raise exception 'member_not_found' using errcode = '23503';
  end if;
  if not public.is_account_active(p_user) then
    raise exception 'member_not_active' using errcode = '42501';
  end if;

  select count(*) into v_count
    from public.conversation_members m where m.conversation_id = p_conversation;
  if v_count >= 32 then
    raise exception 'group_full' using errcode = '22023';
  end if;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (p_conversation, p_user, 'member');
end $$;

create or replace function public.remove_group_member(p_conversation uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_my_role    text := public.group_role(p_conversation);
  v_their_role text := public.group_role(p_conversation, p_user);
begin
  if v_their_role is null then
    raise exception 'not_a_member' using errcode = '22023';
  end if;
  if v_their_role = 'owner' then
    -- The owner can only leave through leave_group, which transfers ownership.
    raise exception 'cannot_remove_owner' using errcode = '42501';
  end if;
  if v_my_role = 'owner' or (v_my_role = 'admin' and v_their_role = 'member') then
    delete from public.conversation_members m
     where m.conversation_id = p_conversation and m.user_id = p_user;
    return;
  end if;
  raise exception 'not_allowed' using errcode = '42501';
end $$;

create or replace function public.set_group_role(p_conversation uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_my_role text := public.group_role(p_conversation);
begin
  if v_my_role is distinct from 'owner' then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'admin', 'member') then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  if public.group_role(p_conversation, p_user) is null then
    raise exception 'not_a_member' using errcode = '22023';
  end if;

  if p_role = 'owner' then
    -- Transferring ownership: exactly one owner afterwards.
    update public.conversation_members set role = 'admin'
     where conversation_id = p_conversation and role = 'owner';
  end if;
  update public.conversation_members set role = p_role
   where conversation_id = p_conversation and user_id = p_user;
end $$;

-- ---------------------------------------------------------------- leave_group
create or replace function public.leave_group(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := auth.uid();
  v_my_role text;
  v_next    uuid;
  v_left    integer;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select m.role into v_my_role
    from public.conversation_members m
   where m.conversation_id = p_conversation and m.user_id = v_me;

  if v_my_role is null then
    raise exception 'not_a_member' using errcode = '22023';
  end if;

  if v_my_role = 'owner' then
    -- Hand the group to an admin first, otherwise the longest-standing member,
    -- so a group can never be left without an owner.
    select m.user_id into v_next
      from public.conversation_members m
     where m.conversation_id = p_conversation and m.user_id <> v_me
     order by (m.role = 'admin') desc, m.joined_at
     limit 1;

    if v_next is not null then
      update public.conversation_members
         set role = 'owner'
       where conversation_id = p_conversation and user_id = v_next;
    end if;
  end if;

  delete from public.conversation_members
   where conversation_id = p_conversation and user_id = v_me;

  -- Nobody left: the conversation has no reason to exist.
  select count(*) into v_left
    from public.conversation_members m where m.conversation_id = p_conversation;
  if v_left = 0 then
    delete from public.conversations where id = p_conversation;
  end if;
end $$;

-- -------------------------------------------------------------- rename_group
create or replace function public.rename_group(p_conversation uuid, p_title text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
begin
  if not public.is_group_admin(p_conversation) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 60 then
    raise exception 'invalid_title' using errcode = '22023';
  end if;
  update public.conversations set title = v_title where id = p_conversation;
end $$;

revoke all on function public.add_group_member(uuid, uuid) from public, anon;
revoke all on function public.remove_group_member(uuid, uuid) from public, anon;
revoke all on function public.set_group_role(uuid, uuid, text) from public, anon;
revoke all on function public.leave_group(uuid) from public, anon;
revoke all on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.add_group_member(uuid, uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.set_group_role(uuid, uuid, text) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.rename_group(uuid, text) to authenticated;

-- ----------------------------------------------------------------------- RLS
-- Only an owner/admin may edit a group's title or avatar, and only those two
-- columns are writable at all (the grant below is column-level).
drop policy if exists conversations_update_group_admin on public.conversations;
create policy conversations_update_group_admin on public.conversations
  for update to authenticated
  using (kind = 'group' and public.is_group_admin(id))
  with check (kind = 'group' and public.is_group_admin(id));

grant update (title, avatar_url) on public.conversations to authenticated;

-- Membership rows stay unwritable by clients: the RPCs above are the only path.
-- UPDATE is revoked at table level and re-granted for the one column chat needs
-- (read receipts), so `role` still cannot be set by a client.
revoke insert, update, delete on public.conversation_members from authenticated;
grant update (last_read_at) on public.conversation_members to authenticated;

commit;
