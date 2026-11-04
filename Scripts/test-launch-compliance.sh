#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
launch_tmp="$(mktemp -d /tmp/manna-launch.XXXXXX)"
cleanup(){ pg_ctl -D "$launch_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true; rm -rf "$launch_tmp"; }
trap cleanup EXIT
initdb -D "$launch_tmp/db" -A trust -U launch_test >/dev/null
pg_ctl -D "$launch_tmp/db" -o "-F -k $launch_tmp -h ''" -l "$launch_tmp/postgres.log" -w start >/dev/null
run_sql(){ psql -h "$launch_tmp" -U launch_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
run_sql <<'SQL'
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema extensions;
create schema storage;
create table auth.users(id uuid primary key default gen_random_uuid(),email text,raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,version text,metadata jsonb,last_accessed_at timestamptz,owner_id text,is_delete_marker boolean default false,archived_at timestamptz,unique(bucket_id,name));
create function storage.foldername(text) returns text[] language sql immutable as $$ select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1] $$;
alter table storage.objects enable row level security;
grant usage on schema auth,storage,public,extensions to authenticated,service_role;
grant select,insert,update,delete on storage.objects to authenticated,service_role;
create publication supabase_realtime;
SQL
# Only hosted scheduling extension installation is omitted; all function,
# policy, trigger and data-migration statements run unchanged.
for migration in "$repo_root"/supabase/migrations/*.sql; do
  if [[ "$migration" == *202611020007* ]]; then run_sql -f "$repo_root/supabase/tests/media_publication_before.sql"; fi
  sed '/^create extension if not exists pg_cron /d; /^create extension if not exists pg_net /d' "$migration" | run_sql
 done
run_sql -f "$repo_root/supabase/tests/media_publication_after.sql"
run_sql -f "$repo_root/supabase/tests/launch_compliance.sql"
run_sql -f "$repo_root/supabase/tests/retention_launch.sql"
run_sql -f "$repo_root/supabase/tests/ready_circle_badges.sql"
run_sql -f "$repo_root/supabase/tests/circle_nudges.sql"
echo 'Full migration-chain launch safety and deletion checks passed.'
