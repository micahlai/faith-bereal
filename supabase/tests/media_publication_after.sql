set time zone 'UTC';
do $$
declare f manna_private.publication_test_ids; p uuid;a uuid; current_prompt uuid; authors uuid[]; outsider uuid:=gen_random_uuid();
begin
 select * into strict f from manna_private.publication_test_ids;
 perform set_config('request.jwt.claim.sub',f.viewer::text,true);
 select prompt_id,author_id into p,a from public.blessings where id=f.normal;
 assert public.can_view_blessing(p,a),'automatic-only hold not released';
 assert not exists(select 1 from manna_private.hidden_content where blessing_id=f.normal);
 assert exists(select 1 from manna_private.hidden_content where blessing_id=f.reported),'independent report hold erased';
 assert exists(select 1 from manna_private.hidden_content where blessing_id=f.rejected),'rejected media silently published';
 assert not public.can_view_blessing(p,(select author_id from public.blessings where id=f.blocked)),'block bypassed';
 assert public.response_is_safe(f.normal_response,a),'ordinary response not released';
 assert not public.response_is_safe(f.hidden_response,(select author_id from public.blessing_responses where id=f.hidden_response)),'reported response leaked';
 assert not exists(select 1 from manna_private.media_review_queue),'blanket review still queued';
 update public.blessings set photo_path=replace(photo_path,'photo.jpg','new.jpg') where id=f.normal;
 assert public.can_view_blessing(p,a),'replacement media hidden automatically';
 assert not exists(select 1 from manna_private.media_review_queue),'replacement still queued';
 -- Current peer posts still require the viewer's own submission.
 insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state) values(f.circle_id,current_date,now()-interval '1 minute',now()+interval '9 minutes',10,'open') on conflict(circle_id,local_date,kind) do update set starts_at=excluded.starts_at,ends_at=excluded.ends_at,state=excluded.state returning id into current_prompt;
 insert into public.blessings(prompt_id,author_id,capture_mode,body,audio_path,submitted_at,is_late) values(current_prompt,a,'voice','Current voice',f.circle_id::text||'/'||current_prompt::text||'/'||a::text||'/current.wav',now(),false);
 assert not public.can_view_blessing(current_prompt,a),'current-day submission gate bypassed';
 insert into public.blessings(prompt_id,author_id,capture_mode,body,submitted_at,is_late) values(current_prompt,f.viewer,'typed','Viewer shares',now(),false);
 assert public.can_view_blessing(current_prompt,a),'current media remained hidden after viewer shared';
 execute 'set local role authenticated';
 assert (select count(*)=1 from public.blessings where id=f.normal),'member RLS did not publish media';
 assert (select count(*)=0 from public.blessings where id in(f.reported,f.rejected,f.blocked)),'member RLS exposed withheld/blocked media';
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 assert not public.can_view_blessing(p,a),'outsider saw private media';
 perform set_config('request.jwt.claim.sub','',true);
 select array_agg(user_id) into authors from public.circle_members where circle_id=f.circle_id;
 delete from public.circles where id=f.circle_id;
 delete from auth.users where id=any(authors);
end $$;
drop table manna_private.publication_test_ids;
