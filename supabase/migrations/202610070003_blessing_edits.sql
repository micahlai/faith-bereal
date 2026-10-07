alter table public.blessings
  add column if not exists edited_at timestamptz;

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
  if char_length(v_body) not between 1 and 600 then
    raise exception 'blessing must be 1 to 600 characters';
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

revoke all on function public.update_blessing(uuid, text, text, text, integer, integer, integer)
from public, anon;
grant execute on function public.update_blessing(uuid, text, text, text, integer, integer, integer)
to authenticated;

comment on column public.blessings.edited_at is
  'Last server-authored edit time. Content may only change during the global ten-minute post-submit window.';
comment on function public.update_blessing(uuid, text, text, text, integer, integer, integer) is
  'Edits only the author-owned text/transcript and optional scripture tag within ten minutes of submission.';
