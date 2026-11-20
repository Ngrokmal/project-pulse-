-- Local-only emulation of the pieces Supabase provides, so migrations and RLS
-- policies can be verified on a plain PostgreSQL instance in CI/dev.
-- NEVER run this against a real Supabase project.
create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Supabase exposes the JWT subject through auth.uid(). It reads the JSON
-- `request.jwt.claims` setting; older code (and some tests) set the single
-- `request.jwt.claim.sub` value instead, so support both.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
  );
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

-- The two tables a suspension acts on. On Supabase, GoTrue cascades
-- auth.refresh_tokens off auth.sessions, which is why deleting a session ends
-- the login; the stub keeps the same foreign key so the behaviour is testable.
create table if not exists auth.sessions (
  id         uuid primary key,
  user_id    uuid not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  aal        text
);

create table if not exists auth.refresh_tokens (
  instance_id uuid,
  id         bigserial primary key,
  token      text,
  user_id    text,
  revoked    boolean default false,
  session_id uuid references auth.sessions (id) on delete cascade
);

-- Supabase ships this publication (Realtime). Migrations that publish a table
-- must be tested against it, not against its absence.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on auth.users to service_role;
