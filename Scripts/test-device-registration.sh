#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
registration_tmp="$(mktemp -d /tmp/manna-registration.XXXXXX)"
case "$registration_tmp" in /tmp/manna-registration.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$registration_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$registration_tmp"
}
trap cleanup EXIT
initdb -D "$registration_tmp/db" -A trust -U registration_test >/dev/null
pg_ctl -D "$registration_tmp/db" -o "-F -k $registration_tmp -h ''" -l "$registration_tmp/postgres.log" -w start >/dev/null
run_sql() { psql -h "$registration_tmp" -U registration_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
# Minimal isolated predecessor schema. Never run this setup on hosted data.
run_sql <<'SQL'
create role anon;
create role authenticated;
create schema auth;
create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
create table public.profiles(id uuid primary key references auth.users, display_name text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to authenticated;
create type public.push_environment as enum ('sandbox','production');
create table public.device_registrations (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles,
  installation_id uuid not null, apns_token text, push_to_start_token text,
  environment public.push_environment not null, last_seen_at timestamptz not null default now(),
  revoked_at timestamptz, unique(user_id,installation_id,environment)
);
alter table public.device_registrations enable row level security;
SQL
run_sql -f "$repo_root/supabase/migrations/202610060005_preserve_device_tokens.sql"
run_sql <<'SQL'
do $$
begin
  begin
    perform public.register_device(p_installation_id=>gen_random_uuid(),p_apns_token=>'synthetic',p_environment=>'production');
    raise exception 'Expected predecessor argument resolution failure';
  exception when undefined_function then null;
  end;
end;
$$;
SQL
run_sql -f "$repo_root/supabase/migrations/202610240001_device_registration_optional_tokens.sql"
run_sql -f "$repo_root/supabase/tests/device_registration_optional_tokens.sql"
