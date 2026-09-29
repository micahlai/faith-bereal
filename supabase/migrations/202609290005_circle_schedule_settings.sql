drop function public.update_circle_settings(uuid, integer, boolean);

create function public.update_circle_settings(
  p_circle_id uuid,
  p_name text,
  p_time_zone text,
  p_window_start time,
  p_window_end time,
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
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  perform 1 from pg_timezone_names where name = p_time_zone;
  if not found then raise exception 'invalid time zone'; end if;
  if p_window_end <= p_window_start then raise exception 'invalid random time range'; end if;
  if p_response_window_minutes <> all (array[1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]) then
    raise exception 'invalid response window';
  end if;

  update public.circles
  set name = trim(p_name),
      time_zone = p_time_zone,
      window_start = p_window_start,
      window_end = p_window_end,
      response_window_minutes = p_response_window_minutes,
      allow_late_blessings = p_allow_late_blessings
  where id = p_circle_id and owner_id = auth.uid()
  returning * into v_circle;

  if v_circle.id is null then raise exception 'circle not found or owner required'; end if;
  return v_circle;
end;
$$;

revoke all on function public.update_circle_settings(
  uuid, text, text, time, time, integer, boolean
) from public, anon;
grant execute on function public.update_circle_settings(
  uuid, text, text, time, time, integer, boolean
) to authenticated;
