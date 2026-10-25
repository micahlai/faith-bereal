-- Hosted-safe rollback-only check: random accounts and registrations, no pushes.
begin;
set local lock_timeout='2s';
set local statement_timeout='15s';
set local plpgsql.check_asserts=on;

do $$
declare
  u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); installation uuid:=gen_random_uuid();
  r public.device_registrations; rejected boolean;
begin
  assert has_function_privilege('authenticated','public.register_device(uuid,text,text,public.push_environment)','execute');
  assert not has_function_privilege('anon','public.register_device(uuid,text,text,public.push_environment)','execute');
  assert (select pronargdefaults=3 from pg_proc where oid='public.register_device(uuid,text,text,public.push_environment)'::regprocedure);
  insert into auth.users(id,raw_user_meta_data) values
    (u,'{"full_name":"Synthetic registration check"}'),
    (other_user,'{"full_name":"Synthetic registration isolation"}');
  insert into public.profiles(id,display_name) values
    (u,'Synthetic registration check'),(other_user,'Synthetic registration isolation')
    on conflict(id) do nothing;
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';

  -- A build which omits either not-yet-delivered token must resolve by name.
  r:=public.register_device(p_installation_id=>installation,p_apns_token=>'synthetic-apns',p_environment=>'production');
  assert r.user_id=u and r.apns_token='synthetic-apns' and r.push_to_start_token is null;
  r:=public.register_device(p_installation_id=>installation,p_push_to_start_token=>'synthetic-activity',p_environment=>'production');
  assert r.apns_token='synthetic-apns' and r.push_to_start_token='synthetic-activity';
  -- New clients send explicit nulls. Neither null nor blank erases a token.
  r:=public.register_device(installation,null,null,'production');
  assert r.apns_token='synthetic-apns' and r.push_to_start_token='synthetic-activity';
  r:=public.register_device(installation,'','', 'production');
  assert r.apns_token='synthetic-apns' and r.push_to_start_token='synthetic-activity';
  r:=public.register_device(installation,'replacement-apns','replacement-activity','production');
  assert r.apns_token='replacement-apns' and r.push_to_start_token='replacement-activity';
  r:=public.register_device(p_installation_id=>installation,p_environment=>'production');
  assert r.apns_token='replacement-apns' and r.push_to_start_token='replacement-activity';

  -- Environment is still mandatory; never silently choose production/sandbox.
  rejected:=false;
  begin perform public.register_device(p_installation_id=>installation,p_apns_token=>'bad');
    exception when invalid_parameter_value then rejected:=true; end;
  assert rejected,'Missing environment accepted';
  rejected:=false;
  begin perform public.register_device(installation,'bad',null,null);
    exception when invalid_parameter_value then rejected:=true; end;
  assert rejected,'Null environment accepted';
  r:=public.register_device(p_installation_id=>installation,p_push_to_start_token=>'sandbox-only',p_environment=>'sandbox');
  assert r.environment='sandbox' and r.apns_token is null and r.push_to_start_token='sandbox-only';
  r:=public.register_device(p_installation_id=>installation,p_apns_token=>'sandbox-apns',p_environment=>'sandbox');
  assert r.apns_token='sandbox-apns' and r.push_to_start_token='sandbox-only';

  perform set_config('request.jwt.claim.sub',other_user::text,true);
  r:=public.register_device(p_installation_id=>installation,p_apns_token=>'other-user',p_environment=>'production');
  assert r.user_id=other_user and r.apns_token='other-user' and r.push_to_start_token is null;
  perform set_config('request.jwt.claim.sub',u::text,true);
  r:=public.register_device(installation,null,null,'production');
  assert r.user_id=u and r.apns_token='replacement-apns' and r.push_to_start_token='replacement-activity';
  execute 'reset role';
  update public.device_registrations set revoked_at=now() where user_id=u and installation_id=installation and environment='production';
  execute 'set local role authenticated';
  r:=public.register_device(p_installation_id=>installation,p_apns_token=>'renewed-apns',p_environment=>'production');
  assert r.revoked_at is null and r.push_to_start_token='replacement-activity';

  perform set_config('request.jwt.claim.sub','',true);
  rejected:=false;
  begin perform public.register_device(installation,null,null,'production');
    exception when raise_exception then assert sqlerrm='authentication required'; rejected:=true; end;
  assert rejected,'Missing identity accepted';
  execute 'set local role anon';
  rejected:=false;
  begin perform public.register_device(p_installation_id=>installation,p_apns_token=>'bad',p_environment=>'production');
    exception when insufficient_privilege then rejected:=true; end;
  assert rejected,'Anonymous registration accepted';
  execute 'reset role';
end;
$$;
rollback;
select 'Device registration compatibility, token preservation and authorization checks passed (rolled back)' as result;
