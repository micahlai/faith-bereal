create or replace function public.leave_circle(p_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_circle public.circles;
  v_successor uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null or not public.is_circle_member(p_circle_id, v_user_id) then
    raise exception 'circle not found or membership required';
  end if;

  if v_circle.owner_id = v_user_id then
    select cm.user_id into v_successor
    from public.circle_members cm
    where cm.circle_id = p_circle_id
      and cm.user_id <> v_user_id
      and cm.removed_at is null
    order by cm.joined_at, cm.user_id
    limit 1;

    if v_successor is null then
      delete from public.circles where id = p_circle_id;
      return;
    end if;

    update public.circles
    set owner_id = v_successor
    where id = p_circle_id;

    update public.circle_members
    set role = 'owner'
    where circle_id = p_circle_id and user_id = v_successor;
  end if;

  update public.circle_members
  set role = 'member', removed_at = now()
  where circle_id = p_circle_id and user_id = v_user_id;
end;
$$;

revoke all on function public.leave_circle(uuid) from public, anon;
grant execute on function public.leave_circle(uuid) to authenticated;
