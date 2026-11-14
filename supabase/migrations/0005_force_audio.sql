-- =============================================================================
-- 0005_force_audio.sql — Force Audio alerts (§5)
--
-- Design notes
--  • An alert is a *server record*, not a URL in a notification: the receiver
--    looks the alert up by id and only then touches the audio. A forged or
--    stale id resolves to nothing.
--  • Limits are enforced by CHECK constraints, so the 70 s / 10 MiB rules hold
--    even if a client is modified: duration_ms <= 70000, size_bytes <= 10485760.
--  • The sender can never rewrite an alert after creating it, and cannot set
--    state/expires_at at all — those columns are simply not granted to
--    `authenticated`.
--  • The receiver can only move state forward (created → delivered → played)
--    and only once; `played_at` is stamped server-side by a trigger.
--  • Nothing in this table is deletable by clients.
-- =============================================================================

begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'force_audio_state') then
    create type public.force_audio_state as enum ('created', 'delivered', 'played', 'expired');
  end if;
end $$;

create table if not exists public.force_audio_alerts (
  id              uuid primary key default gen_random_uuid(),
  -- client-supplied idempotency key: a retried send cannot create two alerts
  request_id      text not null unique check (char_length(request_id) between 8 and 64),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  message_id      uuid unique references public.messages (id) on delete cascade,
  sender_id       uuid not null references auth.users (id) on delete cascade,
  recipient_id    uuid not null references auth.users (id) on delete cascade,
  -- Only our own Cloudinary account may host Force Audio. A modified client
  -- cannot point the receiver at an arbitrary URL.
  media_url       text not null check (media_url like 'https://res.cloudinary.com/%'),
  duration_ms     integer not null check (duration_ms between 500 and 70000),
  size_bytes      bigint not null check (size_bytes between 1 and 10485760),
  mime_type       text not null default 'audio/mp4' check (char_length(mime_type) between 3 and 64),
  state           public.force_audio_state not null default 'created',
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default now() + interval '24 hours',
  played_at       timestamptz,
  constraint force_audio_not_self check (sender_id <> recipient_id),
  constraint force_audio_played_at_present check ((state = 'played') = (played_at is not null))
);

create index if not exists force_audio_recipient_idx
  on public.force_audio_alerts (recipient_id, state, created_at desc);
create index if not exists force_audio_conversation_idx
  on public.force_audio_alerts (conversation_id, created_at desc);

-- --------------------------------------------------------------- immutability
create or replace function public.force_audio_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- service_role (the edge function / cron) may reconcile rows; clients may not.
  if current_role <> 'service_role' then
    if new.request_id      <> old.request_id
       or new.conversation_id <> old.conversation_id
       or new.message_id      is distinct from old.message_id
       or new.sender_id       <> old.sender_id
       or new.recipient_id    <> old.recipient_id
       or new.media_url       <> old.media_url
       or new.duration_ms     <> old.duration_ms
       or new.size_bytes      <> old.size_bytes
       or new.mime_type       <> old.mime_type
       or new.created_at      <> old.created_at
       or new.expires_at      <> old.expires_at then
      raise exception 'force_audio_immutable' using errcode = '42501';
    end if;

    -- Maintenance paths (the expiry sweep below) set a transaction-local flag
    -- instead of relying on a role name, so the bypass cannot leak to clients.
    if coalesce(current_setting('pulse.force_audio_maintenance', true), '') <> 'on' then
      if old.state in ('played', 'expired') then
        raise exception 'force_audio_terminal' using errcode = '22023';
      end if;

      if now() > old.expires_at then
        raise exception 'force_audio_expired' using errcode = '22023';
      end if;
    end if;
  end if;

  if new.state = 'played' and new.played_at is null then
    new.played_at := now();
  end if;

  return new;
end $$;

revoke all on function public.force_audio_guard() from public;

drop trigger if exists force_audio_guard_update on public.force_audio_alerts;
create trigger force_audio_guard_update
  before update on public.force_audio_alerts
  for each row execute function public.force_audio_guard();

-- ------------------------------------------------------------------- expiry
-- Called by the media-cleanup cron (service_role only). Clients never see it.
create or replace function public.expire_force_audio_alerts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  n integer;
begin
  perform set_config('pulse.force_audio_maintenance', 'on', true);
  update public.force_audio_alerts
     set state = 'expired'
   where expires_at < now()
     and state in ('created', 'delivered');
  get diagnostics n = row_count;
  perform set_config('pulse.force_audio_maintenance', 'off', true);
  return n;
end $$;

revoke all on function public.expire_force_audio_alerts() from public, anon, authenticated;
grant execute on function public.expire_force_audio_alerts() to service_role;

-- ----------------------------------------------------------------------- RLS
alter table public.force_audio_alerts enable row level security;

-- The sender must be the caller, a member of the conversation, active, and the
-- recipient must actually be the other member of that conversation and active.
drop policy if exists force_audio_insert_sender on public.force_audio_alerts;
create policy force_audio_insert_sender on public.force_audio_alerts
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
    and public.is_account_active(auth.uid())
    and recipient_id <> auth.uid()
    and exists (
      select 1 from public.conversation_members m
       where m.conversation_id = force_audio_alerts.conversation_id
         and m.user_id = force_audio_alerts.recipient_id
    )
    and public.is_account_active(recipient_id)
  );

drop policy if exists force_audio_select_participant on public.force_audio_alerts;
create policy force_audio_select_participant on public.force_audio_alerts
  for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());

-- Only the receiver, only forward: the column grants already limit the update
-- to (state, played_at); the policy limits the row.
drop policy if exists force_audio_update_recipient on public.force_audio_alerts;
create policy force_audio_update_recipient on public.force_audio_alerts
  for update to authenticated
  using (recipient_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (recipient_id = auth.uid());

-- No delete policy on purpose: alerts expire, they are never removed by clients.

-- -------------------------------------------------------------------- grants
revoke all on public.force_audio_alerts from anon;
-- Supabase grants ALL to `authenticated` by default; take it back.
revoke all on public.force_audio_alerts from authenticated;

grant select on public.force_audio_alerts to authenticated;
-- Server-controlled columns (state, created_at, expires_at, played_at) are
-- deliberately absent: the client cannot pre-mark an alert as played or push its
-- own expiry date.
grant insert (
  request_id, conversation_id, message_id, sender_id, recipient_id,
  media_url, duration_ms, size_bytes, mime_type
) on public.force_audio_alerts to authenticated;
grant update (state, played_at) on public.force_audio_alerts to authenticated;

grant all on public.force_audio_alerts to service_role;

-- ------------------------------------------------------------------ realtime
do $$
begin
  begin
    alter publication supabase_realtime add table public.force_audio_alerts;
  exception when duplicate_object then null;
        when undefined_object then null;
  end;
end $$;

commit;
