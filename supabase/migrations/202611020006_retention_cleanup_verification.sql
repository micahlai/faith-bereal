-- Keep the deletion receipt until physical source removal and durable mirror
-- acknowledgement. Storage API success alone is not proof that both are gone.
create function public.acknowledge_media_deletions(p_paths text[]) returns integer
language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 if coalesce(cardinality(p_paths),0)>100 then raise exception 'Invalid batch'; end if;
 delete from public.media_deletion_queue q where q.storage_path=any(p_paths)
 and not exists(select 1 from storage.objects o where o.bucket_id='blessing-media' and o.name=q.storage_path)
 and not exists(select 1 from manna_private.storage_mirror_jobs j where j.bucket_id='blessing-media'
  and j.object_name=q.storage_path and (j.desired or j.state<>'deleted'));
 get diagnostics removed=row_count;
 return removed;
end $$;
revoke all on function public.acknowledge_media_deletions(text[]) from public,anon,authenticated;
grant execute on function public.acknowledge_media_deletions(text[]) to service_role;
-- A cleanup nulling a recording must not requeue an unchanged, already-reviewed
-- photo. Replacing/adding media continues to require review.
create or replace function manna_private.queue_media_review() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='blessings' then
  if (new.audio_path is not null and (tg_op='INSERT' or new.audio_path is distinct from old.audio_path))
   or (new.video_path is not null and (tg_op='INSERT' or new.video_path is distinct from old.video_path))
   or (new.photo_path is not null and (tg_op='INSERT' or new.photo_path is distinct from old.photo_path)) then
   insert into manna_private.media_review_queue(blessing_id) values(new.id) on conflict do nothing;
   insert into manna_private.hidden_content(blessing_id) values(new.id) on conflict do nothing;
  elsif new.audio_path is null and new.video_path is null and new.photo_path is null then
   if exists(select 1 from manna_private.media_review_queue where blessing_id=new.id)
    and not exists(select 1 from manna_private.content_reports where blessing_id=new.id and status='hidden') then
    delete from manna_private.hidden_content where blessing_id=new.id;
   end if;
   delete from manna_private.media_review_queue where blessing_id=new.id;
  end if;
 elsif new.audio_path is not null and (tg_op='INSERT' or new.audio_path is distinct from old.audio_path) then
  insert into manna_private.media_review_queue(response_id) values(new.id) on conflict do nothing;
  insert into manna_private.hidden_responses(response_id) values(new.id) on conflict do nothing;
 elsif new.audio_path is null then
  if exists(select 1 from manna_private.media_review_queue where response_id=new.id)
   and not exists(select 1 from manna_private.content_reports where response_id=new.id and status='hidden') then
   delete from manna_private.hidden_responses where response_id=new.id;
  end if;
  delete from manna_private.media_review_queue where response_id=new.id;
 end if;
 return null;
end $$;
notify pgrst,'reload schema';
