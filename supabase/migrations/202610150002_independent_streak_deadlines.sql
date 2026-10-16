-- Display metadata only. Each authored circle day resolves independently for
-- general sharing and timely entry to the random blessing. The private clock
-- argument permits operator regression checks; app callers always use now.
create schema if not exists manna_private;
revoke all on schema manna_private from public, anon, authenticated;

create or replace function manna_private.circle_streaks_at(p_circle_id uuid, p_at timestamptz)
returns table(member_id uuid, days integer, on_time_days integer, on_time_today boolean,
  on_time_streak_days integer, next_update_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_today date; v_zone text;
begin
  if auth.uid() is null or not public.is_circle_member(p_circle_id,auth.uid()) then
    raise exception 'circle membership required';
  end if;
  select time_zone into v_zone from public.circles where id=p_circle_id;
  v_today:=(p_at at time zone v_zone)::date;
  return query
  with members as (
    select cm.user_id,(cm.joined_at at time zone v_zone)::date as joined_day
    from public.circle_members cm where cm.circle_id=p_circle_id and cm.removed_at is null
  ), prompt_windows as (
    select p.*,case when p.state='scheduled' then (p.local_date+1)::timestamp at time zone v_zone
      when p.kind='end_of_day' then least(p.ends_at,
      (select min(n.starts_at) from public.daily_prompts n where n.circle_id=p_circle_id
        and n.kind='daily' and n.state<>'scheduled' and n.starts_at>p.starts_at)) else p.ends_at end as cutoff
    from public.daily_prompts p where p.circle_id=p_circle_id and p.local_date<=v_today
      and p.kind in ('daily','end_of_day')
  ), windows as (
    select p.local_date,greatest(max(p.cutoff) filter(where p.state<>'scheduled'),
      case when not bool_or(p.kind='end_of_day' and p.state<>'scheduled') then
        (p.local_date+1)::timestamp at time zone v_zone end) as general_cutoff,
      max(p.ends_at) filter(where p.kind='daily' and p.state<>'scheduled') as timely_cutoff
    from prompt_windows p group by p.local_date
  ), shared as (
    select b.author_id,p.local_date,
      bool_or(p.kind='daily') as daily_shared,
      bool_or(p.kind='daily' and case when g.entered_at is not null then
        g.entered_at>=p.starts_at and g.entered_at<p.ends_at else not coalesce(b.is_late,true) end) as timely
    from public.blessings b join prompt_windows p on p.id=b.prompt_id
    join members m on m.user_id=b.author_id and p.local_date>=m.joined_day
    left join public.blessing_entry_grants g on g.prompt_id=p.id and g.user_id=b.author_id
    -- Pre-notification welcome blessings and future fixture/data rows never earn a day.
    where b.submitted_at>=p.starts_at and b.submitted_at<=p_at and p.starts_at<=p_at and p.state<>'scheduled'
    group by b.author_id,p.local_date
  ), shared_ranked as (
    select s.*,max(s.local_date) over(partition by s.author_id) as latest_day,
      row_number() over(partition by s.author_id order by s.local_date desc)::integer as n
    from shared s
  ), shared_bounds as (
    select s.author_id,max(s.latest_day) as latest_day,
      min(s.local_date) filter(where s.local_date=s.latest_day-s.n+1) as oldest_suffix
    from shared_ranked s group by s.author_id
  ), recent_bound as (
    -- Retain unresolved windows and their preceding day, even across midnight.
    -- Older missing dates cannot contribute unless the latest completed suffix
    -- reaches this boundary; every timely day is also a general shared day.
    select least(v_today-1,coalesce(min(w.local_date) filter(where w.general_cutoff>p_at
      or coalesce(w.timely_cutoff,(w.local_date+1)::timestamp at time zone v_zone)>p_at)-1,v_today-1)) as floor
    from windows w
  ), calendar_bounds as (
    select m.user_id,greatest(m.joined_day,least(r.floor,
      case when s.latest_day>=r.floor then s.oldest_suffix else r.floor end)) as floor
    from members m cross join recent_bound r left join shared_bounds s on s.author_id=m.user_id
  ), calendar as (
    select m.user_id,d.day::date as local_date,
      coalesce(w.general_cutoff,(d.day::date+1)::timestamp at time zone v_zone) as general_cutoff,
      coalesce(w.timely_cutoff,(d.day::date+1)::timestamp at time zone v_zone) as timely_cutoff,
      s.author_id is not null as shared,coalesce(s.daily_shared,false) as daily_shared,
      coalesce(s.timely,false) as timely
    from members m join calendar_bounds b on b.user_id=m.user_id
    cross join lateral generate_series(b.floor::timestamp,v_today::timestamp,interval '1 day') d(day)
    left join windows w on w.local_date=d.day::date
    left join shared s on s.author_id=m.user_id and s.local_date=d.day::date
  ), resolved as (
    select c.*,case when c.shared then true when p_at>=c.general_cutoff then false end as general_result,
      case when c.daily_shared then c.timely when p_at>=c.timely_cutoff then false end as timely_result
    from calendar c
  ), anchors as (
    select r.user_id,max(r.local_date) filter(where r.general_result is not null) as general_anchor,
      max(r.local_date) filter(where r.timely_result is not null) as timely_anchor,
      min(t.deadline) filter(where t.deadline>p_at) as next_deadline
    from resolved r cross join lateral (values
      (case when r.general_result is null then r.general_cutoff end),
      (case when r.timely_result is null then r.timely_cutoff end)) t(deadline)
    group by r.user_id
  ), breaks as (
    select a.*,
      (select max(r.local_date) from resolved r where r.user_id=a.user_id and r.local_date<=a.general_anchor
        and r.general_result is distinct from true) as general_break,
      (select max(r.local_date) from resolved r where r.user_id=a.user_id and r.local_date<=a.timely_anchor
        and r.timely_result is distinct from true) as timely_break
    from anchors a
  )
  select m.user_id,
    count(*) filter(where r.local_date<=a.general_anchor and r.local_date>coalesce(a.general_break,m.joined_day-1)
      and r.general_result)::integer,
    count(*) filter(where r.local_date<=a.general_anchor and r.local_date>coalesce(a.general_break,m.joined_day-1)
      and r.timely)::integer,
    coalesce(bool_or(r.local_date=v_today and r.timely),false),
    count(*) filter(where r.local_date<=a.timely_anchor and r.local_date>coalesce(a.timely_break,m.joined_day-1)
      and r.timely_result)::integer,a.next_deadline
  from members m left join resolved r on r.user_id=m.user_id left join breaks a on a.user_id=m.user_id
  group by m.user_id,m.joined_day,a.general_anchor,a.general_break,a.timely_anchor,a.timely_break,a.next_deadline;
end;
$$;
revoke all on function manna_private.circle_streaks_at(uuid,timestamptz) from public,anon,authenticated;

-- Return shape changed from either deployed four-column or pending five-column
-- predecessors. One statement replaces the wrapper and restores grants even
-- when an operator applies this file without an enclosing migration transaction.
do $migration$
begin
execute 'drop function public.circle_streaks(uuid)';
execute $definition$
create function public.circle_streaks(p_circle_id uuid)
returns table(member_id uuid, days integer, on_time_days integer, on_time_today boolean,
  on_time_streak_days integer, next_update_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
  select * from manna_private.circle_streaks_at(p_circle_id,clock_timestamp());
$$;
$definition$;
execute 'revoke all on function public.circle_streaks(uuid) from public,anon';
execute 'grant execute on function public.circle_streaks(uuid) to authenticated';
end;
$migration$;
