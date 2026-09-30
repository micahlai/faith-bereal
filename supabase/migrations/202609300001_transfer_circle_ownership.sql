create or replace function public.transfer_circle_ownership(
  p_circle_id uuid,
  p_new_owner_id uuid
)
returns public.circles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_circle public.circles;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null then raise exception 'circle not found'; end if;
  if v_circle.owner_id <> v_user_id then raise exception 'circle owner required'; end if;
  if p_new_owner_id = v_user_id or not public.is_circle_member(p_circle_id, p_new_owner_id) then
    raise exception 'new owner must be another active circle member';
  end if;

  update public.circle_members
  set role = case
    when user_id = p_new_owner_id then 'owner'::public.member_role
    else 'member'::public.member_role
  end
  where circle_id = p_circle_id and removed_at is null;

  update public.circles
  set owner_id = p_new_owner_id
  where id = p_circle_id
  returning * into v_circle;

  return v_circle;
end;
$$;

revoke all on function public.transfer_circle_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_circle_ownership(uuid, uuid) to authenticated;
