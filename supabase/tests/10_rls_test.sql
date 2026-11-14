-- RLS / privilege tests. Runs against supabase/tests/00_local_stub.sql on a
-- plain PostgreSQL. Every assertion raises an exception on failure, so a
-- silent pass is impossible: the script either completes or fails loudly.
\set ON_ERROR_STOP on

create or replace function public.test_expect_denied(p_sql text)
returns void language plpgsql as $fn$
begin
  begin
    execute p_sql;
  exception when insufficient_privilege then
    return; -- expected: RLS or column privilege denied the statement
  end;
  raise exception 'SECURITY TEST FAILED: statement was allowed but must be denied: %', p_sql;
end;
$fn$;

create or replace function public.test_row_count(p_sql text)
returns bigint language plpgsql as $fn$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$fn$;

grant execute on function public.test_expect_denied(text), public.test_row_count(text)
  to authenticated, anon;

-- Two accounts: A (caller) and B (other user).
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com', '{"display_name":"User A"}'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com', '{"display_name":"User B"}')
on conflict (id) do nothing;

do $do$
begin
  if (select count(*) from public.profiles) <> 2 then
    raise exception 'trigger did not create a profile per auth user';
  end if;
  if (select count(*) from public.account_status) <> 2 then
    raise exception 'trigger did not create an account_status row per profile';
  end if;
end;
$do$;

-- ===================== as authenticated user A =====================
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

do $do$
declare n bigint;
begin
  -- 1. can read own profile and (by design) other profiles
  select count(*) into n from public.profiles;
  if n <> 2 then raise exception 'profiles select returned % rows, expected 2', n; end if;

  -- 2. can update own profile
  if public.test_row_count($q$update public.profiles set display_name = 'A renamed' where id = auth.uid()$q$) <> 1 then
    raise exception 'owner could not update own profile';
  end if;

  -- 3. cannot update another user's profile
  if public.test_row_count($q$update public.profiles set display_name = 'hacked' where id = '22222222-2222-2222-2222-222222222222'$q$) <> 0 then
    raise exception 'SECURITY: user A updated user B profile';
  end if;

  -- 4. cannot move username to a forbidden format (constraint must fire)
  begin
    execute $q$update public.profiles set username = 'Not Allowed!' where id = auth.uid()$q$;
    raise exception 'invalid username format was accepted';
  exception when check_violation then null;
  end;
end;
$do$;

-- 5. no INSERT policy -> denied
select public.test_expect_denied($q$insert into public.profiles (id, display_name) values ('33333333-3333-3333-3333-333333333333', 'intruder')$q$);

-- 6. no DELETE privilege at all on profiles (revoked + no DELETE policy).
--    The statement must be rejected outright, not silently delete 0 rows.
select public.test_expect_denied($q$delete from public.profiles where id = auth.uid()$q$);

-- 7. column privilege: cannot rewrite joined_at
select public.test_expect_denied($q$update public.profiles set joined_at = now() - interval '3 years' where id = auth.uid()$q$);

-- 8. account_status: sees only own row, cannot change it
do $do$
declare n bigint;
begin
  select count(*) into n from public.account_status;
  if n <> 1 then raise exception 'account_status select returned % rows, expected 1', n; end if;
  -- clients hold no UPDATE privilege on account_status: a restriction can
  -- never be lifted from the client, not even for the caller's own row
  begin
    execute $q$update public.account_status set status = 'active'$q$;
    raise exception 'SECURITY: client changed its own account status';
  exception when insufficient_privilege then null;
  end;
end;
$do$;
select public.test_expect_denied($q$insert into public.account_status (user_id, status) values (auth.uid(), 'active')$q$);

-- 9. devices: cannot register a device from the client
select public.test_expect_denied($q$insert into public.devices (device_hash) values (repeat('a', 64))$q$);

-- 10. fcm token: can register own token, cannot touch another account's
insert into public.fcm_tokens (user_id, token) values (auth.uid(), 'token-for-user-a-0123456789')
  on conflict (token) do nothing;
select public.test_expect_denied($q$insert into public.fcm_tokens (user_id, token) values ('22222222-2222-2222-2222-222222222222', 'token-forged-by-a-0123456789')$q$);
do $do$ begin
  if public.test_row_count($q$update public.fcm_tokens set is_active = false where user_id = '22222222-2222-2222-2222-222222222222'$q$) <> 0 then
    raise exception 'SECURITY: user A modified user B tokens';
  end if;
end; $do$;

-- ===================== as trusted service_role =====================
reset role;
set role service_role;

insert into public.devices (device_hash, hash_version, platform)
values (repeat('b', 64), 1, 'android') returning id \gset dev_
insert into public.account_device_history (user_id, device_id)
values ('11111111-1111-1111-1111-111111111111', :'dev_id');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
do $do$ begin
  if (select count(*) from public.devices) <> 1 then
    raise exception 'linked device not visible to its own account';
  end if;
end; $do$;

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
do $do$ begin
  if (select count(*) from public.devices) <> 0 then
    raise exception 'SECURITY: unrelated account can see the device';
  end if;
end; $do$;

-- ===================== as anon =====================
reset role;
set role anon;
select public.test_expect_denied($q$select * from public.profiles$q$);
select public.test_expect_denied($q$select * from public.account_status$q$);

reset role;
\echo 'ALL RLS TESTS PASSED'
