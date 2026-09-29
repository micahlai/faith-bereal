alter table public.circles
  add column response_window_minutes integer not null default 10,
  add column allow_late_blessings boolean not null default false,
  add constraint circles_response_window_minutes_allowed check (
    response_window_minutes = any (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180])
  );

alter table public.daily_prompts
  add column response_window_minutes integer not null default 10;

alter table public.daily_prompts
  drop constraint if exists daily_prompts_check;

alter table public.daily_prompts
  add constraint daily_prompts_response_window_matches check (
    ends_at = starts_at + make_interval(mins => response_window_minutes)
  );

alter table public.blessings
  add column is_late boolean not null default false;

create or replace function public.prompt_accepts_submission(
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
    public.is_circle_member(p.circle_id, p_user_id)
    and p_at >= p.starts_at
    and (
      p_at < p.ends_at
      or (
        c.allow_late_blessings
        and not exists (
          select 1
          from public.daily_prompts newer
          where newer.circle_id = p.circle_id
            and newer.starts_at > p.starts_at
            and newer.starts_at <= p_at
        )
      )
    )
  ), false)
  from public.daily_prompts p
  join public.circles c on c.id = p.circle_id
  where p.id = p_prompt_id;
$$;

create or replace function public.update_circle_settings(
  p_circle_id uuid,
  p_response_window_minutes integer,
  p_allow_late_blessings boolean
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
  if p_response_window_minutes <> all (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]) then
    raise exception 'invalid response window';
  end if;

  update public.circles
  set response_window_minutes = p_response_window_minutes,
      allow_late_blessings = p_allow_late_blessings
  where id = p_circle_id and owner_id = auth.uid()
  returning * into v_circle;

  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;
  return v_circle;
end;
$$;

create or replace function public.submit_text_blessing(
  p_prompt_id uuid,
  p_mode public.capture_mode,
  p_body text
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_body text := trim(p_body);
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if p_mode not in ('typed', 'voice') then raise exception 'invalid capture mode'; end if;
  if char_length(v_body) not between 1 and 600 then raise exception 'blessing must be 1 to 600 characters'; end if;

  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.prompt_accepts_submission(p_prompt_id, v_user_id, v_submitted_at) then
    raise exception 'response window is closed';
  end if;

  insert into public.blessings (prompt_id, author_id, capture_mode, body, submitted_at, is_late)
  values (p_prompt_id, v_user_id, p_mode, v_body, v_submitted_at, v_submitted_at >= v_prompt.ends_at)
  returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

create or replace function public.finalize_video_blessing(
  p_prompt_id uuid,
  p_video_path text,
  p_thumbnail_path text default null
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_expected_prefix text;
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.prompt_accepts_submission(p_prompt_id, v_user_id, v_submitted_at) then
    raise exception 'response window is closed';
  end if;

  v_expected_prefix := v_prompt.circle_id::text || '/' || p_prompt_id::text || '/' || v_user_id::text || '/';
  if p_video_path not like v_expected_prefix || '%' then raise exception 'invalid video path'; end if;
  if p_thumbnail_path is not null and p_thumbnail_path not like v_expected_prefix || '%' then
    raise exception 'invalid thumbnail path';
  end if;

  insert into public.blessings (
    prompt_id, author_id, capture_mode, video_path, thumbnail_path, submitted_at, is_late
  ) values (
    p_prompt_id, v_user_id, 'video', p_video_path, p_thumbnail_path, v_submitted_at,
    v_submitted_at >= v_prompt.ends_at
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
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
  v_count integer := 0;
begin
  for c in select * from public.circles loop
    v_date := (now() at time zone c.time_zone)::date + 1;
    v_seconds := floor(random() * extract(epoch from (c.window_end - c.window_start)))::integer;
    v_start_local := v_date + c.window_start + make_interval(secs => v_seconds);
    insert into public.daily_prompts (
      circle_id, local_date, starts_at, ends_at, response_window_minutes
    ) values (
      c.id,
      v_date,
      v_start_local at time zone c.time_zone,
      (v_start_local at time zone c.time_zone) + make_interval(mins => c.response_window_minutes),
      c.response_window_minutes
    )
    on conflict (circle_id, local_date) do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end;
$$;

drop policy if exists "media owners upload to prompt path" on storage.objects;
create policy "media owners upload to prompt path"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'blessing-media'
  and (storage.foldername(name))[3] = auth.uid()::text
  and public.prompt_accepts_submission(
    public.try_uuid((storage.foldername(name))[2]),
    auth.uid(),
    clock_timestamp()
  )
);

revoke all on function public.prompt_accepts_submission(uuid, uuid, timestamptz) from public, anon;
revoke all on function public.update_circle_settings(uuid, integer, boolean) from public, anon;
grant execute on function public.update_circle_settings(uuid, integer, boolean) to authenticated;
