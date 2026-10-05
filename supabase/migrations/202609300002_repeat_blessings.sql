alter table public.circles
  add column repeat_window_minutes integer not null default 120,
  add constraint circles_repeat_window_minutes_allowed check (
    repeat_window_minutes = any (array[15, 30, 60, 90, 120, 180, 360, 720, 1440])
  );

alter table public.blessings
  add column repeated_from_blessing_id uuid references public.blessings(id) on delete set null;

drop function public.update_circle_settings(uuid, text, text, time, time, integer, boolean);

create function public.update_circle_settings(
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
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_circle public.circles;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  perform 1 from pg_timezone_names where name = p_time_zone;
  if not found then raise exception 'invalid time zone'; end if;
  if p_window_end <= p_window_start then raise exception 'invalid random time range'; end if;
  if p_response_window_minutes <> all (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]) then
    raise exception 'invalid response window';
  end if;
  if p_repeat_window_minutes <> all (array[15, 30, 60, 90, 120, 180, 360, 720, 1440]) then
    raise exception 'invalid repeat window';
  end if;

  update public.circles
  set name = trim(p_name),
      time_zone = p_time_zone,
      window_start = p_window_start,
      window_end = p_window_end,
      response_window_minutes = p_response_window_minutes,
      allow_late_blessings = p_allow_late_blessings,
      repeat_window_minutes = p_repeat_window_minutes
  where id = p_circle_id and owner_id = auth.uid()
  returning * into v_circle;

  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;
  return v_circle;
end;
$$;

revoke all on function public.update_circle_settings(
  uuid, text, text, time, time, integer, boolean, integer
) from public, anon;
grant execute on function public.update_circle_settings(
  uuid, text, text, time, time, integer, boolean, integer
) to authenticated;

create or replace function public.repeat_blessing(
  p_source_blessing_id uuid,
  p_target_prompt_id uuid
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_source public.blessings;
  v_source_circle_id uuid;
  v_target_prompt public.daily_prompts;
  v_repeat_window_minutes integer;
  v_now timestamptz := clock_timestamp();
  v_blessing public.blessings;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_source
  from public.blessings
  where id = p_source_blessing_id and author_id = v_user_id;

  select circle_id into v_source_circle_id
  from public.daily_prompts
  where id = v_source.prompt_id;

  select * into v_target_prompt
  from public.daily_prompts
  where id = p_target_prompt_id;

  if v_source.id is null or v_target_prompt.id is null then raise exception 'blessing or prompt not found'; end if;
  if v_source_circle_id = v_target_prompt.circle_id then raise exception 'source must be from another circle'; end if;
  if v_source.body is null then raise exception 'source blessing has no reusable message'; end if;

  select repeat_window_minutes into v_repeat_window_minutes
  from public.circles
  where id = v_target_prompt.circle_id;

  if v_now < v_source.submitted_at
    or v_now > v_source.submitted_at + make_interval(mins => v_repeat_window_minutes) then
    raise exception 'repeat window expired';
  end if;
  if not public.prompt_accepts_submission(p_target_prompt_id, v_user_id, v_now) then
    raise exception 'prompt is not accepting submissions';
  end if;

  insert into public.blessings (
    prompt_id,
    author_id,
    capture_mode,
    body,
    submitted_at,
    is_late,
    scripture_book_slug,
    scripture_book_name,
    scripture_chapter,
    scripture_verse_start,
    scripture_verse_end,
    repeated_from_blessing_id
  ) values (
    p_target_prompt_id,
    v_user_id,
    'typed',
    v_source.body,
    v_now,
    v_now >= v_target_prompt.ends_at,
    v_source.scripture_book_slug,
    v_source.scripture_book_name,
    v_source.scripture_chapter,
    v_source.scripture_verse_start,
    v_source.scripture_verse_end,
    v_source.id
  )
  returning * into v_blessing;

  return v_blessing;
end;
$$;

revoke all on function public.repeat_blessing(uuid, uuid) from public, anon;
grant execute on function public.repeat_blessing(uuid, uuid) to authenticated;
