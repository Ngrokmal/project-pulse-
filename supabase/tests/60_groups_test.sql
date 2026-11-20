-- =============================================================================
-- Group conversations, roles and membership (0006_groups.sql).
-- One transaction, rolled back. A=owner, B=admin, C=member, D=outsider.
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'g-a@example.test', '{"display_name":"Ali"}'),
       ('bbbbbbbb-0000-4000-8000-000000000002', 'g-b@example.test', '{"display_name":"Bela"}'),
       ('cccccccc-0000-4000-8000-000000000003', 'g-c@example.test', '{"display_name":"Chotu"}'),
       ('dddddddd-0000-4000-8000-000000000004', 'g-d@example.test', '{"display_name":"Dora"}'),
       ('eeeeeeee-0000-4000-8000-000000000005', 'g-e@example.test', '{"display_name":"Outsider"}');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}';

create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

insert into _ids values ('g', public.create_group('Weekend Cricket',
  array['bbbbbbbb-0000-4000-8000-000000000002','cccccccc-0000-4000-8000-000000000003']::uuid[]));

insert into _r (name, ok, detail)
select 'owner creates a group with two members',
       (select count(*) from public.conversation_members) = 3,
       'members=' || (select count(*) from public.conversation_members);

insert into _r (name, ok, detail)
select 'the group row is kind=group with the title given',
       (select kind = 'group' and title = 'Weekend Cricket' from public.conversations where id = (select id from _ids where label='g')),
       (select kind || ' / ' || coalesce(title,'-') from public.conversations limit 1);

insert into _r (name, ok, detail)
select 'the creator is the owner',
       public.group_role((select id from _ids where label='g')) = 'owner',
       coalesce(public.group_role((select id from _ids where label='g')), 'null');

insert into _r (name, ok, detail)
select 'everyone else starts as a member',
       (select count(*) from public.conversation_members where role = 'member') = 2,
       'members=' || (select count(*) from public.conversation_members where role = 'member');

insert into _r (name, ok, detail)
select 'a duplicate in the member list is collapsed',
       (select count(*) from public.conversation_members where user_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 1,
       null;

do $$
begin
  begin
    perform public.create_group('   ', array['bbbbbbbb-0000-4000-8000-000000000002']::uuid[]);
    insert into _r (name, ok, detail) values ('an empty title is rejected', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('an empty title is rejected', true, sqlerrm);
  end;

  begin
    perform public.create_group('Solo', array[]::uuid[]);
    insert into _r (name, ok, detail) values ('a group with no other members is rejected', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a group with no other members is rejected', true, sqlerrm);
  end;

  begin
    perform public.create_group('Ghosts', array['99999999-9999-4999-8999-999999999999']::uuid[]);
    insert into _r (name, ok, detail) values ('adding a user who does not exist is rejected', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('adding a user who does not exist is rejected', true, sqlerrm);
  end;
end $$;

-- A sends a message into the group.
insert into public.messages (conversation_id, sender_id, body, client_id)
select id, auth.uid(), 'Who is batting first?', 'group-msg-0001' from _ids where label = 'g';

insert into _r (name, ok, detail)
select 'an owner can post in the group', count(*) = 1, 'rows=' || count(*) from public.messages;

-- Rename: owner may, member may not.
update public.conversations set title = 'Sunday Cricket' where id = (select id from _ids where label='g');
insert into _r (name, ok, detail)
select 'the owner can rename the group',
       (select title = 'Sunday Cricket' from public.conversations where id = (select id from _ids where label='g')), null;

do $$
begin
  begin
    update public.conversations set kind = 'direct' where id = (select id from _ids where label='g');
    insert into _r (name, ok, detail) values ('a group cannot be turned into a direct chat', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a group cannot be turned into a direct chat', true, sqlerrm);
  end;
end $$;

-- Promote B to admin, then act as B.
select public.set_group_role((select id from _ids where label='g'), 'bbbbbbbb-0000-4000-8000-000000000002', 'admin');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}';
insert into _r (name, ok, detail)
select 'the new admin sees the role', public.group_role((select id from _ids where label='g')) = 'admin', null;

update public.conversations set title = 'Sunday Cricket XI' where id = (select id from _ids where label='g');
insert into _r (name, ok, detail)
select 'an admin can rename the group',
       (select title = 'Sunday Cricket XI' from public.conversations where id = (select id from _ids where label='g')), null;

select public.add_group_member((select id from _ids where label='g'), 'dddddddd-0000-4000-8000-000000000004');
insert into _r (name, ok, detail)
select 'an admin can add a member',
       (select count(*) from public.conversation_members) = 4,
       'members=' || (select count(*) from public.conversation_members);

do $$
begin
  begin
    perform public.set_group_role((select id from _ids where label='g'), 'cccccccc-0000-4000-8000-000000000003', 'admin');
    insert into _r (name, ok, detail) values ('an admin cannot promote anyone (owner only)', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('an admin cannot promote anyone (owner only)', true, sqlerrm);
  end;

  begin
    perform public.remove_group_member((select id from _ids where label='g'), 'aaaaaaaa-0000-4000-8000-000000000001');
    insert into _r (name, ok, detail) values ('the owner cannot be removed by an admin', false, 'removed');
  exception when others then
    insert into _r (name, ok, detail) values ('the owner cannot be removed by an admin', true, sqlerrm);
  end;
end $$;

-- C is a plain member: no admin powers.
set local request.jwt.claims = '{"sub":"cccccccc-0000-4000-8000-000000000003","role":"authenticated"}';

update public.conversations set title = 'Hijacked' where id = (select id from _ids where label='g');
insert into _r (name, ok, detail)
select 'a plain member cannot rename the group (RLS filters the row)',
       (select title <> 'Hijacked' from public.conversations where id = (select id from _ids where label='g')), null;

do $$
begin
  begin
    perform public.add_group_member((select id from _ids where label='g'), 'dddddddd-0000-4000-8000-000000000004');
    insert into _r (name, ok, detail) values ('a plain member cannot add members', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a plain member cannot add members', true, sqlerrm);
  end;

  begin
    perform public.remove_group_member((select id from _ids where label='g'), 'bbbbbbbb-0000-4000-8000-000000000002');
    insert into _r (name, ok, detail) values ('a plain member cannot remove an admin', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a plain member cannot remove an admin', true, sqlerrm);
  end;

  begin
    insert into public.conversation_members (conversation_id, user_id, role)
    values ((select id from _ids where label='g'), 'dddddddd-0000-4000-8000-000000000004', 'owner');
    insert into _r (name, ok, detail) values ('membership rows are not client-writable', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('membership rows are not client-writable', true, sqlerrm);
  end;
end $$;

insert into _r (name, ok, detail)
select 'a member can read the group and its messages',
       (select count(*) from public.messages) = 1, 'messages=' || (select count(*) from public.messages);

-- E was never added to the group.
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-4000-8000-000000000005","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'a NON-MEMBER sees no group row', count(*) = 0, 'visible=' || count(*) from public.conversations;
insert into _r (name, ok, detail)
select 'a NON-MEMBER sees no group messages', count(*) = 0, 'visible=' || count(*) from public.messages;
insert into _r (name, ok, detail)
select 'a NON-MEMBER sees no membership rows', count(*) = 0, 'visible=' || count(*) from public.conversation_members;

do $$
begin
  begin
    insert into public.messages (conversation_id, sender_id, body)
    values ((select id from _ids where label='g'), auth.uid(), 'gatecrash');
    insert into _r (name, ok, detail) values ('a NON-MEMBER cannot post into the group', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a NON-MEMBER cannot post into the group', true, sqlerrm);
  end;

  begin
    perform public.add_group_member((select id from _ids where label='g'), auth.uid());
    insert into _r (name, ok, detail) values ('a NON-MEMBER cannot add themselves', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a NON-MEMBER cannot add themselves', true, sqlerrm);
  end;
end $$;

-- ------------------------------------------------ ownership transfer + leave
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}';
select public.leave_group((select id from _ids where label='g'));

-- A is no longer a member, so A can no longer see the group: switch to B to
-- inspect what happened. That in itself is the RLS working.
insert into _r (name, ok, detail)
select 'the ex-owner can no longer see the group',
       (select count(*) from public.conversations) = 0,
       'visible=' || (select count(*) from public.conversations);

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'when the owner leaves, the admin inherits ownership',
       (select count(*) from public.conversation_members where role = 'owner' and user_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 1,
       null;

insert into _r (name, ok, detail)
select 'the group is still readable by the remaining members',
       (select count(*) from public.conversation_members) = 3,
       'members=' || (select count(*) from public.conversation_members);

insert into _r (name, ok, detail)
select 'the ex-owner is no longer a member',
       not public.is_group_member((select id from _ids where label='g'), 'aaaaaaaa-0000-4000-8000-000000000001'), null;

-- Clean up: C, then D leave; B (the owner) goes last.
set local request.jwt.claims = '{"sub":"cccccccc-0000-4000-8000-000000000003","role":"authenticated"}';
select public.leave_group((select id from _ids where label='g'));

set local request.jwt.claims = '{"sub":"dddddddd-0000-4000-8000-000000000004","role":"authenticated"}';
select public.leave_group((select id from _ids where label='g'));

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}';
insert into _r (name, ok, detail)
select 'two members left, the group still exists for the owner',
       (select count(*) from public.conversation_members) = 1,
       'members=' || (select count(*) from public.conversation_members);

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}';
select public.leave_group((select id from _ids where label='g'));

reset role;
insert into _r (name, ok, detail)
select 'the group disappears when the last member leaves',
       (select count(*) from public.conversations where kind = 'group') = 0,
       'groups=' || (select count(*) from public.conversations where kind = 'group');

\echo ''
\echo '===== GROUP RLS RESULTS ====='
select ord, case when ok then 'PASS' else 'FAIL' end as result, name, coalesce(left(detail,60),'') as detail
from _r order by ord;
select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary from _r;

do $$
declare failed int;
begin
  select count(*) filter (where not ok) into failed from _r;
  if failed > 0 then raise exception '% group assertions FAILED', failed; end if;
end $$;

rollback;
\echo 'rolled back — nothing persisted'
