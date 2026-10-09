-- Preserve media without a second upload. Reads follow the receiving blessing,
-- not just the original file's circle/path. Retention already protects live refs.
create or replace function public.repeat_blessing(
  p_source_blessing_id uuid, p_target_prompt_id uuid
) returns public.blessings
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_source public.blessings;
  v_source_circle uuid;
  v_target public.daily_prompts;
  v_minutes integer;
  v_now timestamptz := clock_timestamp();
  v_result public.blessings;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  -- Match the cleanup worker's table-before-row order to serialize path reuse.
  lock table public.blessings in row exclusive mode;
  select * into v_source from public.blessings
    where id = p_source_blessing_id and author_id = v_user for share;
  select circle_id into v_source_circle from public.daily_prompts where id = v_source.prompt_id;
  select * into v_target from public.daily_prompts where id = p_target_prompt_id for update;
  if v_source.id is null or v_target.id is null then raise exception 'blessing or prompt not found'; end if;
  if v_source_circle = v_target.circle_id then raise exception 'source must be from another circle'; end if;
  if v_source.body is null then raise exception 'source blessing has no reusable message'; end if;
  select repeat_window_minutes into v_minutes from public.circles where id = v_target.circle_id;
  if v_now < v_source.submitted_at
    or v_now > v_source.submitted_at + make_interval(mins => v_minutes) then
    raise exception 'repeat window expired';
  end if;
  if not public.prompt_accepts_submission(p_target_prompt_id, v_user, v_now) then
    raise exception 'prompt is not accepting submissions';
  end if;
  if (v_source.capture_mode = 'voice' and v_source.audio_path is null)
    or (v_source.capture_mode = 'video' and v_source.video_path is null) then
    raise exception 'This media has expired and cannot be reused';
  end if;
  insert into public.blessings (
    prompt_id, author_id, capture_mode, body, audio_path, video_path, photo_path, thumbnail_path,
    submitted_at, is_late, scripture_book_slug, scripture_book_name, scripture_chapter,
    scripture_verse_start, scripture_verse_end, repeated_from_blessing_id
  ) values (
    p_target_prompt_id, v_user, v_source.capture_mode, v_source.body,
    v_source.audio_path, v_source.video_path, v_source.photo_path, v_source.thumbnail_path,
    v_now, v_now >= v_target.ends_at, v_source.scripture_book_slug, v_source.scripture_book_name,
    v_source.scripture_chapter, v_source.scripture_verse_start, v_source.scripture_verse_end, v_source.id
  ) returning * into v_result;
  return v_result;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;
revoke all on function public.repeat_blessing(uuid, uuid) from public, anon;
grant execute on function public.repeat_blessing(uuid, uuid) to authenticated;

create function public.can_read_blessing_media(p_path text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.blessings b
    where p_path in (b.audio_path, b.video_path, b.photo_path, b.thumbnail_path)
      and public.can_view_blessing(b.prompt_id, b.author_id)
  );
$$;
revoke all on function public.can_read_blessing_media(text) from public, anon;
grant execute on function public.can_read_blessing_media(text) to authenticated;

drop policy if exists "media reads follow blessing visibility" on storage.objects;
create policy "media reads follow blessing visibility" on storage.objects for select to authenticated
using (
  bucket_id = 'blessing-media' and (
    public.can_view_blessing(
      public.try_uuid((storage.foldername(name))[2]),
      public.try_uuid((storage.foldername(name))[3])
    ) or public.can_read_blessing_media(name)
  )
);
