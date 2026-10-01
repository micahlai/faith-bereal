alter table public.blessings
  add column photo_path text;

alter table public.blessings
  drop constraint if exists blessings_capture_payload_valid;

alter table public.blessings
  add constraint blessings_capture_payload_valid check (
    (capture_mode = 'typed' and body is not null and audio_path is null and video_path is null)
    or
    (capture_mode = 'voice' and body is not null and audio_path is not null and video_path is null)
    or
    (capture_mode = 'video' and body is not null and audio_path is null and video_path is not null and photo_path is null)
  );

drop function public.submit_text_blessing(
  uuid, public.capture_mode, text, text, text, text, integer, integer, integer
);

create function public.submit_text_blessing(
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
  if char_length(v_body) not between 1 and 600 then raise exception 'blessing must be 1 to 600 characters'; end if;

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

revoke all on function public.submit_text_blessing(
  uuid, public.capture_mode, text, text, text, text, text, integer, integer, integer
) from public, anon;
grant execute on function public.submit_text_blessing(
  uuid, public.capture_mode, text, text, text, text, text, integer, integer, integer
) to authenticated;
