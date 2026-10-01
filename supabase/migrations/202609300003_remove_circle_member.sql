create or replace function public.remove_circle_member(
  p_circle_id uuid,
  p_member_id uuid
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
  if p_member_id = v_user_id then raise exception 'owner must use leave circle'; end if;

  update public.circle_members
  set removed_at = now(), role = 'member'
  where circle_id = p_circle_id
    and user_id = p_member_id
    and removed_at is null;

  if not found then raise exception 'active member not found'; end if;
  return v_circle;
end;
$$;

revoke all on function public.remove_circle_member(uuid, uuid) from public, anon;
grant execute on function public.remove_circle_member(uuid, uuid) to authenticated;
