do $$
begin
  if not exists (
    select 1 from pg_type where typname = 'prompt_kind' and typnamespace = 'public'::regnamespace
  ) then
    create type public.prompt_kind as enum ('daily', 'end_of_day');
  end if;
end $$;

alter table public.circles
  add column if not exists end_of_day_time time not null default time '22:00:00';

update public.circles
set end_of_day_time = greatest(end_of_day_time, window_end);

alter table public.circles
  drop constraint if exists circles_end_of_day_after_random_window,
  add constraint circles_end_of_day_after_random_window check (end_of_day_time >= window_end);

alter table public.circle_members
  add column if not exists notify_on_end_of_day boolean not null default true;

alter table public.daily_prompts
  add column if not exists kind public.prompt_kind not null default 'daily';

alter table public.daily_prompts
  drop constraint if exists daily_prompts_circle_id_local_date_key;

alter table public.daily_prompts
  add constraint daily_prompts_circle_date_kind_key unique (circle_id, local_date, kind);

create index if not exists daily_prompts_circle_kind_starts_idx
  on public.daily_prompts (circle_id, kind, starts_at desc);

create or replace function public.can_view_blessing(
  p_prompt_id uuid,
  p_author_id uuid,
  p_viewer_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(bool_or(
    public.is_circle_member(p.circle_id, p_viewer_id)
    and (
      p_author_id = p_viewer_id
      or public.has_submitted(p.id, p_viewer_id)
      or (
        p.local_date < (clock_timestamp() at time zone c.time_zone)::date
        and not (
          p.kind = 'end_of_day'
          and clock_timestamp() < p.ends_at
          and not exists (
            select 1 from public.daily_prompts newer
            where newer.circle_id = p.circle_id
              and newer.kind = 'daily'
              and newer.starts_at > p.starts_at
              and newer.starts_at <= clock_timestamp()
          )
        )
      )
    )
  ), false)
  from public.daily_prompts p
  join public.circles c on c.id = p.circle_id
  where p.id = p_prompt_id;
$$;

create or replace function public.prompt_accepts_entry(
  p_prompt_id uuid,
  p_user_id uuid default auth.uid(),
  p_at timestamptz default clock_timestamp()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(bool_or(
    cm.user_id is not null
    and case
      when p.kind = 'end_of_day' then
        p_at >= p.starts_at
        and p_at < p.ends_at
        and not exists (
          select 1 from public.daily_prompts newer
          where newer.circle_id = p.circle_id
            and newer.kind = 'daily'
            and newer.starts_at > p.starts_at
            and newer.starts_at <= p_at
        )
      else
        (
          p_at >= p.starts_at
          and (
            p_at < p.ends_at
            or (
              c.allow_late_blessings
              and not exists (
                select 1 from public.daily_prompts newer
                where newer.circle_id = p.circle_id
                  and newer.kind = 'daily'
                  and newer.starts_at > p.starts_at
                  and newer.starts_at <= p_at
              )
            )
          )
        )
        or (
          (cm.joined_at at time zone c.time_zone)::date = p.local_date
          and (p_at at time zone c.time_zone)::date = p.local_date
        )
    end
  ), false)
  from public.daily_prompts p
  join public.circles c on c.id = p.circle_id
  left join public.circle_members cm
    on cm.circle_id = p.circle_id
   and cm.user_id = p_user_id
   and cm.removed_at is null
  where p.id = p_prompt_id;
$$;

create or replace function public.update_end_of_day_notifications(
  p_circle_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  update public.circle_members
  set notify_on_end_of_day = p_enabled
  where circle_id = p_circle_id
    and user_id = auth.uid()
    and removed_at is null;
  if not found then raise exception 'circle membership required'; end if;
end;
$$;

create or replace function public.create_circle(
  p_name text,
  p_invite_code text,
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
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g'));
  v_circle public.circles;
  v_now timestamptz := clock_timestamp();
  v_local_now timestamp;
  v_local_date date;
  v_range_start timestamp;
  v_range_end timestamp;
  v_available_start timestamp;
  v_start_local timestamp;
  v_starts_at timestamptz;
  v_random_seconds integer;
  v_prompt_state public.prompt_state;
  v_end_of_day_starts_at timestamptz;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  if char_length(v_code) not between 6 and 10 then raise exception 'invalid invite code'; end if;
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

  insert into public.circles (
    name, owner_id, invite_code_hash, time_zone, window_start, window_end,
    response_window_minutes, allow_late_blessings, repeat_window_minutes, end_of_day_time
  ) values (
    trim(p_name), v_user_id, crypt(v_code, gen_salt('bf', 10)), p_time_zone,
    p_window_start, p_window_end, p_response_window_minutes, p_allow_late_blessings,
    p_repeat_window_minutes, p_end_of_day_time
  ) returning * into v_circle;

  insert into public.circle_members (circle_id, user_id, role, joined_at)
  values (v_circle.id, v_user_id, 'owner', v_now);

  v_local_now := v_now at time zone p_time_zone;
  v_local_date := v_local_now::date;
  v_range_start := v_local_date + p_window_start;
  v_range_end := v_local_date + p_window_end;
  v_available_start := case when v_local_now < v_range_end
    then greatest(v_range_start, v_local_now) else v_range_start end;
  v_random_seconds := floor(random() * greatest(
    0.0, extract(epoch from (v_range_end - v_available_start))::double precision
  ))::integer;
  v_start_local := v_available_start + make_interval(secs => v_random_seconds);
  v_starts_at := v_start_local at time zone p_time_zone;
  v_prompt_state := case when v_starts_at + make_interval(mins => p_response_window_minutes) <= v_now
    then 'closed'::public.prompt_state else 'scheduled'::public.prompt_state end;

  insert into public.daily_prompts (
    circle_id, local_date, starts_at, ends_at, response_window_minutes, state, closed_at, kind
  ) values (
    v_circle.id, v_local_date, v_starts_at,
    v_starts_at + make_interval(mins => p_response_window_minutes),
    p_response_window_minutes, v_prompt_state,
    case when v_prompt_state = 'closed' then v_now else null end, 'daily'
  );

  v_end_of_day_starts_at := (v_local_date + p_end_of_day_time) at time zone p_time_zone;
  insert into public.daily_prompts (
    circle_id, local_date, starts_at, ends_at, response_window_minutes, kind
  ) values (
    v_circle.id, v_local_date, v_end_of_day_starts_at,
    v_end_of_day_starts_at + interval '5 hours', 300, 'end_of_day'
  );

  return v_circle;
end;
$$;

create or replace function public.create_circle(
  p_name text,
  p_invite_code text,
  p_time_zone text,
  p_window_start time,
  p_window_end time,
  p_response_window_minutes integer,
  p_allow_late_blessings boolean,
  p_repeat_window_minutes integer
)
returns public.circles
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.create_circle(
    p_name, p_invite_code, p_time_zone, p_window_start, p_window_end,
    p_response_window_minutes, p_allow_late_blessings, p_repeat_window_minutes,
    greatest(p_window_end, time '22:00:00')
  );
$$;

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

  update public.circles
  set name = trim(p_name), time_zone = p_time_zone, window_start = p_window_start,
      window_end = p_window_end, response_window_minutes = p_response_window_minutes,
      allow_late_blessings = p_allow_late_blessings,
      repeat_window_minutes = p_repeat_window_minutes,
      end_of_day_time = p_end_of_day_time
  where id = p_circle_id and owner_id = auth.uid()
  returning * into v_circle;
  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;

  v_local_date := (clock_timestamp() at time zone p_time_zone)::date;
  v_end_of_day_starts_at := (v_local_date + p_end_of_day_time) at time zone p_time_zone;
  update public.daily_prompts
  set starts_at = (local_date + p_end_of_day_time) at time zone p_time_zone,
      ends_at = ((local_date + p_end_of_day_time) at time zone p_time_zone) + interval '5 hours',
      response_window_minutes = 300
  where circle_id = p_circle_id
    and local_date >= v_local_date
    and kind = 'end_of_day'
    and state = 'scheduled'
    and not exists (select 1 from public.blessings b where b.prompt_id = daily_prompts.id);

  return v_circle;
end;
$$;

create or replace function public.update_circle_settings(
  p_circle_id uuid,
  p_name text,
  p_time_zone text,
  p_window_start time,
  p_window_end time,
  p_response_window_minutes integer,
  p_allow_late_blessings boolean,
  p_repeat_window_minutes integer
)
returns public.circles
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.update_circle_settings(
    p_circle_id, p_name, p_time_zone, p_window_start, p_window_end,
    p_response_window_minutes, p_allow_late_blessings, p_repeat_window_minutes,
    (select greatest(end_of_day_time, p_window_end) from public.circles where id = p_circle_id)
  );
$$;

create or replace function public.ensure_tomorrow_prompts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.circles;
  v_date date;
  v_seconds integer;
  v_start_local timestamp;
  v_end_local timestamp;
  v_count integer := 0;
begin
  for c in select * from public.circles loop
    v_date := (clock_timestamp() at time zone c.time_zone)::date + 1;
    v_seconds := floor(random() * extract(epoch from (c.window_end - c.window_start)))::integer;
    v_start_local := v_date + c.window_start + make_interval(secs => v_seconds);
    insert into public.daily_prompts (
      circle_id, local_date, starts_at, ends_at, response_window_minutes, kind
    ) values (
      c.id, v_date, v_start_local at time zone c.time_zone,
      (v_start_local at time zone c.time_zone) + make_interval(mins => c.response_window_minutes),
      c.response_window_minutes, 'daily'
    ) on conflict (circle_id, local_date, kind) do nothing;
    if found then v_count := v_count + 1; end if;

    v_end_local := v_date + c.end_of_day_time;
    insert into public.daily_prompts (
      circle_id, local_date, starts_at, ends_at, response_window_minutes, kind
    ) values (
      c.id, v_date, v_end_local at time zone c.time_zone,
      (v_end_local at time zone c.time_zone) + interval '5 hours', 300, 'end_of_day'
    ) on conflict (circle_id, local_date, kind) do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.claim_due_prompts(p_limit integer default 100)
returns setof public.daily_prompts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_claimed_at timestamptz := clock_timestamp();
begin
  update public.daily_prompts
  set state = 'closed', closed_at = v_claimed_at,
      failure_reason = coalesce(failure_reason, 'Prompt dispatch missed its delivery grace period')
  where kind = 'daily'
    and state = 'scheduled'
    and starts_at <= v_claimed_at - interval '5 minutes';

  update public.daily_prompts eod
  set state = 'closed', closed_at = v_claimed_at
  where eod.kind = 'end_of_day'
    and eod.state in ('scheduled', 'dispatching', 'open')
    and (
      eod.ends_at <= v_claimed_at
      or exists (
        select 1 from public.daily_prompts newer
        where newer.circle_id = eod.circle_id
          and newer.kind = 'daily'
          and newer.starts_at > eod.starts_at
          and newer.starts_at <= v_claimed_at
      )
    );

  return query
  with claimed as (
    select p.id, p.state as prior_state
    from public.daily_prompts p
    where (
        p.state = 'scheduled' and p.starts_at <= v_claimed_at
      ) or (
        p.state = 'dispatching' and p.ends_at > v_claimed_at
        and coalesce(p.dispatched_at, p.created_at) <= v_claimed_at - interval '5 minutes'
      )
    order by p.starts_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.daily_prompts p
  set state = 'dispatching', dispatched_at = v_claimed_at, failure_reason = null,
      starts_at = case when claimed.prior_state = 'scheduled' then v_claimed_at else p.starts_at end,
      ends_at = case when claimed.prior_state = 'scheduled'
        then v_claimed_at + make_interval(mins => p.response_window_minutes) else p.ends_at end
  from claimed where p.id = claimed.id
  returning p.*;
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
  if v_circle.owner_id <> auth.uid() then raise exception 'circle owner required'; end if;
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

revoke all on function public.update_end_of_day_notifications(uuid, boolean) from public, anon;
grant execute on function public.update_end_of_day_notifications(uuid, boolean) to authenticated;
revoke all on function public.create_circle(text, text, text, time, time, integer, boolean, integer, time) from public, anon;
revoke all on function public.update_circle_settings(uuid, text, text, time, time, integer, boolean, integer, time) from public, anon;
grant execute on function public.create_circle(text, text, text, time, time, integer, boolean, integer, time) to authenticated;
grant execute on function public.update_circle_settings(uuid, text, text, time, time, integer, boolean, integer, time) to authenticated;
revoke all on function public.claim_due_prompts(integer) from public, anon, authenticated;

-- Seed the new prompt kind for existing circles immediately, including tomorrow's
-- already-created scheduling rows. Past windows are closed without a stale alert.
insert into public.daily_prompts (
  circle_id, local_date, starts_at, ends_at, response_window_minutes, kind, state, closed_at
)
select c.id, dates.local_date,
       (dates.local_date + c.end_of_day_time) at time zone c.time_zone,
       ((dates.local_date + c.end_of_day_time) at time zone c.time_zone) + interval '5 hours',
       300, 'end_of_day',
       case when ((dates.local_date + c.end_of_day_time) at time zone c.time_zone) < clock_timestamp()
         then 'closed'::public.prompt_state else 'scheduled'::public.prompt_state end,
       case when ((dates.local_date + c.end_of_day_time) at time zone c.time_zone) < clock_timestamp()
         then clock_timestamp() else null end
from public.circles c
cross join lateral (
  select (clock_timestamp() at time zone c.time_zone)::date + offset_days as local_date
  from generate_series(0, 1) as offset_days
) dates
on conflict (circle_id, local_date, kind) do nothing;

comment on column public.circles.end_of_day_time is
  'Circle-local reminder time for the independent end-of-day blessing prompt.';
comment on column public.circle_members.notify_on_end_of_day is
  'Whether this member receives the circle end-of-day reminder.';
comment on column public.daily_prompts.kind is
  'Separates the daily random prompt from the independent end-of-day prompt.';
