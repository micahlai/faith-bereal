create table if not exists public.apns_provider_token_cache (
  singleton boolean primary key default true check (singleton),
  token text not null,
  created_at timestamptz not null default now()
);

alter table public.apns_provider_token_cache enable row level security;

revoke all on table public.apns_provider_token_cache from public, anon, authenticated, service_role;

create or replace function public.claim_apns_provider_token(p_token text)
returns table(token text, created_at timestamptz)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_token is null or length(p_token) < 16 then
    raise exception 'Invalid APNs provider token';
  end if;

  return query
  insert into public.apns_provider_token_cache as cache (singleton, token, created_at)
  values (true, p_token, now())
  on conflict (singleton) do update
  set
    token = case
      when cache.created_at <= now() - interval '45 minutes' then excluded.token
      else cache.token
    end,
    created_at = case
      when cache.created_at <= now() - interval '45 minutes' then excluded.created_at
      else cache.created_at
    end
  returning cache.token, cache.created_at;
end;
$$;

revoke all on function public.claim_apns_provider_token(text) from public, anon, authenticated;
grant execute on function public.claim_apns_provider_token(text) to service_role;

comment on table public.apns_provider_token_cache is
  'Server-only, short-lived APNs JWT cache that prevents Apple TooManyProviderTokenUpdates throttling across Edge Function runtimes.';

comment on function public.claim_apns_provider_token(text) is
  'Returns the current APNs provider token or atomically rotates it after 45 minutes; service role only.';
