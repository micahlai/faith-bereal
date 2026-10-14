-- Opt-in operational metrics. Auth identity is server-derived; no client content or paths.
create schema if not exists manna_private;
revoke all on schema manna_private from public, anon, authenticated;

create table manna_private.backend_diagnostic_reports (
  user_id uuid not null references auth.users(id) on delete cascade,
  report_id uuid not null,
  session_id uuid not null,
  build_number integer not null check(build_number > 0),
  received_at timestamptz not null default clock_timestamp(),
  events jsonb not null check(jsonb_typeof(events)='array' and jsonb_array_length(events) between 1 and 100),
  primary key(user_id, report_id)
);
create index backend_diagnostic_reports_received on manna_private.backend_diagnostic_reports(received_at);
create index backend_diagnostic_reports_account_received on manna_private.backend_diagnostic_reports(user_id,received_at);
alter table manna_private.backend_diagnostic_reports enable row level security;
revoke all on manna_private.backend_diagnostic_reports from public,anon,authenticated;

create function public.ingest_backend_diagnostics(
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
        'httpStatus','transportErrorCode','payloadBytes','receivedBytes'
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
          'storageSign','storageUpload','storageOther','function','other'
        ) then raise exception 'invalid diagnostics request' using errcode='22023'; end if;
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

create function public.prune_backend_diagnostics() returns integer
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_count integer;
begin
  delete from manna_private.backend_diagnostic_reports where (user_id,report_id) in (
    select user_id,report_id from manna_private.backend_diagnostic_reports
    where received_at<clock_timestamp()-interval '14 days' order by received_at limit 10000
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.prune_backend_diagnostics() from public,anon,authenticated;
grant execute on function public.prune_backend_diagnostics() to service_role;

-- Hosted Supabase has pg_cron; disposable fixtures intentionally may not.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('prune-backend-diagnostics','17 * * * *','select public.prune_backend_diagnostics();');
  end if;
end $$;
