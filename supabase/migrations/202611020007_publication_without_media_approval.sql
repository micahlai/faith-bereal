-- Private circle media publishes under the normal membership/submission gates.
-- Reporting, mutual blocks, suspensions and explicit moderation holds remain.
drop trigger queue_blessing_media_review on public.blessings;
drop trigger queue_response_media_review on public.blessing_responses;

-- Release only automatic pending-review holds. Rejected media has no pending
-- queue row and is deliberately untouched; explicit report holds also remain.
delete from manna_private.hidden_content h
where exists(select 1 from manna_private.media_review_queue q where q.blessing_id=h.blessing_id)
 and not exists(select 1 from manna_private.content_reports r where r.blessing_id=h.blessing_id and r.status='hidden');
delete from manna_private.hidden_responses h
where exists(select 1 from manna_private.media_review_queue q where q.response_id=h.response_id)
 and not exists(select 1 from manna_private.content_reports r where r.response_id=h.response_id and r.status='hidden');
delete from manna_private.media_review_queue;

create or replace function public.can_view_blessing(p_prompt_id uuid,p_author_id uuid,p_viewer_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author_id,p_viewer_id)
 and not exists(select 1 from public.blessings b join manna_private.hidden_content h on h.blessing_id=b.id where b.prompt_id=p_prompt_id and b.author_id=p_author_id)
 and manna_private.can_view_blessing_before_safety(p_prompt_id,p_author_id,p_viewer_id);
$$;
create or replace function public.response_is_safe(p_id uuid,p_author uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author)
 and not exists(select 1 from manna_private.hidden_responses h where h.response_id=p_id);
$$;
notify pgrst,'reload schema';
