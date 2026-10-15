-- Operator-only, aggregate output. No client read grants, names, content, or raw IDs.
with samples as (
  select r.build_number, e->>'kind' as kind, coalesce(e->>'stage',e->>'requestKind') as category,
    e->>'outcome' as outcome, (e->>'durationMilliseconds')::double precision as milliseconds,
    (e->>'payloadBytes')::bigint as payload_bytes,
    (e->>'startedAt')::timestamptz as started_at, r.received_at,
    e->>'transportErrorCode' as transport_code, e->>'errorSource' as error_source,
    e->>'errorCode' as error_code, e->>'errorCategory' as error_category
  from manna_private.backend_diagnostic_reports r cross join lateral jsonb_array_elements(r.events) e
), participation as (
  select build_number,count(*) as reports,count(distinct user_id) as participating_accounts,
    count(distinct session_id) as sessions,sum(jsonb_array_length(events)) as records,
    min(received_at) as first_received_utc,max(received_at) as last_received_utc
  from manna_private.backend_diagnostic_reports group by build_number
), event_ranges as (
  select build_number,min(started_at) as first_event_utc,max(started_at) as last_event_utc,
    min(received_at) as first_received_utc,max(received_at) as last_received_utc
  from samples group by build_number
), timings as (
  select build_number,kind,category,count(*) as samples,
    count(*) filter(where outcome='failure') as failures,count(*) filter(where outcome='cancelled') as cancellations,
    round((percentile_cont(0.5) within group(order by milliseconds))::numeric,2) as median_ms,
    round((percentile_cont(0.95) within group(order by milliseconds))::numeric,2) as p95_ms,
    sum(payload_bytes) as upload_payload_bytes
  from samples group by build_number,kind,category
), recent_failures as (
  select build_number,date_trunc('minute',started_at) as failed_minute_utc,
    category as request_category,transport_code,error_source,error_code,error_category,
    count(*) as failed_operations,min(started_at) as first_event_utc,max(started_at) as last_event_utc,
    min(received_at) as first_received_utc,max(received_at) as last_received_utc
  from samples where kind='request' and outcome='failure'
  group by build_number,date_trunc('minute',started_at),category,transport_code,error_source,error_code,error_category
  order by failed_minute_utc desc limit 100
)
select
  coalesce((select jsonb_agg(to_jsonb(p) order by build_number desc) from participation p),'[]'::jsonb) as participation,
  coalesce((select jsonb_agg(to_jsonb(r) order by build_number desc) from event_ranges r),'[]'::jsonb) as event_and_receipt_ranges,
  coalesce((select jsonb_agg(to_jsonb(t) order by build_number desc,kind,category) from timings t),'[]'::jsonb) as timing_samples,
  coalesce((select jsonb_agg(to_jsonb(f) order by failed_minute_utc desc) from recent_failures f),'[]'::jsonb) as recent_failure_minutes;
