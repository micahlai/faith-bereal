-- Rollback-only local permission regression. No Edge dispatch or Storage API.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts=on;
create function pg_temp.denied(p_sql text, p_expected text) returns void language plpgsql as $$
begin
  begin execute p_sql; raise exception 'UNEXPECTED SUCCESS';
  exception when others then assert sqlerrm like '%'||p_expected||'%', sqlerrm; end;
end;
$$;
do $$
declare leader uuid:=gen_random_uuid(); member uuid:=gen_random_uuid(); removed uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  c public.circles; other public.circles; path text; oldcode text; n integer; settings_sql text;
begin
  insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@example.invalid','{}'::jsonb
    from unnest(array[leader,member,removed,outsider]) id;
  insert into public.profiles(id,display_name) select id,'Settings fixture' from unnest(array[leader,member,removed,outsider]) id;
  perform set_config('request.jwt.claim.sub',leader::text,true);
  c:=public.create_circle('Shared settings','SETTINGS01','UTC','12:00','20:00',10,true,120,'22:00');
  other:=public.create_circle('Other settings','SETTINGS02','UTC','12:00','20:00',10,true,120,'22:00');
  assert not c.allow_member_circle_changes;
  insert into public.circle_members(circle_id,user_id,role) values(c.id,member,'member'),(c.id,removed,'member');
  path:=c.id::text||'/circle.jpg';
  settings_sql:=format('select public.update_circle_settings(%L::uuid,%L,%L,%L::time,%L::time,15,false,180,%L::time)',
    c.id,'Renamed','America/New_York','10:00','18:00','21:00');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',member::text,true);
  assert not public.can_manage_circle(c.id);
  perform pg_temp.denied(settings_sql,'authorized member required');
  perform pg_temp.denied(format('select public.update_circle_photo(%L::uuid,%L)',c.id,path),'authorized member required');
  perform pg_temp.denied(format('select public.regenerate_circle_invite_code(%L::uuid,%L)',c.id,'ROTATE001'),'authorized member required');
  perform pg_temp.denied(format('select public.force_circle_prompt(%L::uuid)',c.id),'authorized member required');
  perform pg_temp.denied(format('select public.remove_circle_member(%L::uuid,%L::uuid)',c.id,removed),'authorized member required');
  perform pg_temp.denied(format('insert into storage.objects values(%L,%L)', 'circle-photos',path),'row-level security');
  perform pg_temp.denied(format('select public.set_circle_member_changes(%L::uuid,true)',c.id),'owner required');

  perform set_config('request.jwt.claim.sub',leader::text,true);
  c:=public.set_circle_member_changes(c.id,true);
  assert c.allow_member_circle_changes;
  perform set_config('request.jwt.claim.sub',member::text,true);
  assert public.can_manage_circle(c.id);
  execute settings_sql;
  c:=public.update_circle_settings(c.id,'Renamed again','UTC','09:00','19:00',20,true,60);
  assert c.name='Renamed again' and c.allow_member_circle_changes and c.owner_id=leader;
  perform public.regenerate_circle_invite_code(c.id,'ROTATE001');
  assert public.circle_invite_code(c.id)='ROTATE001';
  perform public.update_circle_photo(c.id,path);
  insert into storage.objects values('circle-photos',path);
  update storage.objects set name=path where bucket_id='circle-photos' and name=path;
  get diagnostics n=row_count; assert n=1;
  perform pg_temp.denied(format('insert into storage.objects values(%L,%L)', 'circle-photos',c.id::text||'/other.jpg'),'row-level security');
  perform pg_temp.denied(format('insert into storage.objects values(%L,%L)', 'circle-photos',other.id::text||'/circle.jpg'),'row-level security');
  perform pg_temp.denied(format('select public.update_circle_photo(%L::uuid,%L)',c.id,other.id::text||'/circle.jpg'),'invalid circle photo path');
  delete from storage.objects where bucket_id='circle-photos' and name=path;
  get diagnostics n=row_count; assert n=1;
  insert into storage.objects values('circle-photos',path);
  perform public.update_circle_photo(c.id,null);
  perform public.force_circle_prompt(c.id);
  perform public.remove_circle_member(c.id,removed);
  perform pg_temp.denied(format('select public.remove_circle_member(%L::uuid,%L::uuid)',c.id,leader),'owner cannot be removed');
  perform pg_temp.denied(format('select public.remove_circle_member(%L::uuid,%L::uuid)',c.id,member),'use leave circle');
  perform pg_temp.denied(format('select public.set_circle_member_changes(%L::uuid,false)',c.id),'owner required');
  perform pg_temp.denied(format('select public.transfer_circle_ownership(%L::uuid,%L::uuid)',c.id,member),'owner required');
  perform pg_temp.denied(format('update public.circles set allow_member_circle_changes=false where id=%L::uuid',c.id),'permission denied');

  -- Removed members and outsiders have no delegated powers, even while on.
  foreach removed in array array[removed,outsider] loop
    perform set_config('request.jwt.claim.sub',removed::text,true);
    assert not public.can_manage_circle(c.id);
    perform pg_temp.denied(settings_sql,'authorized member required');
    perform pg_temp.denied(format('select public.regenerate_circle_invite_code(%L::uuid,%L)',c.id,'ROTATE002'),'authorized member required');
    perform pg_temp.denied(format('select public.force_circle_prompt(%L::uuid)',c.id),'authorized member required');
    perform pg_temp.denied(format('insert into storage.objects values(%L,%L)', 'circle-photos',path),'row-level security');
  end loop;
  perform set_config('request.jwt.claim.sub',leader::text,true);
  c:=public.set_circle_member_changes(c.id,false);
  assert not c.allow_member_circle_changes;
  perform set_config('request.jwt.claim.sub',member::text,true);
  perform pg_temp.denied(settings_sql,'authorized member required');
  perform pg_temp.denied(format('select public.update_circle_photo(%L::uuid,%L)',c.id,path),'authorized member required');
  perform pg_temp.denied(format('select public.regenerate_circle_invite_code(%L::uuid,%L)',c.id,'ROTATE002'),'authorized member required');
  perform pg_temp.denied(format('select public.force_circle_prompt(%L::uuid)',c.id),'authorized member required');
  delete from storage.objects where bucket_id='circle-photos' and name=path;
  get diagnostics n=row_count; assert n=0;
  update storage.objects set name=path where bucket_id='circle-photos' and name=path;
  get diagnostics n=row_count; assert n=0;
  perform set_config('request.jwt.claim.sub',leader::text,true);
  perform public.update_circle_photo(c.id,path);
  perform public.transfer_circle_ownership(c.id,member);
  perform pg_temp.denied(format('select public.set_circle_member_changes(%L::uuid,true)',c.id),'owner required');
  perform set_config('request.jwt.claim.sub',member::text,true);
  c:=public.set_circle_member_changes(c.id,true);
  assert c.owner_id=member;
  execute 'reset role';
  assert not has_function_privilege('anon','public.set_circle_member_changes(uuid,boolean)','execute');
  assert not has_function_privilege('anon','public.can_manage_circle(uuid)','execute');
  assert not has_function_privilege('anon','public.update_circle_settings(uuid,text,text,time,time,integer,boolean,integer,time)','execute');
  assert not has_function_privilege('anon','public.update_circle_photo(uuid,text)','execute');
  assert not has_function_privilege('anon','public.force_circle_prompt(uuid)','execute');
  assert not has_function_privilege('anon','public.remove_circle_member(uuid,uuid)','execute');
  assert not has_function_privilege('anon','public.regenerate_circle_invite_code(uuid,text)','execute');
  assert not has_function_privilege('authenticated','manna_private.regenerate_circle_invite_code(uuid,text)','execute');
end;
$$;
rollback;
