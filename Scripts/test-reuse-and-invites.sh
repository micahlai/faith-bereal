#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
reuse_tmp="$(mktemp -d /tmp/manna-reuse-invites.XXXXXX)"
case "$reuse_tmp" in /tmp/manna-reuse-invites.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$reuse_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$reuse_tmp"
}
trap cleanup EXIT
initdb -D "$reuse_tmp/db" -A trust -U reuse_test >/dev/null
pg_ctl -D "$reuse_tmp/db" -o "-F -k $reuse_tmp -h ''" -l "$reuse_tmp/postgres.log" -w start >/dev/null
run_sql() { psql -h "$reuse_tmp" -U reuse_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
extract_function() {
  awk -v name="$1" '$0 ~ "^create or replace function public\\." name "\\(" { active=1 }
    active { print } active && /^\$\$;/ { active=0 }' "$2" | run_sql
}
# is_circle_member must exist before the fixture's open-entry predicate compiles.
# SQL functions with forward references are resolved after the real helpers load.
run_sql -c 'set check_function_bodies = off' -f "$repo_root/supabase/tests/reuse_invite_schema.sql"
for name in is_circle_member has_submitted try_uuid; do
  extract_function "$name" "$repo_root/supabase/migrations/202609290001_initial_schema.sql"
done
extract_function can_view_blessing "$repo_root/supabase/migrations/202610070008_end_of_day_blessings.sql"
extract_function create_circle "$repo_root/supabase/migrations/202610070008_end_of_day_blessings.sql"
extract_function regenerate_circle_invite_code "$repo_root/supabase/migrations/202610060010_circle_creation_settings_and_code_rotation.sql"
run_sql -f "$repo_root/supabase/migrations/202610070002_universal_circle_invites.sql" \
  -f "$repo_root/supabase/migrations/202610080001_media_retention.sql" \
  -f "$repo_root/supabase/migrations/202610080002_blessing_character_limit.sql" \
  -f "$repo_root/supabase/migrations/202610090001_reuse_blessing_media.sql" \
  -f "$repo_root/supabase/migrations/202610090002_durable_circle_invites.sql" \
  -f "$repo_root/supabase/tests/reuse_blessing_media.sql" \
  -f "$repo_root/supabase/tests/durable_circle_invites.sql" \
  -f "$repo_root/supabase/tests/reuse_storage_visibility.sql"
echo 'Reuse media, invite recovery, and private Storage visibility checks passed locally.'
