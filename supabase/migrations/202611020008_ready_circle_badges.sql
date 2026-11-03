-- One badge unit per circle with an unsubmitted, server-authorized entry.
-- No names/content or peer submission states are returned to the client.
create function manna_private.ready_circle_count(p_user uuid,p_at timestamptz) returns integer
language sql stable security definer set search_path='' as $$
 select case when public.account_is_active(p_user) then (
  select count(distinct p.circle_id)::integer
  from public.circle_members cm join public.circles c on c.id=cm.circle_id
  join public.daily_prompts p on p.circle_id=c.id
  where cm.user_id=p_user and cm.removed_at is null and p.state<>'scheduled'
   and (p.local_date >= (p_at at time zone c.time_zone)::date-1 or p.ends_at>p_at)
   and public.prompt_accepts_entry(p.id,p_user,p_at)
   and not exists(select 1 from public.blessings b where b.prompt_id=p.id and b.author_id=p_user)
 ) else 0 end;
$$;
revoke all on function manna_private.ready_circle_count(uuid,timestamptz) from public,anon,authenticated;

create function public.my_ready_blessing_circle_count() returns integer
language sql stable security definer set search_path='' as $$
 select manna_private.ready_circle_count(auth.uid(),statement_timestamp());
$$;
revoke all on function public.my_ready_blessing_circle_count() from public,anon;
grant execute on function public.my_ready_blessing_circle_count() to authenticated,service_role;

create function public.revoke_installation_notifications(p_installation uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not public.account_is_active() then return; end if;
 update public.device_registrations set revoked_at=clock_timestamp()
 where user_id=auth.uid() and installation_id=p_installation and revoked_at is null;
end $$;
revoke all on function public.revoke_installation_notifications(uuid) from public,anon;
grant execute on function public.revoke_installation_notifications(uuid) to authenticated;

create table manna_private.device_badge_state (
 device_id uuid primary key references public.device_registrations(id) on delete cascade,
 last_badge integer not null default -1,
 last_token_hash text,
 lease_token uuid,
 leased_until timestamptz,
 claimed_count integer,
 claimed_token_hash text,
 last_attempt_at timestamptz
);
alter table manna_private.device_badge_state enable row level security;
revoke all on manna_private.device_badge_state from public,anon,authenticated;

create function public.claim_ready_circle_badges(p_limit integer default 100)
returns table(device_id uuid,user_id uuid,apns_token text,environment public.push_environment,badge_count integer,lease_token uuid)
language plpgsql security definer set search_path='' as $$
begin
 insert into manna_private.device_badge_state(device_id)
 select d.id from public.device_registrations d where d.apns_token is not null and d.revoked_at is null
 on conflict do nothing;
 return query
 with counts as materialized (
  select u.user_id,manna_private.ready_circle_count(u.user_id,statement_timestamp()) as ready
  from (select distinct d.user_id from public.device_registrations d where d.apns_token is not null and d.revoked_at is null) u
 ), candidates as (
  select s.device_id,c.ready,md5(d.apns_token) as token_hash
  from manna_private.device_badge_state s join public.device_registrations d on d.id=s.device_id
  join counts c on c.user_id=d.user_id
  where d.apns_token is not null and d.revoked_at is null
   and (s.leased_until is null or s.leased_until<=clock_timestamp())
   and (s.last_badge<>c.ready or s.last_token_hash is distinct from md5(d.apns_token))
  order by s.last_attempt_at nulls first,s.device_id
  for update of s skip locked limit greatest(1,least(p_limit,500))
 ), claimed as (
  update manna_private.device_badge_state s set lease_token=gen_random_uuid(),
   leased_until=clock_timestamp()+interval '2 minutes',last_attempt_at=clock_timestamp(),
   claimed_count=c.ready,claimed_token_hash=c.token_hash
  from candidates c where s.device_id=c.device_id
  returning s.*
 )
 select d.id,d.user_id,d.apns_token,d.environment,s.claimed_count,s.lease_token
 from claimed s join public.device_registrations d on d.id=s.device_id;
end $$;

create function public.complete_ready_circle_badge(p_device uuid,p_lease uuid,p_success boolean) returns void
language sql security definer set search_path='' as $$
 update manna_private.device_badge_state s set
  last_badge=case when p_success then s.claimed_count else s.last_badge end,
  last_token_hash=case when p_success then s.claimed_token_hash else s.last_token_hash end,
  lease_token=null,leased_until=case when p_success then null else clock_timestamp()+interval '1 minute' end
 where s.device_id=p_device and s.lease_token=p_lease;
$$;
revoke all on function public.claim_ready_circle_badges(integer),public.complete_ready_circle_badge(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.claim_ready_circle_badges(integer),public.complete_ready_circle_badge(uuid,uuid,boolean) to service_role;
notify pgrst,'reload schema';
