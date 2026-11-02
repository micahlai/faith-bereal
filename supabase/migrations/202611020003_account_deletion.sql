-- Deletion is durable, server-only, and never reports completion before media
-- disappearance in both providers. Actual objects are removed through Storage API.
create table manna_private.deletion_receipts (
 receipt_hash text primary key, user_id uuid unique,
 requested_at timestamptz not null default now(), completed_at timestamptz
);
alter table manna_private.deletion_receipts enable row level security;
revoke all on manna_private.deletion_receipts from public,anon,authenticated;
create table manna_private.account_deletion_media (
 user_id uuid not null references manna_private.account_deletions(user_id) on delete cascade,
 bucket_id text not null, object_name text not null, primary key(user_id,bucket_id,object_name)
);
alter table manna_private.account_deletion_media enable row level security;
revoke all on manna_private.account_deletion_media from public,anon,authenticated;
create function public.request_account_deletion(p_user uuid,p_apple_revoked boolean,p_receipt_hash text default null) returns void
language plpgsql security definer set search_path='' as $$
declare c record; successor uuid;
begin
 if p_user is null or not p_apple_revoked then raise exception 'Apple revocation must complete first'; end if;
 if exists(select 1 from manna_private.account_deletions where user_id=p_user) then return; end if;
 -- All mutation triggers below run in a privileged service context. No user JWT
 -- is retained or accepted for these service-only operations.
 if auth.uid() is not null then raise exception 'Service identity required'; end if;
 perform 1 from public.profiles where id=p_user for update;
 if not found then raise exception 'Account not found'; end if;
 insert into manna_private.account_deletions(user_id,apple_revoked) values(p_user,true);
 if p_receipt_hash is not null then
  if p_receipt_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid receipt'; end if;
  insert into manna_private.deletion_receipts(receipt_hash,user_id) values(p_receipt_hash,p_user);
 end if;
 insert into manna_private.account_deletion_media
 select p_user,o.bucket_id,o.name from storage.objects o where
   (o.bucket_id='avatars' and (storage.foldername(o.name))[1]=p_user::text)
   or (o.bucket_id='blessing-media' and (storage.foldername(o.name))[3]=p_user::text)
   or o.owner_id=p_user::text on conflict do nothing;
 for c in select * from public.circles where owner_id=p_user order by id for update loop
  select m.user_id into successor from public.circle_members m where m.circle_id=c.id and m.user_id<>p_user and m.removed_at is null and public.account_is_active(m.user_id) order by m.joined_at,m.user_id limit 1;
  if successor is null then
   insert into manna_private.account_deletion_media select p_user,o.bucket_id,o.name from storage.objects o where o.bucket_id in ('blessing-media','circle-photos') and (storage.foldername(o.name))[1]=c.id::text on conflict do nothing;
   delete from public.circles where id=c.id;
  else
   update public.circles set owner_id=successor where id=c.id;
   update public.circle_members set role='owner' where circle_id=c.id and user_id=successor;
  end if;
 end loop;
 delete from public.blessing_responses where author_id=p_user;
 delete from public.blessings where author_id=p_user;
 delete from public.circle_members where user_id=p_user;
 delete from public.device_registrations where user_id=p_user;
 delete from public.activity_registrations where user_id=p_user;
 -- Strip profile identifiers immediately, retaining only the tombstone/FK until
 -- media cleanup finishes and Supabase Auth deletion cascades the remaining row.
 update public.profiles set display_name='Deleted account',avatar_path=null,deleted_at=now() where id=p_user;
end $$;
create function public.pending_account_deletions(p_limit integer default 5)
returns table(user_id uuid,requested_at timestamptz) language plpgsql security definer set search_path='' as $$
begin
 return query
 with claimed as (
  select a.user_id from manna_private.account_deletions a
  where a.last_attempt_at is null or a.last_attempt_at<now()-interval '2 minutes'
  order by a.last_attempt_at nulls first,a.requested_at for update skip locked limit greatest(1,least(p_limit,10))
 ), updated as (
  update manna_private.account_deletions a set last_attempt_at=now(),attempts=attempts+1 from claimed c where a.user_id=c.user_id returning a.user_id,a.requested_at
 ) select u.user_id,u.requested_at from updated u;
 -- Recover a crash between Auth deletion and recording completion.
 return query select r.user_id,r.requested_at from manna_private.deletion_receipts r
 where r.user_id is not null and not exists(select 1 from auth.users u where u.id=r.user_id)
 order by r.requested_at limit greatest(1,least(p_limit,10));
end $$;
create function public.account_deletion_files(p_user uuid,p_limit integer default 100)
returns table(bucket_id text,object_name text) language sql security definer set search_path='' as $$
 select m.bucket_id,m.object_name from manna_private.account_deletion_media m join storage.objects o on o.bucket_id=m.bucket_id and o.name=m.object_name
 where m.user_id=p_user order by m.bucket_id,m.object_name limit greatest(1,least(p_limit,100));
$$;
create function public.account_deletion_ready(p_user uuid) returns boolean
language sql security definer set search_path='' as $$
 select exists(select 1 from manna_private.account_deletions d where d.user_id=p_user and d.apple_revoked)
 and not exists(select 1 from manna_private.account_deletion_media m join storage.objects o on o.bucket_id=m.bucket_id and o.name=m.object_name where m.user_id=p_user)
 and not exists(select 1 from manna_private.account_deletion_media m join manna_private.storage_mirror_jobs j on j.bucket_id=m.bucket_id and j.object_name=m.object_name where m.user_id=p_user and (j.desired or j.state<>'deleted'));
$$;
create function public.my_account_deletion_status() returns text language sql security definer set search_path='' as $$
 select case when exists(select 1 from manna_private.account_deletions where user_id=auth.uid()) then 'pending' else 'none' end;
$$;
-- Prevent in-flight authorized uploads from appearing after their account was
-- snapshotted. The profile lock serializes the Storage transaction with deletion.
create function manna_private.guard_deleting_storage() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_uuid uuid;
begin
 owner_uuid:=coalesce(public.try_uuid(new.owner_id),case when new.bucket_id='avatars' then public.try_uuid((storage.foldername(new.name))[1]) when new.bucket_id='blessing-media' then public.try_uuid((storage.foldername(new.name))[3]) end);
 if owner_uuid is not null then
  perform 1 from public.profiles where id=owner_uuid for share;
  if not found then raise exception 'Account is unavailable' using errcode='42501'; end if;
  if exists(select 1 from manna_private.account_deletions where user_id=owner_uuid) then raise exception 'Account deletion in progress' using errcode='42501'; end if;
 end if;
 return new;
end $$;
create trigger guard_deleting_storage before insert or update on storage.objects for each row execute function manna_private.guard_deleting_storage();
revoke all on function public.request_account_deletion(uuid,boolean,text),public.pending_account_deletions(integer),public.account_deletion_files(uuid,integer),public.account_deletion_ready(uuid),public.my_account_deletion_status() from public,anon,authenticated;
grant execute on function public.request_account_deletion(uuid,boolean,text),public.pending_account_deletions(integer),public.account_deletion_files(uuid,integer),public.account_deletion_ready(uuid) to service_role;
grant execute on function public.my_account_deletion_status() to authenticated,service_role;
revoke all on function manna_private.guard_deleting_storage() from public,anon,authenticated;
notify pgrst,'reload schema';

create function public.account_deletion_requested(p_user uuid) returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from manna_private.account_deletions where user_id=p_user);
$$;
revoke all on function public.account_deletion_requested(uuid) from public,anon,authenticated;
grant execute on function public.account_deletion_requested(uuid) to service_role;

-- A high-entropy client receipt permits checking completion after Auth is gone.
-- The plaintext capability never enters the database; only its SHA-256 does.
create function public.account_deletion_receipt_status(p_hash text) returns text
language sql security definer set search_path='' as $$
 select coalesce((select case when completed_at is null then 'pending' else 'completed' end from manna_private.deletion_receipts where receipt_hash=p_hash),'unknown');
$$;
create function public.finish_account_deletion_receipt(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 if exists(select 1 from auth.users where id=p_user) then raise exception 'Account still exists'; end if;
 update manna_private.deletion_receipts set user_id=null,completed_at=now() where user_id=p_user;
end $$;
revoke all on function public.account_deletion_receipt_status(text),public.finish_account_deletion_receipt(uuid) from public,anon,authenticated;
grant execute on function public.account_deletion_receipt_status(text),public.finish_account_deletion_receipt(uuid) to service_role;
