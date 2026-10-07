alter table public.circle_members
  add column if not exists notify_on_circle_activity boolean not null default true;

create or replace function public.update_circle_activity_notifications(
  p_circle_id uuid,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  update public.circle_members
  set notify_on_circle_activity = p_enabled
  where circle_id = p_circle_id
    and user_id = v_user_id
    and removed_at is null;

  if not found then raise exception 'circle membership required'; end if;
  return p_enabled;
end;
$$;

revoke all on function public.update_circle_activity_notifications(uuid, boolean)
from public, anon;
grant execute on function public.update_circle_activity_notifications(uuid, boolean)
to authenticated;

create table public.circle_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in ('blessing_shared', 'response_shared')),
  blessing_id uuid not null references public.blessings(id) on delete cascade,
  response_id uuid references public.blessing_responses(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  claimed_at timestamptz,
  delivered_at timestamptz,
  attempt_count integer not null default 0,
  last_error text,
  check (
    (event_type = 'blessing_shared' and response_id is null)
    or (event_type = 'response_shared' and response_id is not null)
  )
);

create unique index circle_notification_outbox_blessing_shared_idx
on public.circle_notification_outbox (blessing_id)
where event_type = 'blessing_shared';

create unique index circle_notification_outbox_response_shared_idx
on public.circle_notification_outbox (response_id)
where event_type = 'response_shared';

create index circle_notification_outbox_pending_idx
on public.circle_notification_outbox (created_at)
where delivered_at is null;

alter table public.circle_notification_outbox enable row level security;
revoke all on table public.circle_notification_outbox from public, anon, authenticated;

create or replace function public.enqueue_blessing_shared_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.circle_notification_outbox (event_type, blessing_id)
  values ('blessing_shared', new.id)
  on conflict do nothing;
  return new;
end;
$$;

create or replace function public.enqueue_response_shared_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.circle_notification_outbox (event_type, blessing_id, response_id)
  values ('response_shared', new.blessing_id, new.id)
  on conflict do nothing;
  return new;
end;
$$;

create trigger blessings_enqueue_shared_notification
after insert on public.blessings
for each row execute function public.enqueue_blessing_shared_notification();

create trigger responses_enqueue_shared_notification
after insert on public.blessing_responses
for each row execute function public.enqueue_response_shared_notification();

create or replace function public.claim_circle_notifications(p_limit integer default 100)
returns setof public.circle_notification_outbox
language sql
security definer
set search_path = public, pg_temp
as $$
  with pending as (
    select id
    from public.circle_notification_outbox
    where delivered_at is null
      and (claimed_at is null or claimed_at <= clock_timestamp() - interval '5 minutes')
    order by created_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.circle_notification_outbox outbox
  set
    claimed_at = clock_timestamp(),
    attempt_count = attempt_count + 1,
    last_error = null
  from pending
  where outbox.id = pending.id
  returning outbox.*;
$$;

create or replace function public.complete_circle_notification(
  p_id uuid,
  p_error text default null
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.circle_notification_outbox
  set
    delivered_at = case
      when p_error is null or attempt_count >= 3 then clock_timestamp()
      else delivered_at
    end,
    claimed_at = case
      when p_error is null or attempt_count >= 3 then claimed_at
      else null
    end,
    last_error = left(p_error, 500)
  where id = p_id;
$$;

revoke all on function public.claim_circle_notifications(integer) from public, anon, authenticated;
revoke all on function public.complete_circle_notification(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_circle_notifications(integer) to service_role;
grant execute on function public.complete_circle_notification(uuid, text) to service_role;

grant select on table public.profiles to service_role;
grant select on table public.blessing_responses to service_role;
grant select on table public.circle_notification_outbox to service_role;

comment on column public.circle_members.notify_on_circle_activity is
  'Per-member switch for blessing-share and followed-response notifications from this circle.';
comment on table public.circle_notification_outbox is
  'Server-only durable queue populated transactionally when blessings and responses are inserted.';
