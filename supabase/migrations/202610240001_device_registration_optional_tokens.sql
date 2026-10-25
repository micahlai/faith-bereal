-- Keep the deployed registration implementation and grants; only permit omitted
-- nullable tokens. An omitted environment still fails explicitly.
do $preflight$
begin
  if not exists (
    select 1 from pg_proc
    where oid='public.register_device(uuid,text,text,public.push_environment)'::regprocedure
      and proargnames=array['p_installation_id','p_apns_token','p_push_to_start_token','p_environment']::text[]
      and pronargdefaults=0 and prosecdef
      and btrim(prosrc,E' \n\r\t')=btrim($predecessor$declare
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
$predecessor$,E' \n\r\t')
  ) then
    raise exception 'register_device predecessor differs; inspect before applying compatibility change';
  end if;
end;
$preflight$;

create or replace function public.register_device(
  p_installation_id uuid,
  p_apns_token text default null,
  p_push_to_start_token text default null,
  p_environment public.push_environment default null
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
  if p_environment is null then
    raise exception 'push environment required' using errcode='22023';
  end if;
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

revoke all on function public.register_device(uuid, text, text, public.push_environment) from public, anon;
grant execute on function public.register_device(uuid, text, text, public.push_environment) to authenticated;

-- Invalidate API argument matching for already-installed clients.
notify pgrst, 'reload schema';
