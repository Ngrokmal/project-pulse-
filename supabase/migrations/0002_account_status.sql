-- 0002_account_status.sql — server-authoritative account restriction state (§25)
begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'account_status_value') then
    create type public.account_status_value as enum ('active', 'suspended', 'banned', 'under_review');
  end if;
end;
$$;

create table if not exists public.account_status (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  status      public.account_status_value not null default 'active',
  reason_code text,
  reason_text text,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  constraint account_status_reason_len check (reason_text is null or char_length(reason_text) <= 500),
  constraint account_status_window check (ends_at is null or ends_at > starts_at)
);

create index if not exists account_status_active_idx
  on public.account_status (user_id) where status <> 'active';

drop trigger if exists account_status_touch_updated_at on public.account_status;
create trigger account_status_touch_updated_at
  before update on public.account_status
  for each row execute function public.touch_updated_at();

-- Every profile gets a status row. Runs after profile creation (0001).
create or replace function public.handle_new_profile_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.account_status (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_profile_status() from public, anon, authenticated;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created
  after insert on public.profiles
  for each row execute function public.handle_new_profile_status();

-- backfill for profiles that existed before this migration
insert into public.account_status (user_id)
select p.id from public.profiles p
on conflict (user_id) do nothing;

-- Server-side helper used by other policies / functions.
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
    true  -- unknown user: do not invent a restriction
  );
$$;

revoke all on function public.is_account_active(uuid) from public, anon;
grant execute on function public.is_account_active(uuid) to authenticated;

-- RLS ------------------------------------------------------------------
alter table public.account_status enable row level security;

drop policy if exists account_status_select_own on public.account_status;
create policy account_status_select_own on public.account_status
  for select to authenticated
  using (user_id = auth.uid());

-- No INSERT/UPDATE/DELETE policies: only service_role (BYPASSRLS) may write.
-- A restricted client therefore cannot lift its own restriction (§25).
revoke all on public.account_status from anon, authenticated;
grant select on public.account_status to authenticated;

commit;
