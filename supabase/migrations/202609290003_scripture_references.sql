alter table public.profiles
  add column bible_version_id text not null default 'web',
  add constraint profiles_bible_version_public_domain check (
    bible_version_id = any (array['web', 'bsb', 'kjv', 'asv', 'ylt', 'dra', 'bbe', 'geneva1599'])
  );

alter table public.blessings
  add column scripture_book_slug text,
  add column scripture_book_name text,
  add column scripture_chapter integer,
  add column scripture_verse_start integer,
  add column scripture_verse_end integer,
  add constraint blessings_scripture_reference_complete check (
    (
      scripture_book_slug is null
      and scripture_book_name is null
      and scripture_chapter is null
      and scripture_verse_start is null
      and scripture_verse_end is null
    )
    or
    (
      char_length(scripture_book_slug) between 2 and 40
      and char_length(scripture_book_name) between 2 and 40
      and scripture_chapter between 1 and 150
      and scripture_verse_start between 1 and 176
      and scripture_verse_end between scripture_verse_start and 176
    )
  );

create or replace function public.update_bible_version(p_version_id text)
returns public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_version_id <> all (array['web', 'bsb', 'kjv', 'asv', 'ylt', 'dra', 'bbe', 'geneva1599']) then
    raise exception 'unsupported Bible version';
  end if;

  update public.profiles
  set bible_version_id = p_version_id
  where id = auth.uid()
  returning * into v_profile;
  return v_profile;
end;
$$;

drop function public.submit_text_blessing(uuid, public.capture_mode, text);
create function public.submit_text_blessing(
  p_prompt_id uuid,
  p_mode public.capture_mode,
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
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_body text := trim(p_body);
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if p_mode not in ('typed', 'voice') then raise exception 'invalid capture mode'; end if;
  if char_length(v_body) not between 1 and 600 then raise exception 'blessing must be 1 to 600 characters'; end if;

  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.prompt_accepts_submission(p_prompt_id, v_user_id, v_submitted_at) then
    raise exception 'response window is closed';
  end if;

  insert into public.blessings (
    prompt_id, author_id, capture_mode, body, submitted_at, is_late,
    scripture_book_slug, scripture_book_name, scripture_chapter,
    scripture_verse_start, scripture_verse_end
  ) values (
    p_prompt_id, v_user_id, p_mode, v_body, v_submitted_at, v_submitted_at >= v_prompt.ends_at,
    p_scripture_book_slug, p_scripture_book_name, p_scripture_chapter,
    p_scripture_verse_start, p_scripture_verse_end
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

drop function public.finalize_video_blessing(uuid, text, text);
create function public.finalize_video_blessing(
  p_prompt_id uuid,
  p_video_path text,
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
  v_submitted_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
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
    prompt_id, author_id, capture_mode, video_path, thumbnail_path, submitted_at, is_late,
    scripture_book_slug, scripture_book_name, scripture_chapter,
    scripture_verse_start, scripture_verse_end
  ) values (
    p_prompt_id, v_user_id, 'video', p_video_path, p_thumbnail_path, v_submitted_at,
    v_submitted_at >= v_prompt.ends_at,
    p_scripture_book_slug, p_scripture_book_name, p_scripture_chapter,
    p_scripture_verse_start, p_scripture_verse_end
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

revoke all on function public.update_bible_version(text) from public, anon;
grant execute on function public.update_bible_version(text) to authenticated;
grant execute on function public.submit_text_blessing(
  uuid, public.capture_mode, text, text, text, integer, integer, integer
) to authenticated;
grant execute on function public.finalize_video_blessing(
  uuid, text, text, text, text, integer, integer, integer
) to authenticated;
