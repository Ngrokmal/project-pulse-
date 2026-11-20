-- =============================================================================
-- Live verification of "suspended means closed" against the real project.
--
-- Runs inside ONE transaction and ends with ROLLBACK: it creates two throwaway
-- auth.users rows, has a real conversation, suspends one of them, and undoes
-- everything. Safe to run against the production database.
--
-- Usage: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/23_live_suspension_test.sql
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

\set a_id '''aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'''
\set b_id '''bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'''

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'susp-a@example.test', '{"display_name":"Suspended A"}'),
       ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'susp-b@example.test', '{"display_name":"Active B"}');

-- A phone that is signed in: a session, a refresh token, a push token and a
-- presence row — all of the things that must disappear when A is suspended.
insert into auth.sessions (id, user_id, created_at, updated_at, aal)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now(), now(), 'aal1');

insert into auth.refresh_tokens (instance_id, id, token, user_id, revoked, session_id)
values ('00000000-0000-0000-0000-000000000000', 900001, 'refresh-token-a',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');

insert into public.fcm_tokens (user_id, token) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   repeat('fcm-token-placeholder-', 6))
on conflict do nothing;

insert into public.user_presence (user_id, last_seen_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now())
on conflict (user_id) do update set last_seen_at = now();

-- A real conversation with a real message, so "cannot read" is not "empty
-- table" in disguise.
select public.start_direct_conversation('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
  from (select set_config('request.jwt.claims',
        '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true)) _;

-- ---------------------------------------------------------------------------
-- 1. The switch keeps both columns true to each other
-- ---------------------------------------------------------------------------
insert into _results (name, ok, detail)
select 'a new account starts active, unsuspended, with a case code',
       not exists (select 1 from public.account_status
                    where user_id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
                      and (suspended or status <> 'active' or case_code is null)),
       (select string_agg(case_code, ' | ') from public.account_status
         where user_id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));

update public.account_status set suspended = true
 where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into _results (name, ok, detail)
select 'ticking `suspended` flips the enum too',
       (select suspended and status = 'suspended' and starts_at <= now()
          from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       (select status::text from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

insert into _results (name, ok, detail)
select 'a fresh suspension starts a new window',
       (select starts_at > now() - interval '1 minute'
          from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       (select starts_at::text from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

-- ---------------------------------------------------------------------------
-- 2. The session, the push token and the presence row are gone
-- ---------------------------------------------------------------------------
insert into _results (name, ok, detail)
select 'suspending deletes the session and with it every refresh token',
       not exists (select 1 from auth.sessions where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
       and not exists (select 1 from auth.refresh_tokens where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       coalesce((select count(*)::text from auth.refresh_tokens
                  where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '0');

insert into _results (name, ok, detail)
select 'suspending deletes push tokens and the presence row',
       not exists (select 1 from public.fcm_tokens where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
       and not exists (select 1 from public.user_presence where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       'fcm + presence cleared';

-- ---------------------------------------------------------------------------
-- 3. As the suspended account: nothing works but the two doors that must
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

do $$
declare
  v_uid uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_n int;
  v_code text;
  v_state text;
begin
  -- the row that says "you are on hold" is still readable: it is how the app
  -- knows what to show.
  select suspended, case_code into v_state, v_code
    from public.account_status where user_id = v_uid;
  insert into _results (name, ok, detail)
  values ('own status row is readable while suspended', v_state = 'true' and v_code like 'PULSE-%', v_code);

  -- reads
  select count(*) into v_n from public.messages;
  insert into _results values (default, 'messages are unreadable while suspended', v_n = 0, v_n || ' rows');

  select count(*) into v_n from public.conversations;
  insert into _results values (default, 'conversations are unreadable while suspended', v_n = 0, v_n || ' rows');

  select count(*) into v_n from public.conversation_members;
  insert into _results values (default, 'conversation membership is unreadable while suspended', v_n = 0, v_n || ' rows');

  select count(*) into v_n from public.profiles;
  insert into _results values (default, 'other people''s profiles are unreadable while suspended', v_n = 0, v_n || ' rows');

  select count(*) into v_n from public.user_presence;
  insert into _results values (default, 'presence is unreadable while suspended', v_n = 0, v_n || ' rows');

  -- writes: the one that matters is the message
  begin
    insert into public.messages (conversation_id, sender_id, kind, body)
    values ((select id from public.conversations limit 1), v_uid, 'text', 'should never land');
    insert into _results values (default, 'a suspended account cannot send a message', false, 'insert succeeded');
  exception when others then
    insert into _results values (default, 'a suspended account cannot send a message', true, sqlerrm);
  end;

  -- a definer function bypasses RLS on purpose; the table guard still refuses
  begin
    perform public.start_direct_conversation('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    insert into _results values (default, 'a suspended account cannot start a chat through the RPC', false, 'RPC succeeded');
  exception when others then
    insert into _results values (default, 'a suspended account cannot start a chat through the RPC',
      sqlstate = 'PULSE', sqlstate || ': ' || sqlerrm);
  end;

  begin
    perform public.touch_presence();
    insert into _results values (default, 'a suspended account cannot heartbeat presence', false, 'RPC succeeded');
  exception when others then
    insert into _results values (default, 'a suspended account cannot heartbeat presence', true, sqlstate || ': ' || sqlerrm);
  end;

  -- the door that stays open
  begin
    insert into public.account_appeals (user_id, case_code, note)
    values (v_uid, 'PULSE-WRONG-000', 'this reference is not mine');
    insert into _results values (default, 'an appeal needs the caller''s own case code', false, 'accepted a foreign code');
  exception when others then
    insert into _results values (default, 'an appeal needs the caller''s own case code', true, sqlerrm);
  end;

  begin
    insert into public.account_appeals (user_id, case_code, note)
    values (v_uid, v_code, 'I shared a work document in a group and stopped when asked.');
    insert into _results values (default, 'a suspended account can appeal, once', true, 'inserted');
  exception when others then
    insert into _results values (default, 'a suspended account can appeal, once', false, sqlerrm);
  end;

  begin
    insert into public.account_appeals (user_id, case_code, note)
    values (v_uid, v_code, 'A second appeal while the first is open.');
    insert into _results values (default, 'a second open appeal is refused', false, 'second insert succeeded');
  exception when others then
    insert into _results values (default, 'a second open appeal is refused', true, sqlerrm);
  end;

  -- and cannot lift its own suspension
  begin
    update public.account_status set suspended = false where user_id = v_uid;
    insert into _results values (default, 'a suspended account cannot unsuspend itself',
      (select suspended from public.account_status where user_id = v_uid), 'update returned');
  exception when others then
    insert into _results values (default, 'a suspended account cannot unsuspend itself', true, sqlerrm);
  end;

  if (select suspended from public.account_status where user_id = v_uid) then
    insert into _results values (default, 'still suspended after trying', true, 'unchanged');
  else
    insert into _results values (default, 'still suspended after trying', false, 'it unsuspended itself');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. The other person is untouched — a suspension is not a chat outage
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.conversations;
  insert into _results values (default, 'the other side still sees the conversation', v_n = 1, v_n || ' rows');

  select count(*) into v_n from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  insert into _results values (default, 'the other side still sees the profile row', v_n = 1, v_n || ' rows');

  begin
    insert into public.messages (conversation_id, sender_id, kind, body)
    values ((select id from public.conversations limit 1),
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'text', 'still able to talk');
    insert into _results values (default, 'the other side can still send', true, 'inserted');
  exception when others then
    insert into _results values (default, 'the other side can still send', false, sqlerrm);
  end;

  begin
    insert into public.account_appeals (user_id, case_code, note)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            (select case_code from public.account_status where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
            'an active account has nothing to appeal');
    insert into _results values (default, 'an active account cannot file an appeal', false, 'inserted');
  exception when others then
    insert into _results values (default, 'an active account cannot file an appeal', true, sqlerrm);
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- 5. Restoring the account restores everything
-- ---------------------------------------------------------------------------
update public.account_status set suspended = false
 where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into _results (name, ok, detail)
select 'unsuspending puts the enum back to active',
       (select not suspended and status = 'active' from public.account_status
         where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       (select status::text from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

update public.account_status set status = 'banned'
 where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into _results (name, ok, detail)
select 'writing the enum also sets the switch',
       (select suspended from public.account_status where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
       'banned → suspended = true';

update public.account_status set suspended = false
 where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.messages;
  insert into _results values (default, 'restored: messages are readable again', v_n >= 1, v_n || ' rows');
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- 6. The guard cannot be forgotten by the next migration
-- ---------------------------------------------------------------------------
insert into _results (name, ok, detail)
select 'every policy on a user-owned table asks is_account_active',
       not exists (
         select 1 from pg_policies p
          where p.schemaname = 'public'
            and p.tablename in (
              'messages', 'conversations', 'conversation_members', 'friend_requests',
              'friendships', 'blocks', 'profile_visits', 'calls', 'force_audio_alerts',
              'user_presence', 'fcm_tokens', 'reports', 'account_device_history',
              'devices', 'profiles'
            )
            and coalesce(p.qual, '') || coalesce(p.with_check, '') not ilike '%is_account_active%'
       ),
       (select coalesce(string_agg(p.tablename || '.' || p.policyname, ', '), 'none')
          from pg_policies p
         where p.schemaname = 'public'
           and p.tablename in (
             'messages', 'conversations', 'conversation_members', 'friend_requests',
             'friendships', 'blocks', 'profile_visits', 'calls', 'force_audio_alerts',
             'user_presence', 'fcm_tokens', 'reports', 'account_device_history',
             'devices', 'profiles'
           )
           and coalesce(p.qual, '') || coalesce(p.with_check, '') not ilike '%is_account_active%');

insert into _results (name, ok, detail)
select 'every activity table carries the suspend guard trigger',
       (select count(*) from pg_trigger t
         where not t.tgisinternal
           and t.tgname like 'guard\_%\_activity'
           and t.tgenabled = 'O') = 13,
       (select count(*)::text || ' triggers' from pg_trigger t
         where not t.tgisinternal and t.tgname like 'guard\_%\_activity');

insert into _results (name, ok, detail)
select 'the switch and the enum cannot drift apart',
       not exists (select 1 from public.account_status where suspended <> (status <> 'active')),
       (select count(*)::text || ' rows checked' from public.account_status);

insert into _results (name, ok, detail)
select 'account_status is published to Realtime so the flip reaches an open app',
       exists (select 1 from pg_publication_tables
                where pubname = 'supabase_realtime' and tablename = 'account_status'),
       'publication membership';

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
\echo ''
\echo '===== LIVE SUSPENSION RESULTS ====='
select ord,
       case when ok then 'PASS' else 'FAIL' end as result,
       name,
       coalesce(left(detail, 70), '') as detail
from _results order by ord;

select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary from _results;

do $$
declare
  failed int;
  total int;
begin
  select count(*) filter (where not ok), count(*) into failed, total from _results;
  if failed > 0 then
    raise exception '% of % suspension assertions FAILED', failed, total;
  end if;
end $$;

-- leave the production database exactly as we found it
rollback;
\echo 'rolled back — no rows persisted';
