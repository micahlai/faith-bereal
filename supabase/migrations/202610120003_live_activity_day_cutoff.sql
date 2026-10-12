-- The dispatcher uses PostgreSQL's IANA-zone calendar, including DST, rather
-- than guessing midnight from a fixed 24-hour interval in JavaScript.
create function public.daily_prompt_entry_cutoff(p_prompt_id uuid)
returns timestamptz language sql stable security definer set search_path=public,pg_temp as $$
  select case when c.allow_late_blessings then
    greatest(p.ends_at, (p.local_date+1)::timestamp at time zone c.time_zone)
    else p.ends_at end
  from public.daily_prompts p join public.circles c on c.id=p.circle_id
  where p.id=p_prompt_id and p.kind='daily';
$$;
revoke all on function public.daily_prompt_entry_cutoff(uuid) from public,anon,authenticated;
grant execute on function public.daily_prompt_entry_cutoff(uuid) to service_role;
