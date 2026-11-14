-- 0001_profiles.sql — profile of every account (1:1 with auth.users)
-- Forward-only migration. Safe to re-run (idempotent guards).
begin;

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text,
  display_name text not null default '',
  bio          text not null default '',
  avatar_url   text,
  cover_url    text,
  joined_at    timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- usernames are stored lowercase only, so a plain unique index is enough
  constraint profiles_username_format check (username is null or username ~ '^[a-z0-9_]{3,24}$'),
  constraint profiles_display_name_len check (char_length(display_name) <= 60),
  constraint profiles_bio_len check (char_length(bio) <= 200)
);

create unique index if not exists profiles_username_key
  on public.profiles (username) where username is not null;

create index if not exists profiles_display_name_idx
  on public.profiles (lower(display_name));

comment on table public.profiles is
  'Public profile, one row per auth.users row, created by trigger on signup.';

-- updated_at maintenance
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Create the profile automatically for every new auth user.
-- SECURITY DEFINER is required because clients have no INSERT policy.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_display text;
begin
  v_display := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(new.email, 'Pulse user'), '@', 1)
  );

  insert into public.profiles (id, display_name)
  values (new.id, left(v_display, 60))
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS ------------------------------------------------------------------
alter table public.profiles enable row level security;

-- Any signed-in account may read profiles (needed for Explore / friend search).
drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated on public.profiles
  for select to authenticated
  using (true);

-- Only the owner may update their own row.
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- No INSERT/DELETE policies on purpose: rows are created by the signup
-- trigger and removed by the auth.users cascade.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, username, bio, avatar_url, cover_url)
  on public.profiles to authenticated;

commit;
