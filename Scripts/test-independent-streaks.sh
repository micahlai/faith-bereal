#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
streak_tmp="$(mktemp -d /tmp/manna-independent-streaks.XXXXXX)"
case "$streak_tmp" in /tmp/manna-independent-streaks.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$streak_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$streak_tmp"
}
trap cleanup EXIT
initdb -D "$streak_tmp/db" -A trust -U streak_test >/dev/null
pg_ctl -D "$streak_tmp/db" -o "-F -k $streak_tmp -h ''" -l "$streak_tmp/postgres.log" -w start >/dev/null
run_sql() { psql -h "$streak_tmp" -U streak_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
run_sql -c 'set check_function_bodies = off' -f "$repo_root/supabase/tests/reuse_invite_schema.sql"
awk '$0 ~ "^create or replace function public\\.is_circle_member\\(" { active=1 }
  active { print } active && /^\$\$;/ { active=0 }' \
  "$repo_root/supabase/migrations/202609290001_initial_schema.sql" | run_sql
# Exercise the hosted four-column predecessor without enabling shared settings.
run_sql -f "$repo_root/supabase/migrations/202610130001_circle_streaks.sql" \
  -f "$repo_root/supabase/migrations/202610150002_independent_streak_deadlines.sql" \
  -f "$repo_root/supabase/tests/independent_streak_deadlines.sql" \
  -f "$repo_root/supabase/tests/independent_streak_performance.sql"
# Tighten the disposable fixture to the production fields/checks used by the
# hosted rollback suite, including automatic profile creation on auth insert.
run_sql <<'SQL'
alter table public.profiles add column time_zone text not null default 'UTC';
alter table public.profiles alter column display_name set not null;
alter table public.circles alter column name set not null;
alter table public.circles alter column owner_id set not null;
alter table public.circles alter column invite_code_hash set not null;
alter table public.circles add check(window_end>window_start);
alter table public.circles add check(end_of_day_time>=window_end);
alter table public.daily_prompts alter column response_window_minutes set not null;
alter table public.daily_prompts add check(ends_at=starts_at+make_interval(mins=>response_window_minutes));
alter table public.blessings alter column is_late set not null;
SQL
awk '$0 ~ "^create or replace function public\\.handle_new_auth_user\\(" { active=1 }
  active { print } active && /^\$\$;/ { active=0 }' \
  "$repo_root/supabase/migrations/202609290007_auth_profiles_and_client_grants.sql" | run_sql
run_sql -c 'create trigger auth_user_created_profile after insert on auth.users for each row execute function public.handle_new_auth_user();'
run_sql -f "$repo_root/supabase/tests/independent_streak_deadlines_hosted.sql"
echo 'Independent streak posting, deadlines, DST, cross-midnight, and membership checks passed locally.'
