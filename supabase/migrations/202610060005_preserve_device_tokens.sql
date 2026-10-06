create or replace function public.register_device(
  p_installation_id uuid,
  p_apns_token text,
  p_push_to_start_token text,
  p_environment public.push_environment
)
returns public.device_registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.device_registrations;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into public.device_registrations (
    user_id, installation_id, apns_token, push_to_start_token, environment, last_seen_at, revoked_at
  ) values (
    auth.uid(), p_installation_id, nullif(p_apns_token, ''), nullif(p_push_to_start_token, ''),
    p_environment, now(), null
  )
  on conflict (user_id, installation_id, environment) do update set
    apns_token = coalesce(excluded.apns_token, device_registrations.apns_token),
    push_to_start_token = coalesce(excluded.push_to_start_token, device_registrations.push_to_start_token),
    last_seen_at = now(),
    revoked_at = null
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.register_device(uuid, text, text, public.push_environment) from public;
grant execute on function public.register_device(uuid, text, text, public.push_environment) to authenticated;
