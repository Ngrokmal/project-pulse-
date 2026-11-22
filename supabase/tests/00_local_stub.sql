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

-- Synthetic Storage only; this does not emulate managed Storage API behavior.
create schema if not exists storage;
create table storage.buckets(id text primary key, name text not null, public boolean not null default false, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text not null, name text not null, unique(bucket_id,name));
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name,'/') $$;
grant usage on schema storage to anon,authenticated,service_role;
grant execute on function storage.foldername(text) to authenticated,service_role;
grant select on storage.objects to anon;
grant select,insert,update,delete on storage.objects to authenticated,service_role;
grant all on storage.buckets to service_role;
