begin;
do $$
declare
  v_old uuid;
  v_fresh uuid;
  v_video uuid;
  v_recent_response uuid;
begin
  insert into public.blessings(capture_mode, body, audio_path, photo_path, submitted_at)
  values ('voice', 'Keep transcript and photo', 'old/audio.m4a', 'old/photo.jpg', now() - interval '14 days')
  returning id into v_old;
  insert into public.blessings(capture_mode, body, audio_path, submitted_at)
  values ('voice', 'Shared repeat', 'old/audio.m4a', now() - interval '13 days') returning id into v_fresh;
  insert into public.blessings(capture_mode, body, video_path, thumbnail_path, submitted_at)
  values ('video', 'Keep video transcript', 'old/video.mp4', 'old/thumbnail.jpg', now() - interval '15 days')
  returning id into v_video;
  insert into public.blessing_responses(blessing_id, mode, body, audio_path, submitted_at)
  values (v_old, 'voice', 'Old response transcript', 'old/response.m4a', now() - interval '14 days');
  insert into public.blessing_responses(blessing_id, mode, body, audio_path, submitted_at)
  values (v_old, 'voice', 'Younger response', 'fresh/response.m4a', now() - interval '2 days')
  returning id into v_recent_response;

  perform public.queue_expired_media(100);
  if (select audio_path is not null or media_expired_at is null from public.blessings where id = v_old) then
    raise exception 'exact 14-day boundary must expire'; end if;
  if (select body <> 'Keep transcript and photo' or photo_path <> 'old/photo.jpg' from public.blessings where id = v_old) then
    raise exception 'cleanup must retain text and photo'; end if;
  if exists(select 1 from public.media_deletion_queue where storage_path = 'old/audio.m4a') then
    raise exception 'shared path is still needed by younger repeat'; end if;
  if (select audio_path is null from public.blessings where id = v_fresh) then
    raise exception 'unexpired repeat reference must stay'; end if;
  if (select audio_path is null from public.blessing_responses where id = v_recent_response) then
    raise exception 'response must use its own submission date'; end if;
  if (select count(*) from public.media_deletion_queue) <> 3 then
    raise exception 'video, thumbnail and expired response must be queued'; end if;
  perform public.queue_expired_media(100);
  if (select count(*) from public.media_deletion_queue) <> 3 then
    raise exception 'queue retries must be idempotent'; end if;

  begin
    insert into public.blessings(capture_mode, body, audio_path)
    values ('voice', 'Cannot resurrect queued media', 'old/response.m4a');
    raise exception 'queued-media guard did not reject reuse';
  exception when raise_exception then
    if sqlerrm <> 'This media has expired and cannot be reused' then raise; end if;
  end;
  update public.blessings set submitted_at = now() - interval '14 days' where id = v_fresh;
  perform public.queue_expired_media(1);
  if not exists(select 1 from public.media_deletion_queue where storage_path = 'old/audio.m4a') then
    raise exception 'shared bytes must be queued after the final reference expires'; end if;
  if has_function_privilege('anon', 'public.queue_expired_media(integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.queue_expired_media(integer)', 'EXECUTE') then
    raise exception 'clients must not invoke cleanup'; end if;
  if has_table_privilege('authenticated', 'public.media_deletion_queue', 'SELECT') then
    raise exception 'clients must not see the private deletion queue'; end if;
end;
$$;
rollback;
