-- Feature metadata only: no content, media paths, or cross-circle information.
create function public.circle_streaks(p_circle_id uuid)
returns table(member_id uuid, days integer, on_time_days integer, on_time_today boolean)
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
  ), counts as (
    select r.author_id, count(*) filter(where r.local_date=r.anchor-r.n+1)::integer as days,
      count(*) filter(where r.local_date=r.anchor-r.n+1 and r.timely)::integer as on_time_days,
      bool_or(r.local_date=v_today and r.timely) as on_time_today
    from ranked r group by r.author_id
  )
  select cm.user_id,coalesce(s.days,0),coalesce(s.on_time_days,0),coalesce(s.on_time_today,false)
  from public.circle_members cm left join counts s on s.author_id=cm.user_id
  where cm.circle_id=p_circle_id and cm.removed_at is null;
end;
$$;
revoke all on function public.circle_streaks(uuid) from public,anon;
grant execute on function public.circle_streaks(uuid) to authenticated;
