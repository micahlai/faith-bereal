-- Widen blessing text/transcripts only; response limits stay at 600.
-- Existing submission, entry, media ownership, duplicate and edit guards remain.
alter table public.blessings drop constraint blessings_body_check;
alter table public.blessings add constraint blessings_body_length_valid
  check (body is null or char_length(body) between 1 and 1200);

create or replace function public.submit_text_blessing(
  p_prompt_id uuid,
  p_mode public.capture_mode,
  p_body text,
  p_audio_path text default null,
  p_photo_path text default null,
  p_scripture_book_slug text default null,
  p_scripture_book_name text default null,
  p_scripture_chapter integer default null,
  p_scripture_verse_start integer default null,
  p_scripture_verse_end integer default null
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_body text := trim(p_body);
  v_expected_prefix text;
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if p_mode not in ('typed', 'voice') then raise exception 'invalid capture mode'; end if;
  if v_body is null or char_length(v_body) not between 1 and 1200 then raise exception 'blessing must be 1 to 1200 characters'; end if;

  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.prompt_accepts_submission(p_prompt_id, v_user_id, v_submitted_at) then
    raise exception 'response window is closed';
  end if;

  v_expected_prefix := v_prompt.circle_id::text || '/' || p_prompt_id::text || '/' || v_user_id::text || '/';
  if p_mode = 'typed' and p_audio_path is not null then raise exception 'typed blessings cannot include audio'; end if;
  if p_mode = 'voice' and (p_audio_path is null or p_audio_path not like v_expected_prefix || '%') then
    raise exception 'invalid audio path';
  end if;
  if p_photo_path is not null and p_photo_path not like v_expected_prefix || '%' then
    raise exception 'invalid photo path';
  end if;

  insert into public.blessings (
    prompt_id, author_id, capture_mode, body, audio_path, photo_path, submitted_at, is_late,
    scripture_book_slug, scripture_book_name, scripture_chapter,
    scripture_verse_start, scripture_verse_end
  ) values (
    p_prompt_id, v_user_id, p_mode, v_body, p_audio_path, p_photo_path, v_submitted_at,
    v_submitted_at >= v_prompt.ends_at,
    p_scripture_book_slug, p_scripture_book_name, p_scripture_chapter,
    p_scripture_verse_start, p_scripture_verse_end
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

create or replace function public.finalize_video_blessing(
  p_prompt_id uuid,
  p_video_path text,
  p_transcript text,
  p_thumbnail_path text default null,
  p_scripture_book_slug text default null,
  p_scripture_book_name text default null,
  p_scripture_chapter integer default null,
  p_scripture_verse_start integer default null,
  p_scripture_verse_end integer default null
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_expected_prefix text;
  v_transcript text := trim(p_transcript);
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if v_transcript is null or char_length(v_transcript) not between 1 and 1200 then
    raise exception 'transcript must be 1 to 1200 characters';
  end if;
  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.prompt_accepts_submission(p_prompt_id, v_user_id, v_submitted_at) then
    raise exception 'response window is closed';
  end if;

  v_expected_prefix := v_prompt.circle_id::text || '/' || p_prompt_id::text || '/' || v_user_id::text || '/';
  if p_video_path not like v_expected_prefix || '%' then raise exception 'invalid video path'; end if;
  if p_thumbnail_path is not null and p_thumbnail_path not like v_expected_prefix || '%' then
    raise exception 'invalid thumbnail path';
  end if;

  insert into public.blessings (
    prompt_id, author_id, capture_mode, body, video_path, thumbnail_path, submitted_at, is_late,
    scripture_book_slug, scripture_book_name, scripture_chapter,
    scripture_verse_start, scripture_verse_end
  ) values (
    p_prompt_id, v_user_id, 'video', v_transcript, p_video_path, p_thumbnail_path,
    v_submitted_at, v_submitted_at >= v_prompt.ends_at,
    p_scripture_book_slug, p_scripture_book_name, p_scripture_chapter,
    p_scripture_verse_start, p_scripture_verse_end
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

create or replace function public.update_blessing(
  p_blessing_id uuid,
  p_body text,
  p_scripture_book_slug text default null,
  p_scripture_book_name text default null,
  p_scripture_chapter integer default null,
  p_scripture_verse_start integer default null,
  p_scripture_verse_end integer default null
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_body text := trim(p_body);
  v_existing public.blessings;
  v_updated public.blessings;
  v_has_any_reference boolean;
  v_has_complete_reference boolean;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if v_body is null or char_length(v_body) not between 1 and 1200 then
    raise exception 'blessing must be 1 to 1200 characters';
  end if;

  select * into v_existing
  from public.blessings
  where id = p_blessing_id
  for update;

  if v_existing.id is null then raise exception 'blessing not found'; end if;
  if v_existing.author_id <> v_user_id then raise exception 'not blessing author'; end if;
  if v_now >= v_existing.submitted_at + interval '10 minutes' then
    raise exception 'blessing edit window closed';
  end if;

  v_has_any_reference := p_scripture_book_slug is not null
    or p_scripture_book_name is not null
    or p_scripture_chapter is not null
    or p_scripture_verse_start is not null
    or p_scripture_verse_end is not null;
  v_has_complete_reference := p_scripture_book_slug is not null
    and p_scripture_book_name is not null
    and p_scripture_chapter is not null
    and p_scripture_verse_start is not null
    and p_scripture_verse_end is not null;

  if v_has_any_reference and not v_has_complete_reference then
    raise exception 'incomplete scripture reference';
  end if;
  if v_has_complete_reference and (
    p_scripture_chapter < 1
    or p_scripture_verse_start < 1
    or p_scripture_verse_end < p_scripture_verse_start
  ) then
    raise exception 'invalid scripture reference';
  end if;

  update public.blessings
  set
    body = v_body,
    scripture_book_slug = p_scripture_book_slug,
    scripture_book_name = p_scripture_book_name,
    scripture_chapter = p_scripture_chapter,
    scripture_verse_start = p_scripture_verse_start,
    scripture_verse_end = p_scripture_verse_end,
    edited_at = v_now
  where id = p_blessing_id
  returning * into v_updated;

  return v_updated;
end;
$$;

revoke all on function public.submit_text_blessing(uuid, public.capture_mode, text, text, text, text, text, integer, integer, integer) from public, anon;
grant execute on function public.submit_text_blessing(uuid, public.capture_mode, text, text, text, text, text, integer, integer, integer) to authenticated;

revoke all on function public.finalize_video_blessing(uuid, text, text, text, text, text, integer, integer, integer) from public, anon;
grant execute on function public.finalize_video_blessing(uuid, text, text, text, text, text, integer, integer, integer) to authenticated;

revoke all on function public.update_blessing(uuid, text, text, text, integer, integer, integer) from public, anon;
grant execute on function public.update_blessing(uuid, text, text, text, integer, integer, integer) to authenticated;

