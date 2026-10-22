-- Deterministic photo previews follow exactly the same visibility as their full photo,
-- including reused blessings whose original circle is no longer accessible.
create or replace function public.can_read_blessing_media(p_path text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.blessings b
    where (p_path in (b.audio_path, b.video_path, b.photo_path, b.thumbnail_path)
      or p_path = b.photo_path || '.preview.jpg')
      and public.can_view_blessing(b.prompt_id, b.author_id)
  );
$$;
revoke all on function public.can_read_blessing_media(text) from public, anon;
grant execute on function public.can_read_blessing_media(text) to authenticated;
