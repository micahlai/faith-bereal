create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create index if not exists daily_prompts_dispatch_recovery_idx
  on public.daily_prompts (dispatched_at)
  where state = 'dispatching';

create or replace function public.claim_due_prompts(p_limit integer default 100)
returns setof public.daily_prompts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with claimed as (
    select p.id
    from public.daily_prompts p
    where (
        p.state = 'scheduled'
        and p.starts_at <= now()
      ) or (
        p.state = 'dispatching'
        and p.ends_at > now()
        and coalesce(p.dispatched_at, p.created_at) <= now() - interval '5 minutes'
      )
    order by p.starts_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.daily_prompts p
  set state = 'dispatching', dispatched_at = now(), failure_reason = null
  from claimed
  where p.id = claimed.id
  returning p.*;
end;
$$;

revoke all on function public.claim_due_prompts(integer) from public, anon, authenticated;

update public.daily_prompts
set
  state = 'closed',
  closed_at = coalesce(closed_at, now()),
  failure_reason = coalesce(failure_reason, 'Dispatch was interrupted before the response window ended')
where state = 'dispatching'
  and ends_at <= now();

comment on function public.claim_due_prompts(integer) is
  'Atomically claims scheduled prompts and retries interrupted, still-open dispatches after five minutes.';
