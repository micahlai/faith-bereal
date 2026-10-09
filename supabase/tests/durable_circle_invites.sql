-- All fixtures, codes, scheduling, and queue events roll back. No rotation of real circles.
begin;
set local plpgsql.check_asserts=on;
do $$
declare
  v_owner uuid:=gen_random_uuid(); v_peer uuid:=gen_random_uuid(); v_other uuid:=gen_random_uuid();
  v_circle public.circles; v_result public.circles; v_code text;
  v_hash text; v_joined timestamptz; v_error text;
begin
  insert into auth.users(id,email,raw_user_meta_data)
    select id,id::text||'@example.invalid','{"name":"Invite regression"}'::jsonb from unnest(array[v_owner,v_peer,v_other]) id;
  insert into public.profiles(id,display_name) values(v_owner,'Invite regression'),(v_peer,'Invite peer'),(v_other,'Outsider')
    on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  execute 'set local role authenticated';
  v_code:=upper(left(replace(gen_random_uuid()::text,'-',''),10));
  v_circle:=public.create_circle('Temporary invite regression',v_code,'UTC',time '12:00',time '22:00',10,true,120);
  assert public.circle_invite_code(v_circle.id)=v_code;
  assert public.circle_invite_code(v_circle.id,'WRONG7')=v_code;
  execute 'reset role';
  v_hash:=v_circle.invite_code_hash;
  -- Simulate a legacy hash-only circle. Never generate a new code to recover it.
  delete from manna_private.circle_invite_codes where circle_id=v_circle.id;
  execute 'set local role authenticated';
  assert public.circle_invite_code(v_circle.id) is null;
  assert public.circle_invite_code(v_circle.id,'WRONG7') is null;
  assert public.circle_invite_code(v_circle.id,lower(v_code))=v_code;
  perform set_config('request.jwt.claim.sub',v_other::text,true);
  begin
    perform public.circle_invite_code(v_circle.id,v_code);
    raise exception 'outsider recovered code';
  exception when others then get stacked diagnostics v_error=message_text; assert v_error='circle membership required',v_error; end;
  perform set_config('request.jwt.claim.sub',v_peer::text,true);
  v_result:=public.join_circle(lower(v_code));
  assert v_result.id=v_circle.id;
  assert public.circle_invite_code(v_circle.id)=v_code;
  begin
    perform public.regenerate_circle_invite_code(v_circle.id,'NEW123');
    raise exception 'non-owner rotated';
  exception when others then get stacked diagnostics v_error=message_text; assert v_error='circle not found or owner required',v_error; end;
  execute 'reset role';
  assert (select invite_code_hash=v_hash from public.circles where id=v_circle.id);
  select joined_at into v_joined from public.circle_members where circle_id=v_circle.id and user_id=v_peer;
  execute 'set local role authenticated';
  perform public.join_circle(v_code);
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  v_result:=public.regenerate_circle_invite_code(v_circle.id,'NEW123');
  assert public.circle_invite_code(v_circle.id,v_code)='NEW123';
  perform set_config('request.jwt.claim.sub',v_peer::text,true);
  assert public.circle_invite_code(v_circle.id)='NEW123';
  begin
    perform public.join_circle(v_code);
    raise exception 'old code accepted';
  exception when others then get stacked diagnostics v_error=message_text; assert v_error='invalid invite code',v_error; end;
  execute 'reset role';
  assert (select joined_at=v_joined from public.circle_members where circle_id=v_circle.id and user_id=v_peer);
  update public.circle_members set removed_at=now() where circle_id=v_circle.id and user_id=v_peer;
  execute 'set local role authenticated';
  begin
    perform public.circle_invite_code(v_circle.id);
    raise exception 'removed member recovered code';
  exception when others then get stacked diagnostics v_error=message_text; assert v_error='circle membership required',v_error; end;
  execute 'reset role';
  assert not has_function_privilege('anon','public.circle_invite_code(uuid,text)','execute');
  assert not has_schema_privilege('authenticated','manna_private','usage');
  assert not has_table_privilege('authenticated','manna_private.circle_invite_codes','select');
end;
$$;
rollback;
