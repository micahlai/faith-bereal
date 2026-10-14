-- Minimal disposable fixture for diagnostic ingestion security regressions.
-- Never run this schema against an existing database or hosted Supabase.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
