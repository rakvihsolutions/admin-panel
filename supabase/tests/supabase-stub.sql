-- Minimal stand-in for what a Supabase project already has (roles, auth, storage),
-- so the migrations can be tested on a plain local Postgres (PGlite). NOT for production.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema auth;
create table auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text, phone text,
  encrypted_password text, email_confirmed_at timestamptz, last_sign_in_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb, created_at timestamptz default now(), updated_at timestamptz default now(),
  confirmation_token text, email_change text, email_change_token_new text, recovery_token text
);
create table auth.identities (
  id uuid primary key, user_id uuid references auth.users(id) on delete cascade, provider_id text, identity_data jsonb,
  provider text, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz
);
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), auth.jwt() ->> 'sub')::uuid
$$;
create function auth.role() returns text language sql stable as $$ select auth.jwt() ->> 'role' $$;
grant usage on schema auth, extensions to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;

create schema storage;
create table storage.buckets (
  id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now()
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text,
  owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), metadata jsonb
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;
