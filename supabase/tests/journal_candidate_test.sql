\set ON_ERROR_STOP on
-- Synthetic data only. Assertions deliberately raise on failure.
do $$ begin
  if (select count(*) from public.pulse_message_changes) <> 1 then raise exception 'backfill missing'; end if;
end $$;
begin;
insert into public.messages(id,conversation_id,sender_id,body,client_id) values
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','aborted','journal-rollback');
rollback;
insert into public.messages(id,conversation_id,sender_id,body,client_id) values
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','synthetic private text','journal-committed');
update public.messages set body='edited' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
delete from public.messages where id='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
do $$ begin
  if (select array_agg(revision order by revision) from public.pulse_message_changes) <> array[1,2,3,4]::bigint[] then
    raise exception 'revisions not contiguous';
  end if;
end $$;
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
do $$ declare n int; begin
  select count(*) into n from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,2);
  if n <> 2 then raise exception 'paging failed'; end if;
  select count(*) into n from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,100) where message_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd' and message is null;
  if n <> 2 then raise exception 'hard-deleted content exposed or tombstones missing'; end if;
  select count(*) into n from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,100) where message_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and message->>'body'='edited';
  if n <> 2 then raise exception 'current row absent'; end if;
  begin perform * from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',5,100); raise exception 'future cursor accepted'; exception when invalid_parameter_value then null; end;
  begin perform * from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,501); raise exception 'oversized page accepted'; exception when invalid_parameter_value then null; end;
  begin perform count(*) from public.pulse_message_changes; raise exception 'direct journal read accepted'; exception when insufficient_privilege then null; end;
end $$;
set request.jwt.claims = '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
do $$ begin
  begin perform * from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,100); raise exception 'outsider accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.account_status set status='suspended' where user_id='22222222-2222-4222-8222-222222222222';
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
do $$ begin
  begin perform * from public.pulse_message_changes_since('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0,100); raise exception 'suspended member accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
reset request.jwt.claims;
delete from public.conversations where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$ begin
  if exists(select 1 from public.pulse_message_changes) or exists(select 1 from public.pulse_message_revision_heads) then raise exception 'cascade left journal'; end if;
end $$;
select 'journal candidate local assertions passed' as result;
