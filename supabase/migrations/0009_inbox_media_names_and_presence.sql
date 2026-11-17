-- =============================================================================
-- 0009_inbox_media_names_and_presence.sql
--
-- Two things the personal inbox needs and could not get from the schema:
--
--  • `messages.media_name` — the *original* file name the sender's device had.
--    Until now the UI had to guess a name out of the Cloudinary URL, which is a
--    random public id; a photo called "eid_with_family.jpg" arrived as
--    "xj9d2k1_1.jpg". The name is stored once, at insert, and never derived.
--
--  • `user_presence` — one row per account with the last time the app pinged.
--    "online" is derived from that (last_seen within 90 s), "last seen …" comes
--    from the same row. Only the owner may write their row; every signed-in
--    user may read it, because a chat header needs to know.
--
-- Forward-only and idempotent, like every other migration here.
-- =============================================================================

begin;

-- ------------------------------------------------------- original media names
alter table public.messages
  add column if not exists media_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'messages_media_name_len'
  ) then
    alter table public.messages
      add constraint messages_media_name_len
      check (media_name is null or char_length(media_name) between 1 and 160);
  end if;
end $$;

comment on column public.messages.media_name is
  'Original file name as the sender''s device had it; never derived from a URL.';

-- ------------------------------------------------------------------- presence
create table if not exists public.user_presence (
  user_id      uuid primary key references public.profiles (id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists user_presence_last_seen_idx
  on public.user_presence (last_seen_at desc);

alter table public.user_presence enable row level security;

-- Anyone signed in can read presence (it is what the chat header shows);
-- nobody can read it anonymously.
drop policy if exists user_presence_select_all on public.user_presence;
create policy user_presence_select_all on public.user_presence
  for select to authenticated
  using (true);

drop policy if exists user_presence_insert_own on public.user_presence;
create policy user_presence_insert_own on public.user_presence
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_presence_update_own on public.user_presence;
create policy user_presence_update_own on public.user_presence
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on public.user_presence from anon;
revoke all on public.user_presence from authenticated;
grant select on public.user_presence to authenticated;
grant insert (user_id, last_seen_at, updated_at) on public.user_presence
  to authenticated;
grant update (last_seen_at, updated_at) on public.user_presence
  to authenticated;
grant all on public.user_presence to service_role;

-- ------------------------------------------------------------------ heartbeat
-- One call, server clock. A client cannot backdate or forward-date presence.
create or replace function public.touch_presence()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  me   uuid := auth.uid();
  seen timestamptz := now();
begin
  if me is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  insert into public.user_presence (user_id, last_seen_at, updated_at)
  values (me, seen, seen)
  on conflict (user_id) do update
    set last_seen_at = excluded.last_seen_at,
        updated_at   = excluded.updated_at;
  return seen;
end $$;

revoke all on function public.touch_presence() from public;
grant execute on function public.touch_presence() to authenticated;

-- ------------------------------------------------------------------- realtime
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
begin
  begin
    alter publication supabase_realtime add table public.user_presence;
  exception when duplicate_object then null;
  end;
end $$;

commit;
