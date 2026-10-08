#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
limit_tmp="$(mktemp -d /tmp/manna-character-limit.XXXXXX)"
case "$limit_tmp" in /tmp/manna-character-limit.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$limit_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  # Only the validated, newly created fixture directory is removed.
  rm -rf "$limit_tmp"
}
trap cleanup EXIT
initdb -D "$limit_tmp/db" -A trust -U limit_test >/dev/null
pg_ctl -D "$limit_tmp/db" -o "-F -k $limit_tmp -h ''" -l "$limit_tmp/postgres.log" -w start >/dev/null
psql -h "$limit_tmp" -U limit_test -d postgres -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/blessing_character_limit_schema.sql" \
  -f "$repo_root/supabase/migrations/202610080002_blessing_character_limit.sql" \
  -f "$repo_root/supabase/tests/blessing_character_limit.sql"
echo 'Blessing length migration and transactional fixture passed locally.'
