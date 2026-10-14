-- Exercises the real migration under client roles, with all fixture writes rolled back.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts = on;

create function pg_temp.expect_ingest_rejection(p_events jsonb, p_report uuid default gen_random_uuid(),
  p_session uuid default '00000000-0000-0000-0000-000000000003', p_build integer default 42,
  p_expected_state text default '22023')
returns void language plpgsql as $$
declare rejected boolean := false;
begin
  begin
    perform public.ingest_backend_diagnostics(p_report, p_session, p_build, p_events);
  exception when others then
    assert sqlstate=p_expected_state, 'Unexpected rejection SQLSTATE: ' || sqlstate || ' ' || sqlerrm;
    rejected := true;
  end;
  assert rejected, 'Invalid diagnostic batch was accepted';
end;
$$;

do $$
declare
  account_a uuid := '00000000-0000-0000-0000-000000000001';
  account_b uuid := '00000000-0000-0000-0000-000000000002';
  session_a uuid := '00000000-0000-0000-0000-000000000003';
  report_a uuid := '00000000-0000-0000-0000-000000000004';
  event jsonb := jsonb_build_object('kind','request','startedAt',to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'durationMilliseconds',12.5,'requestKind','blessings','outcome','success','httpStatus',200,
    'payloadBytes',120,'receivedBytes',240);
  stage jsonb := jsonb_build_object('kind','stage','startedAt',to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'durationMilliseconds',25,'stage','submit','outcome','failure');
  events jsonb;
  bad jsonb;
  denied boolean;
  field text;
begin
  insert into auth.users(id) values(account_a), (account_b);
  assert not has_function_privilege('anon','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','EXECUTE');
  assert has_function_privilege('authenticated','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','EXECUTE');
  assert not has_function_privilege('authenticated','public.prune_backend_diagnostics()','EXECUTE');
  assert not has_function_privilege('anon','public.prune_backend_diagnostics()','EXECUTE');
  assert has_function_privilege('service_role','public.prune_backend_diagnostics()','EXECUTE');
  assert (select relrowsecurity from pg_class where oid='manna_private.backend_diagnostic_reports'::regclass);
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','SELECT');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','INSERT');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','UPDATE');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','DELETE');
  assert not has_table_privilege('anon','manna_private.backend_diagnostic_reports','SELECT');

  events := jsonb_build_array(event, stage);
  perform set_config('request.jwt.claim.sub',account_a::text,true);
  execute 'set local role anon';
  perform pg_temp.expect_ingest_rejection(events,p_expected_state=>'42501');
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.expect_ingest_rejection(events,p_expected_state=>'42501');
  perform set_config('request.jwt.claim.sub',account_a::text,true);
  assert public.ingest_backend_diagnostics(report_a,session_a,42,events)=2;
  -- Exact retry must succeed even when a new report would be rate limited.
  assert public.ingest_backend_diagnostics(report_a,session_a,42,events)=2;
  perform pg_temp.expect_ingest_rejection(events || jsonb_build_array(event),report_a,session_a,42);
  perform pg_temp.expect_ingest_rejection(events,report_a,gen_random_uuid(),42);
  perform pg_temp.expect_ingest_rejection(events,report_a,session_a,43);
  perform pg_temp.expect_ingest_rejection(events,p_expected_state=>'54000');
  denied := false;
  begin execute 'select * from manna_private.backend_diagnostic_reports';
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'Client read its own diagnostic reports';
  denied := false;
  begin perform public.prune_backend_diagnostics();
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'Authenticated client invoked administrative cleanup';
  execute 'reset role';
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports);
  assert exists(select 1 from manna_private.backend_diagnostic_reports where user_id=account_a and report_id=report_a);

  -- The caller identity comes only from auth.uid; another account can reuse report UUIDs.
  perform set_config('request.jwt.claim.sub',account_b::text,true);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(report_a,session_a,42,events)=2;
  denied := false;
  begin execute 'select * from manna_private.backend_diagnostic_reports';
  exception when insufficient_privilege then denied := true; end;
  assert denied, 'Peer client read diagnostic reports';
  execute 'reset role';
  assert (select count(*)=2 from manna_private.backend_diagnostic_reports);
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports where user_id=account_b);
  delete from manna_private.backend_diagnostic_reports;
  perform set_config('request.jwt.claim.sub',account_a::text,true);

  -- No malicious batch may leave a partially inserted report. Test without rate-limit masking.
  execute 'set local role authenticated';
  perform pg_temp.expect_ingest_rejection(null);
  perform pg_temp.expect_ingest_rejection('{}');
  perform pg_temp.expect_ingest_rejection('[]');
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(null));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(42));
  perform pg_temp.expect_ingest_rejection(events,null,session_a,42);
  perform pg_temp.expect_ingest_rejection(events,gen_random_uuid(),null,42);
  perform pg_temp.expect_ingest_rejection(events,gen_random_uuid(),session_a,0);
  perform pg_temp.expect_ingest_rejection(events,gen_random_uuid(),session_a,null);
  select jsonb_agg(event) into bad from generate_series(1,101);
  perform pg_temp.expect_ingest_rejection(bad);
  foreach field in array array['user_id','token','url','errorDescription','body','email'] loop
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,'sensitive')));
  end loop;
  foreach field in array array['kind','startedAt','durationMilliseconds','outcome','requestKind'] loop
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event - field));
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,null)));
  end loop;
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"kind":"private"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"outcome":"private"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"requestKind":"private"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(stage || '{"stage":"private"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(stage - 'stage'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"stage":"submit"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(stage || '{"requestKind":"rpc"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"durationMilliseconds":-1}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"durationMilliseconds":3600001}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"durationMilliseconds":"12"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"httpStatus":99}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"httpStatus":600}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"httpStatus":200.5}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"httpStatus":null}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"httpStatus":"200"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"transportErrorCode":1}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"transportErrorCode":-200001}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"transportErrorCode":-1.5}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"transportErrorCode":null}'));
  foreach field in array array['payloadBytes','receivedBytes'] loop
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,-1)));
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,1073741825::bigint)));
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,1.5)));
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,'100')));
    perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object(field,null)));
  end loop;
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || '{"startedAt":"not-a-date"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object('startedAt',
    to_char(now()-interval '15 days', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object('startedAt',
    to_char(now()+interval '6 minutes', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object('startedAt',42)));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event,event || '{"body":"private"}'));
  perform pg_temp.expect_ingest_rejection(jsonb_build_array(event || jsonb_build_object('body',repeat('x',65537))));
  execute 'reset role';
  assert (select count(*)=0 from manna_private.backend_diagnostic_reports), 'Rejected batches wrote reports';

  select jsonb_agg(event) into bad from generate_series(1,100);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(gen_random_uuid(),session_a,42,bad)=100;
  execute 'reset role';
  delete from manna_private.backend_diagnostic_reports;

  -- Every enum category emitted by the client is accepted, including numeric edges.
  select jsonb_agg(stage || jsonb_build_object('stage',category)) into bad from unnest(array[
    'bootstrapVisible','circleSwitch','circleRefresh','timelineRefresh','submit','submissionPrepare',
    'thumbnail','uploadAudio','uploadPhoto','uploadVideo','uploadThumbnail','finalize','mediaSigning',
    'widgetRefresh','automaticSaving']) category;
  select bad || jsonb_agg(event || jsonb_build_object('requestKind',category)) into bad from unnest(array[
    'auth','circles','members','profiles','prompts','blessings','responses','rpc','storageSign','storageUpload',
    'storageOther','function','other']) category;
  bad := bad || jsonb_build_array(event || jsonb_build_object('durationMilliseconds',0,'httpStatus',100,
    'transportErrorCode',0,'payloadBytes',0,'receivedBytes',0,'outcome','cancelled'),
    event || jsonb_build_object('durationMilliseconds',3600000,'httpStatus',599,
      'transportErrorCode',-200000,'payloadBytes',1073741824,'receivedBytes',1073741824,'outcome','failure'));
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(gen_random_uuid(),session_a,2147483647,bad)=30;
  execute 'reset role';
  delete from manna_private.backend_diagnostic_reports;

  -- Hourly retention is server-time based and does not trust event timestamps.
  insert into manna_private.backend_diagnostic_reports(user_id,report_id,session_id,build_number,received_at,events)
    values(account_a,gen_random_uuid(),session_a,42,now()-interval '15 days',events),
      (account_b,gen_random_uuid(),session_a,42,now()-interval '15 days',events),
      (account_b,gen_random_uuid(),session_a,42,now()-interval '1 day',events);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(gen_random_uuid(),session_a,42,events)=2;
  execute 'reset role';
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports where user_id=account_a);
  assert (select count(*)=2 from manna_private.backend_diagnostic_reports where user_id=account_b);
  execute 'set local role service_role';
  assert public.prune_backend_diagnostics()=1;
  execute 'reset role';
  assert (select count(*)=2 from manna_private.backend_diagnostic_reports);
  delete from manna_private.backend_diagnostic_reports;

  insert into manna_private.backend_diagnostic_reports(user_id,report_id,session_id,build_number,received_at,events)
    select account_a,gen_random_uuid(),session_a,42,now()-interval '10 minutes',events from generate_series(1,100);
  execute 'set local role authenticated';
  perform pg_temp.expect_ingest_rejection(events,p_expected_state=>'54000');
  perform set_config('request.jwt.claim.sub',account_b::text,true);
  assert public.ingest_backend_diagnostics(gen_random_uuid(),session_a,42,events)=2;
  execute 'reset role';
  assert (select count(*)=100 from manna_private.backend_diagnostic_reports where user_id=account_a);
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports where user_id=account_b);
  -- A previous day's reports no longer consume today's quota, while retained data remains.
  update manna_private.backend_diagnostic_reports set received_at=now()-interval '25 hours' where user_id=account_a;
  perform set_config('request.jwt.claim.sub',account_a::text,true);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(gen_random_uuid(),session_a,42,events)=2;
  execute 'reset role';
  assert (select count(*)=101 from manna_private.backend_diagnostic_reports where user_id=account_a);
  delete from auth.users where id=account_a;
  assert (select count(*)=0 from manna_private.backend_diagnostic_reports where user_id=account_a);
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports where user_id=account_b);
end;
$$;
rollback;
