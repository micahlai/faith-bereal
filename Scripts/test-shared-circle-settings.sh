#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
migration_order="${1:-standard}"
case "$migration_order" in standard|--streak-first) ;; *) echo 'Unknown migration order.' >&2; exit 1 ;; esac
settings_tmp="$(mktemp -d /tmp/manna-shared-settings.XXXXXX)"
case "$settings_tmp" in /tmp/manna-shared-settings.*) ;; *) exit 1 ;; esac
cleanup() {
  pg_ctl -D "$settings_tmp/db" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$settings_tmp"
}
trap cleanup EXIT
initdb -D "$settings_tmp/db" -A trust -U settings_test >/dev/null
pg_ctl -D "$settings_tmp/db" -o "-F -k $settings_tmp -h ''" -l "$settings_tmp/postgres.log" -w start >/dev/null
run_sql() { psql -h "$settings_tmp" -U settings_test -d postgres -v ON_ERROR_STOP=1 "$@"; }
extract_function() {
  awk -v name="$1" '$0 ~ "^create or replace function public\\." name "\\(" { active=1 }
    active { print } active && /^\$\$;/ { active=0 }' "$2" | run_sql
}
# Synthetic schema only; tested RPCs/policies below come from real migrations.
run_sql -c 'set check_function_bodies = off' -f "$repo_root/supabase/tests/reuse_invite_schema.sql"
for name in is_circle_member try_uuid; do
  extract_function "$name" "$repo_root/supabase/migrations/202609290001_initial_schema.sql"
done
run_sql -f "$repo_root/supabase/tests/shared_circle_settings_schema.sql"
for name in create_circle update_circle_settings force_circle_prompt; do
  extract_function "$name" "$repo_root/supabase/migrations/202610070008_end_of_day_blessings.sql"
done
extract_function regenerate_circle_invite_code "$repo_root/supabase/migrations/202610060010_circle_creation_settings_and_code_rotation.sql"
run_sql <<'SQL'
revoke all on function public.update_circle_settings(uuid,text,text,time,time,integer,boolean,integer,time) from public, anon;
revoke all on function public.update_circle_settings(uuid,text,text,time,time,integer,boolean,integer) from public, anon;
revoke all on function public.force_circle_prompt(uuid) from public, anon;
grant execute on function public.update_circle_settings(uuid,text,text,time,time,integer,boolean,integer,time) to authenticated;
grant execute on function public.update_circle_settings(uuid,text,text,time,time,integer,boolean,integer) to authenticated;
grant execute on function public.force_circle_prompt(uuid) to authenticated;
SQL
run_sql -f "$repo_root/supabase/migrations/202610070002_universal_circle_invites.sql" \
  -f "$repo_root/supabase/migrations/202610070004_circle_photos.sql" \
  -f "$repo_root/supabase/migrations/202610070006_circle_photo_storage_policy.sql" \
  -f "$repo_root/supabase/migrations/202609300001_transfer_circle_ownership.sql" \
  -f "$repo_root/supabase/migrations/202609300003_remove_circle_member.sql" \
  -f "$repo_root/supabase/migrations/202610090002_durable_circle_invites.sql" \
  -f "$repo_root/supabase/migrations/202610120001_seven_hour_evening.sql" \
  -f "$repo_root/supabase/migrations/202610130001_circle_streaks.sql"
if [ "$migration_order" = '--streak-first' ]; then
  run_sql -f "$repo_root/supabase/migrations/202610150002_independent_streak_deadlines.sql"
fi
run_sql \
  -f "$repo_root/supabase/migrations/202610140001_shared_circle_settings.sql" \
  -f "$repo_root/supabase/tests/shared_circle_settings.sql"
if [ "$migration_order" = standard ]; then
  run_sql -f "$repo_root/supabase/tests/circle_streaks.sql" \
    -f "$repo_root/supabase/tests/consecutive_timely_streaks.sql"
  run_sql -f "$repo_root/supabase/migrations/202610150002_independent_streak_deadlines.sql"
else
  # Do not reapply the newer migration here: the pending settings migration must
  # leave its six-column shape, private helper, and grants intact by itself.
  run_sql -c "do \$\$ begin assert (select 'next_update_at'=any(proargnames) and cardinality(proallargtypes)=7 from pg_proc where oid='public.circle_streaks(uuid)'::regprocedure); assert not has_function_privilege('authenticated','manna_private.circle_streaks_at(uuid,timestamptz)','execute'); end; \$\$;"
fi
# Also prove the new streak-only migration upgrades the pending five-column
# predecessor while leaving every shared-settings authorization check intact.
run_sql -f "$repo_root/supabase/tests/independent_streak_deadlines.sql"
# Simulate a setting edit already waiting when the leader revokes delegation.
# The edit must authorize the updated row after the leader releases its lock.
run_sql <<'SQL'
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000101'),('00000000-0000-0000-0000-000000000102');
insert into public.profiles(id) select id from auth.users;
insert into public.circles(id,name,owner_id,time_zone,window_start,window_end,response_window_minutes,
  allow_late_blessings,repeat_window_minutes,end_of_day_time,allow_member_circle_changes)
values('00000000-0000-0000-0000-000000000103','Race settings','00000000-0000-0000-0000-000000000101',
  'UTC','12:00','20:00',10,true,120,'22:00',true);
insert into public.circle_members(circle_id,user_id,role) values
  ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000101','owner'),
  ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000102','member');
SQL
cat > "$settings_tmp/revoke.sql" <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000101';
select public.set_circle_member_changes('00000000-0000-0000-0000-000000000103',false);
select 'REVOCATION_LOCKED';
select pg_sleep(1);
commit;
SQL
run_sql -At -f "$settings_tmp/revoke.sql" >"$settings_tmp/revoke.log" 2>&1 &
revoke_pid=$!
# Bounded synchronization to ensure the competing transaction waits on the row.
for attempt in {1..100}; do
  if rg -q 'REVOCATION_LOCKED' "$settings_tmp/revoke.log"; then break; fi
  sleep 0.02
done
if ! rg -q 'REVOCATION_LOCKED' "$settings_tmp/revoke.log"; then
  cat "$settings_tmp/revoke.log"; echo 'Revocation race did not acquire its lock.' >&2; exit 1
fi
set +e
run_sql >"$settings_tmp/edit.log" 2>&1 <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000102';
select public.update_circle_settings('00000000-0000-0000-0000-000000000103',
  'Unauthorized race edit','UTC','12:00','20:00',10,true,120,'22:00');
commit;
SQL
edit_status=$?
wait "$revoke_pid"; revoke_status=$?
set -e
if [ "$edit_status" -eq 0 ] || [ "$revoke_status" -ne 0 ] || ! rg -q 'authorized member required' "$settings_tmp/edit.log"; then
  cat "$settings_tmp/revoke.log" "$settings_tmp/edit.log"; exit 1
fi
run_sql -c "do \$\$ begin assert (select name='Race settings' and not allow_member_circle_changes from public.circles where id='00000000-0000-0000-0000-000000000103'); end; \$\$;" >/dev/null
echo 'Shared circle settings, Storage permissions, ownership boundaries, and consecutive timely streak checks passed locally.'
if [ "$migration_order" = standard ]; then
  "$repo_root/Scripts/test-shared-circle-settings.sh" --streak-first
  echo 'Reverse migration order preserves independent streaks and shared settings.'
fi
