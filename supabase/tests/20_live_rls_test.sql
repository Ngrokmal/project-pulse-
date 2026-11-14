-- =============================================================================
-- Live RLS verification against the real Supabase project.
-- Runs inside ONE transaction and ends with ROLLBACK: it creates two throwaway
-- auth.users rows (which the signup trigger turns into profiles) and then
-- undoes everything. Safe to run against the production database.
-- Usage: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/20_live_rls_test.sql
-- =============================================================================
begin;

create temp table _results (
  ord serial primary key,
  name text not null,
  ok boolean not null,
  detail text
) on commit drop;

-- the test acts as authenticated/anon, so the scratch table must be writable by them
grant select, insert on _results to public;
grant usage, select on sequence _results_ord_seq to public;

-- Two identities: A = the actor, B = "someone else".
\set a_id '''11111111-1111-4111-8111-111111111111'''
\set b_id '''22222222-2222-4222-8222-222222222222'''

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-4111-8111-111111111111', 'live-a@example.test', '{"display_name":"Live A"}'),
       ('22222222-2222-4222-8222-222222222222', 'live-b@example.test', '{"display_name":"Live B"}');

-- 1. signup trigger creates profile + account_status
insert into _results (name, ok, detail)
select 'auth.users insert → profile + account_status created',
       (select count(*) from public.profiles where id in ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222')) = 2
       and (select count(*) from public.account_status where user_id in ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222')) = 2,
       (select string_agg(display_name, ' | ') from public.profiles);

-- 2. handle_new_profile_status gave everyone an 'active' status
insert into _results (name, ok, detail)
select 'default account status is active',
       not exists (select 1 from public.account_status
                   where user_id in ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222')
                     and status <> 'active'), null;

-- service_role seeds a device + link (the Edge Function's job) before we act as A
insert into public.devices (device_hash, platform, hash_version)
values (repeat('a', 64), 'android', 1);
insert into public.account_device_history (user_id, device_id)
select '11111111-1111-4111-8111-111111111111', id from public.devices where device_hash = repeat('a', 64);

-- ---------------------------------------------------------------------------
-- Act as authenticated user A
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'A updates own display_name',
       (select display_name from public.profiles where id = auth.uid()) is not null, null;

update public.profiles set display_name = 'Live A renamed' where id = '11111111-1111-4111-8111-111111111111';
insert into _results (name, ok, detail)
select 'own profile update allowed',
       (select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111') = 'Live A renamed', null;

-- cross-user update must touch zero rows (RLS USING clause), not error
with touched as (
  update public.profiles set display_name = 'hacked'
  where id = '22222222-2222-4222-8222-222222222222'
  returning 1
)
insert into _results (name, ok, detail)
select 'cross-user profile update affects 0 rows', count(*) = 0, 'rows=' || count(*) from touched;

insert into _results (name, ok, detail)
select 'cross-user row unchanged (still readable)',
       (select display_name from public.profiles where id = '22222222-2222-4222-8222-222222222222') = 'Live B', null;

-- invalid username must be rejected by the DB constraint too
do $$
begin
  begin
    update public.profiles set username = 'Bad Name' where id = auth.uid();
    insert into _results (name, ok, detail) values ('username check constraint rejects bad value', false, 'no error raised');
  exception when check_violation then
    insert into _results (name, ok, detail) values ('username check constraint rejects bad value', true, sqlerrm);
  end;
  begin
    update public.profiles set username = 'live_a' where id = auth.uid();
    insert into _results (name, ok, detail) values ('valid username accepted', true, null);
  exception when others then
    insert into _results (name, ok, detail) values ('valid username accepted', false, sqlerrm);
  end;
  begin
    insert into public.profiles (id, display_name) values (gen_random_uuid(), 'rogue');
    insert into _results (name, ok, detail) values ('client cannot INSERT profiles', false, 'insert succeeded');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('client cannot INSERT profiles', true, sqlerrm);
  end;
  begin
    delete from public.profiles where id = auth.uid();
    insert into _results (name, ok, detail) values ('client cannot DELETE profiles', false, 'delete succeeded');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('client cannot DELETE profiles', true, sqlerrm);
  end;
  begin
    update public.profiles set joined_at = now() - interval '1 year' where id = auth.uid();
    insert into _results (name, ok, detail) values ('joined_at is not client-writable', false, 'update succeeded');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('joined_at is not client-writable', true, sqlerrm);
  end;
end $$;

insert into _results (name, ok, detail)
select 'account_status shows only own row',
       count(*) = 1 and bool_and(user_id = '11111111-1111-4111-8111-111111111111'),
       'visible=' || count(*)
from public.account_status;

do $$
begin
  begin
    update public.account_status set status = 'banned' where user_id = auth.uid();
    insert into _results (name, ok, detail) values ('client cannot write account_status', false, 'update succeeded');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('client cannot write account_status', true, sqlerrm);
  end;
  begin
    insert into public.devices (device_hash, platform, hash_version) values (repeat('b', 64), 'android', 1);
    insert into _results (name, ok, detail) values ('client cannot INSERT devices', false, 'insert succeeded');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('client cannot INSERT devices', true, sqlerrm);
  end;
  begin
    perform 1 from public.device_security_events;
    insert into _results (name, ok, detail) values ('device_security_events hidden from clients', false, 'select allowed');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('device_security_events hidden from clients', true, sqlerrm);
  end;
end $$;

insert into _results (name, ok, detail)
select 'device visible only through own link',
       count(*) = 1, 'visible devices=' || count(*)
from public.devices;

-- own FCM token CRUD
do $$
declare
  inserted int;
begin
  begin
    insert into public.fcm_tokens (user_id, token, platform) values (auth.uid(), 'dGVzdC10b2tlbi1saXZlLWEt0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'android');
    insert into _results (name, ok, detail) values ('own FCM token insert allowed', true, null);
  exception when others then
    insert into _results (name, ok, detail) values ('own FCM token insert allowed', false, sqlerrm);
  end;
  begin
    insert into public.fcm_tokens (user_id, token, platform)
    values ('22222222-2222-4222-8222-222222222222', 'dGVzdC10b2tlbi1mb3JnZWQtfedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210', 'android');
    insert into _results (name, ok, detail) values ('forged FCM token for another user denied', false, 'insert succeeded');
  exception when insufficient_privilege or check_violation then
    insert into _results (name, ok, detail) values ('forged FCM token for another user denied', true, sqlerrm);
  end;
  update public.fcm_tokens set is_active = true where user_id = auth.uid();
  insert into _results (name, ok, detail)
  select 'own FCM token update allowed', count(*) = 1, 'rows=' || count(*) from public.fcm_tokens where user_id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- Act as user B: must see A's profile (needed to chat) but never A's devices
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _results (name, ok, detail)
select 'B can read A''s public profile (chat requires it)',
       exists (select 1 from public.profiles where id = '11111111-1111-4111-8111-111111111111'), null;

insert into _results (name, ok, detail)
select 'B sees no rows in a device table linked to A',
       (select count(*) from public.devices) = 0, 'visible=' || (select count(*) from public.devices);

insert into _results (name, ok, detail)
select 'B cannot read A''s account_status',
       (select count(*) from public.account_status where user_id = '11111111-1111-4111-8111-111111111111') = 0
       and (select count(*) from public.account_status) = 1, null;

insert into _results (name, ok, detail)
select 'B sees only own FCM tokens',
       not exists (select 1 from public.fcm_tokens where user_id = '11111111-1111-4111-8111-111111111111'), null;

-- ---------------------------------------------------------------------------
-- anon must be locked out entirely
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  begin
    perform 1 from public.profiles limit 1;
    insert into _results (name, ok, detail) values ('anon cannot select profiles', false, 'select allowed');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('anon cannot select profiles', true, sqlerrm);
  end;
  begin
    perform 1 from public.account_status limit 1;
    insert into _results (name, ok, detail) values ('anon cannot select account_status', false, 'select allowed');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('anon cannot select account_status', true, sqlerrm);
  end;
  begin
    perform 1 from public.fcm_tokens limit 1;
    insert into _results (name, ok, detail) values ('anon cannot select fcm_tokens', false, 'select allowed');
  exception when insufficient_privilege then
    insert into _results (name, ok, detail) values ('anon cannot select fcm_tokens', true, sqlerrm);
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
\echo ''
\echo '===== LIVE RLS RESULTS ====='
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
    raise exception '% of % live RLS assertions FAILED', failed, total;
  end if;
end $$;

-- leave the production database exactly as we found it
rollback;
\echo 'rolled back — no rows persisted'
