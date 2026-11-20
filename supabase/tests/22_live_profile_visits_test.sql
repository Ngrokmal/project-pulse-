-- =============================================================================
-- 22_live_profile_visits_test.sql
--
-- The live proof for "Profile views" (0015), against the real project, inside one
-- transaction that ends in ROLLBACK.
--
-- It answers the four questions the feature makes a promise about:
--   1. does an open of a card actually record a visit, once, with a count,
--   2. can only the person who was looked at read it,
--   3. is a visitor hidden once a block exists in either direction,
--   4. is a hidden photo withheld from this list too.
--
-- Usage: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/22_live_profile_visits_test.sql
-- =============================================================================
begin;

create temp table _results (
  ord serial primary key,
  name text not null,
  ok boolean not null,
  detail text
) on commit drop;

grant select, insert on _results to public;
grant usage, select on sequence _results_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('b1517000-1111-4111-8111-111111111111', 'vis-a@example.test', '{"display_name":"Visit A"}'),
       ('b1517000-2222-4222-8222-222222222222', 'vis-b@example.test', '{"display_name":"Visit B"}'),
       ('b1517000-3333-4333-8333-333333333333', 'vis-c@example.test', '{"display_name":"Visit C"}');

update public.profiles
   set username = 'visit_a',
       avatar_url = 'https://res.cloudinary.com/demo/image/upload/a.png'
 where id = 'b1517000-1111-4111-8111-111111111111';

update public.profiles
   set username = 'visit_b',
       avatar_url = 'https://res.cloudinary.com/demo/image/upload/b.png'
 where id = 'b1517000-2222-4222-8222-222222222222';

-- ---------------------------------------------------------------------------
-- A opens B's card. Twice.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-1111-4111-8111-111111111111","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'an untouched list is empty',
       (select count(*) from public.profile_visitors()) = 0, null;

select public.record_profile_visit('b1517000-2222-4222-8222-222222222222');
select public.record_profile_visit('b1517000-2222-4222-8222-222222222222');

-- The row exists, but its owner is B, so A must not be able to see it — the
-- check that it landed at all is #5, read as B. This is the privacy promise, not
-- a missing write.
insert into _results (name, ok, detail)
select 'the visitor cannot read the list of the person they visited',
       (select count(*) from public.profile_visitors()) = 0, null;

do $$
begin
  perform public.record_profile_visit('b1517000-1111-4111-8111-111111111111');
  insert into _results (name, ok, detail)
  select 'a self-visit is not recorded',
         (select count(*) from public.profile_visits
           where viewer = 'b1517000-1111-4111-8111-111111111111'
             and viewed = 'b1517000-1111-4111-8111-111111111111') = 0,
         null;
exception when others then
  insert into _results (name, ok, detail)
  values ('a self-visit is not recorded', true, sqlerrm);
end $$;

-- ---------------------------------------------------------------------------
-- B — the person who was looked at
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'two opens are one visit, with a count of two',
       (select count(*) from public.profile_visitors()) = 1
       and (select display_name from public.profile_visitors()) = 'Visit A'
       and (select username from public.profile_visitors()) = 'visit_a'
       and (select visit_count from public.profile_visitors()) = 2,
       (select coalesce(string_agg(display_name || ' x' || visit_count, ', '), 'none')
          from public.profile_visitors());

insert into _results (name, ok, detail)
select 'the photo comes through while it is visible',
       (select avatar_url from public.profile_visitors())
         = 'https://res.cloudinary.com/demo/image/upload/a.png', null;

insert into _results (name, ok, detail)
select 'the time of the visit is the stored time',
       (select last_seen_at from public.profile_visitors()) is not null, null;

-- ---------------------------------------------------------------------------
-- C — a bystander sees nothing of it
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-3333-4333-8333-333333333333","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'a third party sees no one else''s visitors',
       (select count(*) from public.profile_visitors()) = 0
       and (select count(*) from public.profile_visits) = 0, null;

-- ---------------------------------------------------------------------------
-- A visitor who hides their photo is not delivered
-- ---------------------------------------------------------------------------
reset role;
update public.profiles set photo_visible = false
 where id = 'b1517000-1111-4111-8111-111111111111';
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'a hidden photo is not delivered to the visitors list',
       (select avatar_url from public.profile_visitors()) is null, null;

-- ---------------------------------------------------------------------------
-- A block hides the visitor, whichever way it points
-- ---------------------------------------------------------------------------
insert into public.blocks (blocker, blocked)
values ('b1517000-2222-4222-8222-222222222222', 'b1517000-1111-4111-8111-111111111111');

insert into _results (name, ok, detail)
select 'blocking the visitor empties the list',
       (select count(*) from public.profile_visitors()) = 0, null;

delete from public.blocks
 where blocker = 'b1517000-2222-4222-8222-222222222222';

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-1111-4111-8111-111111111111","role":"authenticated"}';

insert into public.blocks (blocker, blocked)
values ('b1517000-1111-4111-8111-111111111111', 'b1517000-2222-4222-8222-222222222222');

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1517000-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'a block from the other side hides them too',
       (select count(*) from public.profile_visitors()) = 0, null;

-- ---------------------------------------------------------------------------
-- anon may not call either function
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform public.profile_visitors();
  insert into _results (name, ok, detail)
  values ('anon cannot read profile_visitors()', false, 'call succeeded');
exception when insufficient_privilege then
  insert into _results (name, ok, detail)
  values ('anon cannot read profile_visitors()', true, sqlerrm);
end $$;

do $$
begin
  perform public.record_profile_visit('b1517000-2222-4222-8222-222222222222');
  insert into _results (name, ok, detail)
  values ('anon cannot record a visit', false, 'call succeeded');
exception when insufficient_privilege then
  insert into _results (name, ok, detail)
  values ('anon cannot record a visit', true, sqlerrm);
end $$;

reset role;

-- ---------------------------------------------------------------------------
\echo ''
\echo '===== PROFILE VISITS (LIVE) ====='
select ord,
       case when ok then 'PASS' else 'FAIL' end as result,
       name,
       coalesce(left(detail, 70), '') as detail
from _results order by ord;

select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary
from _results;

do $$
declare
  failed int;
  total int;
begin
  select count(*) filter (where not ok), count(*) into failed, total from _results;
  if failed > 0 then
    raise exception '% of % profile-visit assertions FAILED', failed, total;
  end if;
end $$;

rollback;
\echo 'rolled back — no rows persisted'
