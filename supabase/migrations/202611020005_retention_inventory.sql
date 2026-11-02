-- Read bounded pages under the caller's existing RLS. Include old parent posts
-- with newer response audio; a prompt-date-only scan misses those recordings.
create function public.retained_blessings_page(p_circle uuid,p_after uuid default null)
returns setof public.blessings language sql stable security invoker set search_path='' as $$
 select b.* from public.blessings b join public.daily_prompts p on p.id=b.prompt_id
 where p.circle_id=p_circle and (p_after is null or b.id>p_after)
 and (b.submitted_at>now()-interval '30 days' or b.audio_path is not null or b.video_path is not null or exists(
   select 1 from public.blessing_responses r where r.blessing_id=b.id
   and r.mode='voice' and r.audio_path is not null))
 order by b.id limit 41;
$$;
revoke all on function public.retained_blessings_page(uuid,uuid) from public,anon;
grant execute on function public.retained_blessings_page(uuid,uuid) to authenticated,service_role;
notify pgrst,'reload schema';
