-- Forward-migration contract: old clients plus sanitized service/Speech/audio failures.
-- All synthetic writes are rolled back; no hosted execution is performed by the harness.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts = on;

create or replace function pg_temp.expect_error_metadata_rejection(p_event jsonb)
returns void language plpgsql as $$
declare rejected boolean := false;
begin
  begin
    perform public.ingest_backend_diagnostics(gen_random_uuid(),
      '00000000-0000-0000-0000-000000000023',43,jsonb_build_array(p_event));
  exception when others then
    assert sqlstate='22023', 'Unexpected metadata rejection SQLSTATE: ' || sqlstate;
    rejected := true;
  end;
  assert rejected, 'Invalid error metadata accepted';
end;
$$;

do $$
declare
  account_a uuid := '00000000-0000-0000-0000-000000000021';
  account_b uuid := '00000000-0000-0000-0000-000000000022';
  session_a uuid := '00000000-0000-0000-0000-000000000023';
  report_a uuid := '00000000-0000-0000-0000-000000000024';
  event jsonb := jsonb_build_object('kind','request','startedAt',
    to_char(now()-interval '6 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'durationMilliseconds',123,'requestKind','rpc','outcome','failure');
  events jsonb;
  bad jsonb;
  field text;
  value jsonb;
  n integer;
begin
  insert into auth.users(id) values(account_a),(account_b);
  perform set_config('request.jwt.claim.sub',account_a::text,true);
  execute 'set local role authenticated';
  foreach field in array array['message','errorMessage','localizedDescription','domain','errorDomain','rawError','details','hint'] loop
    perform pg_temp.expect_error_metadata_rejection(event || jsonb_build_object(field,'too many connections'));
  end loop;
  -- Source is mandatory whenever any richer metadata is present, including explicit nulls.
  perform pg_temp.expect_error_metadata_rejection(event || '{"errorCode":"53300"}');
  perform pg_temp.expect_error_metadata_rejection(event || '{"errorCategory":"connectionLimit"}');
  foreach value in array array['null'::jsonb,'42'::jsonb,'false'::jsonb,'"unknown"'::jsonb,'""'::jsonb,'{}'::jsonb] loop
    perform pg_temp.expect_error_metadata_rejection(event || jsonb_build_object('errorSource',value));
  end loop;
  bad := event || '{"errorSource":"postgrest"}';
  foreach value in array array['null'::jsonb,'42'::jsonb,'false'::jsonb,'""'::jsonb,'"12345678901234567"'::jsonb,
    '"too many connections"'::jsonb,'"postgres://secret"'::jsonb,'"with.dot"'::jsonb,'"with/slash"'::jsonb,
    '"line\nbreak"'::jsonb,'"café"'::jsonb,'{}'::jsonb] loop
    perform pg_temp.expect_error_metadata_rejection(bad || jsonb_build_object('errorCode',value));
  end loop;
  foreach value in array array['null'::jsonb,'42'::jsonb,'false'::jsonb,'"unknown"'::jsonb,'""'::jsonb,'{}'::jsonb] loop
    perform pg_temp.expect_error_metadata_rejection(bad || jsonb_build_object('errorCategory',value));
  end loop;
  foreach field in array array['success','cancelled'] loop
    perform pg_temp.expect_error_metadata_rejection(bad || jsonb_build_object('outcome',field));
  end loop;
  perform pg_temp.expect_error_metadata_rejection((bad - 'requestKind') || '{"kind":"stage","stage":"submit"}');
  execute 'reset role';
  assert (select count(*)=0 from manna_private.backend_diagnostic_reports), 'Rejected metadata wrote rows';

  -- Every source and new request kind is accepted; source/category can exist without a code.
  select jsonb_agg(event || jsonb_build_object('errorSource',source,'errorCode','53300','errorCategory','connectionLimit'))
    into events from unnest(array['postgrest','storage','auth','url','speech','audio','other']) source;
  select events || jsonb_agg(event || jsonb_build_object('requestKind',request_kind))
    into events from unnest(array['speech','audio','diagnosticsUpload']) request_kind;
  events := events || jsonb_build_array(
    bad,
    bad || '{"errorCategory":"other"}',
    bad || '{"errorCode":"A_b-C0123456789Z"}',
    event || '{"errorSource":"url","errorCode":"-1009","transportErrorCode":-1009}',
    event || '{"errorSource":"speech","errorCode":"1101"}',
    event || '{"errorSource":"audio","errorCode":"-50","errorCategory":"other"}',
    event || '{"errorSource":"postgrest","errorCode":"PGRST003","errorCategory":"connectionLimit"}',
    event || '{"outcome":"success"}');
  n := jsonb_array_length(events);
  execute 'set local role authenticated';
  assert public.ingest_backend_diagnostics(report_a,session_a,43,events)=n;
  assert public.ingest_backend_diagnostics(report_a,session_a,43,events)=n, 'Exact retry changed';
  -- A different authenticated user receives their own row, never relabels a report.
  perform set_config('request.jwt.claim.sub',account_b::text,true);
  assert public.ingest_backend_diagnostics(report_a,session_a,43,events)=n;
  execute 'reset role';
  assert (select count(*)=2 from manna_private.backend_diagnostic_reports);
  assert (select bool_and(r.received_at > (r.events->0->>'startedAt')::timestamptz + interval '5 hours')
    from manna_private.backend_diagnostic_reports r), 'Receipt time replaced delayed event time';
end;
$$;

-- Run the real aggregate query against delayed synthetic failures without exposing IDs/content.
\ir ../queries/backend_diagnostics_summary.sql
rollback;
