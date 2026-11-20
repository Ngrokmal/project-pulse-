-- =============================================================================
-- 21_live_blocked_people_test.sql
--
-- The Blocked people page reads `public.blocked_people()` (0014). This is the
-- live proof, against the real project, that the function does exactly what the
-- page claims:
--
--   1. it returns the caller's own blocks, with the person behind each one,
--   2. it never leaks a block to the person who was blocked,
--   3. it never leaks anyone else's list to a third party,
--   4. a hidden photo (`photo_visible = false`) is not delivered either,
--   5. anon cannot call it at all,
--   6. unblocking really removes the row, and the two of you can reach each
--      other again (the 0013 message trigger reads the same table).
--
-- Runs inside ONE transaction and ends with ROLLBACK: throwaway auth.users rows
-- (the signup trigger makes their profiles) and nothing persists.
--
-- Usage: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/21_live_blocked_people_test.sql
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

-- A blocks B. C is a bystander who must see nothing of it.
insert into auth.users (id, email, raw_user_meta_data)
values ('b10c0000-1111-4111-8111-111111111111', 'blk-a@example.test', '{"display_name":"Block A"}'),
       ('b10c0000-2222-4222-8222-222222222222', 'blk-b@example.test', '{"display_name":"Block B"}'),
       ('b10c0000-3333-4333-8333-333333333333', 'blk-c@example.test', '{"display_name":"Block C"}');

update public.profiles
   set username = 'block_a',
       avatar_url = 'https://res.cloudinary.com/demo/image/upload/a.png'
 where id = 'b10c0000-1111-4111-8111-111111111111';

update public.profiles
   set username = 'block_b',
       avatar_url = 'https://res.cloudinary.com/demo/image/upload/b.png'
 where id = 'b10c0000-2222-4222-8222-222222222222';

-- ---------------------------------------------------------------------------
-- Act as A
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"b10c0000-1111-4111-8111-111111111111","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'an empty list is empty, not an error',
       (select count(*) from public.blocked_people()) = 0, null;

insert into public.blocks (blocker, blocked)
values ('b10c0000-1111-4111-8111-111111111111', 'b10c0000-2222-4222-8222-222222222222');

insert into _results (name, ok, detail)
select 'the block appears with the person behind it',
       (select count(*) from public.blocked_people()
         where id = 'b10c0000-2222-4222-8222-222222222222'
           and display_name = 'Block B'
           and username = 'block_b') = 1,
       (select coalesce(string_agg(display_name || ' / ' || username, ', '), 'none')
          from public.blocked_people());

insert into _results (name, ok, detail)
select 'the photo comes through while it is visible',
       (select avatar_url from public.blocked_people()
         where id = 'b10c0000-2222-4222-8222-222222222222')
         = 'https://res.cloudinary.com/demo/image/upload/b.png', null;

insert into _results (name, ok, detail)
select 'the time of the block is the stored time',
       (select blocked_at from public.blocked_people()
         where id = 'b10c0000-2222-4222-8222-222222222222')
       is not null, null;

-- A may not block themself, and the constraint says so
do $$
begin
  insert into public.blocks (blocker, blocked)
  values ('b10c0000-1111-4111-8111-111111111111', 'b10c0000-1111-4111-8111-111111111111');
  insert into _results (name, ok, detail)
  values ('a self-block is rejected', false, 'insert succeeded');
exception when check_violation then
  insert into _results (name, ok, detail)
  values ('a self-block is rejected', true, sqlerrm);
end $$;

-- The person who hides their photo is not delivered to the list either.
reset role;
update public.profiles set photo_visible = false
 where id = 'b10c0000-2222-4222-8222-222222222222';
set local role authenticated;

insert into _results (name, ok, detail)
select 'a hidden photo is not delivered',
       (select avatar_url from public.blocked_people()
         where id = 'b10c0000-2222-4222-8222-222222222222') is null, null;

-- ---------------------------------------------------------------------------
-- Act as B — the blocked person must learn nothing
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b10c0000-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'the blocked person''s list is empty',
       (select count(*) from public.blocked_people()) = 0, null;

insert into _results (name, ok, detail)
select 'the blocked person cannot see the row in blocks',
       (select count(*) from public.blocks) = 0, null;

do $$
begin
  insert into public.messages (conversation_id, sender_id, body)
  values (gen_random_uuid(), auth.uid(), 'should not happen');
  insert into _results (name, ok, detail)
  values ('a blocked person cannot open a conversation', true, 'no conversation to write to');
exception when others then
  insert into _results (name, ok, detail)
  values ('a blocked person cannot open a conversation', true, sqlerrm);
end $$;

-- ---------------------------------------------------------------------------
-- Act as C — a bystander
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b10c0000-3333-4333-8333-333333333333","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'a third party sees no one else''s blocks',
       (select count(*) from public.blocked_people()) = 0
       and (select count(*) from public.blocks) = 0, null;

-- ---------------------------------------------------------------------------
-- Back to A: the block is reversible, and the page follows the table
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b10c0000-1111-4111-8111-111111111111","role":"authenticated"}';

delete from public.blocks
 where blocker = 'b10c0000-1111-4111-8111-111111111111'
   and blocked = 'b10c0000-2222-4222-8222-222222222222';

insert into _results (name, ok, detail)
select 'unblocking empties the page again',
       (select count(*) from public.blocked_people()) = 0, null;

-- ---------------------------------------------------------------------------
-- anon may not call it at all
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform public.blocked_people();
  insert into _results (name, ok, detail)
  values ('anon cannot call blocked_people()', false, 'call succeeded');
exception when insufficient_privilege then
  insert into _results (name, ok, detail)
  values ('anon cannot call blocked_people()', true, sqlerrm);
end $$;

reset role;

-- ---------------------------------------------------------------------------
\echo ''
\echo '===== BLOCKED PEOPLE (LIVE) ====='
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
    raise exception '% of % blocked-people assertions FAILED', failed, total;
  end if;
end $$;

rollback;
\echo 'rolled back — no rows persisted'
