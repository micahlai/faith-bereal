-- The server resolves the welcome blessing's calendar date; clients cannot
-- invent a historical prompt or use a late Live Activity to grant stale entry.
create function public.first_join_blessing_prompt(p_circle_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_circle public.circles; v_today date; v_prompt public.daily_prompts; v_id uuid; v_now timestamptz:=clock_timestamp();
begin
  select * into v_circle from public.circles where id=p_circle_id for share;
  if not public.is_circle_member(p_circle_id,auth.uid()) then raise exception 'circle membership required'; end if;
  v_today:=(v_now at time zone v_circle.time_zone)::date;
  if not exists(select 1 from public.circle_members where circle_id=p_circle_id and user_id=auth.uid()
    and removed_at is null and (joined_at at time zone v_circle.time_zone)::date=v_today) then return null; end if;
  select * into v_prompt from public.daily_prompts where circle_id=p_circle_id and kind='daily' and local_date=v_today;
  if v_prompt.id is null or v_now>=v_prompt.starts_at then return null; end if;
  insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,kind,state)
    values(p_circle_id,v_today-1,((v_today-1)+v_circle.window_start) at time zone v_circle.time_zone,
      (((v_today-1)+v_circle.window_start) at time zone v_circle.time_zone)+make_interval(mins=>v_circle.response_window_minutes),
      v_circle.response_window_minutes,'daily','closed') on conflict(circle_id,local_date,kind) do nothing;
  select id into v_id from public.daily_prompts where circle_id=p_circle_id and local_date=v_today-1 and kind='daily';
  return v_id;
end;
$$;
revoke all on function public.first_join_blessing_prompt(uuid) from public,anon;
grant execute on function public.first_join_blessing_prompt(uuid) to authenticated;

create or replace function public.prompt_accepts_entry(p_prompt_id uuid,p_user_id uuid default auth.uid(),p_at timestamptz default clock_timestamp())
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.daily_prompts p join public.circles c on c.id=p.circle_id
    join public.circle_members cm on cm.circle_id=p.circle_id and cm.user_id=p_user_id and cm.removed_at is null
    where p.id=p_prompt_id and case when p.kind='end_of_day' then
      p_at>=p.starts_at and p_at<p.ends_at and not exists(select 1 from public.daily_prompts newer
        where newer.circle_id=p.circle_id and newer.kind='daily' and newer.starts_at>p.starts_at and newer.starts_at<=p_at)
    else
      (p_at>=p.starts_at and (p_at<p.ends_at or (c.allow_late_blessings
        and (p_at at time zone c.time_zone)::date=p.local_date
        and not exists(select 1 from public.daily_prompts newer where newer.circle_id=p.circle_id
          and newer.kind='daily' and newer.starts_at>p.starts_at and newer.starts_at<=p_at))))
      or (p_at>=cm.joined_at and (cm.joined_at at time zone c.time_zone)::date=(p_at at time zone c.time_zone)::date
        and ((p.local_date=(p_at at time zone c.time_zone)::date and p_at>=p.starts_at)
          or (p.local_date=(p_at at time zone c.time_zone)::date-1 and exists(
            select 1 from public.daily_prompts current_day where current_day.circle_id=p.circle_id and current_day.kind='daily'
              and current_day.local_date=(p_at at time zone c.time_zone)::date and current_day.starts_at>p_at))))
    end);
$$;

-- Nudges never use the welcome entry exception. Late nudges also stop at midnight.
create or replace function public.nudge_window_is_open(p_prompt_id uuid,p_user_id uuid,p_at timestamptz)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.daily_prompts p join public.circles c on c.id=p.circle_id
    where p.id=p_prompt_id and public.is_circle_member(p.circle_id,p_user_id) and p_at>=p.starts_at
      and case when p.kind='end_of_day' then p_at<p.ends_at and not exists(select 1 from public.daily_prompts newer
        where newer.circle_id=p.circle_id and newer.kind='daily' and newer.starts_at>p.starts_at and newer.starts_at<=p_at)
      else p_at<p.ends_at or (c.allow_late_blessings and (p_at at time zone c.time_zone)::date=p.local_date
        and not exists(select 1 from public.daily_prompts newer where newer.circle_id=p.circle_id
          and newer.kind='daily' and newer.starts_at>p.starts_at and newer.starts_at<=p_at)) end);
$$;
