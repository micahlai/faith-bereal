-- The leader may delegate ordinary circle administration to active members.
-- This switch and ownership transfer always remain leader-only.
alter table public.circles add column allow_member_circle_changes boolean not null default false;

create function public.can_manage_circle(p_circle_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.circles c
    where c.id = p_circle_id
      and public.is_circle_member(c.id, auth.uid())
      and (c.owner_id = auth.uid() or c.allow_member_circle_changes)
  );
$$;
revoke all on function public.can_manage_circle(uuid) from public, anon;
grant execute on function public.can_manage_circle(uuid) to authenticated, service_role;

create function public.set_circle_member_changes(p_circle_id uuid, p_allowed boolean)
returns public.circles language plpgsql security definer set search_path = public, pg_temp as $$
declare v_circle public.circles;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_allowed is null then raise exception 'permission setting required'; end if;
  select * into v_circle from public.circles where id = p_circle_id for update;
  if v_circle.id is null then raise exception 'circle not found'; end if;
  if v_circle.owner_id <> auth.uid() or not public.is_circle_member(p_circle_id) then
    raise exception 'circle owner required';
  end if;
  update public.circles set allow_member_circle_changes = p_allowed where id = p_circle_id
    returning * into v_circle;
  return v_circle;
end;
$$;
revoke all on function public.set_circle_member_changes(uuid, boolean) from public, anon;
grant execute on function public.set_circle_member_changes(uuid, boolean) to authenticated;

create or replace function public.update_circle_settings(
  p_circle_id uuid,
  p_name text,
  p_time_zone text,
  p_window_start time,
  p_window_end time,
  p_response_window_minutes integer,
  p_allow_late_blessings boolean,
  p_repeat_window_minutes integer,
  p_end_of_day_time time
)
returns public.circles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_circle public.circles;
  v_local_date date;
  v_end_of_day_starts_at timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  perform 1 from pg_timezone_names where name = p_time_zone;
  if not found then raise exception 'invalid time zone'; end if;
  if p_window_end <= p_window_start then raise exception 'invalid random time range'; end if;
  if p_end_of_day_time < p_window_end then raise exception 'end-of-day time must follow the random range'; end if;
  if p_response_window_minutes <> all (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]) then
    raise exception 'invalid response window';
  end if;
  if p_repeat_window_minutes <> all (array[15, 30, 60, 90, 120, 180, 360, 720, 1440]) then
    raise exception 'invalid repeat window';
  end if;

  select * into v_circle from public.circles where id = p_circle_id for update;
  if v_circle.id is null then raise exception 'circle not found'; end if;
  if not public.is_circle_member(p_circle_id) or
     (v_circle.owner_id <> auth.uid() and not v_circle.allow_member_circle_changes) then
    raise exception 'circle owner or authorized member required';
  end if;

  update public.circles
  set name = trim(p_name), time_zone = p_time_zone, window_start = p_window_start,
      window_end = p_window_end, response_window_minutes = p_response_window_minutes,
      allow_late_blessings = p_allow_late_blessings,
      repeat_window_minutes = p_repeat_window_minutes,
      end_of_day_time = p_end_of_day_time
  where id = p_circle_id
  returning * into v_circle;
  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;

  v_local_date := (clock_timestamp() at time zone p_time_zone)::date;
  v_end_of_day_starts_at := (v_local_date + p_end_of_day_time) at time zone p_time_zone;
  update public.daily_prompts
  set starts_at = (local_date + p_end_of_day_time) at time zone p_time_zone,
      ends_at = ((local_date + p_end_of_day_time) at time zone p_time_zone) + interval '7 hours',
      response_window_minutes = 420
  where circle_id = p_circle_id
    and local_date >= v_local_date
    and kind = 'end_of_day'
    and state = 'scheduled'
    and not exists (select 1 from public.blessings b where b.prompt_id = daily_prompts.id);

  return v_circle;
end;
$$;

create or replace function manna_private.regenerate_circle_invite_code(
  p_circle_id uuid,
  p_invite_code text
)
returns public.circles
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_code text := upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g'));
  v_circle public.circles;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if char_length(v_code) not between 6 and 10 then raise exception 'invalid invite code'; end if;

  select * into v_circle from public.circles where id = p_circle_id for update;
  if v_circle.id is null then raise exception 'circle not found'; end if;
  if not public.is_circle_member(p_circle_id) or
     (v_circle.owner_id <> auth.uid() and not v_circle.allow_member_circle_changes) then
    raise exception 'circle owner or authorized member required';
  end if;

  update public.circles
  set invite_code_hash = crypt(v_code, gen_salt('bf', 10))
  where id = p_circle_id
  returning * into v_circle;

  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;
  return v_circle;
end;
$$;

create or replace function public.update_circle_photo(
  p_circle_id uuid,
  p_photo_path text default null
)
returns public.circles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_circle public.circles;
  v_expected_path text := p_circle_id::text || '/circle.jpg';
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null then raise exception 'circle not found'; end if;
  if not public.is_circle_member(p_circle_id) or
     (v_circle.owner_id <> auth.uid() and not v_circle.allow_member_circle_changes) then
    raise exception 'circle owner or authorized member required';
  end if;
  if p_photo_path is not null and p_photo_path <> v_expected_path then
    raise exception 'invalid circle photo path';
  end if;

  update public.circles
  set photo_path = p_photo_path
  where id = p_circle_id
  returning * into v_circle;
  return v_circle;
end;
$$;

create or replace function public.force_circle_prompt(p_circle_id uuid)
returns public.daily_prompts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_circle public.circles;
  v_prompt public.daily_prompts;
  v_now timestamptz := clock_timestamp();
  v_local_date date;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select * into v_circle from public.circles where id = p_circle_id for update;
  if v_circle.id is null then raise exception 'circle not found'; end if;
  if not public.is_circle_member(p_circle_id) or
     (v_circle.owner_id <> auth.uid() and not v_circle.allow_member_circle_changes) then
    raise exception 'circle owner or authorized member required';
  end if;
  v_local_date := (v_now at time zone v_circle.time_zone)::date;

  insert into public.daily_prompts (
    circle_id, local_date, starts_at, ends_at, response_window_minutes, kind,
    state, dispatch_key, dispatched_at, closed_at, failure_reason
  ) values (
    v_circle.id, v_local_date, v_now,
    v_now + make_interval(mins => v_circle.response_window_minutes),
    v_circle.response_window_minutes, 'daily', 'dispatching', gen_random_uuid(), v_now, null, null
  ) on conflict (circle_id, local_date, kind) do update set
    starts_at = excluded.starts_at, ends_at = excluded.ends_at,
    response_window_minutes = excluded.response_window_minutes,
    state = 'dispatching', dispatch_key = gen_random_uuid(),
    dispatched_at = excluded.dispatched_at, closed_at = null, failure_reason = null
  returning * into v_prompt;
  return v_prompt;
end;
$$;

create or replace function public.remove_circle_member(
  p_circle_id uuid,
  p_member_id uuid
)
returns public.circles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_circle public.circles;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null then raise exception 'circle not found'; end if;
  if not public.is_circle_member(p_circle_id) or
     (v_circle.owner_id <> auth.uid() and not v_circle.allow_member_circle_changes) then
    raise exception 'circle owner or authorized member required';
  end if;
  if p_member_id = v_user_id then raise exception 'use leave circle to remove yourself'; end if;
  if p_member_id = v_circle.owner_id then raise exception 'circle owner cannot be removed; transfer ownership first'; end if;

  update public.circle_members
  set removed_at = now(), role = 'member'
  where circle_id = p_circle_id
    and user_id = p_member_id
    and removed_at is null;

  if not found then raise exception 'active member not found'; end if;
  return v_circle;
end;
$$;
-- Canonical photo key remains fixed; delegation never authorizes other buckets,
-- circles, or paths. Public table updates remain unavailable to clients.
drop policy if exists "circle owners upload circle photos" on storage.objects;
create policy "circle owners upload circle photos" on storage.objects for insert to authenticated
with check (bucket_id = 'circle-photos' and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg') and public.can_manage_circle(public.try_uuid((storage.foldername(name))[1])))
;

drop policy if exists "circle owners update circle photos" on storage.objects;
create policy "circle owners update circle photos" on storage.objects for update to authenticated
using (bucket_id = 'circle-photos' and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg') and public.can_manage_circle(public.try_uuid((storage.foldername(name))[1])))
with check (bucket_id = 'circle-photos' and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg') and public.can_manage_circle(public.try_uuid((storage.foldername(name))[1])))
;

drop policy if exists "circle owners delete circle photos" on storage.objects;
create policy "circle owners delete circle photos" on storage.objects for delete to authenticated
using (bucket_id = 'circle-photos' and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg') and public.can_manage_circle(public.try_uuid((storage.foldername(name))[1])))
;

-- CREATE OR REPLACE preserves the existing grants, including the private
-- invite implementation's lack of authenticated access. The public wrapper
-- still persists its newly rotated code through member-authorized recovery.
revoke all on function manna_private.regenerate_circle_invite_code(uuid, text) from public, anon, authenticated;
comment on column public.circles.allow_member_circle_changes is
  'Leader-controlled delegation of circle settings to current members; transfer and this switch remain leader-only.';
comment on function public.can_manage_circle(uuid) is
  'RLS-safe authorization for the current authenticated active member to administer a circle.';
comment on function public.regenerate_circle_invite_code(uuid, text) is
  'Leader or delegated active-member invite-code rotation; immediately invalidates the previous code.';
comment on column public.circles.photo_path is
  'Private canonical Storage path for the circle photo, editable by the leader or delegated current members.';
comment on function public.update_circle_photo(uuid, text) is
  'Sets/removes the canonical private circle photo after current administration authorization.';

-- Separate consecutive timely-entry run for the blue flame explanation.
-- Feature metadata only: no content, media paths, or cross-circle information.
-- This migration is still unapplied. Preserve the newer independent-deadline
-- RPC when that streak-only correction has already deployed out of order.
do $streak_upgrade$
begin
  if exists(select 1 from pg_proc where oid='public.circle_streaks(uuid)'::regprocedure
    and 'next_update_at'=any(proargnames) and cardinality(proallargtypes)>=7) then
    return;
  end if;
execute 'drop function public.circle_streaks(uuid)';
execute $streak_definition$
create function public.circle_streaks(p_circle_id uuid)
returns table(member_id uuid, days integer, on_time_days integer, on_time_today boolean, on_time_streak_days integer)
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_today date;
begin
  if auth.uid() is null or not public.is_circle_member(p_circle_id,auth.uid()) then
    raise exception 'circle membership required';
  end if;
  select (clock_timestamp() at time zone time_zone)::date into v_today from public.circles where id=p_circle_id;
  return query
  with shared_days as (
    select b.author_id, p.local_date, bool_or(case when g.entered_at is not null then
      g.entered_at>=p.starts_at and g.entered_at<p.ends_at else not b.is_late end) as timely
    from public.blessings b join public.daily_prompts p on p.id=b.prompt_id
    join public.circles c on c.id=p.circle_id
    join public.circle_members cm on cm.circle_id=p.circle_id and cm.user_id=b.author_id and cm.removed_at is null
    left join public.blessing_entry_grants g on g.prompt_id=p.id and g.user_id=b.author_id
    where p.circle_id=p_circle_id and p.local_date<=v_today
      and p.local_date>=(cm.joined_at at time zone c.time_zone)::date
    group by b.author_id,p.local_date
  ), ranked as (
    select s.*, row_number() over(partition by s.author_id order by s.local_date desc)::integer as n,
      case when max(s.local_date) over(partition by s.author_id)=v_today then v_today else v_today-1 end as anchor
    from shared_days s
  ), timely_ranked as (
    select r.*, row_number() over(partition by r.author_id order by r.local_date desc)::integer as timely_n
    from ranked r where r.timely
  ), timely_counts as (
    select t.author_id, count(*) filter(where t.local_date=t.anchor-t.timely_n+1)::integer as streak
    from timely_ranked t group by t.author_id
  ), counts as (
    select r.author_id, count(*) filter(where r.local_date=r.anchor-r.n+1)::integer as days,
      count(*) filter(where r.local_date=r.anchor-r.n+1 and r.timely)::integer as on_time_days,
      bool_or(r.local_date=v_today and r.timely) as on_time_today
    from ranked r group by r.author_id
  )
  select cm.user_id,coalesce(s.days,0),coalesce(s.on_time_days,0),coalesce(s.on_time_today,false),coalesce(t.streak,0)
  from public.circle_members cm left join counts s on s.author_id=cm.user_id
  left join timely_counts t on t.author_id=cm.user_id
  where cm.circle_id=p_circle_id and cm.removed_at is null;
end;
$$;
$streak_definition$;
execute 'revoke all on function public.circle_streaks(uuid) from public,anon';
execute 'grant execute on function public.circle_streaks(uuid) to authenticated';
end;
$streak_upgrade$;
