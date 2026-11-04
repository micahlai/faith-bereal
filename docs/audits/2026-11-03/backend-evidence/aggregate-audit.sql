-- Read-only aggregates: no content, identifiers, paths, tokens or credentials.
select jsonb_pretty(jsonb_build_object(
  'checked_at_utc', now(),
  'latest_migration', (select max(version) from supabase_migrations.schema_migrations),
  'database_bytes', pg_database_size(current_database()),
  'database_connections', (select count(*) from pg_stat_activity where datname=current_database()),
  'storage', (select jsonb_agg(s) from (
    select bucket_id, count(*) as objects,
      sum(coalesce((metadata->>'size')::bigint,0)) as bytes,
      round(percentile_cont(0.5) within group(order by coalesce((metadata->>'size')::bigint,0))) as median_bytes,
      round(percentile_cont(0.95) within group(order by coalesce((metadata->>'size')::bigint,0))) as p95_bytes,
      max(coalesce((metadata->>'size')::bigint,0)) as largest_bytes
    from storage.objects group by bucket_id order by bucket_id
  ) s),
  'storage_mirror', (select jsonb_agg(m) from public.storage_mirror_status() m),
  'pending_account_deletions', (select count(*) from manna_private.account_deletions),
  'oldest_account_deletion', (select min(requested_at) from manna_private.account_deletions),
  'media_deletion_queue', (select count(*) from public.media_deletion_queue),
  'open_reports', (select count(*) from manna_private.content_reports where status='open'),
  'oldest_open_report', (select min(created_at) from manna_private.content_reports where status='open'),
  'diagnostics_older_than_14_days', (select count(*) from manna_private.backend_diagnostic_reports where received_at<now()-interval '14 days'),
  'cron_jobs', (select jsonb_agg(j) from (select jobid,jobname,schedule,active from cron.job order by jobid) j),
  'cron_last_day', (select jsonb_agg(j) from (
    select jobid,status,count(*) as runs,max(end_time) as latest_end
    from cron.job_run_details where start_time>now()-interval '1 day' group by jobid,status order by jobid,status
  ) j)
)) as backend_readiness;
