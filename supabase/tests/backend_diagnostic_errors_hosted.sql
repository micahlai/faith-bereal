-- SAFE hosted postflight: synthetic random accounts and their diagnostic rows only.
-- No global writes/count assumptions, pruning, dispatch, or IDs/content in results.
-- The outer rollback removes fixture auth users, their profile triggers, and reports.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts = on;
set local lock_timeout = '2s';
set local statement_timeout = '20s';

create or replace function pg_temp.expect_diagnostic_error_rejection(
  p_report uuid, p_session uuid, p_events jsonb, p_expected_state text default '22023'
) returns void language plpgsql as $$
declare rejected boolean := false;
begin
  begin
    perform public.ingest_backend_diagnostics(p_report,p_session,43,p_events);
  exception when others then
    assert sqlstate=p_expected_state, 'Unexpected diagnostic rejection state';
    rejected := true;
  end;
  assert rejected, 'Invalid diagnostic input was accepted';
end;
$$;

do $$
declare
  account_new uuid := gen_random_uuid();
  account_old uuid := gen_random_uuid();
  session_id uuid := gen_random_uuid();
  v_report_id uuid := gen_random_uuid();
  event_new jsonb := jsonb_build_object('kind','request','startedAt',
    to_char(now()-interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'durationMilliseconds',75,'requestKind','speech','outcome','failure',
    'errorSource','speech','errorCode','1101','errorCategory','connectionLimit');
  event_old jsonb := jsonb_build_object('kind','request','startedAt',
    to_char(now()-interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'durationMilliseconds',12,'requestKind','rpc','outcome','failure','transportErrorCode',-1009);
  events_new jsonb;
  events_old jsonb;
  key text;
  denied boolean;
begin
  -- Assert the same public/client boundary before any synthetic report is sent.
  assert has_function_privilege('authenticated','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','EXECUTE');
  assert not has_function_privilege('anon','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','EXECUTE');
  assert not has_function_privilege('authenticated','public.prune_backend_diagnostics()','EXECUTE');
  assert not has_schema_privilege('authenticated','manna_private','USAGE');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','SELECT');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','INSERT');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','UPDATE');
  assert not has_table_privilege('authenticated','manna_private.backend_diagnostic_reports','DELETE');
  assert (select relrowsecurity from pg_class where oid='manna_private.backend_diagnostic_reports'::regclass);

  insert into auth.users(id) values(account_new),(account_old);
  events_new := jsonb_build_array(event_new,
    event_new || '{"requestKind":"audio","errorSource":"audio","errorCode":"-50","errorCategory":"other"}',
    event_new || '{"requestKind":"diagnosticsUpload","errorSource":"postgrest","errorCode":"PGRST003"}',
    event_new || '{"requestKind":"rpc","errorSource":"postgrest","errorCode":"53300"}');
  events_old := jsonb_build_array(event_old);
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('request.jwt.claim.sub',account_new::text,true);
  execute 'set local role anon';
  perform pg_temp.expect_diagnostic_error_rejection(v_report_id,session_id,events_new,'42501');
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.expect_diagnostic_error_rejection(v_report_id,session_id,events_new,'42501');
  perform set_config('request.jwt.claim.sub',account_new::text,true);
  assert public.ingest_backend_diagnostics(v_report_id,session_id,43,events_new)=4;
  -- Exact enriched retry bypasses the new-report quota, without adding a row.
  assert public.ingest_backend_diagnostics(v_report_id,session_id,43,events_new)=4;
  perform pg_temp.expect_diagnostic_error_rejection(v_report_id,session_id,
    events_new || jsonb_build_array(event_old));
  -- A new valid report for the same account remains subject to the minute quota.
  perform pg_temp.expect_diagnostic_error_rejection(gen_random_uuid(),session_id,events_new,'54000');
  foreach key in array array['message','errorMessage','errorDescription','localizedDescription','details','hint','url','body'] loop
    perform pg_temp.expect_diagnostic_error_rejection(gen_random_uuid(),session_id,
      jsonb_build_array(event_new || jsonb_build_object(key,'synthetic raw text')));
  end loop;
  perform pg_temp.expect_diagnostic_error_rejection(gen_random_uuid(),session_id,
    jsonb_build_array(event_new || '{"errorCode":"too many connections"}'));
  perform pg_temp.expect_diagnostic_error_rejection(gen_random_uuid(),session_id,
    jsonb_build_array((event_new - 'errorSource')));
  perform pg_temp.expect_diagnostic_error_rejection(gen_random_uuid(),session_id,
    jsonb_build_array(event_new || '{"outcome":"success"}'));
  denied := false;
  begin
    execute 'select count(*) from manna_private.backend_diagnostic_reports where user_id=$1' using account_new;
  exception when insufficient_privilege then denied := true;
  end;
  assert denied, 'Client could read private diagnostics';
  execute 'reset role';

  -- Old payload compatibility uses a distinct account so the minute quota is unchanged.
  -- Reusing the report UUID across accounts also verifies the account-scoped key.
  perform set_config('request.jwt.claim.sub',account_old::text,true);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(v_report_id,session_id,43,events_old)=1;
  assert public.ingest_backend_diagnostics(v_report_id,session_id,43,events_old)=1;
  execute 'reset role';
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports r where r.user_id=account_new);
  assert (select count(*)=1 from manna_private.backend_diagnostic_reports r where r.user_id=account_old);
  assert exists(select 1 from manna_private.backend_diagnostic_reports r
    where r.user_id=account_new and r.report_id=v_report_id and r.events=events_new
      and r.received_at > (r.events->0->>'startedAt')::timestamptz + interval '1 hour');
  assert exists(select 1 from manna_private.backend_diagnostic_reports r
    where r.user_id=account_old and r.report_id=v_report_id and r.events=events_old);
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$$;
rollback;
