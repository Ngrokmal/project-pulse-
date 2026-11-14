-- =============================================================================
-- Force Audio alert RLS + constraint verification (0005_force_audio.sql).
-- One transaction, rolled back. Users A (sender), B (receiver), C (outsider).
-- =============================================================================
begin;

create temp table _r (ord serial primary key, name text, ok boolean, detail text) on commit drop;
grant select, insert on _r to public;
grant usage, select on sequence _r_ord_seq to public;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaaaaaa-1111-4111-8111-111111111111', 'fa-a@example.test', '{"display_name":"Ali"}'),
       ('bbbbbbbb-2222-4222-8222-222222222222', 'fa-b@example.test', '{"display_name":"Bela"}'),
       ('cccccccc-3333-4333-8333-333333333333', 'fa-c@example.test', '{"display_name":"Outsider"}');

-- ---------------------------------------------------------------- as A (sender)
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}';

create temp table _ids (label text primary key, id uuid) on commit drop;
grant select, insert on _ids to public;

insert into _ids values ('conv', public.start_direct_conversation('bbbbbbbb-2222-4222-8222-222222222222'));

with m as (
  insert into public.messages (conversation_id, sender_id, kind, body, media_url, media_bytes, duration_ms)
  values ((select id from _ids where label='conv'), auth.uid(), 'force_audio', '',
          'https://res.cloudinary.com/kojvlesm/raw/upload/v1/pulse/messages/fa-probe.m4a', 240000, 42000)
  returning id
)
insert into _ids values ('msg', (select id from m));

insert into public.force_audio_alerts
  (request_id, conversation_id, message_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
values
  ('fa-request-0001', (select id from _ids where label='conv'), (select id from _ids where label='msg'),
   auth.uid(), 'bbbbbbbb-2222-4222-8222-222222222222',
   'https://res.cloudinary.com/kojvlesm/raw/upload/v1/pulse/messages/fa-probe.m4a', 42000, 240000);

insert into _r (name, ok, detail)
select 'sender (a conversation member) can create an alert', count(*) = 1, 'rows=' || count(*) from public.force_audio_alerts;

insert into _r (name, ok, detail)
select 'alert starts in state created with a server-set expiry',
       (select state = 'created' and expires_at > now() + interval '23 hours' from public.force_audio_alerts limit 1),
       (select state::text || ' / ' || expires_at::text from public.force_audio_alerts limit 1);

-- The message trigger keeps the chat preview honest.
insert into _r (name, ok, detail)
select 'force_audio message sets a Force Audio conversation preview',
       (select last_message_preview from public.conversations limit 1) = 'Force audio alert',
       (select last_message_preview from public.conversations limit 1);

do $$
begin
  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, message_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0001', (select id from _ids where label='conv'), null,
            auth.uid(), 'bbbbbbbb-2222-4222-8222-222222222222',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('replaying the same request_id is rejected (idempotent)', false, 'allowed');
  exception when unique_violation then
    insert into _r (name, ok, detail) values ('replaying the same request_id is rejected (idempotent)', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0002', (select id from _ids where label='conv'), auth.uid(),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 70001, 1000);
    insert into _r (name, ok, detail) values ('duration above 70 s is rejected by the database', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('duration above 70 s is rejected by the database', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0003', (select id from _ids where label='conv'), auth.uid(),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 10485761);
    insert into _r (name, ok, detail) values ('size above 10 MiB is rejected by the database', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('size above 10 MiB is rejected by the database', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0004', (select id from _ids where label='conv'), auth.uid(),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'https://evil.example.com/nope.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('a non-Cloudinary URL is rejected', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a non-Cloudinary URL is rejected', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0005', (select id from _ids where label='conv'), auth.uid(), auth.uid(),
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('sending a Force Audio to yourself is rejected', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('sending a Force Audio to yourself is rejected', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0006', (select id from _ids where label='conv'), auth.uid(),
            'cccccccc-3333-4333-8333-333333333333',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('cannot address someone outside the conversation', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('cannot address someone outside the conversation', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0007', (select id from _ids where label='conv'),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'aaaaaaaa-1111-4111-8111-111111111111',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('cannot create an alert as another user', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('cannot create an alert as another user', true, sqlerrm);
  end;

  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes, state)
    values ('fa-request-0008', (select id from _ids where label='conv'), auth.uid(),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000, 'played');
    insert into _r (name, ok, detail) values ('the client cannot insert an already-played alert', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('the client cannot insert an already-played alert', true, sqlerrm);
  end;
end $$;

do $$
begin
  -- RLS filters the row out instead of raising, so assert on the resulting state.
  update public.force_audio_alerts set state = 'played' where request_id = 'fa-request-0001';
  insert into _r (name, ok, detail)
  select 'the sender cannot mark its own alert as played',
         (select state = 'created' from public.force_audio_alerts where request_id = 'fa-request-0001'),
         (select state::text from public.force_audio_alerts where request_id = 'fa-request-0001');

  begin
    update public.force_audio_alerts set media_url = 'https://res.cloudinary.com/kojvlesm/raw/upload/v1/swap.m4a'
     where request_id = 'fa-request-0001';
    insert into _r (name, ok, detail) values ('the audio URL cannot be swapped after sending', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('the audio URL cannot be swapped after sending', true, sqlerrm);
  end;

  begin
    delete from public.force_audio_alerts where request_id = 'fa-request-0001';
    insert into _r (name, ok, detail) values ('alerts cannot be deleted by a client', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('alerts cannot be deleted by a client', true, sqlerrm);
  end;
end $$;

insert into _r (name, ok, detail)
select 'every invalid alert above was actually rejected (still one row)',
       count(*) = 1, 'rows=' || count(*) from public.force_audio_alerts;

insert into _r (name, ok, detail)
select 'the sender can still read its own alert', count(*) = 1, 'rows=' || count(*) from public.force_audio_alerts;

-- Still as A: a second, untouched alert so the outsider has something to fail on.
insert into public.force_audio_alerts
  (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
values ('fa-request-0010', (select id from _ids where label='conv'), auth.uid(),
        'bbbbbbbb-2222-4222-8222-222222222222',
        'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);

-- -------------------------------------------------------------- as B (receiver)
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-2222-4222-8222-222222222222","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'the receiver can read the alerts addressed to them', count(*) = 2, 'rows=' || count(*) from public.force_audio_alerts;


update public.force_audio_alerts set state = 'delivered' where request_id = 'fa-request-0001';
update public.force_audio_alerts set state = 'played' where request_id = 'fa-request-0001';

insert into _r (name, ok, detail)
select 'the receiver can mark it played, and played_at is stamped by the server',
       (select state = 'played' and played_at is not null from public.force_audio_alerts where request_id = 'fa-request-0001'),
       (select state::text || ' / ' || coalesce(played_at::text, 'null') from public.force_audio_alerts where request_id = 'fa-request-0001');

do $$
begin
  begin
    update public.force_audio_alerts set state = 'delivered' where request_id = 'fa-request-0001';
    insert into _r (name, ok, detail) values ('a played alert is terminal (no replay, no rewind)', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('a played alert is terminal (no replay, no rewind)', true, sqlerrm);
  end;

  begin
    update public.force_audio_alerts set played_at = null, state = 'created' where request_id = 'fa-request-0001';
    insert into _r (name, ok, detail) values ('the played stamp cannot be cleared', false, 'allowed');
  exception when others then
    insert into _r (name, ok, detail) values ('the played stamp cannot be cleared', true, sqlerrm);
  end;
end $$;

-- -------------------------------------------------------------- as C (outsider)
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-3333-4333-8333-333333333333","role":"authenticated"}';

insert into _r (name, ok, detail)
select 'an outsider sees no alerts at all', count(*) = 0, 'visible=' || count(*) from public.force_audio_alerts;

with touched as (
  update public.force_audio_alerts set state = 'played' where request_id = 'fa-request-0010' returning 1
)
insert into _r (name, ok, detail)
select 'an outsider cannot touch an alert', count(*) = 0, 'rows updated=' || count(*) from touched;

reset role;

-- ------------------------------------------------------- banned receiver
update public.account_status set status = 'banned'
 where user_id = 'bbbbbbbb-2222-4222-8222-222222222222';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}';
do $$
begin
  begin
    insert into public.force_audio_alerts
      (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes)
    values ('fa-request-0009', (select id from _ids where label='conv'), auth.uid(),
            'bbbbbbbb-2222-4222-8222-222222222222',
            'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000);
    insert into _r (name, ok, detail) values ('a banned recipient cannot be force-audioed', false, 'allowed');
  exception when insufficient_privilege then
    insert into _r (name, ok, detail) values ('a banned recipient cannot be force-audioed', true, sqlerrm);
  end;
end $$;

reset role;

-- --------------------------------------------------- expiry via service_role
insert into public.force_audio_alerts
  (request_id, conversation_id, sender_id, recipient_id, media_url, duration_ms, size_bytes, expires_at)
values ('fa-request-expired', (select id from _ids where label='conv'),
        'aaaaaaaa-1111-4111-8111-111111111111', 'bbbbbbbb-2222-4222-8222-222222222222',
        'https://res.cloudinary.com/kojvlesm/raw/upload/v1/x.m4a', 1000, 1000, now() - interval '1 hour');

set local role service_role;
insert into _r (name, ok, detail)
select 'the cron sweep expires stale alerts', public.expire_force_audio_alerts() >= 1,
       'expired=' || public.expire_force_audio_alerts();
reset role;

insert into _r (name, ok, detail)
select 'the outsider attempt changed nothing',
       (select state = 'created' from public.force_audio_alerts where request_id = 'fa-request-0010'),
       (select state::text from public.force_audio_alerts where request_id = 'fa-request-0010');

insert into _r (name, ok, detail)
select 'the stale alert is now in state expired',
       (select state = 'expired' from public.force_audio_alerts where request_id = 'fa-request-expired'),
       (select state::text from public.force_audio_alerts where request_id = 'fa-request-expired');

\echo ''
\echo '===== FORCE AUDIO RLS RESULTS ====='
select ord, case when ok then 'PASS' else 'FAIL' end as result, name, coalesce(left(detail,60),'') as detail
from _r order by ord;
select format('%s / %s assertions passed', count(*) filter (where ok), count(*)) as summary from _r;

do $$
declare failed int;
begin
  select count(*) filter (where not ok) into failed from _r;
  if failed > 0 then raise exception '% force audio assertions FAILED', failed; end if;
end $$;

rollback;
\echo 'rolled back — nothing persisted'
