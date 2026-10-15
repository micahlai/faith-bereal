-- Forward-compatible, sanitized failure metadata for field diagnostics.
-- Existing reports and old clients remain valid. Authentication, quotas, exact retry
-- idempotency, payload limits, private storage, and pruning are unchanged.
create or replace function public.ingest_backend_diagnostics(
  p_report_id uuid, p_session_id uuid, p_build_number integer, p_events jsonb
) returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp();
  v_event jsonb; v_time timestamptz; v_key text; v_n numeric;
  v_previous manna_private.backend_diagnostic_reports%rowtype;
begin
  if v_user is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_report_id is null or p_session_id is null or p_build_number is null or p_build_number<=0
    or p_events is null or jsonb_typeof(p_events)<>'array' then
    raise exception 'invalid diagnostics batch' using errcode='22023';
  end if;
  if jsonb_array_length(p_events) not between 1 and 100 or octet_length(p_events::text)>65536 then
    raise exception 'diagnostics batch limit' using errcode='22023';
  end if;
  -- One account's concurrent requests cannot race quotas or idempotency.
  perform pg_advisory_xact_lock(hashtextextended(v_user::text,731));
  select * into v_previous from manna_private.backend_diagnostic_reports
    where user_id=v_user and report_id=p_report_id;
  if found then
    if v_previous.session_id<>p_session_id or v_previous.build_number<>p_build_number or v_previous.events<>p_events then
      raise exception 'diagnostics report conflict' using errcode='22023';
    end if;
    return jsonb_array_length(v_previous.events);
  end if;
  for v_event in select value from jsonb_array_elements(p_events) loop
    if jsonb_typeof(v_event)<>'object' or exists (
      select 1 from jsonb_object_keys(v_event) k where k not in (
        'kind','startedAt','durationMilliseconds','stage','requestKind','outcome',
        'httpStatus','transportErrorCode','payloadBytes','receivedBytes',
        'errorSource','errorCode','errorCategory'
      )
    ) then raise exception 'invalid diagnostics fields' using errcode='22023'; end if;
    if jsonb_typeof(v_event->'kind') is distinct from 'string'
      or (v_event->>'kind') not in ('stage','request')
      or jsonb_typeof(v_event->'outcome') is distinct from 'string'
      or (v_event->>'outcome') not in ('success','failure','cancelled')
      or jsonb_typeof(v_event->'startedAt') is distinct from 'string'
      or jsonb_typeof(v_event->'durationMilliseconds') is distinct from 'number' then
      raise exception 'invalid diagnostics types' using errcode='22023';
    end if;
    if v_event->>'kind'='stage' then
      if jsonb_typeof(v_event->'stage') is distinct from 'string' or v_event ? 'requestKind'
        or (v_event->>'stage') not in (
          'bootstrapVisible','circleSwitch','circleRefresh','timelineRefresh','submit','submissionPrepare',
          'thumbnail','uploadAudio','uploadPhoto','uploadVideo','uploadThumbnail','finalize','mediaSigning',
          'widgetRefresh','automaticSaving'
        ) or v_event ?| array['httpStatus','transportErrorCode','payloadBytes','receivedBytes'] then
        raise exception 'invalid diagnostics stage' using errcode='22023';
      end if;
    else
      if jsonb_typeof(v_event->'requestKind') is distinct from 'string' or v_event ? 'stage'
        or (v_event->>'requestKind') not in (
          'auth','circles','members','profiles','prompts','blessings','responses','rpc',
          'storageSign','storageUpload','storageOther','function','other','speech','audio','diagnosticsUpload'
        ) then raise exception 'invalid diagnostics request' using errcode='22023'; end if;
    end if;
    -- Closed, sanitized failure metadata only. Never accept messages, descriptions, or arbitrary keys.
    if v_event ?| array['errorSource','errorCode','errorCategory'] then
      if v_event->>'kind'<>'request' or v_event->>'outcome'<>'failure' then
        raise exception 'invalid diagnostics error context' using errcode='22023';
      end if;
      if jsonb_typeof(v_event->'errorSource') is distinct from 'string'
        or (v_event->>'errorSource') not in ('postgrest','storage','auth','url','speech','audio','other') then
        raise exception 'invalid diagnostics error source' using errcode='22023';
      end if;
      if v_event ? 'errorCode' and (
        jsonb_typeof(v_event->'errorCode') is distinct from 'string'
        or (v_event->>'errorCode') !~ '^[A-Za-z0-9_-]{1,16}$'
      ) then raise exception 'invalid diagnostics error code' using errcode='22023'; end if;
      if v_event ? 'errorCategory' and (
        jsonb_typeof(v_event->'errorCategory') is distinct from 'string'
        or (v_event->>'errorCategory') not in ('connectionLimit','other')
      ) then raise exception 'invalid diagnostics error category' using errcode='22023'; end if;
    end if;
    -- Require an explicit UTC instant; no natural-language/relative date input.
    if (v_event->>'startedAt') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$' then
      raise exception 'invalid diagnostics timestamp' using errcode='22023';
    end if;
    begin v_time := (v_event->>'startedAt')::timestamptz;
    exception when others then raise exception 'invalid diagnostics timestamp' using errcode='22023'; end;
    if v_time<v_now-interval '14 days' or v_time>v_now+interval '5 minutes' then
      raise exception 'diagnostics timestamp range' using errcode='22023';
    end if;
    v_n := (v_event->>'durationMilliseconds')::numeric;
    if v_n<0 or v_n>3600000 then raise exception 'diagnostics duration range' using errcode='22023'; end if;
    foreach v_key in array array['httpStatus','transportErrorCode','payloadBytes','receivedBytes'] loop
      if v_event ? v_key then
        if jsonb_typeof(v_event->v_key)<>'number' then raise exception 'invalid diagnostics numeric field' using errcode='22023'; end if;
        v_n := (v_event->>v_key)::numeric;
        if v_n<>trunc(v_n) or (v_key='httpStatus' and (v_n<100 or v_n>599))
          or (v_key='transportErrorCode' and (v_n < -200000 or v_n>0))
          or (v_key in ('payloadBytes','receivedBytes') and (v_n<0 or v_n>1073741824)) then
          raise exception 'diagnostics numeric range' using errcode='22023';
        end if;
      end if;
    end loop;
  end loop;
  delete from manna_private.backend_diagnostic_reports where user_id=v_user and received_at<v_now-interval '14 days';
  if exists(select 1 from manna_private.backend_diagnostic_reports where user_id=v_user and received_at>v_now-interval '60 seconds')
    or (select count(*) from manna_private.backend_diagnostic_reports where user_id=v_user and received_at>v_now-interval '24 hours')>=100 then
    raise exception 'diagnostics rate limit' using errcode='54000';
  end if;
  insert into manna_private.backend_diagnostic_reports(user_id,report_id,session_id,build_number,events)
    values(v_user,p_report_id,p_session_id,p_build_number,p_events);
  return jsonb_array_length(p_events);
end;
$$;
revoke all on function public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb) from public,anon;
grant execute on function public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb) to authenticated;
