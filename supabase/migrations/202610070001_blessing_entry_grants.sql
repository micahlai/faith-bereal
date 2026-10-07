create table public.blessing_entry_grants (
  prompt_id uuid not null references public.daily_prompts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  entered_at timestamptz not null default clock_timestamp(),
  primary key (prompt_id, user_id)
);

alter table public.blessing_entry_grants enable row level security;
revoke all on table public.blessing_entry_grants from public, anon, authenticated;

create or replace function public.prompt_accepts_entry(
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

create or replace function public.begin_blessing_entry(p_prompt_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_entered_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if exists (
    select 1 from public.blessings
    where prompt_id = p_prompt_id and author_id = v_user_id
  ) then
    raise exception 'already submitted';
  end if;
  if not public.prompt_accepts_entry(p_prompt_id, v_user_id, v_entered_at) then
    raise exception 'response window is closed';
  end if;

  insert into public.blessing_entry_grants (prompt_id, user_id, entered_at)
  values (p_prompt_id, v_user_id, v_entered_at)
  on conflict (prompt_id, user_id) do update
    set entered_at = public.blessing_entry_grants.entered_at
  returning entered_at into v_entered_at;

  return v_entered_at;
end;
$$;

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
    and (
      public.prompt_accepts_entry(p.id, p_user_id, p_at)
      or exists (
        select 1 from public.blessing_entry_grants grant_row
        where grant_row.prompt_id = p.id
          and grant_row.user_id = p_user_id
      )
    )
  ), false)
  from public.daily_prompts p
  where p.id = p_prompt_id;
$$;

revoke all on function public.prompt_accepts_entry(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.begin_blessing_entry(uuid) from public, anon;
revoke all on function public.prompt_accepts_submission(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.begin_blessing_entry(uuid) to authenticated;
grant execute on function public.prompt_accepts_submission(uuid, uuid, timestamptz) to authenticated;

create or replace function public.claim_due_prompts(p_limit integer default 100)
returns setof public.daily_prompts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_claimed_at timestamptz := clock_timestamp();
begin
  update public.daily_prompts
  set
    state = 'closed',
    closed_at = v_claimed_at,
    failure_reason = coalesce(failure_reason, 'Prompt dispatch missed its delivery grace period')
  where state = 'scheduled'
    and starts_at <= v_claimed_at - interval '5 minutes';

  return query
  with claimed as (
    select p.id, p.state as prior_state
    from public.daily_prompts p
    where (
        p.state = 'scheduled'
        and p.starts_at <= v_claimed_at
      ) or (
        p.state = 'dispatching'
        and p.ends_at > v_claimed_at
        and coalesce(p.dispatched_at, p.created_at) <= v_claimed_at - interval '5 minutes'
      )
    order by p.starts_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.daily_prompts p
  set
    state = 'dispatching',
    dispatched_at = v_claimed_at,
    failure_reason = null,
    starts_at = case
      when claimed.prior_state = 'scheduled' then v_claimed_at
      else p.starts_at
    end,
    ends_at = case
      when claimed.prior_state = 'scheduled'
        then v_claimed_at + make_interval(mins => p.response_window_minutes)
      else p.ends_at
    end
  from claimed
  where p.id = claimed.id
  returning p.*;
end;
$$;

revoke all on function public.claim_due_prompts(integer) from public, anon, authenticated;

comment on table public.blessing_entry_grants is
  'Server-issued proof that a member opened a prompt while entry was allowed; submission may finish later.';
comment on function public.begin_blessing_entry(uuid) is
  'Opens a composer session while the prompt entry deadline permits it.';
comment on function public.claim_due_prompts(integer) is
  'Claims due prompts, authors the response deadline from actual dispatch time, and suppresses stale alerts.';
