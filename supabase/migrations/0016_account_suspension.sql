-- =============================================================================
-- 0016_account_suspension.sql
--
-- One switch, and the account is closed. Somebody opens `account_status` in the
-- Supabase table editor, ticks `suspended`, and from that instant:
--
--   * every read and every write the client can perform is denied by RLS — the
--     chat list, the messages, the inbox, presence, friends, visits, calls,
--     avatars, everything. `is_account_active(auth.uid())` is part of every
--     policy on a user-owned table, so a *modified* client cannot get past it:
--     the check lives in the database, not in the app;
--   * every refresh token of that user is deleted (`auth.sessions` cascade), so
--     the session cannot be renewed and goes dark on its own;
--   * the presence row and the push tokens are deleted, so the account stops
--     appearing online and stops receiving notifications;
--   * the API stops accepting writes outright, so an in-flight message send
--     fails instead of queueing up somewhere.
--
-- The two things that stay open on purpose are the row that *says* the account
-- is suspended (`account_status`, own row only) and `account_appeals` — without
-- them the person could neither be told what happened nor ask a human to look
-- again. Everything else is shut.
--
-- The flag itself is one column, `suspended`, and it is kept equal to
-- `status <> 'active'` by a trigger in both directions: the table editor, the
-- enum, and any future admin tool can write either one and cannot drift apart.
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. The switch
-- ---------------------------------------------------------------------------
alter table public.account_status
  add column if not exists suspended boolean;

update public.account_status
   set suspended = (status <> 'active')
 where suspended is distinct from (status <> 'active');

alter table public.account_status
  alter column suspended set default false,
  alter column suspended set not null;

comment on column public.account_status.suspended is
  'The one switch. True = this account may do nothing: RLS denies every '
  'user-owned table, refresh tokens are deleted, presence and push are dropped. '
  'Kept equal to (status <> ''active'') by sync_account_suspension().';

-- A stable, human reference for support ("the case PULSE-1A2B3C-4D5"). It is
-- printed on the hold screen and on the receipt of an appeal, so it must never
-- change for a given account.
alter table public.account_status
  add column if not exists case_code text;

update public.account_status
   set case_code = 'PULSE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9))
 where case_code is null;

alter table public.account_status
  alter column case_code set default (
    'PULSE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9))
  ),
  alter column case_code set not null;

create unique index if not exists account_status_case_code_key
  on public.account_status (case_code);

-- Both directions, one invariant. Whichever column the human (or a future tool)
-- writes, the other follows:
--
--   * `suspended` changed  -> it is the switch, so it decides `status`;
--   * only `status` changed -> the enum decides the switch;
--   * neither changed       -> nothing to reconcile (a reason_text edit, say).
--
-- When both arrive in the same statement, `suspended` wins: it is the one
-- column that is documented as the switch, so its value cannot be ignored.
create or replace function public.sync_account_suspension()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_from_status boolean := (coalesce(new.status::text, 'active') <> 'active');
begin
  if tg_op = 'INSERT' then
    new.suspended := v_from_status;
  elsif new.suspended is distinct from old.suspended then
    new.status := case
      when new.suspended then 'suspended'::public.account_status_value
      else 'active'::public.account_status_value
    end;
  elsif new.status is distinct from old.status then
    new.suspended := v_from_status;
  end if;

  -- A fresh suspension starts now, whatever an older window said. OLD does not
  -- exist yet on INSERT, so it may only be read on the UPDATE path.
  if new.suspended then
    if tg_op = 'INSERT' then
      new.starts_at := now();
    elsif not old.suspended then
      new.starts_at := now();
    end if;
  end if;

  if new.case_code is null then
    new.case_code := 'PULSE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9));
  end if;

  return new;
end;
$$;

revoke all on function public.sync_account_suspension() from public, anon, authenticated;

drop trigger if exists account_status_sync_suspension on public.account_status;
create trigger account_status_sync_suspension
  before insert or update on public.account_status
  for each row execute function public.sync_account_suspension();

-- ---------------------------------------------------------------------------
-- 2. The predicate every policy asks
-- ---------------------------------------------------------------------------
create or replace function public.is_account_active(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select a.status = 'active' and (a.ends_at is null or a.ends_at > now())
       from public.account_status a
      where a.user_id = p_user),
    -- No row yet (a profile created microseconds ago) must not read as a ban.
    true
  );
$$;

revoke all on function public.is_account_active(uuid) from public, anon;
grant execute on function public.is_account_active(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Being suspended also ends the session
--
-- RLS already makes the token useless; deleting the session makes it *stop
-- existing*, so the app cannot sit on a stale JWT and retry for an hour. GoTrue
-- cascades refresh tokens off `auth.sessions`, and a refresh token that is not
-- there is a signed-out phone.
-- ---------------------------------------------------------------------------
create or replace function public.on_account_suspended()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if new.suspended and not coalesce(old.suspended, false) then
    delete from auth.sessions s where s.user_id = new.user_id;
    delete from public.fcm_tokens t where t.user_id = new.user_id;
    delete from public.user_presence p where p.user_id = new.user_id;
  end if;

  return null;
end;
$$;

revoke all on function public.on_account_suspended() from public, anon, authenticated;

drop trigger if exists account_status_end_sessions on public.account_status;
create trigger account_status_end_sessions
  after insert or update of suspended, status on public.account_status
  for each row execute function public.on_account_suspended();

-- ---------------------------------------------------------------------------
-- 4. The appeal — the one door that stays open while suspended
-- ---------------------------------------------------------------------------
create table if not exists public.account_appeals (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  case_code   text not null,
  note        text not null,
  status      text not null default 'open',
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  constraint account_appeals_note_len check (char_length(note) between 8 and 1200),
  constraint account_appeals_status check (status in ('open', 'reviewing', 'accepted', 'declined'))
);

comment on table public.account_appeals is
  'A suspended account asking a human to look again. Written only by the '
  'suspended account itself, read by the same account and by the service role. '
  'One open appeal at a time — a second one updates nothing and is refused.';

create index if not exists account_appeals_user_idx
  on public.account_appeals (user_id, created_at desc);

create unique index if not exists account_appeals_one_open
  on public.account_appeals (user_id) where status in ('open', 'reviewing');

alter table public.account_appeals enable row level security;

drop policy if exists account_appeals_select_own on public.account_appeals;
create policy account_appeals_select_own on public.account_appeals
  for select to authenticated
  using (user_id = auth.uid());

-- Deliberately *not* guarded by is_account_active: an active account has
-- nothing to appeal, and a suspended one must be able to write here.
drop policy if exists account_appeals_insert_own on public.account_appeals;
create policy account_appeals_insert_own on public.account_appeals
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'open'
    and not public.is_account_active(auth.uid())
    and case_code = (
      select a.case_code from public.account_status a where a.user_id = auth.uid()
    )
  );

-- No client update, no client delete: the verdict is not the client's to write.
revoke all on public.account_appeals from public, anon;
grant select, insert on public.account_appeals to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Every policy on a user-owned table asks the same question
-- ---------------------------------------------------------------------------
-- Rewriting the existing policies in place (alter, not drop) keeps their names,
-- their commands and their roles: this migration changes *who may pass*, never
-- *what a policy is for*.

-- messages --------------------------------------------------------------
alter policy messages_select_member on public.messages
  using (
    public.is_account_active(auth.uid())
    and public.is_conversation_member(conversation_id)
  );

alter policy messages_insert_own on public.messages
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
    and public.is_account_active(auth.uid())
  );

alter policy messages_update_own on public.messages
  using (sender_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id)
    and public.is_account_active(auth.uid())
  );

alter policy messages_delete_own on public.messages
  using (sender_id = auth.uid() and public.is_account_active(auth.uid()));

-- conversations ---------------------------------------------------------
alter policy conversations_select_member on public.conversations
  using (public.is_account_active(auth.uid()) and public.is_conversation_member(id));

alter policy conversations_update_group_admin on public.conversations
  using (
    kind = 'group'
    and public.is_account_active(auth.uid())
    and public.is_group_admin(id)
  )
  with check (
    kind = 'group'
    and public.is_account_active(auth.uid())
    and public.is_group_admin(id)
  );

alter policy conversation_members_select_member on public.conversation_members
  using (public.is_account_active(auth.uid()) and public.is_conversation_member(conversation_id));

alter policy conversation_members_update_own on public.conversation_members
  using (user_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (user_id = auth.uid() and public.is_account_active(auth.uid()));

-- people -----------------------------------------------------------------
alter policy profiles_select_authenticated on public.profiles
  using (public.is_account_active(auth.uid()));

alter policy profiles_update_own on public.profiles
  using (id = auth.uid() and public.is_account_active(auth.uid()))
  with check (id = auth.uid() and public.is_account_active(auth.uid()));

alter policy friendships_select_own on public.friendships
  using (user_id = auth.uid() and public.is_account_active(auth.uid()));

alter policy friend_requests_select_own on public.friend_requests
  using (
    (requester_id = auth.uid() or addressee_id = auth.uid())
    and public.is_account_active(auth.uid())
  );

alter policy blocks_read_own on public.blocks
  using (blocker = auth.uid() and public.is_account_active(auth.uid()));

alter policy blocks_insert_own on public.blocks
  with check (blocker = auth.uid() and public.is_account_active(auth.uid()));

alter policy blocks_delete_own on public.blocks
  using (blocker = auth.uid() and public.is_account_active(auth.uid()));

alter policy reports_insert_own on public.reports
  with check (reporter = auth.uid() and public.is_account_active(auth.uid()));

-- presence: a suspended account is not online, and does not see who is
alter policy user_presence_select_all on public.user_presence
  using (public.is_account_active(auth.uid()));

alter policy user_presence_insert_own on public.user_presence
  with check (user_id = auth.uid() and public.is_account_active(auth.uid()));

alter policy user_presence_update_own on public.user_presence
  using (user_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (user_id = auth.uid() and public.is_account_active(auth.uid()));

-- visits and devices ------------------------------------------------------
alter policy profile_visits_read_own on public.profile_visits
  using (viewed = auth.uid() and public.is_account_active(auth.uid()));

alter policy profile_visits_record_own on public.profile_visits
  with check (
    viewer = auth.uid()
    and viewed <> auth.uid()
    and public.is_account_active(auth.uid())
  );

alter policy devices_select_linked on public.devices
  using (
    public.is_account_active(auth.uid())
    and exists (
      select 1 from public.account_device_history h
       where h.device_id = devices.id and h.user_id = auth.uid()
    )
  );

alter policy account_device_history_select_own on public.account_device_history
  using (user_id = auth.uid() and public.is_account_active(auth.uid()));

-- push: no tokens, no notifications
alter policy fcm_tokens_select_own on public.fcm_tokens
  using (user_id = auth.uid() and public.is_account_active(auth.uid()));

alter policy fcm_tokens_insert_own on public.fcm_tokens
  with check (user_id = auth.uid() and public.is_account_active(auth.uid()));

alter policy fcm_tokens_update_own on public.fcm_tokens
  using (user_id = auth.uid() and public.is_account_active(auth.uid()))
  with check (user_id = auth.uid() and public.is_account_active(auth.uid()));

alter policy fcm_tokens_delete_own on public.fcm_tokens
  using (user_id = auth.uid() and public.is_account_active(auth.uid()));

-- calls -------------------------------------------------------------------
alter policy "calls: participants can read" on public.calls
  using (
    (auth.uid() = caller_id or auth.uid() = callee_id)
    and public.is_account_active(auth.uid())
  );

alter policy force_audio_select_participant on public.force_audio_alerts
  using (
    (sender_id = auth.uid() or recipient_id = auth.uid())
    and public.is_account_active(auth.uid())
  );

-- avatars (storage) -------------------------------------------------------
-- The bucket lives in Supabase's own `storage` schema, which a plain Postgres
-- checkout (and the local test harness) does not have. Same policy, same guard,
-- skipped cleanly where there is nothing to guard.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    return;
  end if;

  execute $p$alter policy avatars_read on storage.objects
    using (bucket_id = 'avatars')$p$;

  execute $p$alter policy avatars_insert_own on storage.objects
    with check (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = (auth.uid())::text
      and public.is_account_active(auth.uid())
    )$p$;

  execute $p$alter policy avatars_update_own on storage.objects
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = (auth.uid())::text
      and public.is_account_active(auth.uid())
    )
    with check (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = (auth.uid())::text
      and public.is_account_active(auth.uid())
    )$p$;

  execute $p$alter policy avatars_delete_own on storage.objects
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = (auth.uid())::text
      and public.is_account_active(auth.uid())
    )$p$;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5b. The same answer inside the SECURITY DEFINER functions
--
-- Policies only bind the client. Half of Pulse's writes go through definer
-- functions (start_direct_conversation, start_call, send_friend_request,
-- record_profile_visit, touch_presence, the group RPCs...), and a definer
-- function runs as its owner, where RLS does not apply. Guarding thirty
-- functions one by one would also mean guarding the thirty-first that nobody
-- has written yet.
--
-- So the question is asked once, at the table: any row written *by a caller*
-- whose account is suspended is refused, whichever door it came through. Admin
-- and service-role work carries no caller (auth.uid() is null) and is not
-- affected, which is what lets a human unsuspend an account.
--
-- SQLSTATE 'PULSE' exists so the app can tell "you are suspended" apart from
-- "the network is down" and log the phone out instead of retrying.
-- ---------------------------------------------------------------------------
create or replace function public.guard_account_activity()
returns trigger
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_account_active(v_uid) then
    raise exception 'account_suspended'
      using errcode = 'PULSE',
            detail = 'This account is on hold and may not write.',
            hint = 'Nothing was saved. The account has to be restored first.';
  end if;

  -- A BEFORE trigger that returns NULL does not "pass": it cancels the row
  -- silently. Returning the row is the whole difference between "allowed" and
  -- "quietly thrown away".
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.guard_account_activity() from public, anon, authenticated;

do $$
declare
  t text;
begin
  -- Writing anything: refused.
  foreach t in array array[
    'messages', 'conversations', 'conversation_members', 'friend_requests',
    'friendships', 'blocks', 'profile_visits', 'calls', 'force_audio_alerts',
    'user_presence', 'fcm_tokens', 'reports', 'account_device_history'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'guard_' || t || '_activity', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.guard_account_activity()',
      'guard_' || t || '_activity', t
    );
  end loop;

  -- Removing content: refused too. Deleting is not "using the app", but a
  -- suspended account has no business editing an archive either.
  --
  -- `user_presence`, `fcm_tokens` and `account_device_history` are deliberately
  -- *not* in this list: signing out has to be able to delete the phone's own
  -- presence row and push token, even when the account it is signing out of is
  -- the suspended one.
  foreach t in array array[
    'messages', 'conversations', 'conversation_members', 'friend_requests',
    'friendships', 'blocks', 'profile_visits', 'calls', 'force_audio_alerts',
    'reports'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'guard_' || t || '_removal', t);
    execute format(
      'create trigger %I before delete on public.%I '
      'for each row execute function public.guard_account_activity()',
      'guard_' || t || '_removal', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The flip has to reach the phone that is already open
--
-- The app watches its own row; publishing the table to Realtime is what turns
-- "the admin ticked a box" into "the screen goes dark in the same second"
-- instead of "at the next launch".
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'account_status'
  ) then
    alter publication supabase_realtime add table public.account_status;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'account_appeals'
  ) then
    alter publication supabase_realtime add table public.account_appeals;
  end if;
end;
$$;

commit;
