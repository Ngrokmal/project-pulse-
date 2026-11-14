-- =============================================================================
-- Calls: the state machine, who may move it, and who may not even see it.
-- (0007_calls.sql). One transaction, rolled back.
-- A = caller, B = callee, C = outsider.
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-0000-4000-8000-000000000001', 'c-a@example.test', '{"display_name":"Ayesha"}'),
       ('22222222-0000-4000-8000-000000000002', 'c-b@example.test', '{"display_name":"Bashir"}'),
       ('33333333-0000-4000-8000-000000000003', 'c-c@example.test', '{"display_name":"Chandni"}');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}';

create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

insert into _ids values ('conv', public.start_direct_conversation('22222222-0000-4000-8000-000000000002'));

-- ---------------------------------------------------------------- start
insert into _ids values ('call', public.start_call((select id from _ids where label='conv'), 'audio'));

insert into _r (name, ok, detail)
select 'a call starts in state ringing',
       (select state = 'ringing' from public.calls where id = (select id from _ids where label='call')),
       coalesce((select state from public.calls where id = (select id from _ids where label='call')), 'null');

insert into _r (name, ok, detail)
select 'the caller is me and the callee is the other person',
       (select caller_id = '11111111-0000-4000-8000-000000000001'
                 and callee_id = '22222222-0000-4000-8000-000000000002'
          from public.calls where id = (select id from _ids where label='call')),
       'parties';

insert into _r (name, ok, detail)
select 'only one call row exists so far',
       (select count(*) from public.calls) = 1,
       'calls=' || (select count(*) from public.calls);
do $$
begin
  perform public.start_call((select id from _ids where label='conv'), 'audio');
  insert into _r (name, ok, detail) values ('a second call while one is ringing is refused', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('a second call while one is ringing is refused', true, 'refused');
end $$;

-- a bogus kind is refused outright
do $$
begin
  perform public.start_call((select id from _ids where label='conv'), 'hologram');
  insert into _r (name, ok, detail) values ('an unknown call kind is refused', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('an unknown call kind is refused', true, 'refused');
end $$;

-- ---------------------------------------------------------------- accept
-- the caller may not accept their own call
do $$
begin
  perform public.accept_call((select id from _ids where label='call'));
  insert into _r (name, ok, detail) values ('the caller cannot accept their own call', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('the caller cannot accept their own call', true, 'refused');
end $$;

set local request.jwt.claims = '{"sub":"22222222-0000-4000-8000-000000000002","role":"authenticated"}';
select public.accept_call((select id from _ids where label='call'));
insert into _r (name, ok, detail)
select 'the callee accepts and the call is connecting, not connected',
       (select state = 'connecting' and answered_at is not null
          from public.calls where id = (select id from _ids where label='call')),
       coalesce((select state from public.calls where id = (select id from _ids where label='call')), 'null');

-- accepting twice is not a legal transition
do $$
begin
  perform public.accept_call((select id from _ids where label='call'));
  insert into _r (name, ok, detail) values ('accepting twice is refused', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('accepting twice is refused', true, 'refused');
end $$;

-- ---------------------------------------------------------------- connect
select public.confirm_call_connected((select id from _ids where label='call'));
insert into _r (name, ok, detail)
select 'confirming media moves connecting -> active',
       (select state = 'active' from public.calls where id = (select id from _ids where label='call')),
       coalesce((select state from public.calls where id = (select id from _ids where label='call')), 'null');

-- ---------------------------------------------------------------- reconnecting
select public.set_call_reconnecting((select id from _ids where label='call'), true);
insert into _r (name, ok, detail)
select 'a blip moves the call to reconnecting',
       (select state = 'reconnecting' from public.calls where id = (select id from _ids where label='call')),
       'state';
select public.set_call_reconnecting((select id from _ids where label='call'), false);
insert into _r (name, ok, detail)
select 'and back to active when it recovers',
       (select state = 'active' from public.calls where id = (select id from _ids where label='call')),
       'state';

-- ---------------------------------------------------------------- end
select public.end_call((select id from _ids where label='call'), 'hangup');
insert into _r (name, ok, detail)
select 'hanging up ends the call with a reason',
       (select state = 'ended' and end_reason = 'hangup' and ended_at is not null
          from public.calls where id = (select id from _ids where label='call')),
       (select state || '/' || coalesce(end_reason,'-') from public.calls where id = (select id from _ids where label='call'));

select public.end_call((select id from _ids where label='call'), 'hangup');
insert into _r (name, ok, detail)
select 'ending an ended call is idempotent',
       (select state = 'ended' from public.calls where id = (select id from _ids where label='call')),
       'state';

-- ---------------------------------------------------------------- declined / missed
-- No DELETE grant for clients: ended calls stay in the history, and an ended
-- call does not block the next one.
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}';
insert into _ids values ('call2', public.start_call((select id from _ids where label='conv'), 'video'));
set local request.jwt.claims = '{"sub":"22222222-0000-4000-8000-000000000002","role":"authenticated"}';
select public.decline_call((select id from _ids where label='call2'));
insert into _r (name, ok, detail)
select 'declining lands in declined/declined',
       (select state = 'declined' and end_reason = 'declined'
          from public.calls where id = (select id from _ids where label='call2')),
       (select state from public.calls where id = (select id from _ids where label='call2'));

set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}';
insert into _ids values ('call3', public.start_call((select id from _ids where label='conv'), 'audio'));
select public.end_call((select id from _ids where label='call3'), 'timeout');
insert into _r (name, ok, detail)
select 'a timeout while ringing is recorded as missed',
       (select state = 'missed' and end_reason = 'timeout'
          from public.calls where id = (select id from _ids where label='call3')),
       (select state from public.calls where id = (select id from _ids where label='call3'));

-- a caller hanging up while it still rings ends it, it does not become missed
insert into _ids values ('call4', public.start_call((select id from _ids where label='conv'), 'audio'));
select public.end_call((select id from _ids where label='call4'), 'hangup');
insert into _r (name, ok, detail)
select 'the caller hanging up while ringing ends the call',
       (select state = 'ended' from public.calls where id = (select id from _ids where label='call4')),
       (select state from public.calls where id = (select id from _ids where label='call4'));

-- ---------------------------------------------------------------- outsiders
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000003","role":"authenticated"}';
insert into _r (name, ok, detail)
select 'an outsider sees none of these calls',
       (select count(*) from public.calls) = 0,
       'visible=' || (select count(*) from public.calls);

do $$
begin
  perform public.accept_call((select id from _ids where label='call4'));
  insert into _r (name, ok, detail) values ('an outsider cannot accept a call', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('an outsider cannot accept a call', true, 'refused');
end $$;

do $$
begin
  perform public.end_call((select id from _ids where label='call4'), 'hangup');
  insert into _r (name, ok, detail) values ('an outsider cannot end a call', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('an outsider cannot end a call', true, 'refused');
end $$;

do $$
begin
  perform public.start_call((select id from _ids where label='conv'), 'audio');
  insert into _r (name, ok, detail) values ('an outsider cannot start a call in someone else''s chat', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('an outsider cannot start a call in someone else''s chat', true, 'refused');
end $$;

-- ---------------------------------------------------------------- direct writes
do $$
begin
  insert into public.calls (conversation_id, caller_id, callee_id)
  values ((select id from _ids where label='conv'),
          '33333333-0000-4000-8000-000000000003',
          '11111111-0000-4000-8000-000000000001');
  insert into _r (name, ok, detail) values ('a client cannot insert a call row directly', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('a client cannot insert a call row directly', true, 'refused');
end $$;

-- ---------------------------------------------------------------- groups
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000001","role":"authenticated"}';
insert into _ids values ('grp', public.create_group('Call me maybe', array['33333333-0000-4000-8000-000000000003']::uuid[]));
do $$
begin
  perform public.start_call((select id from _ids where label='grp'), 'audio');
  insert into _r (name, ok, detail) values ('group calls are refused by name, not half-supported', false, 'allowed');
exception when others then
  insert into _r (name, ok, detail) values ('group calls are refused by name, not half-supported', true, 'refused');
end $$;

do $$
declare failed int;
begin
  select count(*) filter (where not ok) into failed from _r;
  if failed > 0 then raise exception '% call assertions FAILED', failed; end if;
end $$;

select ord, case when ok then 'PASS' else 'FAIL' end as result, name, coalesce(left(detail, 60), '') as detail
  from _r order by ord;
select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary from _r;

rollback;
