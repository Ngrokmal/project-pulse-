-- 0003_devices_and_tokens.sql — device identity (§31.7) + FCM tokens (§9)
begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'device_status_value') then
    create type public.device_status_value as enum ('active', 'restricted', 'under_review', 'banned');
  end if;
end;
$$;

-- Devices are identified by a SERVER-side keyed hash of the Android ID.
-- The raw Android ID is never stored (see functions/device-register).
create table if not exists public.devices (
  id           uuid primary key default gen_random_uuid(),
  device_hash  text not null,
  hash_version smallint not null default 1,
  platform     text not null default 'android',
  status       public.device_status_value not null default 'active',
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  constraint devices_hash_hex check (device_hash ~ '^[0-9a-f]{64}$'),
  constraint devices_platform_allowed check (platform in ('android')),
  constraint devices_hash_version_positive check (hash_version > 0)
);

create unique index if not exists devices_identity_key
  on public.devices (device_hash, hash_version);

create table if not exists public.account_device_history (
  user_id    uuid not null references auth.users (id) on delete cascade,
  device_id  uuid not null references public.devices (id) on delete cascade,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  primary key (user_id, device_id)
);

create index if not exists account_device_history_device_idx
  on public.account_device_history (device_id);

create table if not exists public.device_security_events (
  id         bigint generated always as identity primary key,
  device_id  uuid references public.devices (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete set null,
  event      text not null,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint device_security_event_len check (char_length(event) <= 64)
);

create index if not exists device_security_events_device_idx
  on public.device_security_events (device_id, created_at desc);

create table if not exists public.fcm_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  device_id  uuid references public.devices (id) on delete cascade,
  token      text not null unique,
  platform   text not null default 'android',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fcm_tokens_len check (char_length(token) between 20 and 4096)
);

create index if not exists fcm_tokens_active_idx
  on public.fcm_tokens (user_id) where is_active;

drop trigger if exists fcm_tokens_touch_updated_at on public.fcm_tokens;
create trigger fcm_tokens_touch_updated_at
  before update on public.fcm_tokens
  for each row execute function public.touch_updated_at();

-- RLS ------------------------------------------------------------------
alter table public.devices enable row level security;
alter table public.account_device_history enable row level security;
alter table public.device_security_events enable row level security;
alter table public.fcm_tokens enable row level security;

-- A user can see the device rows linked to their own account.
drop policy if exists devices_select_linked on public.devices;
create policy devices_select_linked on public.devices
  for select to authenticated
  using (
    exists (
      select 1 from public.account_device_history h
      where h.device_id = devices.id and h.user_id = auth.uid()
    )
  );

drop policy if exists account_device_history_select_own on public.account_device_history;
create policy account_device_history_select_own on public.account_device_history
  for select to authenticated
  using (user_id = auth.uid());

-- Client may read its own token rows and register/refresh its own token.
drop policy if exists fcm_tokens_select_own on public.fcm_tokens;
create policy fcm_tokens_select_own on public.fcm_tokens
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists fcm_tokens_insert_own on public.fcm_tokens;
create policy fcm_tokens_insert_own on public.fcm_tokens
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists fcm_tokens_update_own on public.fcm_tokens;
create policy fcm_tokens_update_own on public.fcm_tokens
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists fcm_tokens_delete_own on public.fcm_tokens;
create policy fcm_tokens_delete_own on public.fcm_tokens
  for delete to authenticated
  using (user_id = auth.uid());

-- devices / account_device_history / device_security_events are written only
-- by trusted server code (Edge Function with service_role).
revoke all on public.devices from anon, authenticated;
revoke all on public.account_device_history from anon, authenticated;
revoke all on public.device_security_events from anon, authenticated;
grant select on public.devices to authenticated;
grant select on public.account_device_history to authenticated;

revoke all on public.fcm_tokens from anon, authenticated;
grant select, insert, update, delete on public.fcm_tokens to authenticated;

commit;
