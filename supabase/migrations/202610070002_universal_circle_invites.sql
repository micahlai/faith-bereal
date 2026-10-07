create or replace function public.join_circle(p_invite_code text)
returns public.circles
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(trim(p_invite_code));
  v_circle public.circles;
  v_attempts integer;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' then raise exception 'invalid invite code'; end if;

  select count(*) into v_attempts
  from public.invite_join_attempts
  where user_id = v_user_id and attempted_at > now() - interval '15 minutes';
  if v_attempts >= 10 then raise exception 'too many attempts'; end if;

  select c.* into v_circle
  from public.circles c
  where c.invite_code_hash = crypt(v_code, c.invite_code_hash)
  order by c.created_at desc
  limit 1;

  insert into public.invite_join_attempts (user_id, succeeded)
  values (v_user_id, v_circle.id is not null);
  if v_circle.id is null then raise exception 'invalid invite code'; end if;

  insert into public.circle_members as membership (circle_id, user_id, role, joined_at, removed_at)
  values (v_circle.id, v_user_id, 'member', clock_timestamp(), null)
  on conflict (circle_id, user_id) do update
    set role = case
          when membership.removed_at is null then membership.role
          else 'member'::public.member_role
        end,
        joined_at = case
          when membership.removed_at is null then membership.joined_at
          else clock_timestamp()
        end,
        removed_at = null;
  return v_circle;
end;
$$;

grant execute on function public.join_circle(text) to authenticated;
