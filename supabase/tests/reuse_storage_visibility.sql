-- Local-only check of the actual Storage SELECT policy, including locked peers.
begin;
set local plpgsql.check_asserts=on;
do $$
declare
  v_author uuid:=gen_random_uuid(); v_peer uuid:=gen_random_uuid();
  v_a public.circles; v_b public.circles; v_pa public.daily_prompts; v_pb public.daily_prompts;
  v_source public.blessings; v_copy public.blessings; v_path text;
begin
  insert into auth.users(id) values(v_author),(v_peer);
  insert into public.profiles(id,display_name) values(v_author,'Author'),(v_peer,'Peer');
  perform set_config('request.jwt.claim.sub',v_author::text,true);
  v_a:=public.create_circle('A','SOURCE7','UTC',time '12:00',time '22:00',10,true,120);
  v_b:=public.create_circle('B','TARGET7','UTC',time '12:00',time '22:00',10,true,120);
  insert into public.circle_members(circle_id,user_id,role) values(v_b.id,v_peer,'member');
  update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes'
    where circle_id=v_a.id and kind='daily' returning * into strict v_pa;
  update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes'
    where circle_id=v_b.id and kind='daily' returning * into strict v_pb;
  v_path:=v_a.id::text||'/'||v_pa.id::text||'/'||v_author::text||'/photo.jpg';
  v_source:=public.submit_text_blessing(v_pa.id,'typed','Photo',null,v_path);
  v_copy:=public.repeat_blessing(v_source.id,v_pb.id);
  insert into storage.objects(bucket_id,name) values('blessing-media',v_path),('avatars',v_path),('blessing-media','not-referenced.jpg');
  perform set_config('request.jwt.claim.sub',v_peer::text,true);
  execute 'set local role authenticated';
  assert (select count(*) from storage.objects)=0;
  perform public.submit_text_blessing(v_pb.id,'typed','Unlock');
  assert (select count(*) from storage.objects)=1;
  assert (select name=v_path from storage.objects);
  execute 'reset role';
end;
$$;
rollback;
