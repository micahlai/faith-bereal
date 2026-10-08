-- Keep history, remove only audio/video bytes through the Storage API.
-- No historical cleanup is executed by installing this migration.
alter table public.blessings add column media_expired_at timestamptz;
alter table public.blessing_responses add column media_expired_at timestamptz;

alter table public.blessings drop constraint blessings_capture_payload_valid;
alter table public.blessings add constraint blessings_capture_payload_valid check (
  (capture_mode = 'typed' and body is not null and audio_path is null and video_path is null)
  or (capture_mode = 'voice' and body is not null and video_path is null
    and (audio_path is not null or media_expired_at is not null))
  or (capture_mode = 'video' and body is not null and audio_path is null and photo_path is null
    and (video_path is not null or media_expired_at is not null))
);
alter table public.blessing_responses drop constraint blessing_responses_check;
alter table public.blessing_responses add constraint blessing_responses_check check (
  (mode = 'typed' and audio_path is null)
  or (mode = 'voice' and (audio_path is not null or media_expired_at is not null))
);

create table public.media_deletion_queue (
  storage_path text primary key,
  queued_at timestamptz not null default now()
);
alter table public.media_deletion_queue enable row level security;
revoke all on public.media_deletion_queue from anon, authenticated;
grant all on public.media_deletion_queue to service_role;

-- A repeat must never reattach a path that a cleanup worker has queued.
create function public.reject_queued_media_reference() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.media_deletion_queue q
    where q.storage_path = new.audio_path
      or (tg_table_name = 'blessings' and q.storage_path = (to_jsonb(new)->>'video_path'))
      or (tg_table_name = 'blessings' and q.storage_path = (to_jsonb(new)->>'thumbnail_path'))
  ) then raise exception 'This media has expired and cannot be reused'; end if;
  return new;
end;
$$;
create trigger reject_expired_blessing_media before insert or update on public.blessings
for each row execute function public.reject_queued_media_reference();
create trigger reject_expired_response_media before insert or update on public.blessing_responses
for each row execute function public.reject_queued_media_reference();

create function public.queue_expired_media(p_limit integer default 100)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_paths text[] := '{}';
  v_added text[];
  v_count integer;
  v_blessing_ids uuid[];
  v_response_ids uuid[];
begin
  if p_limit < 1 or p_limit > 1000 then raise exception 'invalid batch size'; end if;
  -- Serialize reference checks with new posts/repeats; a queued path cannot be
  -- resurrected after commit because the reference triggers check the queue.
  lock table public.blessings, public.blessing_responses in share row exclusive mode;
  select array_agg(id) into v_blessing_ids from (
    select id from public.blessings
    where submitted_at <= now() - interval '14 days'
      and (audio_path is not null or video_path is not null or thumbnail_path is not null)
    order by submitted_at limit p_limit for update
  ) expired;
  with old_paths as (
    select b.audio_path, b.video_path, b.thumbnail_path from public.blessings b where id = any(v_blessing_ids)
  )
  select array_agg(path) into v_added from old_paths,
    lateral unnest(array[audio_path, video_path, thumbnail_path]) path where path is not null;
  v_paths := coalesce(v_added, '{}');
  update public.blessings set audio_path = null, video_path = null,
    thumbnail_path = null, media_expired_at = now()
  where id = any(v_blessing_ids);

  select array_agg(id) into v_response_ids from (
    select id from public.blessing_responses
    where submitted_at <= now() - interval '14 days' and audio_path is not null
    order by submitted_at limit p_limit for update
  ) expired;
  select array_agg(r.audio_path) into v_added
    from public.blessing_responses r where id = any(v_response_ids);
  v_paths := v_paths || coalesce(v_added, '{}');
  update public.blessing_responses set audio_path = null, media_expired_at = now()
  where id = any(v_response_ids);

  insert into public.media_deletion_queue(storage_path)
  select distinct path from unnest(v_paths) path
  where not exists (select 1 from public.blessings b
    where b.audio_path = path or b.video_path = path or b.thumbnail_path = path or b.photo_path = path)
    and not exists (select 1 from public.blessing_responses r where r.audio_path = path)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.queue_expired_media(integer) from public, anon, authenticated;
grant execute on function public.queue_expired_media(integer) to service_role;
revoke all on function public.reject_queued_media_reference() from public, anon, authenticated;

create index blessings_media_retention_idx on public.blessings(submitted_at)
  where audio_path is not null or video_path is not null or thumbnail_path is not null;
create index response_media_retention_idx on public.blessing_responses(submitted_at) where audio_path is not null;
