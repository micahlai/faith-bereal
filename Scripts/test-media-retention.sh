#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
retention_tmp="$(mktemp -d /tmp/manna-retention.XXXXXX)"
case "$retention_tmp" in /tmp/manna-retention.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$retention_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  # Only the validated, newly created fixture directory is removed.
  rm -rf "$retention_tmp"
}
trap cleanup EXIT
initdb -D "$retention_tmp/db" -A trust -U retention_test >/dev/null
pg_ctl -D "$retention_tmp/db" -o "-F -k $retention_tmp -h ''" -l "$retention_tmp/postgres.log" -w start >/dev/null
psql -h "$retention_tmp" -U retention_test -d postgres -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/media_retention_schema.sql" \
  -f "$repo_root/supabase/migrations/202610080001_media_retention.sql" \
  -f "$repo_root/supabase/tests/media_retention.sql"
echo 'Media retention migration and transactional fixture passed locally.'
