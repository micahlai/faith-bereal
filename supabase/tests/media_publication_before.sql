set time zone 'UTC';
-- Disposable migration regression. The hosted runner must wrap all three files
-- (before, migration, after) in one ROLLBACK-only transaction.
create table manna_private.publication_test_ids(viewer uuid,circle_id uuid,normal uuid,reported uuid,rejected uuid,blocked uuid,normal_response uuid,hidden_response uuid);
do $$
declare v uuid:=gen_random_uuid(); authors uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()]; c public.circles; p uuid; ids uuid[]:='{}'; b uuid; r1 uuid:=gen_random_uuid();r2 uuid:=gen_random_uuid();i integer;
begin
 insert into auth.users(id,raw_user_meta_data) select x,'{}'::jsonb from unnest(array[v]||authors) x;
 perform set_config('request.jwt.claim.sub',v::text,true);
 c:=public.create_circle('Publication migration fixture',upper(left(replace(v::text,'-',''),8)),'UTC','12:00','22:00',10,true,120,'22:00');
 insert into public.circle_members(circle_id,user_id,role,joined_at) select c.id,x,'member',now()-interval '3 days' from unnest(authors) x;
 insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state) values(c.id,current_date-1,now()-interval '1 day',now()-interval '1 day'+interval '10 minutes',10,'closed') returning id into p;
 for i in 1..4 loop
  insert into public.blessings(prompt_id,author_id,capture_mode,body,photo_path,submitted_at,is_late) values(p,authors[i],'typed','Publication fixture',c.id::text||'/'||p::text||'/'||authors[i]::text||'/photo.jpg',now()-interval '1 day',false) returning id into b;
  ids:=array_append(ids,b);
 end loop;
 insert into public.blessing_responses(id,blessing_id,author_id,mode,body,audio_path,submitted_at) values
 (r1,ids[1],authors[1],'voice','Normal response',c.id::text||'/'||p::text||'/'||authors[1]::text||'/reply.wav',now()),
 (r2,ids[1],authors[2],'voice','Reported response',c.id::text||'/'||p::text||'/'||authors[2]::text||'/reply.wav',now());
 insert into manna_private.content_reports(reporter,blessing_id,reason,status) values(v,ids[2],'other','hidden');
 insert into manna_private.content_reports(reporter,response_id,reason,status) values(v,r2,'other','hidden');
 -- A rejected recording has no pending queue row; keep its explicit hold.
 delete from manna_private.media_review_queue where blessing_id=ids[3];
 insert into manna_private.user_blocks(blocker,blocked) values(v,authors[4]);
 assert not public.can_view_blessing(p,authors[1]),'predecessor did not reproduce hidden posted media';
 insert into manna_private.publication_test_ids values(v,c.id,ids[1],ids[2],ids[3],ids[4],r1,r2);
end $$;
