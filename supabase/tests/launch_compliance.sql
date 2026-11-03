begin;
set local time zone 'UTC';
do $$
declare viewer uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); c public.circles; p public.daily_prompts; b uuid; response uuid; report uuid; review uuid; denied boolean;
begin
 insert into auth.users(id,raw_user_meta_data) values(viewer,'{}'),(peer,'{}'),(outsider,'{}');
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 c:=public.create_circle('Safety fixture',upper(left(replace(viewer::text,'-',''),8)),'UTC','12:00','22:00',10,true,120,'22:00');
 insert into public.circle_members(circle_id,user_id,role,joined_at) values(c.id,peer,'member',now()-interval '2 days');
 update public.circle_members set joined_at=now()-interval '3 days' where circle_id=c.id;
 insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state) values(c.id,current_date-1,now()-interval '1 day',now()-interval '1 day'+interval '10 minutes',10,'closed') returning * into p;
 insert into public.blessings(prompt_id,author_id,capture_mode,body,submitted_at,is_late) values(p.id,peer,'typed','A safe message',now()-interval '1 day',false) returning id into b;
 insert into public.blessing_responses(blessing_id,author_id,mode,body) values(b,peer,'typed','A response') returning id into response;
 assert public.can_view_blessing(p.id,peer);
 execute 'set local role authenticated';
 assert (select count(*)=1 from public.blessings where id=b);
 report:=public.report_content(b,null,'harassment','Please review');
 assert report is not null;
 perform public.set_user_block(peer,true);
 assert not public.can_view_blessing(p.id,peer);
 assert (select count(*)=0 from public.blessings where id=b);
 assert (select count(*)=0 from public.blessing_responses where id=response);
 assert (select count(*)=1 from public.my_blocked_users());
 perform public.set_user_block(peer,false);
 assert public.can_view_blessing(p.id,peer);
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 denied:=false;
 begin perform public.report_content(b,null,'other',''); exception when others then denied:=true; end;
 assert denied,'outsider reported inaccessible content';
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.resolve_content_report(report,'hide');exception when insufficient_privilege then denied:=true;end;
 assert denied,'client moderated content';
 execute 'reset role';
 perform public.resolve_content_report(report,'hide');
 assert not public.can_view_blessing(p.id,peer),'hidden content visible';
 denied:=false;begin insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late) values(p.id,viewer,'typed','kill yourself',false);exception when sqlstate '22023' then denied:=true;end;
 assert denied,'text filter bypassed';
 -- Adding media does not introduce another hold or undo an explicit hide.
 perform set_config('request.jwt.claim.sub',peer::text,true);
 update public.blessings set photo_path=c.id::text||'/'||p.id::text||'/'||peer::text||'/fixture.jpg' where id=b;
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 assert not public.can_view_blessing(p.id,peer),'media replacement undid report hold';
 assert not exists(select 1 from manna_private.media_review_queue where blessing_id=b),'new media queued for mandatory approval';
 -- Explicit service-only fixture restoration; dismissing a report alone does not unhide.
 update manna_private.content_reports set status='dismissed' where id=report;
 delete from manna_private.hidden_content where blessing_id=b;
 assert public.can_view_blessing(p.id,peer),'ordinary media stayed hidden';
 -- Own account deletion must transfer ownership, remove authored content, block
 -- old sessions and future uploads, and wait for both stores before readiness.
 insert into storage.objects(bucket_id,name,version,owner_id) values('avatars',viewer::text||'/avatar.jpg','1',viewer::text);
 perform set_config('request.jwt.claim.sub','',true);
 execute 'set local role service_role';
 perform public.request_account_deletion(viewer,true,repeat('a',64));
 assert not public.account_deletion_ready(viewer),'source media not considered';
 execute 'reset role';
 assert (select owner_id=peer from public.circles where id=c.id);
 assert not public.account_is_active(viewer);
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 denied:=false;begin update public.profiles set display_name='Bypass' where id=viewer;exception when others then denied:=true;end;
 assert denied,'deleted identity mutated through RPC';
 denied:=false;begin insert into storage.objects(bucket_id,name,owner_id) values('avatars',viewer::text||'/late.jpg',viewer::text);exception when insufficient_privilege then denied:=true;end;
 assert denied,'late upload recreated media';
 perform set_config('request.jwt.claim.sub','',true);
 -- Local metadata-only fixture simulates Storage deletion. Hosted acceptance
 -- must use the real API and check physical source/R2 absence separately.
 delete from storage.objects where bucket_id='avatars' and name=viewer::text||'/avatar.jpg';
 assert not public.account_deletion_ready(viewer),'unfinished R2 deletion ignored';
 update manna_private.storage_mirror_jobs set state='deleted',desired=false where bucket_id='avatars' and object_name=viewer::text||'/avatar.jpg';
 assert public.account_deletion_ready(viewer);
 assert public.verify_account_deletion_cleanup(viewer);
 assert public.account_deletion_receipt_status(repeat('a',64))='pending';
 delete from auth.users where id=viewer;
 assert exists(select 1 from public.pending_account_deletions() where user_id=viewer),'lost completion recovery';
 perform public.finish_account_deletion_receipt(viewer);
 assert public.account_deletion_receipt_status(repeat('a',64))='completed';
 assert public.account_deletion_receipt_status(repeat('b',64))='unknown';
 assert not exists(select 1 from public.profiles where id=viewer);
 assert not has_function_privilege('authenticated','public.request_account_deletion(uuid,boolean,text)','execute');
 assert not has_table_privilege('authenticated','manna_private.content_reports','select');
end $$;
rollback;
