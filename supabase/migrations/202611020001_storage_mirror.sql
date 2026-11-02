-- Supabase remains authoritative. No media, credentials, or read URLs are exposed
-- by these service-only RPCs. Observe Storage API writes; never modify its rows.
create schema if not exists manna_private;
revoke all on schema manna_private from public, anon, authenticated;

create table manna_private.storage_mirror_jobs (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null check (bucket_id in ('blessing-media','avatars','circle-photos')),
  object_name text not null,
  source_id uuid not null,
  source_version text,
  desired boolean not null default true,
  state text not null default 'pending' check (state in ('pending','copied','deleted')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  last_copy_claim_at timestamptz,
  last_error text check (last_error in ('source','storage','transport','configuration')),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create unique index storage_mirror_current on manna_private.storage_mirror_jobs(bucket_id, object_name) where desired;
create index storage_mirror_ready on manna_private.storage_mirror_jobs(available_at)
  where (desired and state='pending') or (not desired and state<>'deleted');
create index storage_mirror_receipts on manna_private.storage_mirror_jobs(completed_at)
  where not desired and state='deleted';
alter table manna_private.storage_mirror_jobs enable row level security;
revoke all on manna_private.storage_mirror_jobs from public, anon, authenticated, service_role;

create or replace function manna_private.enqueue_storage_mirror() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- last_accessed_at and unrelated bookkeeping must never enqueue a download.
  if tg_op = 'UPDATE' and
     (new.id, new.bucket_id, new.name, new.version, new.metadata, new.is_delete_marker, new.archived_at) is not distinct from
     (old.id, old.bucket_id, old.name, old.version, old.metadata, old.is_delete_marker, old.archived_at) then
    return null;
  end if;
  if tg_op <> 'INSERT' then
    update manna_private.storage_mirror_jobs set desired = false,
      -- An acknowledged PUT has finished. Ambiguous/in-flight PUTs retain the
      -- grace period, including copies that committed before a lost ACK.
      available_at = case when state='copied' and lease_token is null then now()
        else greatest(now(), coalesce(last_copy_claim_at + interval '30 minutes', now())) end
    where bucket_id = old.bucket_id and object_name = old.name and desired;
  end if;
  if tg_op <> 'DELETE' and new.bucket_id in ('blessing-media','avatars','circle-photos')
     and not coalesce(new.is_delete_marker,false) and new.archived_at is null then
    insert into manna_private.storage_mirror_jobs(bucket_id,object_name,source_id,source_version)
    values(new.bucket_id,new.name,new.id,new.version);
  end if;
  return null;
end;
$$;
revoke all on function manna_private.enqueue_storage_mirror() from public, anon, authenticated, service_role;
create trigger enqueue_storage_mirror after insert or update or delete on storage.objects
for each row execute function manna_private.enqueue_storage_mirror();

create or replace function public.claim_storage_mirror_jobs(p_limit integer default 5)
returns table(job_id uuid, lease_token uuid, operation text, bucket_id text, object_name text, r2_key text)
language plpgsql security definer set search_path = '' as $$
begin
  -- Purge only our completed deletion receipts, never Supabase Storage rows.
  delete from manna_private.storage_mirror_jobs where id in (
    select j.id from manna_private.storage_mirror_jobs j
    where not j.desired and j.state='deleted' and j.completed_at < now()-interval '7 days'
    order by j.completed_at limit 100 for update skip locked
  );
  return query
  with ready as (
    select j.id from manna_private.storage_mirror_jobs j
    where j.available_at <= now() and (j.lease_until is null or j.lease_until <= now())
      and ((j.desired and j.state = 'pending') or (not j.desired and j.state <> 'deleted'))
    order by j.available_at, j.id for update skip locked
    limit greatest(1, least(coalesce(p_limit,5),10))
  ), claimed as (
    update manna_private.storage_mirror_jobs j set
      lease_token = gen_random_uuid(), lease_until = now() + interval '20 minutes',
      last_copy_claim_at = case when j.desired then now() else j.last_copy_claim_at end,
      attempts = least(j.attempts + 1, 1000000)
    from ready where j.id = ready.id returning j.*
  ) select j.id,j.lease_token,case when j.desired then 'copy' else 'delete' end,
    j.bucket_id,j.object_name,'v1/' || j.id::text from claimed j;
end;
$$;

create or replace function public.finish_storage_mirror_job(p_job_id uuid, p_lease_token uuid, p_operation text, p_error text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare j manna_private.storage_mirror_jobs;
begin
  select * into j from manna_private.storage_mirror_jobs where id = p_job_id for update;
  if not found or p_lease_token is null or j.lease_token is null or j.lease_until is null
     or j.lease_token is distinct from p_lease_token or j.lease_until <= now() then
    return false;
  end if;
  if p_operation not in ('copy','delete') or p_operation is null or
     (p_operation = 'delete' and j.desired) then
    raise exception 'Invalid mirror operation';
  end if;
  if p_error is not null then
    if p_error not in ('source','storage','transport','configuration') then
      raise exception 'Invalid mirror error';
    end if;
    update manna_private.storage_mirror_jobs set lease_token = null, lease_until = null,
      last_error = p_error,
      available_at = greatest(
        now() + make_interval(secs => least(21600, 30 * power(2, least(j.attempts,10))::integer)),
        case when not desired and state<>'copied' then coalesce(last_copy_claim_at + interval '30 minutes', now()) else now() end)
    where id = j.id;
  else
    update manna_private.storage_mirror_jobs set lease_token = null, lease_until = null,
      state = case when p_operation = 'copy' then 'copied' else 'deleted' end,
      completed_at = now(), last_error = null,
      -- A valid copy ACK proves the last possible PUT completed. Retired
      -- generations can now be deleted without waiting out an ambiguous lease.
      available_at = now()
    where id = j.id;
  end if;
  return true;
end;
$$;

-- Opt-in, bounded backfill. The caller advances the returned UUID cursor; this
-- migration deliberately does not download the existing library automatically.
create or replace function public.backfill_storage_mirror(p_after uuid default null, p_limit integer default 100)
returns table(next_cursor uuid, scanned integer, enqueued integer)
language plpgsql security definer set search_path = '' as $$
begin
  -- Coordinate with Storage writes: each selected row is locked until enqueue
  -- commits, so a concurrent replacement/delete cannot leave a stale desired row.
  return query with source as materialized (
    select o.id,o.bucket_id,o.name,o.version from storage.objects o
    where o.bucket_id in ('blessing-media','avatars','circle-photos') and (p_after is null or o.id > p_after)
      and not coalesce(o.is_delete_marker,false) and o.archived_at is null
    order by o.id limit greatest(1,least(coalesce(p_limit,100),500)) for update
  ), inserted as (
    insert into manna_private.storage_mirror_jobs(bucket_id,object_name,source_id,source_version)
    select s.bucket_id,s.name,s.id,s.version from source s
    on conflict (bucket_id,object_name) where desired do nothing returning id
  ) select (select s.id from source s order by s.id desc limit 1),
      (select count(*)::integer from source),(select count(*)::integer from inserted);
end;
$$;

create or replace function public.storage_mirror_status()
returns table(desired boolean,state text,jobs bigint,oldest_pending_at timestamptz,failures bigint)
language sql security definer set search_path = '' as $$
  select j.desired,j.state,count(*),min(j.created_at) filter(where j.state='pending'),
    count(*) filter(where j.last_error is not null)
  from manna_private.storage_mirror_jobs j group by j.desired,j.state;
$$;

revoke all on function public.claim_storage_mirror_jobs(integer) from public,anon,authenticated;
revoke all on function public.finish_storage_mirror_job(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.backfill_storage_mirror(uuid,integer) from public,anon,authenticated;
revoke all on function public.storage_mirror_status() from public,anon,authenticated;
grant execute on function public.claim_storage_mirror_jobs(integer), public.finish_storage_mirror_job(uuid,uuid,text,text),
  public.backfill_storage_mirror(uuid,integer), public.storage_mirror_status() to service_role;

notify pgrst, 'reload schema';
