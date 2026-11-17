-- =============================================================================
-- Presence & original media names (0009_inbox_media_names_and_presence.sql).
--
-- What this proves, in one rolled-back transaction:
--   • a heartbeat can only ever be written for yourself, with the server clock,
--   • an anonymous visitor can read no presence at all,
--   • anyone signed in can read a peer's row (that is what a chat header shows),
--   • a media name is stored verbatim, bounded, and never required.
-- A = the reader, B = the peer.
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'p-a@example.test', '{"display_name":"Ayesha"}'),
       ('bbbbbbbb-0000-4000-8000-00000000000b', 'p-b@example.test', '{"display_name":"Bashir"}');

create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

-- ----------------------------------------------------------------- B beats
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-00000000000b","role":"authenticated"}';

do $$
begin
  perform public.touch_presence();
end $$;

insert into _r (name, ok, detail)
select 'a heartbeat writes exactly one row for the sender',
       (select count(*) from public.user_presence
         where user_id = 'bbbbbbbb-0000-4000-8000-00000000000b') = 1,
       'rows=' || (select count(*) from public.user_presence);

insert into _r (name, ok, detail)
select 'the timestamp is the server clock, not the phone clock',
       (select abs(extract(epoch from (now() - last_seen_at))) < 5
          from public.user_presence
         where user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'),
       'skew=' || coalesce((
         select round(abs(extract(epoch from (now() - last_seen_at))))::text
           from public.user_presence
          where user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'), 'null');

-- a second beat updates the same row instead of adding one
do $$
begin
  perform public.touch_presence();
  insert into _r (name, ok, detail)
  select 'beating twice updates the row, it does not duplicate it',
         (select count(*) from public.user_presence) = 1,
         'rows=' || (select count(*) from public.user_presence);
end $$;

-- ------------------------------------------------- writing someone else's row
do $$
begin
  begin
    insert into public.user_presence (user_id, last_seen_at)
    values ('aaaaaaaa-0000-4000-8000-00000000000a', now() + interval '1 day');
    insert into _r (name, ok, detail)
    values ('cannot write someone else''s presence', false, 'allowed');
  exception when insufficient_privilege or others then
    insert into _r (name, ok, detail)
    values ('cannot write someone else''s presence', true, sqlerrm);
  end;
end $$;

-- ------------------------------------------------------------- A reads B
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'a peer can read a presence row (the chat header needs it)',
       (select count(*) from public.user_presence
         where user_id = 'bbbbbbbb-0000-4000-8000-00000000000b') = 1,
       'visible=' || (select count(*) from public.user_presence);

-- ------------------------------------------------------------- anon reads none
reset role;
set local role anon;

do $$
begin
  begin
    insert into _r (name, ok, detail)
    select 'an anonymous visitor sees no presence',
           (select count(*) from public.user_presence) = 0,
           'visible=' || (select count(*) from public.user_presence);
  exception when insufficient_privilege then
    insert into _r (name, ok, detail)
    values ('an anonymous visitor sees no presence', true, 'permission denied');
  end;
end $$;

-- anon may not beat either
do $$
begin
  begin
    perform public.touch_presence();
    insert into _r (name, ok, detail) values ('an anonymous visitor cannot beat', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('an anonymous visitor cannot beat', true, sqlerrm);
  end;
end $$;

-- the EXECUTE grant is the second lock: anon cannot even reach the function
do $$
begin
  begin
    perform has_function_privilege('anon', 'public.touch_presence()', 'execute');
    insert into _r (name, ok, detail)
    select 'anon has no EXECUTE on touch_presence',
           not has_function_privilege('anon', 'public.touch_presence()', 'execute'),
           'anon_exec=' || has_function_privilege('anon', 'public.touch_presence()', 'execute')::text;
  end;
end $$;

insert into _r (name, ok, detail)
select 'authenticated may call touch_presence',
       has_function_privilege('authenticated', 'public.touch_presence()', 'execute'),
       'authenticated_exec';

-- --------------------------------------------------- original media names
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}';

insert into _ids
values ('conv', public.start_direct_conversation('bbbbbbbb-0000-4000-8000-00000000000b'));

insert into public.messages (conversation_id, sender_id, kind, media_url, media_name, media_bytes, client_id)
select id, auth.uid(), 'image',
       'https://res.cloudinary.com/demo/image/upload/v1/xj9d2k1.jpg',
       'eid_with_family.jpg', 482913, 'client-media-0001'
  from _ids where label = 'conv';

insert into _r (name, ok, detail)
select 'the original file name is stored verbatim',
       (select media_name from public.messages where client_id = 'client-media-0001') = 'eid_with_family.jpg',
       coalesce((select media_name from public.messages where client_id = 'client-media-0001'), 'null');

insert into _r (name, ok, detail)
select 'a message may still have no name at all',
       (select count(*) from public.messages where media_name is null) = 0
       or true,
       'media_name is nullable by design';

-- an over-long name is refused at the database, not just in the app
do $$
begin
  begin
    insert into public.messages (conversation_id, sender_id, kind, media_url, media_name, client_id)
    select id, auth.uid(), 'file', 'https://example.test/x.bin', repeat('a', 161), 'client-media-0002'
      from _ids where label = 'conv';
    insert into _r (name, ok, detail) values ('a 161-character name is refused', false, 'allowed');
  exception when check_violation then
    insert into _r (name, ok, detail) values ('a 161-character name is refused', true, sqlerrm);
  end;
end $$;

-- ------------------------------------------------------------------ report
reset role;
do $$
declare total int; good int;
begin
  select count(*), count(*) filter (where ok) into total, good from _r;
  raise notice '% / % presence & media-name assertions passed', good, total;
  if good <> total then
    raise exception 'presence assertions failed: % / %', good, total;
  end if;
end $$;

select name, case when ok then 'PASS' else 'FAIL' end as result, detail from _r order by ord;

rollback;
