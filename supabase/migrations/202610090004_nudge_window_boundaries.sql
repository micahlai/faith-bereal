-- Nudges follow the ordinary window, not first-day entry exceptions or grants.
create function public.nudge_window_is_open(p_prompt_id uuid,p_user_id uuid,p_at timestamptz)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.daily_prompts p join public.circles c on c.id=p.circle_id
    where p.id=p_prompt_id and public.is_circle_member(p.circle_id,p_user_id)
      and p_at>=p.starts_at
      and case when p.kind='end_of_day' then
        p_at<p.ends_at and not exists(select 1 from public.daily_prompts newer
          where newer.circle_id=p.circle_id and newer.kind='daily'
            and newer.starts_at>p.starts_at and newer.starts_at<=p_at)
      else p_at<p.ends_at or (c.allow_late_blessings and not exists(
        select 1 from public.daily_prompts newer where newer.circle_id=p.circle_id
          and newer.kind='daily' and newer.starts_at>p.starts_at and newer.starts_at<=p_at)) end);
$$;
revoke all on function public.nudge_window_is_open(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.nudge_window_is_open(uuid,uuid,timestamptz) to service_role;

-- Preserve the existing permission, submission, deduplication and opt-out guards;
-- replace only the entry predicate in both queue and dispatch functions.
do $$
declare v_signature text; v_definition text;
begin
  foreach v_signature in array array['public.nudge_circle_member(uuid,uuid)',
                                     'public.nudge_is_deliverable(uuid)'] loop
    v_definition:=pg_get_functiondef(v_signature::regprocedure);
    if strpos(v_definition,'public.prompt_accepts_entry(')=0 then
      raise exception 'Expected nudge entry predicate missing in %',v_signature;
    end if;
    execute replace(v_definition,'public.prompt_accepts_entry(','public.nudge_window_is_open(');
  end loop;
end;
$$;
