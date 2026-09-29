create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Circle member'
  );
  insert into public.profiles (id, display_name, time_zone)
  values (new.id, left(v_name, 60), 'UTC')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_created_profile on auth.users;
create trigger auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant select on public.circles to authenticated;
grant select on public.circle_members to authenticated;
grant select on public.daily_prompts to authenticated;
grant select on public.blessings to authenticated;
grant select on public.blessing_responses to authenticated;
grant select, insert, update on public.device_registrations to authenticated;
grant select, insert, update on public.activity_registrations to authenticated;
