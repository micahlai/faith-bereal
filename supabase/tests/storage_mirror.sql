begin;
do $$
declare j record; k record; old_id uuid; old_token uuid; new_id uuid; initial_count bigint;
begin
  assert not has_schema_privilege('authenticated','manna_private','usage');
  assert not has_table_privilege('service_role','manna_private.storage_mirror_jobs','select');
  assert not has_function_privilege('anon','public.claim_storage_mirror_jobs(integer)','execute');
  assert not has_function_privilege('authenticated','public.finish_storage_mirror_job(uuid,uuid,text,text)','execute');
  assert not has_function_privilege('authenticated','public.backfill_storage_mirror(uuid,integer)','execute');
  assert not has_function_privilege('anon','public.storage_mirror_status()','execute');
  assert has_function_privilege('service_role','public.claim_storage_mirror_jobs(integer)','execute');
  insert into storage.objects(bucket_id,name,version) values ('other','ignored','1');
  assert (select count(*)=0 from manna_private.storage_mirror_jobs);
  insert into storage.objects(bucket_id,name,version,metadata) values ('avatars','user/avatar.jpg','1','{"size":4}');
  assert not public.finish_storage_mirror_job((select id from manna_private.storage_mirror_jobs),null,'copy'), 'unleased null token accepted';
  select * into j from public.claim_storage_mirror_jobs(1);
  assert j.operation='copy' and j.r2_key='v1/'||j.job_id::text;
  old_id:=j.job_id; old_token:=j.lease_token;
  assert (select count(*)=0 from public.claim_storage_mirror_jobs(10)), 'leased job claimed twice';
  assert not public.finish_storage_mirror_job(j.job_id,gen_random_uuid(),'copy');
  update storage.objects set last_accessed_at=now() where bucket_id='avatars';
  assert (select count(*)=1 from manna_private.storage_mirror_jobs), 'reads queued copies';
  -- Replacement during an in-flight copy preserves its lease and retires its key.
  update storage.objects set version='2' where bucket_id='avatars';
  assert (select not desired and lease_token=old_token and available_at>=now()+interval '30 minutes'
          from manna_private.storage_mirror_jobs where id=old_id);
  select * into k from public.claim_storage_mirror_jobs(1);
  assert k.operation='copy' and k.job_id<>old_id;
  new_id:=k.job_id;
  assert public.finish_storage_mirror_job(old_id,old_token,'copy');
  assert public.finish_storage_mirror_job(k.job_id,k.lease_token,'copy');
  assert (select count(*)=0 from public.claim_storage_mirror_jobs(10));
  update manna_private.storage_mirror_jobs set available_at=now() where id=old_id;
  select * into j from public.claim_storage_mirror_jobs(1);
  assert j.operation='delete' and j.job_id=old_id;
  assert public.finish_storage_mirror_job(j.job_id,j.lease_token,'delete');
  assert (select desired and state='copied' from manna_private.storage_mirror_jobs where id=new_id), 'old cleanup touched new copy';
  -- Actual Storage deletion queues the current version, including successful copies.
  delete from storage.objects where bucket_id='avatars';
  assert (select not desired and state='copied' from manna_private.storage_mirror_jobs where id=new_id);
  assert (select count(*)=0 from public.claim_storage_mirror_jobs(10)), 'deletion skipped in-flight grace';
  update manna_private.storage_mirror_jobs set available_at=now() where id=new_id;
  select * into j from public.claim_storage_mirror_jobs(1);
  assert j.operation='delete' and j.job_id=new_id;
  assert public.finish_storage_mirror_job(j.job_id,j.lease_token,'delete','storage');
  assert (select last_error='storage' and available_at>now() from manna_private.storage_mirror_jobs where id=new_id);
  -- Crashed copy retries with a new token after lease expiry; stale ACKs are fenced.
  insert into storage.objects(bucket_id,name,version) values ('blessing-media','circle/prompt/author/a.mov','3');
  select * into j from public.claim_storage_mirror_jobs(1);
  update manna_private.storage_mirror_jobs set lease_until=now()-interval '1 second' where id=j.job_id;
  select * into k from public.claim_storage_mirror_jobs(1);
  assert j.job_id=k.job_id and j.lease_token<>k.lease_token;
  assert not public.finish_storage_mirror_job(j.job_id,j.lease_token,'copy');
  assert public.finish_storage_mirror_job(k.job_id,k.lease_token,'copy','source');
  assert (select count(*)=0 from public.claim_storage_mirror_jobs(10)), 'backoff not enforced';
  -- Metadata edits and object moves enqueue a new generation; access timestamps do not.
  update storage.objects set metadata='{"size":5}', name='circle/prompt/author/b.mov' where bucket_id='blessing-media';
  select * into j from public.claim_storage_mirror_jobs(1);
  assert j.object_name='circle/prompt/author/b.mov';
  assert public.finish_storage_mirror_job(j.job_id,j.lease_token,'copy');
  -- Bounded backfill includes objects created before trigger installation, never duplicates.
  alter table storage.objects disable trigger enqueue_storage_mirror;
  insert into storage.objects(bucket_id,name,version) values ('circle-photos','c/circle.jpg','a'),('avatars','u/avatar.jpg','b');
  alter table storage.objects enable trigger enqueue_storage_mirror;
  select * into j from public.backfill_storage_mirror(null,1);
  assert j.scanned=1 and j.next_cursor is not null;
  initial_count := (select count(*) from manna_private.storage_mirror_jobs);
  perform public.backfill_storage_mirror(null,500);
  assert (select count(*)>=initial_count from manna_private.storage_mirror_jobs);
  initial_count := (select count(*) from manna_private.storage_mirror_jobs);
  select * into j from public.backfill_storage_mirror(null,500);
  assert j.enqueued=0 and (select count(*)=initial_count from manna_private.storage_mirror_jobs);
  update storage.objects set is_delete_marker=true where bucket_id='circle-photos';
  assert not exists(select 1 from manna_private.storage_mirror_jobs where bucket_id='circle-photos' and desired);
  perform public.backfill_storage_mirror(null,500);
  assert not exists(select 1 from manna_private.storage_mirror_jobs where bucket_id='circle-photos' and desired), 'backfilled deletion marker';
  update storage.objects set archived_at=now() where bucket_id='avatars';
  assert not exists(select 1 from manna_private.storage_mirror_jobs where bucket_id='avatars' and desired);
  update manna_private.storage_mirror_jobs set completed_at=now()-interval '8 days' where state='deleted';
  perform public.claim_storage_mirror_jobs(1);
  assert not exists(select 1 from manna_private.storage_mirror_jobs where state='deleted'), 'deletion receipts retained indefinitely';
end;
$$;
-- Exercise actual restricted role, not just catalog grants.
set local role service_role;
select * from public.storage_mirror_status();
select * from public.claim_storage_mirror_jobs(1);
reset role;
rollback;
