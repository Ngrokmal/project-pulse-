-- =============================================================================
-- 0015_profile_visits.sql
--
-- "Who looked at my card, and when." The one thing this must never become is a
-- tracker: a visit is recorded only when someone deliberately opens a card, it
-- is stored as one row per (viewer, viewed) pair with a count, it is readable by
-- exactly one person — the person who was looked at — and it is removed with
-- either account and hidden the moment a block exists in either direction.
--
--   record_profile_visit(target)   the writer. Bumps an existing row instead of
--                                  erroring, refuses self-visits, and can only
--                                  ever record the caller as the viewer.
--   profile_visitors(limit)        the reader. Newest first, the photo masked by
--                                  the visitor's own `photo_visible`, and no
--                                  block in sight.
-- =============================================================================
begin;

create table if not exists public.profile_visits (
  viewer uuid not null references public.profiles (id) on delete cascade,
  viewed uuid not null references public.profiles (id) on delete cascade,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  visit_count integer not null default 1 check (visit_count > 0),
  primary key (viewer, viewed),
  constraint profile_visits_not_self check (viewer <> viewed)
);

comment on table public.profile_visits is
  'Profile card opens, one row per (viewer, viewed). Readable only by the person '
  'who was viewed; written only through record_profile_visit().';

create index if not exists profile_visits_viewed_idx
  on public.profile_visits (viewed, last_seen_at desc);

alter table public.profile_visits enable row level security;

-- The person who was looked at can see that someone looked. Nobody else.
drop policy if exists profile_visits_read_own on public.profile_visits;
create policy profile_visits_read_own on public.profile_visits
  for select to authenticated
  using (viewed = auth.uid());

-- A client may only ever write itself as the viewer, and never itself as the
-- target. (The function below is the supported path; this keeps the raw table
-- honest for anyone who tries it directly.)
drop policy if exists profile_visits_record_own on public.profile_visits;
create policy profile_visits_record_own on public.profile_visits
  for insert to authenticated
  with check (viewer = auth.uid() and viewed <> auth.uid());

-- No update, no delete from a client: the count is the server's, and a visit is
-- permanent until one of the accounts goes away.
revoke all on public.profile_visits from public, anon;
grant select, insert on public.profile_visits to authenticated;

-- ---------------------------------------------------------------------------
-- Record one open of someone's card.
-- ---------------------------------------------------------------------------
create or replace function public.record_profile_visit(target uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.profile_visits (viewer, viewed)
  select auth.uid(), target
  where auth.uid() is not null
    and target is not null
    and auth.uid() <> target
  on conflict (viewer, viewed) do update
    set last_seen_at = now(),
        visit_count = public.profile_visits.visit_count + 1;
$$;

revoke all on function public.record_profile_visit(uuid) from public, anon;
grant execute on function public.record_profile_visit(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Who looked at my card.
-- ---------------------------------------------------------------------------
create or replace function public.profile_visitors(limit_count integer default 50)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  last_seen_at timestamptz,
  visit_count integer
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select
    p.id,
    coalesce(nullif(btrim(p.display_name), ''), 'Pulse user') as display_name,
    p.username,
    -- A hidden photo is not delivered anywhere, this list included.
    case when coalesce(p.photo_visible, true) then p.avatar_url end as avatar_url,
    v.last_seen_at,
    v.visit_count
  from public.profile_visits v
  join public.profiles p on p.id = v.viewer
  where v.viewed = auth.uid()
    -- A block hides the visitor from the list, whichever way it points.
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker = auth.uid() and b.blocked = v.viewer)
         or (b.blocker = v.viewer and b.blocked = auth.uid())
    )
  order by v.last_seen_at desc
  limit greatest(1, least(coalesce(limit_count, 50), 200));
$$;

revoke all on function public.profile_visitors(integer) from public, anon;
grant execute on function public.profile_visitors(integer) to authenticated;

commit;
