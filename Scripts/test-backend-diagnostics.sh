#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
diagnostics_tmp="$(mktemp -d /tmp/manna-diagnostics.XXXXXX)"
case "$diagnostics_tmp" in /tmp/manna-diagnostics.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$diagnostics_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  # Only the newly created, validated fixture directory is removed.
  rm -rf "$diagnostics_tmp"
}
trap cleanup EXIT
initdb -D "$diagnostics_tmp/db" -A trust -U diagnostics_test >/dev/null
pg_ctl -D "$diagnostics_tmp/db" -o "-F -k $diagnostics_tmp -h ''" -l "$diagnostics_tmp/postgres.log" -w start >/dev/null
run_sql() { psql -h "$diagnostics_tmp" -U diagnostics_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
run_sql -f "$repo_root/supabase/tests/backend_diagnostics_schema.sql" \
  -f "$repo_root/supabase/migrations/202610130002_backend_diagnostics.sql" \
  -f "$repo_root/supabase/tests/backend_diagnostics.sql"

# A simultaneous two-connection upload must preserve the account rate limit.
# This is a bounded local race against the real RPC, not a hosted load test.
run_sql -c "insert into auth.users(id) values ('00000000-0000-0000-0000-000000000011');" >/dev/null
cat > "$diagnostics_tmp/race.sql" <<'SQL'
begin;
set local role authenticated;
set local time zone 'UTC';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select public.ingest_backend_diagnostics(gen_random_uuid(),
  '00000000-0000-0000-0000-000000000012',42,
  jsonb_build_array(jsonb_build_object('kind','stage','startedAt',to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'stage','submit','durationMilliseconds',10,'outcome','success')));
-- Keep the winning transaction's account lock held while the other caller waits.
select pg_sleep(1);
commit;
SQL
set +e
run_sql -f "$diagnostics_tmp/race.sql" >"$diagnostics_tmp/race-1.log" 2>&1 &
race_one=$!
run_sql -f "$diagnostics_tmp/race.sql" >"$diagnostics_tmp/race-2.log" 2>&1 &
race_two=$!
wait "$race_one"; status_one=$?
wait "$race_two"; status_two=$?
set -e
if ! { [ "$status_one" -eq 0 ] && [ "$status_two" -ne 0 ]; } && \
  ! { [ "$status_two" -eq 0 ] && [ "$status_one" -ne 0 ]; }; then
  cat "$diagnostics_tmp/race-1.log" "$diagnostics_tmp/race-2.log"
  echo 'Expected exactly one concurrent diagnostic report to be accepted.' >&2
  exit 1
fi
run_sql -c "do \$\$ begin assert (select count(*)=1 from manna_private.backend_diagnostic_reports); end; \$\$;" >/dev/null
echo 'Diagnostic authorization, validation, retries, quotas, retention, and concurrent rate checks passed locally.'
