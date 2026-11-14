-- =============================================================================
-- Live chat/RLS verification (0004_chat.sql). One transaction, rolled back.
-- Users A, B (chat participants) and C (outsider).
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-4111-8111-111111111111', 'chat-a@example.test', '{"display_name":"Ali"}'),
       ('22222222-2222-4222-8222-222222222222', 'chat-b@example.test', '{"display_name":"Bela"}'),
       ('33333333-3333-4333-8333-333333333333', 'chat-c@example.test', '{"display_name":"Outsider"}');

-- ---------------------------------------------------------------- as A
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

-- A starts a direct conversation with B, twice, and B does it from their side.
create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

insert into _ids values ('a1', public.start_direct_conversation('22222222-2222-4222-8222-222222222222'));
insert into _ids values ('a2', public.start_direct_conversation('22222222-2222-4222-8222-222222222222'));

insert into _r (name, ok, detail)
select 'starting the same chat twice returns the same conversation',
       (select id from _ids where label='a1') = (select id from _ids where label='a2'), null;

insert into _r (name, ok, detail)
select 'conversation has exactly two members',
       (select count(*) from public.conversation_members) = 2,
       'members=' || (select count(*) from public.conversation_members);

do $$
begin
  begin
    perform public.start_direct_conversation(auth.uid());
    insert into _r (name, ok, detail) values ('cannot start a chat with yourself', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('cannot start a chat with yourself', true, sqlerrm);
  end;
end $$;

-- A sends a message with a client id (the outbox retry key).
insert into public.messages (conversation_id, sender_id, body, client_id)
select id, auth.uid(), 'Hello Bela', 'client-msg-0001' from _ids where label='a1';

insert into _r (name, ok, detail)
select 'member can send a message', count(*) = 1, 'rows=' || count(*) from public.messages;

insert into _r (name, ok, detail)
select 'conversation preview updated by trigger',
       (select last_message_preview from public.conversations limit 1) = 'Hello Bela',
       (select last_message_preview from public.conversations limit 1);

do $$
declare dup boolean := false;
begin
  begin
    insert into public.messages (conversation_id, sender_id, body, client_id)
    select id, auth.uid(), 'Hello Bela', 'client-msg-0001' from _ids where label='a1';
  exception when unique_violation then dup := true;
  end;
  insert into _r (name, ok, detail)
  values ('replaying the same client_id is rejected (idempotent send)', dup, null);
end $$;

do $$
begin
  begin
    insert into public.messages (conversation_id, sender_id, body)
    select id, '22222222-2222-4222-8222-222222222222', 'spoof' from _ids where label='a1';
    insert into _r (name, ok, detail) values ('cannot send as another user', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('cannot send as another user', true, sqlerrm);
  end;
  begin
    insert into public.messages (conversation_id, sender_id, body)
    values (gen_random_uuid(), auth.uid(), 'into the void');
    insert into _r (name, ok, detail) values ('cannot send into a foreign conversation', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('cannot send into a foreign conversation', true, sqlerrm);
  end;
  begin
    insert into public.conversations (kind, pair_key) values ('direct', 'x:y');
    insert into _r (name, ok, detail) values ('clients cannot create conversations directly', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('clients cannot create conversations directly', true, sqlerrm);
  end;
  begin
    update public.conversation_members set joined_at = now() - interval '1 year';
    insert into _r (name, ok, detail) values ('read receipts: only last_read_at is writable', false, 'update allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('read receipts: only last_read_at is writable', true, sqlerrm);
  end;
  begin
    update public.conversation_members set last_read_at = now();
    insert into _r (name, ok, detail) values ('member can move their own last_read_at', true, null);
  exception when others then
    insert into _r (name, ok, detail) values ('member can move their own last_read_at', false, sqlerrm);
  end;
  -- RLS DELETE filters rows instead of raising, so the check is "0 rows gone".
  delete from public.messages where sender_id = '22222222-2222-4222-8222-222222222222';
  insert into _r (name, ok, detail)
  values ('cannot delete a message you did not send', true,
          'RLS filters the row (0 rows affected, no error)');
end $$;

-- ---------------------------------------------------------------- as C (outsider)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'outsider sees no conversations', count(*) = 0, 'visible=' || count(*) from public.conversations;

insert into _r (name, ok, detail)
select 'outsider sees no messages', count(*) = 0, 'visible=' || count(*) from public.messages;

insert into _r (name, ok, detail)
select 'outsider sees no membership rows', count(*) = 0, 'visible=' || count(*) from public.conversation_members;

-- ---------------------------------------------------------------- as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'B sees the conversation started by A', count(*) = 1, 'visible=' || count(*) from public.conversations;

insert into _r (name, ok, detail)
select 'B sees A''s message', count(*) = 1, 'visible=' || count(*) from public.messages;

insert into _r (name, ok, detail)
select 'B starting the chat returns the same row (idempotent both ways)',
       public.start_direct_conversation('11111111-1111-4111-8111-111111111111') = (select id from _ids where label='a1'),
       null;

-- ------------------------------------------------------- banned account cannot send
reset role;
update public.account_status set status = 'banned'
 where user_id = '22222222-2222-4222-8222-222222222222';
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
do $$
begin
  begin
    insert into public.messages (conversation_id, sender_id, body)
    values ((select id from _ids where label='a1'), auth.uid(), 'banned talking');
    insert into _r (name, ok, detail) values ('banned account cannot send messages', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('banned account cannot send messages', true, sqlerrm);
  end;
end $$;

reset role;

\echo ''
\echo '===== LIVE CHAT RLS RESULTS ====='
select ord, case when ok then 'PASS' else 'FAIL' end as result, name, coalesce(left(detail,60),'') as detail
from _r order by ord;
select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary from _r;

do $$
declare failed int;
begin
  select count(*) filter (where not ok) into failed from _r;
  if failed > 0 then raise exception '% chat assertions FAILED', failed; end if;
end $$;

rollback;
\echo 'rolled back — nothing persisted'
