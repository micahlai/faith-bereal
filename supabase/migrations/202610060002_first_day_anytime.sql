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
    cm.user_id is not null
    and (
      (
        p_at >= p.starts_at
        and (
          p_at < p.ends_at
          or (
            c.allow_late_blessings
            and not exists (
              select 1 from public.daily_prompts newer
              where newer.circle_id = p.circle_id
                and newer.starts_at > p.starts_at
                and newer.starts_at <= p_at
            )
          )
        )
      )
      or (
        (cm.joined_at at time zone c.time_zone)::date = p.local_date
        and (p_at at time zone c.time_zone)::date = p.local_date
      )
    )
  ), false)
  from public.daily_prompts p
  join public.circles c on c.id = p.circle_id
  left join public.circle_members cm
    on cm.circle_id = p.circle_id
   and cm.user_id = p_user_id
   and cm.removed_at is null
  where p.id = p_prompt_id;
$$;

revoke all on function public.prompt_accepts_submission(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.prompt_accepts_submission(uuid, uuid, timestamptz) to authenticated;
