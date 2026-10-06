drop function if exists public.create_circle(text, text, text);

create function public.create_circle(
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
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  if char_length(v_code) not between 6 and 10 then raise exception 'invalid invite code'; end if;
  perform 1 from pg_timezone_names where name = p_time_zone;
  if not found then raise exception 'invalid time zone'; end if;
  if p_window_end <= p_window_start then raise exception 'invalid random time range'; end if;
  if p_response_window_minutes <> all (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]) then
    raise exception 'invalid response window';
  end if;
  if p_repeat_window_minutes <> all (array[15, 30, 60, 90, 120, 180, 360, 720, 1440]) then
    raise exception 'invalid repeat window';
  end if;

  insert into public.circles (
    name,
    owner_id,
    invite_code_hash,
    time_zone,
    window_start,
    window_end,
    response_window_minutes,
    allow_late_blessings,
    repeat_window_minutes
  ) values (
    trim(p_name),
    v_user_id,
    crypt(v_code, gen_salt('bf', 10)),
    p_time_zone,
    p_window_start,
    p_window_end,
    p_response_window_minutes,
    p_allow_late_blessings,
    p_repeat_window_minutes
  )
  returning * into v_circle;

  insert into public.circle_members (circle_id, user_id, role, joined_at)
  values (v_circle.id, v_user_id, 'owner', v_now);

  v_local_now := v_now at time zone p_time_zone;
  v_local_date := v_local_now::date;
  v_range_start := v_local_date + p_window_start;
  v_range_end := v_local_date + p_window_end;

  if v_local_now < v_range_end then
    v_available_start := greatest(v_range_start, v_local_now);
  else
    v_available_start := v_range_start;
  end if;

  v_random_seconds := floor(
    random() * greatest(
      0.0,
      extract(epoch from (v_range_end - v_available_start))::double precision
    )
  )::integer;
  v_start_local := v_available_start + make_interval(secs => v_random_seconds);
  v_starts_at := v_start_local at time zone p_time_zone;
  v_prompt_state := case
    when v_starts_at + make_interval(mins => p_response_window_minutes) <= v_now then 'closed'::public.prompt_state
    else 'scheduled'::public.prompt_state
  end;

  insert into public.daily_prompts (
    circle_id,
    local_date,
    starts_at,
    ends_at,
    response_window_minutes,
    state,
    closed_at
  ) values (
    v_circle.id,
    v_local_date,
    v_starts_at,
    v_starts_at + make_interval(mins => p_response_window_minutes),
    p_response_window_minutes,
    v_prompt_state,
    case when v_prompt_state = 'closed' then v_now else null end
  );

  return v_circle;
end;
$$;

revoke all on function public.create_circle(
  text, text, text, time, time, integer, boolean, integer
) from public, anon;
grant execute on function public.create_circle(
  text, text, text, time, time, integer, boolean, integer
) to authenticated;

create or replace function public.regenerate_circle_invite_code(
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

  update public.circles
  set invite_code_hash = crypt(v_code, gen_salt('bf', 10))
  where id = p_circle_id and owner_id = auth.uid()
  returning * into v_circle;

  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;
  return v_circle;
end;
$$;

revoke all on function public.regenerate_circle_invite_code(uuid, text) from public, anon;
grant execute on function public.regenerate_circle_invite_code(uuid, text) to authenticated;

comment on function public.create_circle(text, text, text, time, time, integer, boolean, integer) is
  'Creates a circle with its owner-selected settings and schedules the current local-day prompt transactionally.';
comment on function public.regenerate_circle_invite_code(uuid, text) is
  'Owner-only invite-code rotation. The previous code stops matching immediately.';
