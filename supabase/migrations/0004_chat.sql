-- =============================================================================
-- 0004_chat.sql — direct conversations, messages, realtime, read receipts
--
-- Design notes
--  • One chat type only: `direct` (no groups yet, no Premium, no follow).
--  • Conversation creation goes through a SECURITY DEFINER RPC that is
--    idempotent for a pair of users, so two phones starting a chat at the same
--    time cannot create two conversations.
--  • `client_id` makes sending idempotent: the offline outbox can retry the
--    same message any number of times without duplicating it.
--  • Nothing is hard-deleted by clients; messages are soft-deleted.
-- =============================================================================

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- conversations
create table if not exists public.conversations (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null default 'direct' check (kind in ('direct')),
  pair_key      text unique,           -- canonical "uuidA:uuidB" for direct chats
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_message_at      timestamptz,
  last_message_preview text check (char_length(last_message_preview) <= 140),
  last_message_sender  uuid references auth.users (id) on delete set null
);

create index if not exists conversations_last_message_idx
  on public.conversations (last_message_at desc nulls last);

drop trigger if exists conversations_touch_updated_at on public.conversations;
create trigger conversations_touch_updated_at
  before update on public.conversations
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------- conversation_members
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_members_user_idx
  on public.conversation_members (user_id);

-- -------------------------------------------------------------------- messages
do $$
begin
  if not exists (select 1 from pg_type where typname = 'message_kind') then
    create type public.message_kind as enum ('text', 'image', 'video', 'file', 'audio', 'force_audio');
  end if;
end $$;

create table if not exists public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references auth.users (id) on delete cascade,
  kind             public.message_kind not null default 'text',
  body             text check (body is null or char_length(body) <= 4000),
  media_url        text,
  media_thumb_url  text,
  media_bytes      bigint check (media_bytes is null or media_bytes > 0),
  duration_ms      integer check (duration_ms is null or duration_ms between 0 and 600000),
  client_id        text check (client_id is null or char_length(client_id) between 8 and 64),
  created_at       timestamptz not null default now(),
  edited_at        timestamptz,
  deleted_at       timestamptz,
  constraint messages_content_present check (
    deleted_at is not null
    or (kind = 'text' and body is not null and char_length(btrim(body)) > 0)
    or (kind <> 'text' and media_url is not null)
  )
);

create unique index if not exists messages_client_id_idx
  on public.messages (conversation_id, client_id)
  where client_id is not null;

create index if not exists messages_conversation_time_idx
  on public.messages (conversation_id, created_at desc);

-- ------------------------------------------------------------------- helpers
create or replace function public.is_conversation_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated, service_role;

-- Idempotent direct conversation creation for the caller + one other user.
create or replace function public.start_direct_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me     uuid := auth.uid();
  v_key    text;
  v_conv   uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_other is null or p_other = v_me then
    raise exception 'invalid_recipient' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other) then
    raise exception 'recipient_not_found' using errcode = '23503';
  end if;

  -- canonical ordering so (A,B) and (B,A) collide on the same row
  v_key := least(v_me::text, p_other::text) || ':' || greatest(v_me::text, p_other::text);

  insert into public.conversations (kind, pair_key, created_by)
  values ('direct', v_key, v_me)
  on conflict (pair_key) do update set updated_at = now()
  returning id into v_conv;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_conv, v_me), (v_conv, p_other)
  on conflict do nothing;

  return v_conv;
end $$;

revoke all on function public.start_direct_conversation(uuid) from public;
grant execute on function public.start_direct_conversation(uuid) to authenticated, service_role;

-- Keep the conversation's preview in sync with the newest visible message.
create or replace function public.handle_new_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.conversations c
     set last_message_at = new.created_at,
         last_message_preview = case
           when new.deleted_at is not null then 'Message deleted'
           when new.kind = 'text' then left(new.body, 140)
           when new.kind = 'image' then 'Photo'
           when new.kind = 'video' then 'Video'
           when new.kind = 'audio' then 'Voice message'
           when new.kind = 'force_audio' then 'Force audio alert'
           else 'Attachment'
         end,
         last_message_sender = new.sender_id
   where c.id = new.conversation_id
     and (c.last_message_at is null or c.last_message_at <= new.created_at);
  return new;
end $$;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.handle_new_message();

-- ----------------------------------------------------------------------- RLS
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

drop policy if exists conversations_select_member on public.conversations;
create policy conversations_select_member on public.conversations
  for select to authenticated
  using (public.is_conversation_member(id));

drop policy if exists conversation_members_select_member on public.conversation_members;
create policy conversation_members_select_member on public.conversation_members
  for select to authenticated
  using (public.is_conversation_member(conversation_id));

drop policy if exists messages_select_member on public.messages;
create policy messages_select_member on public.messages
  for select to authenticated
  using (public.is_conversation_member(conversation_id));

-- Clients may only send as themselves, only into a conversation they belong to,
-- and only while their account is active.
drop policy if exists messages_insert_own on public.messages;
create policy messages_insert_own on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
    and public.is_account_active(auth.uid())
  );

-- Editing is limited to your own message and cannot rewrite who/where it was.
drop policy if exists messages_update_own on public.messages;
create policy messages_update_own on public.messages
  for update to authenticated
  using (sender_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
  );

drop policy if exists messages_delete_own on public.messages;
create policy messages_delete_own on public.messages
  for delete to authenticated
  using (sender_id = auth.uid());

-- Read receipts: a member may move their own last_read_at forward, nothing else.
drop policy if exists conversation_members_update_own on public.conversation_members;
create policy conversation_members_update_own on public.conversation_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ------------------------------------------------------------------- grants
revoke all on public.conversations, public.conversation_members, public.messages from anon;

-- Supabase's default privileges grant ALL on every new public table to
-- `authenticated`, which silently makes columns like joined_at writable. Take it
-- back explicitly and hand out only what each table needs (this is the same
-- column-level discipline the profiles table uses).
revoke insert, update, delete on public.conversations from authenticated;
revoke insert, update, delete on public.conversation_members from authenticated;
revoke all on public.messages from authenticated;

grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant update (last_read_at) on public.conversation_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant all on public.conversations, public.conversation_members, public.messages to service_role;

-- ------------------------------------------------------------------ realtime
-- The hosted project ships with this publication; a bare PostgreSQL (the local
-- migration harness, CI) does not, so create it when missing.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.conversations;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.conversation_members;
  exception when duplicate_object then null;
  end;
end $$;

commit;
