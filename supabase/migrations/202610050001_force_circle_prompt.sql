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

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null then raise exception 'circle not found'; end if;
  if v_circle.owner_id <> auth.uid() then raise exception 'circle owner required'; end if;

  v_local_date := (v_now at time zone v_circle.time_zone)::date;

  insert into public.daily_prompts (
    circle_id,
    local_date,
    starts_at,
    ends_at,
    response_window_minutes,
    state,
    dispatch_key,
    dispatched_at,
    closed_at,
    failure_reason
  ) values (
    v_circle.id,
    v_local_date,
    v_now,
    v_now + make_interval(mins => v_circle.response_window_minutes),
    v_circle.response_window_minutes,
    'dispatching',
    gen_random_uuid(),
    v_now,
    null,
    null
  )
  on conflict (circle_id, local_date) do update set
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    response_window_minutes = excluded.response_window_minutes,
    state = 'dispatching',
    dispatch_key = gen_random_uuid(),
    dispatched_at = excluded.dispatched_at,
    closed_at = null,
    failure_reason = null
  returning * into v_prompt;

  return v_prompt;
end;
$$;

revoke all on function public.force_circle_prompt(uuid) from public, anon;
grant execute on function public.force_circle_prompt(uuid) to authenticated;

comment on function public.force_circle_prompt(uuid) is
  'Owner-only test action that opens today''s prompt immediately for Edge Function dispatch.';
