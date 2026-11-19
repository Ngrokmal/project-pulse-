-- =============================================================================
-- 0010_friends.sql
--
-- Everything the Explore tab needs, and nothing it does not:
--
--  • `friend_requests` — one row per ask. `status` moves pending → accepted |
--    declined | cancelled. A pair can only have ONE open request, in either
--    direction (unique index on the unordered pair, partial on pending), so two
--    phones tapping "Add" at the same moment cannot create two conversations.
--
--  • `friendships`  — the accepted edge, stored twice (a→b, b→a). A friendship
--    is symmetric, but storing both directions turns "my friends" and "mutual
--    friends" into one index scan each instead of an OR over two columns.
--    It is written only by `accept_friend_request()`, inside the same
--    transaction as the status change, so the two can never disagree.
--
--  • `search_people()` — the server half of the 50 % rule. The client has the
--    same scorer in `lib/features/explore/domain/people_match.dart` and the two
--    are unit-tested against the same table, because a rule that only lives in
--    the UI is a rule that drifts.
--
-- Forward-only and idempotent, like every other migration here.
-- =============================================================================

begin;

-- ---------------------------------------------------------------- requests
create table if not exists public.friend_requests (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles (id) on delete cascade,
  addressee_id  uuid not null references public.profiles (id) on delete cascade,
  status        text not null default 'pending'
                  check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  constraint friend_requests_not_self check (requester_id <> addressee_id)
);

comment on table public.friend_requests is
  'One row per friend ask. Only functions write it; the client reads its own two columns.';

-- one open request per unordered pair, whichever way it points
create unique index if not exists friend_requests_open_pair
  on public.friend_requests (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  )
  where status = 'pending';

create index if not exists friend_requests_inbox_idx
  on public.friend_requests (addressee_id, created_at desc)
  where status = 'pending';

create index if not exists friend_requests_outbox_idx
  on public.friend_requests (requester_id, created_at desc)
  where status = 'pending';

-- -------------------------------------------------------------- friendships
create table if not exists public.friendships (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  friend_id  uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint friendships_not_self check (user_id <> friend_id)
);

comment on table public.friendships is
  'Accepted edge, stored in both directions. Written only by accept_friend_request().';

create index if not exists friendships_friend_idx
  on public.friendships (friend_id);

-- --------------------------------------------------------------------- RLS
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;

drop policy if exists friend_requests_select_own on public.friend_requests;
create policy friend_requests_select_own on public.friend_requests
  for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists friendships_select_own on public.friendships;
create policy friendships_select_own on public.friendships
  for select to authenticated
  using (user_id = auth.uid());

-- No insert/update/delete policies on purpose: every write goes through a
-- security-definer function below so it can enforce who may do what.

revoke all on public.friend_requests from anon;
revoke all on public.friendships from anon;

-- ============================================================================
-- scoring — the server half of the 50 % rule
-- ============================================================================

-- Longest common subsequence length. Both sides are capped at 64 characters,
-- which is longer than any display name the schema allows (60).
create or replace function public.friend_lcs_len(a text, b text)
returns int
language plpgsql
immutable
as $$
declare
  m int;
  n int;
  prev int[];
  cur  int[];
  tmp  int[];
  i int;
  j int;
  ca text;
  cb text;
begin
  m := least(char_length(coalesce(a, '')), 64);
  n := least(char_length(coalesce(b, '')), 64);
  if m = 0 or n = 0 then
    return 0;
  end if;

  a := left(a, m);
  b := left(b, n);
  prev := array_fill(0, array[n]);
  cur  := array_fill(0, array[n]);

  for i in 1..m loop
    ca := substr(a, i, 1);
    for j in 1..n loop
      cb := substr(b, j, 1);
      if ca = cb then
        cur[j] := coalesce(prev[j - 1], 0) + 1;
      else
        cur[j] := greatest(coalesce(prev[j], 0), coalesce(cur[j - 1], 0));
      end if;
    end loop;
    tmp := prev;
    prev := cur;
    cur := tmp;
  end loop;

  return coalesce(prev[n], 0);
end;
$$;

comment on function public.friend_lcs_len(text, text) is
  'Longest common subsequence of two short strings. Mirror of PeopleMatch.lcsLength().';

-- The rule, in one place:
--   exact name/handle → 100 · prefix → 95 · substring → 88
--   otherwise the share of the typed letters that survived, and only when that
--   share is at least half AND at least three letters (so a three-letter query
--   cannot "match" half the network).
create or replace function public.friend_match_score(
  q text,
  p_name text,
  p_handle text
)
returns int
language plpgsql
immutable
as $$
declare
  qq text;
  best int := 0;
  fields text[];
  f text;
  hit int;
  cov numeric;
begin
  qq := lower(regexp_replace(coalesce(q, ''), '[^a-zA-Z0-9]+', '', 'g'));
  if char_length(qq) < 2 then
    return 0;
  end if;

  fields := array[
    lower(regexp_replace(coalesce(p_name, ''), '[^a-zA-Z0-9]+', '', 'g')),
    lower(regexp_replace(coalesce(p_handle, ''), '[^a-zA-Z0-9]+', '', 'g'))
  ];

  foreach f in array fields loop
    continue when f is null or f = '';

    if f = qq then
      best := greatest(best, 100);
    elsif position(qq in f) = 1 then
      best := greatest(best, 95);
    elsif position(qq in f) > 1 then
      best := greatest(best, 88);
    else
      hit := public.friend_lcs_len(qq, f);
      cov := hit::numeric / char_length(qq)::numeric;
      if cov >= 0.5 and hit >= least(3, char_length(qq)) then
        best := greatest(best, round(28 + cov * 58)::int);
      end if;
    end if;
  end loop;

  return best;
end;
$$;

comment on function public.friend_match_score(text, text, text) is
  'The 50 % letter rule. Mirror of PeopleMatch.score(); both are tested against the same cases.';

-- ---------------------------------------------------------------- relations
create or replace function public.friend_state(me uuid, other uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if me is null or other is null then
    return 'none';
  end if;
  if me = other then
    return 'self';
  end if;
  if exists (
    select 1 from public.friendships f
    where f.user_id = me and f.friend_id = other
  ) then
    return 'friend';
  end if;
  if exists (
    select 1 from public.friend_requests r
    where r.status = 'pending' and r.requester_id = me and r.addressee_id = other
  ) then
    return 'requested_by_me';
  end if;
  if exists (
    select 1 from public.friend_requests r
    where r.status = 'pending' and r.requester_id = other and r.addressee_id = me
  ) then
    return 'requested_me';
  end if;
  return 'none';
end;
$$;

create or replace function public.mutual_friend_count(me uuid, other uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.friendships mine
  join public.friendships theirs on theirs.friend_id = mine.friend_id
  where mine.user_id = me
    and theirs.user_id = other
    and me is not null
    and other is not null;
$$;

-- ============================================================================
-- reads
-- ============================================================================

create or replace function public.search_people(q text, max_rows int default 20)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  mutual_count int,
  friend_state text,
  score int,
  last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  lim int := greatest(1, least(50, coalesce(max_rows, 20)));
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Cost note: the scorer walks every profile. That is deliberate — the 50 %
  -- rule cannot be answered by a prefix index — and it is paid once per
  -- explicit submit, never per keystroke. For a profile table in the hundreds
  -- of thousands, add `pg_trgm` candidates before the score; the client API
  -- does not change.
  return query
  with scored as (
    select
      p.id,
      p.display_name,
      p.username,
      p.avatar_url,
      public.friend_match_score(q, p.display_name, p.username) as sc
    from public.profiles p
    where p.id <> me
  )
  select
    s.id,
    s.display_name,
    s.username,
    s.avatar_url,
    public.mutual_friend_count(me, s.id) as mutual_count,
    public.friend_state(me, s.id) as friend_state,
    s.sc as score,
    up.last_seen_at
  from scored s
  left join public.user_presence up on up.user_id = s.id
  where s.sc >= 50
  order by s.sc desc, mutual_count desc, s.display_name asc, s.id asc
  limit lim;
end;
$$;

-- The two closest names that did NOT clear the floor. Only asked for when the
-- main search came back empty, so a normal search never pays for it.
create or replace function public.near_people(q text, max_rows int default 2)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  mutual_count int,
  friend_state text,
  score int,
  last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  lim int := greatest(1, least(5, coalesce(max_rows, 2)));
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  with scored as (
    select
      p.id,
      p.display_name,
      p.username,
      p.avatar_url,
      public.friend_match_score(q, p.display_name, p.username) as sc
    from public.profiles p
    where p.id <> me
  )
  select
    s.id,
    s.display_name,
    s.username,
    s.avatar_url,
    public.mutual_friend_count(me, s.id),
    public.friend_state(me, s.id),
    s.sc,
    up.last_seen_at
  from scored s
  left join public.user_presence up on up.user_id = s.id
  where s.sc >= 18 and s.sc < 50
  order by s.sc desc, s.display_name asc
  limit lim;
end;
$$;

create or replace function public.explore_incoming(max_rows int default 100)
returns table (
  request_id uuid,
  person_id uuid,
  display_name text,
  username text,
  avatar_url text,
  mutual_count int,
  score int,
  last_seen_at timestamptz,
  sent_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select
    r.id,
    p.id,
    p.display_name,
    p.username,
    p.avatar_url,
    public.mutual_friend_count(me, p.id),
    0,
    up.last_seen_at,
    r.created_at
  from public.friend_requests r
  join public.profiles p on p.id = r.requester_id
  left join public.user_presence up on up.user_id = p.id
  where r.addressee_id = me and r.status = 'pending'
  order by r.created_at desc
  limit greatest(1, least(500, coalesce(max_rows, 100)));
end;
$$;

create or replace function public.explore_sent(max_rows int default 100)
returns table (
  request_id uuid,
  person_id uuid,
  display_name text,
  username text,
  avatar_url text,
  mutual_count int,
  score int,
  last_seen_at timestamptz,
  sent_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select
    r.id,
    p.id,
    p.display_name,
    p.username,
    p.avatar_url,
    public.mutual_friend_count(me, p.id),
    0,
    up.last_seen_at,
    r.created_at
  from public.friend_requests r
  join public.profiles p on p.id = r.addressee_id
  left join public.user_presence up on up.user_id = p.id
  where r.requester_id = me and r.status = 'pending'
  order by r.created_at desc
  limit greatest(1, least(500, coalesce(max_rows, 100)));
end;
$$;

create or replace function public.explore_friends(max_rows int default 200)
returns table (
  person_id uuid,
  display_name text,
  username text,
  avatar_url text,
  mutual_count int,
  friends_since timestamptz,
  last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.username,
    p.avatar_url,
    public.mutual_friend_count(me, p.id),
    f.created_at,
    up.last_seen_at
  from public.friendships f
  join public.profiles p on p.id = f.friend_id
  left join public.user_presence up on up.user_id = p.id
  where f.user_id = me
  order by f.created_at desc
  limit greatest(1, least(1000, coalesce(max_rows, 200)));
end;
$$;

-- ============================================================================
-- writes
-- ============================================================================

create or replace function public.send_friend_request(p_target uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  existing public.friend_requests;
  created uuid;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_target is null or p_target = me then
    raise exception 'invalid_target' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.friendships f
    where f.user_id = me and f.friend_id = p_target
  ) then
    return query select null::uuid, 'friend'::text;
    return;
  end if;

  select * into existing from public.friend_requests r
  where r.status = 'pending'
    and (
      (r.requester_id = me and r.addressee_id = p_target)
      or (r.requester_id = p_target and r.addressee_id = me)
    )
  limit 1;

  if found then
    -- They already asked me: accept instead of stacking a second row.
    if existing.requester_id = p_target then
      return query select * from public.accept_friend_request(existing.id);
    else
      return query select existing.id, 'requested_by_me'::text;
    end if;
    return;
  end if;

  insert into public.friend_requests (requester_id, addressee_id)
  values (me, p_target)
  returning id into created;

  return query select created, 'requested_by_me'::text;
exception
  when unique_violation then
    raise exception 'request_already_open' using errcode = '23505';
end;
$$;

create or replace function public.accept_friend_request(p_request uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.id = p_request and r.status = 'pending'
  for update;

  if not found then
    raise exception 'request_not_open' using errcode = 'P0002';
  end if;
  if row.addressee_id <> me then
    raise exception 'not_your_request' using errcode = '42501';
  end if;

  update public.friend_requests r
  set status = 'accepted', responded_at = now()
  where r.id = row.id;

  insert into public.friendships (user_id, friend_id)
  values (row.requester_id, row.addressee_id), (row.addressee_id, row.requester_id)
  on conflict do nothing;

  return query select row.id, 'friend'::text;
end;
$$;

create or replace function public.decline_friend_request(p_request uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.id = p_request and r.status = 'pending'
  for update;

  if not found then
    raise exception 'request_not_open' using errcode = 'P0002';
  end if;
  if row.addressee_id <> me then
    raise exception 'not_your_request' using errcode = '42501';
  end if;

  update public.friend_requests r
  set status = 'declined', responded_at = now()
  where r.id = row.id;

  return query select row.id, 'none'::text;
end;
$$;

create or replace function public.cancel_friend_request(p_request uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.id = p_request and r.status = 'pending'
  for update;

  if not found then
    raise exception 'request_not_open' using errcode = 'P0002';
  end if;
  if row.requester_id <> me then
    raise exception 'not_your_request' using errcode = '42501';
  end if;

  update public.friend_requests r
  set status = 'cancelled', responded_at = now()
  where r.id = row.id;

  return query select row.id, 'none'::text;
end;
$$;

-- The search sheet knows *who* it is looking at, not which row of
-- `friend_requests` belongs to them. These two functions close that gap for the
-- two taps a result row can make, so the client never has to fetch a request id
-- just to press Cancel or Accept.
create or replace function public.cancel_request_to(p_target uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.requester_id = me and r.addressee_id = p_target and r.status = 'pending'
  for update;

  if not found then
    raise exception 'request_not_open' using errcode = 'P0002';
  end if;

  update public.friend_requests r
  set status = 'cancelled', responded_at = now()
  where r.id = row.id;

  return query select row.id, 'none'::text;
end;
$$;

create or replace function public.accept_request_from(p_person uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.requester_id = p_person and r.addressee_id = me and r.status = 'pending'
  for update;

  if not found then
    raise exception 'request_not_open' using errcode = 'P0002';
  end if;

  update public.friend_requests r
  set status = 'accepted', responded_at = now()
  where r.id = row.id;

  insert into public.friendships (user_id, friend_id)
  values (row.requester_id, row.addressee_id), (row.addressee_id, row.requester_id)
  on conflict do nothing;

  return query select row.id, 'friend'::text;
end;
$$;

-- Undo for a decline: the addressee may put their own decision back.
-- This is what the toast's Undo calls — a declined request is not deleted, it
-- is a state, and states can be walked back exactly once.
create or replace function public.undo_decline_friend_request(p_request uuid)
returns table (request_id uuid, state text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
  row public.friend_requests;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into row from public.friend_requests r
  where r.id = p_request and r.status = 'declined'
  for update;

  if not found then
    raise exception 'nothing_to_undo' using errcode = 'P0002';
  end if;
  if row.addressee_id <> me then
    raise exception 'not_your_request' using errcode = '42501';
  end if;

  update public.friend_requests r
  set status = 'pending', responded_at = null
  where r.id = row.id;

  return query select row.id, 'requested_me'::text;
end;
$$;

-- ------------------------------------------------------------------- grants
revoke all on function public.friend_lcs_len(text, text) from public;
revoke all on function public.friend_match_score(text, text, text) from public;
revoke all on function public.friend_state(uuid, uuid) from public;
revoke all on function public.mutual_friend_count(uuid, uuid) from public;
revoke all on function public.search_people(text, int) from public;
revoke all on function public.near_people(text, int) from public;
revoke all on function public.explore_incoming(int) from public;
revoke all on function public.explore_sent(int) from public;
revoke all on function public.explore_friends(int) from public;
revoke all on function public.send_friend_request(uuid) from public;
revoke all on function public.accept_friend_request(uuid) from public;
revoke all on function public.decline_friend_request(uuid) from public;
revoke all on function public.cancel_friend_request(uuid) from public;
revoke all on function public.undo_decline_friend_request(uuid) from public;
revoke all on function public.cancel_request_to(uuid) from public;
revoke all on function public.accept_request_from(uuid) from public;

grant execute on function public.search_people(text, int) to authenticated;
grant execute on function public.near_people(text, int) to authenticated;
grant execute on function public.explore_incoming(int) to authenticated;
grant execute on function public.explore_sent(int) to authenticated;
grant execute on function public.explore_friends(int) to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.decline_friend_request(uuid) to authenticated;
grant execute on function public.cancel_friend_request(uuid) to authenticated;
grant execute on function public.undo_decline_friend_request(uuid) to authenticated;
grant execute on function public.cancel_request_to(uuid) to authenticated;
grant execute on function public.accept_request_from(uuid) to authenticated;

commit;
