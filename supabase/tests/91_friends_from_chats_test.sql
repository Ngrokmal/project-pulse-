-- =============================================================================
-- Friends from chats (0011_friends_from_chats.sql).
--
-- What this proves, in one rolled-back transaction:
--   • one member alone is not a friendship; the second member joining is,
--   • and it lands in BOTH directions,
--   • a group is a room, not a relationship — no edges appear,
--   • an open request between two people who already chat is settled to
--     `accepted`, so the Sent tab stops asking a question the chat answered,
--   • joining twice adds nothing, and the readers agree with the table.
-- A = the first member, B = the second, C = the group-only person.
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('cccccccc-0000-4000-8000-00000000000a', 'f-a@example.test', '{"display_name":"Ayesha"}'),
       ('dddddddd-0000-4000-8000-00000000000b', 'f-b@example.test', '{"display_name":"Bashir"}'),
       ('eeeeeeee-0000-4000-8000-00000000000c', 'f-c@example.test', '{"display_name":"Chotu"}');

create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

-- ------------------------------------------------- a direct chat, one member
insert into public.conversations (kind, pair_key, created_by)
values ('direct', 'cccccccc-0000-4000-8000-00000000000a:dddddddd-0000-4000-8000-00000000000b',
        'cccccccc-0000-4000-8000-00000000000a');

insert into _ids (label, id)
select 'direct_ab', id from public.conversations
where pair_key = 'cccccccc-0000-4000-8000-00000000000a:dddddddd-0000-4000-8000-00000000000b';

insert into public.conversation_members (conversation_id, user_id, role)
select id, 'cccccccc-0000-4000-8000-00000000000a', 'member' from _ids where label = 'direct_ab';

insert into _r (name, ok, detail)
select 'one member alone is not a friendship',
       (select count(*) from public.friendships
         where user_id = 'cccccccc-0000-4000-8000-00000000000a'
           and friend_id = 'dddddddd-0000-4000-8000-00000000000b') = 0,
       'edges=' || (select count(*) from public.friendships);

-- --------------------------------------------------- the second one joins
insert into public.conversation_members (conversation_id, user_id, role)
select id, 'dddddddd-0000-4000-8000-00000000000b', 'member' from _ids where label = 'direct_ab';

insert into _r (name, ok, detail)
select 'the second member joining makes A → B',
       exists (select 1 from public.friendships
                where user_id = 'cccccccc-0000-4000-8000-00000000000a'
                  and friend_id = 'dddddddd-0000-4000-8000-00000000000b'),
       'edges=' || (select count(*) from public.friendships);

insert into _r (name, ok, detail)
select 'and B → A in the same breath',
       exists (select 1 from public.friendships
                where user_id = 'dddddddd-0000-4000-8000-00000000000b'
                  and friend_id = 'cccccccc-0000-4000-8000-00000000000a'),
       'edges=' || (select count(*) from public.friendships);

insert into _r (name, ok, detail)
select 'exactly two edges for one direct chat',
       (select count(*) from public.friendships
         where (user_id, friend_id) in (
           ('cccccccc-0000-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-00000000000b'),
           ('dddddddd-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000a'))) = 2,
       'edges=' || (select count(*) from public.friendships);

-- ------------------------------------------------------------ a group is not
insert into public.conversations (kind, created_by, title)
values ('group', 'cccccccc-0000-4000-8000-00000000000a', 'Weekend plan');

insert into _ids (label, id)
select 'group_ac', id from public.conversations where title = 'Weekend plan';

insert into public.conversation_members (conversation_id, user_id, role)
select id, 'cccccccc-0000-4000-8000-00000000000a', 'owner' from _ids where label = 'group_ac';
insert into public.conversation_members (conversation_id, user_id, role)
select id, 'eeeeeeee-0000-4000-8000-00000000000c', 'member' from _ids where label = 'group_ac';

insert into _r (name, ok, detail)
select 'a group creates no friendship',
       not exists (select 1 from public.friendships
                    where (user_id = 'cccccccc-0000-4000-8000-00000000000a'
                           and friend_id = 'eeeeeeee-0000-4000-8000-00000000000c')
                       or (user_id = 'eeeeeeee-0000-4000-8000-00000000000c'
                           and friend_id = 'cccccccc-0000-4000-8000-00000000000a')),
       'edges=' || (select count(*) from public.friendships);

-- ------------------------------------------- an open request is settled by it
insert into public.friend_requests (requester_id, addressee_id, status)
values ('cccccccc-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000c', 'pending');

insert into _ids (label, id)
select 'pending_ac', id from public.friend_requests
where requester_id = 'cccccccc-0000-4000-8000-00000000000a'
  and addressee_id = 'eeeeeeee-0000-4000-8000-00000000000c';

insert into public.conversations (kind, pair_key, created_by)
values ('direct', 'cccccccc-0000-4000-8000-00000000000a:eeeeeeee-0000-4000-8000-00000000000c',
        'cccccccc-0000-4000-8000-00000000000a');

insert into _ids (label, id)
select 'direct_ac', id from public.conversations
where pair_key = 'cccccccc-0000-4000-8000-00000000000a:eeeeeeee-0000-4000-8000-00000000000c';

insert into public.conversation_members (conversation_id, user_id, role)
select id, 'cccccccc-0000-4000-8000-00000000000a', 'member' from _ids where label = 'direct_ac';
insert into public.conversation_members (conversation_id, user_id, role)
select id, 'eeeeeeee-0000-4000-8000-00000000000c', 'member' from _ids where label = 'direct_ac';

insert into _r (name, ok, detail)
select 'a chat settles the pending request between the pair',
       (select status from public.friend_requests where id = (select id from _ids where label = 'pending_ac')) = 'accepted',
       'status=' || (select status from public.friend_requests where id = (select id from _ids where label = 'pending_ac'));

insert into _r (name, ok, detail)
select 'and it makes the friendship too',
       exists (select 1 from public.friendships
                where user_id = 'eeeeeeee-0000-4000-8000-00000000000c'
                  and friend_id = 'cccccccc-0000-4000-8000-00000000000a'),
       'edges=' || (select count(*) from public.friendships);

insert into _r (name, ok, detail)
select 'no request is left waiting anywhere',
       (select count(*) from public.friend_requests where status = 'pending') = 0,
       'pending=' || (select count(*) from public.friend_requests where status = 'pending');

-- ------------------------------------------------------------- idempotency
insert into public.conversation_members (conversation_id, user_id, role)
select id, 'dddddddd-0000-4000-8000-00000000000b', 'member' from _ids where label = 'direct_ac'
on conflict do nothing;

insert into _r (name, ok, detail)
select 'joining a second chat adds no duplicate edge',
       (select count(*) from public.friendships
         where user_id = 'cccccccc-0000-4000-8000-00000000000a'
           and friend_id = 'dddddddd-0000-4000-8000-00000000000b') = 1,
       'edges=' || (select count(*) from public.friendships);

insert into _r (name, ok, detail)
select 'the friend readers agree with the edges',
       public.friend_state('cccccccc-0000-4000-8000-00000000000a',
                           'dddddddd-0000-4000-8000-00000000000b') = 'friend'
       and public.mutual_friend_count('cccccccc-0000-4000-8000-00000000000a',
                                      'dddddddd-0000-4000-8000-00000000000b') >= 0,
       'state=' || public.friend_state('cccccccc-0000-4000-8000-00000000000a',
                                       'dddddddd-0000-4000-8000-00000000000b');

-- ------------------------------------------------------------------ report
reset role;
do $$
declare total int; good int;
begin
  select count(*), count(*) filter (where ok) into total, good from _r;
  raise notice '% / % friends-from-chats assertions passed', good, total;
  if good <> total then
    raise exception 'friends-from-chats assertions failed: % / %', good, total;
  end if;
end $$;

select name, case when ok then 'PASS' else 'FAIL' end as result, detail from _r order by ord;

rollback;
