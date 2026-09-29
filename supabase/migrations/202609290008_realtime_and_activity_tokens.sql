alter table public.activity_registrations
  add column if not exists environment public.push_environment not null default 'sandbox';

create or replace function public.register_activity(
  p_prompt_id uuid,
  p_activity_id text,
  p_push_token text,
  p_environment public.push_environment
)
returns public.activity_registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.activity_registrations;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists (
    select 1
    from public.daily_prompts p
    where p.id = p_prompt_id
      and public.is_circle_member(p.circle_id, auth.uid())
  ) then
    raise exception 'prompt not found or circle membership required';
  end if;
  if nullif(trim(p_activity_id), '') is null or nullif(trim(p_push_token), '') is null then
    raise exception 'activity id and push token are required';
  end if;

  insert into public.activity_registrations (
    prompt_id, user_id, activity_id, push_token, environment, ended_at
  ) values (
    p_prompt_id, auth.uid(), p_activity_id, p_push_token, p_environment, null
  )
  on conflict (prompt_id, user_id, activity_id) do update set
    push_token = excluded.push_token,
    environment = excluded.environment,
    ended_at = null
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.register_activity(uuid, text, text, public.push_environment)
  from public, anon;
grant execute on function public.register_activity(uuid, text, text, public.push_environment)
  to authenticated;

insert into public.profiles (id, display_name, time_zone)
select
  u.id,
  left(coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Circle member'
  ), 60),
  'UTC'
from auth.users u
on conflict (id) do nothing;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'blessings',
    'blessing_responses',
    'daily_prompts',
    'circle_members'
  ] loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;
