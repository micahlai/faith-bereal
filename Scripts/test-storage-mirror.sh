#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mirror_tmp="$(mktemp -d /tmp/manna-mirror.XXXXXX)"
cleanup() {
  pg_ctl -D "$mirror_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$mirror_tmp"
}
trap cleanup EXIT
initdb -D "$mirror_tmp/db" -A trust -U mirror_test >/dev/null
pg_ctl -D "$mirror_tmp/db" -o "-F -k $mirror_tmp -h ''" -l "$mirror_tmp/postgres.log" -w start >/dev/null
psql -h "$mirror_tmp" -U mirror_test -d postgres -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/storage_mirror_schema.sql" \
  -f "$repo_root/supabase/migrations/202611020001_storage_mirror.sql" \
  -f "$repo_root/supabase/tests/storage_mirror.sql"
run_sql() { psql -h "$mirror_tmp" -U mirror_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
run_sql -c "insert into storage.objects(bucket_id,name,version) values ('avatars','concurrent/avatar.jpg','1');" >/dev/null
# A locked job must be skipped immediately by another claimant, not blocked.
run_sql >"$mirror_tmp/lock.log" <<'SQL' &
begin;
select id from manna_private.storage_mirror_jobs for update;
select pg_sleep(2);
commit;
SQL
locker_pid=$!
# Poll the server for the lock holder rather than trusting a startup delay.
for attempt in {1..100}; do
  if [ "$(run_sql -Atc "select count(*) from pg_stat_activity where wait_event='PgSleep'")" = 1 ]; then break; fi
done
run_sql <<'SQL'
set statement_timeout='1s';
do $$ begin assert (select count(*)=0 from public.claim_storage_mirror_jobs(1)), 'locked job was claimed'; end $$;
SQL
wait "$locker_pid"
run_sql <<'SQL'
do $$ begin assert (select count(*)=1 from public.claim_storage_mirror_jobs(1)), 'unlocked job was lost'; end $$;
SQL
