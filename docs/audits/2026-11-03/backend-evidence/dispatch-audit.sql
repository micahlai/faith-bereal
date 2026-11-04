-- Aggregate operational outcomes only; no prompt IDs, content or error descriptions.
select jsonb_pretty(jsonb_build_object(
'checked_at_utc',now(),
'last_day_prompt_states',(select jsonb_agg(x) from (select kind,state,count(*) as prompts,count(*) filter(where failure_reason is not null) as with_failure from public.daily_prompts where starts_at>now()-interval '1 day' and starts_at<=now() group by kind,state order by kind,state) x),
'overdue_scheduled',(select count(*) from public.daily_prompts where state='scheduled' and starts_at<now()-interval '5 minutes'),
'active_stale_dispatching',(select count(*) from public.daily_prompts where state='dispatching' and ends_at>now() and coalesce(dispatched_at,created_at)<now()-interval '5 minutes'),
'last_six_hours_outcomes',(select jsonb_build_object('prompt_outcomes',count(*),'errors',count(*) filter(where o.value ? 'error'),'attempted',coalesce(sum((o.value->>'attempted')::int),0),'delivered',coalesce(sum((o.value->>'delivered')::int),0),'failed',coalesce(sum((o.value->>'failed')::int),0)) from net._http_response r cross join lateral jsonb_array_elements(coalesce(r.content::jsonb->'outcomes','[]'::jsonb)) o where r.created>now()-interval '6 hours' and r.status_code=200)
)) as dispatch_readiness;
