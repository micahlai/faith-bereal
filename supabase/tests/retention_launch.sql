-- Isolated full-chain fixture only. All rows and physical-delete simulations roll back.
begin;
set local time zone 'UTC';
do $$
declare viewer uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); c public.circles;
 p uuid; b uuid; old_parent uuid; cursor_id uuid; n integer; path text; photo text; review uuid;
begin
 insert into auth.users(id,raw_user_meta_data) values(viewer,'{}'),(outsider,'{}');
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 c:=public.create_circle('Retention fixture',upper(left(replace(viewer::text,'-',''),8)),'UTC','12:00','22:00',10,true,120,'22:00');
 for i in 1..44 loop
  insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state)
   values(c.id,current_date-i-40,now()-(i+40)*interval '1 day',now()-(i+40)*interval '1 day'+interval '10 minutes',10,'closed') returning id into p;
  insert into public.blessings(prompt_id,author_id,capture_mode,body,submitted_at,is_late)
   values(p,viewer,'typed','History',now()-interval '28 days',false) returning id into b;
 end loop;
 update public.blessings set submitted_at=now()-interval '50 days' where id=b;
 old_parent:=b;
 path:=c.id::text||'/'||p::text||'/'||viewer::text||'/response.m4a';
 insert into public.blessing_responses(blessing_id,author_id,mode,body,audio_path,submitted_at)
  values(old_parent,viewer,'voice','Newer voice response',path,now()-interval '28 days');
 execute 'set local role authenticated';
 select count(*) into n from public.retained_blessings_page(c.id,null);
 assert n=41,'inventory page was incomplete or unbounded';
 select id into cursor_id from public.retained_blessings_page(c.id,null) order by id offset 39 limit 1;
 select count(*) into n from public.retained_blessings_page(c.id,cursor_id);
 assert n=4,'keyset skipped or repeated a blessing';
 execute 'reset role';
 -- The old parent is included through its newer response, with no 7-day prompt filter.
 assert exists(select 1 from public.retained_blessings_page(c.id,null) where id=old_parent)
  or exists(select 1 from public.retained_blessings_page(c.id,cursor_id) where id=old_parent);
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 execute 'set local role authenticated';
 assert (select count(*)=0 from public.retained_blessings_page(c.id,null)),'outsider inventory leaked';
 assert not has_function_privilege('authenticated','public.acknowledge_media_deletions(text[])','execute');
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 -- Cleanup of a recording must preserve an approved photo's visibility.
 photo:=c.id::text||'/'||p::text||'/'||viewer::text||'/photo.jpg';
 update public.blessings set photo_path=photo where id=old_parent;
 assert not exists(select 1 from manna_private.media_review_queue where blessing_id=old_parent);
 update public.blessings set media_expired_at=now(),audio_path=null,video_path=null where id=old_parent;
 assert not exists(select 1 from manna_private.media_review_queue where blessing_id=old_parent),'unchanged photo was requeued';
 assert (select photo_path=photo and body='History' from public.blessings where id=old_parent);
 -- Acknowledge only after source AND all R2 generations have disappeared.
 insert into storage.objects(bucket_id,name,owner_id) values('blessing-media',path,viewer::text);
 insert into public.media_deletion_queue(storage_path) values(path);
 assert public.acknowledge_media_deletions(array[path])=0,'source existence ignored';
 delete from storage.objects where bucket_id='blessing-media' and name=path;
 assert public.acknowledge_media_deletions(array[path])=0,'unfinished R2 removal ignored';
 update manna_private.storage_mirror_jobs set desired=false,state='deleted' where object_name=path;
 assert public.acknowledge_media_deletions(array[path])=1,'completed removal was not acknowledged';
 assert public.acknowledge_media_deletions(array[path])=0,'acknowledgement was not idempotent';
end $$;
rollback;
