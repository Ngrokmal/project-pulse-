-- =============================================================================
-- 0013_avatar_block_report.sql
--
-- The v4 profile card needs four things the database did not have yet:
--
--   1. somewhere to keep a photo      → storage bucket `avatars`
--   2. a way to stop someone           → public.blocks (+ a guard on messages)
--   3. a way to say "this is wrong"    → public.reports (write-only for the app)
--   4. "clear this chat" that is real → conversation_members.cleared_at + RPC
--
-- Rules kept from 0012: nothing is inferred about a person. A block is a row
-- its owner wrote; a report is a row its reporter wrote; clearing is a timestamp
-- on the clearer's own membership. No counts, no scores, no shadow profile.
--
-- Forward-only and idempotent, like every migration in this folder.
-- =============================================================================

begin;

-- ---------------------------------------------------------------- avatars bucket
-- Public-read because every surface of the app (inbox, explore, chat) renders
-- an avatar from its URL without a round trip; the path is scoped to the owner
-- and `profiles.photo_visible = false` is honoured by the client before a photo
-- is ever painted. Writes are strictly own-folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatars_read on storage.objects;
create policy avatars_read
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists avatars_insert_own on storage.objects;
create policy avatars_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- --------------------------------------------------------------------- blocks
create table if not exists public.blocks (
  blocker    uuid not null references auth.users (id) on delete cascade,
  blocked    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  constraint blocks_not_self check (blocker <> blocked)
);

create index if not exists blocks_blocked_idx on public.blocks (blocked);

alter table public.blocks enable row level security;

drop policy if exists blocks_read_own on public.blocks;
create policy blocks_read_own
  on public.blocks for select to authenticated
  using (blocker = auth.uid());

drop policy if exists blocks_insert_own on public.blocks;
create policy blocks_insert_own
  on public.blocks for insert to authenticated
  with check (blocker = auth.uid());

drop policy if exists blocks_delete_own on public.blocks;
create policy blocks_delete_own
  on public.blocks for delete to authenticated
  using (blocker = auth.uid());

-- Either direction counts: the blocked person must not reach the blocker either.
create or replace function public.pulse_is_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b)
       or (blocker = b and blocked = a)
  );
$$;

revoke all on function public.pulse_is_blocked(uuid, uuid) from anon;
grant execute on function public.pulse_is_blocked(uuid, uuid) to authenticated;

-- The block has to hold *everywhere*, not only in the screen that set it, so it
-- is enforced at the one place every message passes through.
create or replace function public.tg_messages_block_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  peer uuid;
begin
  -- direct conversations only; groups keep working with the rest of their people
  select m.user_id into peer
    from public.conversation_members m
   where m.conversation_id = new.conversation_id
     and m.user_id <> new.sender_id
   limit 1;

  if peer is not null and public.pulse_is_blocked(new.sender_id, peer) then
    raise exception 'blocked' using
      errcode = '42501',
      hint    = 'Messages between these accounts are switched off.';
  end if;

  return new;
end;
$$;

drop trigger if exists messages_block_guard on public.messages;
create trigger messages_block_guard
  before insert on public.messages
  for each row execute function public.tg_messages_block_guard();

-- -------------------------------------------------------------------- reports
create table if not exists public.reports (
  id         uuid primary key default gen_random_uuid(),
  reporter   uuid not null references auth.users (id) on delete cascade,
  reported   uuid not null references auth.users (id) on delete cascade,
  reason     text not null check (char_length(reason) between 1 and 60),
  note       text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  constraint reports_not_self check (reporter <> reported)
);

create index if not exists reports_reported_idx on public.reports (reported);

alter table public.reports enable row level security;

-- Write-only from the app: a reporter can file one, nobody can read them back
-- without the service role. (No select policy on purpose.)
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own
  on public.reports for insert to authenticated
  with check (reporter = auth.uid());

-- --------------------------------------------------------------- clear for me
alter table public.conversation_members
  add column if not exists cleared_at timestamptz;

create or replace function public.clear_conversation(conv uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.conversation_members
     set cleared_at = now()
   where conversation_id = conv
     and user_id = auth.uid();
$$;

revoke all on function public.clear_conversation(uuid) from anon;
grant execute on function public.clear_conversation(uuid) to authenticated;

comment on column public.conversation_members.cleared_at is
  'When this member cleared their copy. Messages older than this are not theirs to see.';
comment on table public.blocks is
  'One row per decision: blocker chose to stop hearing from blocked.';
comment on table public.reports is
  'Write-only from the client. Read by the service role only.';

commit;
