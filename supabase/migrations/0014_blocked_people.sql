-- =============================================================================
-- 0014_blocked_people.sql
--
-- The Blocked people page needs one thing the database did not have: a way to
-- list *my* blocks together with the person behind each one.
--
-- Why a function and not a plain join: `public.blocks` points at
-- `auth.users`, and `public.profiles` is a separate table, so PostgREST cannot
-- embed one from the other. Doing it client-side would mean two round trips and
-- a page that shows names a moment after it shows the rows.
--
-- Rules kept from 0013:
--   • a block is visible to exactly one person — the one who wrote it;
--   • nothing is inferred: no "they blocked you", no counts, no shadow list;
--   • unblocking is the same row disappearing, not a soft flag somewhere else.
--
-- Forward-only and idempotent, like every migration in this folder.
-- =============================================================================

begin;

-- ------------------------------------------------------------------ the list
-- SECURITY DEFINER so the join can read `profiles` for people whose row the
-- caller could not otherwise see, while `where b.blocker = auth.uid()` keeps the
-- result to the caller's own blocks. `search_path` is pinned as the hardening
-- step for every definer function.
create or replace function public.blocked_people()
returns table (
  id           uuid,
  display_name text,
  username     text,
  avatar_url   text,
  blocked_at   timestamptz
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select
    b.blocked,
    coalesce(nullif(p.display_name, ''), 'Pulse user'),
    p.username,
    -- The card's own rule: a photo the owner hid is not delivered to a page
    -- either. `photo_visible` defaults true (0012).
    case when coalesce(p.photo_visible, true) then p.avatar_url end,
    b.created_at
  from public.blocks b
  left join public.profiles p on p.id = b.blocked
  where b.blocker = auth.uid()
  order by b.created_at desc;
$$;

revoke all on function public.blocked_people() from public, anon;
grant execute on function public.blocked_people() to authenticated;

-- `blocks` is keyed (blocker, blocked); this is the page's access path.
create index if not exists blocks_blocker_created_idx
  on public.blocks (blocker, created_at desc);

commit;
