-- Caller-owned ready AND unanswered circle IDs for the switcher. The icon
-- badge and existing server delivery use this same entry/submission predicate.
create function manna_private.ready_circle_ids(p_user uuid,p_at timestamptz) returns uuid[]
language sql stable security definer set search_path='' as $$
 select case when public.account_is_active(p_user) then (
  select coalesce(array_agg(distinct p.circle_id order by p.circle_id), array[]::uuid[])
  from public.circle_members cm join public.circles c on c.id=cm.circle_id
  join public.daily_prompts p on p.circle_id=c.id
  where cm.user_id=p_user and cm.removed_at is null and p.state<>'scheduled'
   and (p.local_date >= (p_at at time zone c.time_zone)::date-1 or p.ends_at>p_at)
   and public.prompt_accepts_entry(p.id,p_user,p_at)
   and not exists(select 1 from public.blessings b where b.prompt_id=p.id and b.author_id=p_user)
 ) else array[]::uuid[] end;
$$;
revoke all on function manna_private.ready_circle_ids(uuid,timestamptz) from public,anon,authenticated;

create or replace function manna_private.ready_circle_count(p_user uuid,p_at timestamptz) returns integer
language sql stable security definer set search_path='' as $$
 select cardinality(manna_private.ready_circle_ids(p_user,p_at));
$$;

create function public.my_ready_blessing_circle_ids() returns uuid[]
language sql stable security definer set search_path='' as $$
 select manna_private.ready_circle_ids(auth.uid(),statement_timestamp());
$$;
revoke all on function public.my_ready_blessing_circle_ids() from public,anon;
grant execute on function public.my_ready_blessing_circle_ids() to authenticated,service_role;
notify pgrst,'reload schema';
