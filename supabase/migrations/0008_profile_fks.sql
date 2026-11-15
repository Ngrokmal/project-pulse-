-- 0008_profile_fks.sql — make the profile joins PostgREST needs explicit
--
-- The client embeds the sender/member profile in one request:
--
--   conversations?select=id,...,conversation_members(user_id,role,profiles(...))
--   messages?select=...,... (sender profile from `profiles` when needed)
--
-- PostgREST can only resolve an embed through a real foreign key, and the
-- membership/message tables only referenced `auth.users`. Result: every inbox
-- load failed with PGRST200 "Could not find a relationship between
-- conversation_members and profiles" — a server-side 400 the app could only
-- report as "something went wrong".
--
-- The fix is the constraint the schema should have had from the start: a profile
-- row exists for every account (0001 trigger), so membership and messages can
-- point at it. ON DELETE CASCADE keeps the delete paths unchanged.

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'conversation_members_profile_fkey'
       and conrelid = 'public.conversation_members'::regclass
  ) then
    -- NOT VALID so pre-existing rows can never block the deploy; new rows are
    -- checked from now on and the relationship is visible to PostgREST either
    -- way.
    alter table public.conversation_members
      add constraint conversation_members_profile_fkey
      foreign key (user_id) references public.profiles (id)
      on delete cascade not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'messages_sender_profile_fkey'
       and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_sender_profile_fkey
      foreign key (sender_id) references public.profiles (id)
      on delete cascade not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'conversations_created_by_profile_fkey'
       and conrelid = 'public.conversations'::regclass
  ) then
    alter table public.conversations
      add constraint conversations_created_by_profile_fkey
      foreign key (created_by) references public.profiles (id)
      on delete set null not valid;
  end if;
end $$;

-- Ask PostgREST to pick the new relationships up immediately on the hosted
-- project (a local psql run simply ignores the notification).
notify pgrst, 'reload schema';
