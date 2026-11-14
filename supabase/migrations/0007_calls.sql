-- 0007_calls.sql — call records, state machine enforced in SQL, realtime ready
--
-- No media vendor yet (§8 phase 8): the DB owns the *state machine* and the
-- participants, the app owns the media abstraction. A call row can only move
-- along transitions the plan allows, and only a participant can move it.
--
--   ringing ──accept──▶ connecting ──media-ready──▶ active ──▶ ended
--      │                     │                        │
--      ├──decline──▶ declined └──fail──▶ failed       └──reconnect──▶ reconnecting
--      └──timeout──▶ missed

create table if not exists public.calls (
  id             uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  caller_id      uuid not null references auth.users (id) on delete cascade,
  callee_id      uuid not null references auth.users (id) on delete cascade,
  kind           text not null default 'audio' check (kind in ('audio', 'video')),
  state          text not null default 'ringing' check (state in (
                   'ringing', 'connecting', 'active', 'reconnecting',
                   'ended', 'declined', 'missed', 'failed')),
  end_reason     text check (end_reason in (
                   'hangup', 'declined', 'timeout', 'error', 'cancelled', 'answered_elsewhere')),
  created_at     timestamptz not null default now(),
  answered_at    timestamptz,
  ended_at       timestamptz,
  constraint calls_distinct_parties check (caller_id <> callee_id)
);

create index if not exists calls_callee_idx on public.calls (callee_id, state, created_at desc);
create index if not exists calls_caller_idx on public.calls (caller_id, state, created_at desc);
create index if not exists calls_conversation_idx on public.calls (conversation_id, created_at desc);

alter table public.calls enable row level security;

-- Both parties see their own calls; nobody else does.
drop policy if exists "calls: participants can read" on public.calls;
create policy "calls: participants can read"
  on public.calls for select to authenticated
  using (auth.uid() in (caller_id, callee_id));

-- No direct writes at all: every change goes through the RPCs below, which
-- re-check who is allowed to make that transition.
revoke all on public.calls from authenticated;
grant select on public.calls to authenticated;
grant all on public.calls to service_role;

-- --------------------------------------------------------------- helpers
create or replace function public.call_role(p_call uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when c.caller_id = auth.uid() then 'caller'
           when c.callee_id = auth.uid() then 'callee'
         end
    from public.calls c
   where c.id = p_call
$$;

create or replace function public.is_call_participant(p_call uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.calls c
     where c.id = p_call and auth.uid() in (c.caller_id, c.callee_id)
  )
$$;

-- --------------------------------------------------------------- RPCs
-- Start a call with the other member of a direct conversation. Groups are not
-- callable yet (phase 8 scope: 1:1 audio), so a group is refused by name.
create or replace function public.start_call(
  p_conversation uuid,
  p_kind text default 'audio'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me       uuid := auth.uid();
  v_kind     text := coalesce(p_kind, 'audio');
  v_other    uuid;
  v_kind_db  text;
  v_busy     integer;
  v_call     uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_kind not in ('audio', 'video') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;

  select c.kind into v_kind_db
    from public.conversations c
   where c.id = p_conversation
     and exists (select 1 from public.conversation_members m
                  where m.conversation_id = c.id and m.user_id = v_me);

  if v_kind_db is null then
    raise exception 'not_a_member' using errcode = '22023';
  end if;
  if v_kind_db <> 'direct' then
    raise exception 'group_calls_not_supported' using errcode = '22023';
  end if;

  select m.user_id into v_other
    from public.conversation_members m
   where m.conversation_id = p_conversation and m.user_id <> v_me
   limit 1;

  if v_other is null then
    raise exception 'no_peer' using errcode = '22023';
  end if;

  -- One live call per person at a time, in either direction.
  select count(*) into v_busy
    from public.calls c
   where c.state in ('ringing', 'connecting', 'active', 'reconnecting')
     and v_me in (c.caller_id, c.callee_id);
  if v_busy > 0 then
    raise exception 'already_in_call' using errcode = '22023';
  end if;

  select count(*) into v_busy
    from public.calls c
   where c.state in ('ringing', 'connecting', 'active', 'reconnecting')
     and v_other in (c.caller_id, c.callee_id);
  if v_busy > 0 then
    raise exception 'peer_busy' using errcode = '22023';
  end if;

  insert into public.calls (conversation_id, caller_id, callee_id, kind)
  values (p_conversation, v_me, v_other, v_kind)
  returning id into v_call;

  return v_call;
end $$;

-- Callee accepts: ringing → connecting. Media confirmation moves it to active.
create or replace function public.accept_call(p_call uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state text;
  v_callee uuid;
begin
  select state, callee_id into v_state, v_callee from public.calls where id = p_call;
  if v_state is null then
    raise exception 'not_found' using errcode = '22023';
  end if;
  if v_callee <> auth.uid() then
    raise exception 'not_allowed' using errcode = '28000';
  end if;
  if v_state <> 'ringing' then
    raise exception 'invalid_transition:%', v_state using errcode = '22023';
  end if;

  update public.calls
     set state = 'connecting', answered_at = now()
   where id = p_call;
end $$;

-- Media is up on both ends: connecting → active. Only a participant may say so.
create or replace function public.confirm_call_connected(p_call uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state text;
begin
  if not public.is_call_participant(p_call) then
    raise exception 'not_allowed' using errcode = '28000';
  end if;

  select state into v_state from public.calls where id = p_call;
  if v_state is null then
    raise exception 'not_found' using errcode = '22023';
  end if;
  if v_state <> 'connecting' then
    raise exception 'invalid_transition:%', v_state using errcode = '22023';
  end if;

  update public.calls set state = 'active' where id = p_call;
end $$;

create or replace function public.decline_call(p_call uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state text;
  v_callee uuid;
begin
  select state, callee_id into v_state, v_callee from public.calls where id = p_call;
  if v_state is null then
    raise exception 'not_found' using errcode = '22023';
  end if;
  if v_callee <> auth.uid() then
    raise exception 'not_allowed' using errcode = '28000';
  end if;
  if v_state not in ('ringing', 'connecting') then
    raise exception 'invalid_transition:%', v_state using errcode = '22023';
  end if;

  update public.calls
     set state = 'declined', end_reason = 'declined', ended_at = now()
   where id = p_call;
end $$;

create or replace function public.end_call(
  p_call uuid,
  p_reason text default 'hangup'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state text;
  v_reason text := coalesce(p_reason, 'hangup');
  v_caller uuid;
begin
  select state, caller_id into v_state, v_caller from public.calls where id = p_call;
  if v_state is null then
    raise exception 'not_found' using errcode = '22023';
  end if;
  if not public.is_call_participant(p_call) then
    raise exception 'not_allowed' using errcode = '28000';
  end if;
  if v_state in ('ended', 'declined', 'missed', 'failed') then
    return; -- idempotent: ending a finished call is a no-op
  end if;
  if v_reason not in ('hangup', 'declined', 'timeout', 'error', 'cancelled', 'answered_elsewhere') then
    raise exception 'invalid_reason' using errcode = '22023';
  end if;

  update public.calls
     set state = case
                   when v_state = 'ringing' and v_reason = 'timeout' then 'missed'
                   when v_state = 'ringing' and v_reason = 'cancelled' and v_caller = auth.uid() then 'ended'
                   when v_state = 'ringing' and v_caller = auth.uid() then 'ended'
                   when v_state = 'ringing' then 'missed'
                   when v_reason = 'error' then 'failed'
                   else 'ended'
                 end,
         end_reason = v_reason,
         ended_at = now()
   where id = p_call;
end $$;

-- Transient blip: active ↔ reconnecting. Kept explicit so the app never has to
-- invent a state.
create or replace function public.set_call_reconnecting(p_call uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state text;
begin
  if not public.is_call_participant(p_call) then
    raise exception 'not_allowed' using errcode = '28000';
  end if;

  select state into v_state from public.calls where id = p_call;
  if p_on and v_state <> 'active' then
    raise exception 'invalid_transition:%', v_state using errcode = '22023';
  end if;
  if not p_on and v_state <> 'reconnecting' then
    raise exception 'invalid_transition:%', v_state using errcode = '22023';
  end if;

  update public.calls
     set state = case when p_on then 'reconnecting' else 'active' end
   where id = p_call;
end $$;

-- --------------------------------------------------------------- realtime
do $$
begin
  begin
    alter publication supabase_realtime add table public.calls;
  exception when duplicate_object or undefined_object then null;
  end;
end $$;

-- --------------------------------------------------------------- grants
grant execute on function public.start_call(uuid, text) to authenticated;
grant execute on function public.accept_call(uuid) to authenticated;
grant execute on function public.confirm_call_connected(uuid) to authenticated;
grant execute on function public.decline_call(uuid) to authenticated;
grant execute on function public.end_call(uuid, text) to authenticated;
grant execute on function public.set_call_reconnecting(uuid, boolean) to authenticated;
grant execute on function public.call_role(uuid) to authenticated;
grant execute on function public.is_call_participant(uuid) to authenticated;
