-- Read-only catalog, access and HTTP outcome aggregates. No request bodies, headers or user data.
select jsonb_pretty(jsonb_build_object(
  'checked_at_utc', now(),
  'private_buckets', (select jsonb_agg(jsonb_build_object('bucket',id,'public',public,'file_size_limit',file_size_limit)) from storage.buckets),
  'tables_without_rls', (select jsonb_agg(n.nspname||'.'||c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','manna_private','storage') and c.relkind='r' and not c.relrowsecurity),
  'private_schema_access', jsonb_build_object('anon',has_schema_privilege('anon','manna_private','USAGE'),'authenticated',has_schema_privilege('authenticated','manna_private','USAGE')),
  'service_only_function_access', (select jsonb_agg(jsonb_build_object('function',p.proname,'anon',has_function_privilege('anon',p.oid,'EXECUTE'),'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),'service_role',has_function_privilege('service_role',p.oid,'EXECUTE'))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('claim_storage_mirror_jobs','finish_storage_mirror_job','backfill_storage_mirror','storage_mirror_status','pending_account_deletions','account_deletion_files','verify_account_deletion_cleanup','moderation_inbox','resolve_content_report','claim_ready_circle_badges','complete_ready_circle_badge','queue_expired_media')),
  'blessing_unique_constraints', (select jsonb_agg(pg_get_constraintdef(oid)) from pg_constraint where conrelid='public.blessings'::regclass and contype='u'),
  'http_response_outcomes', (select jsonb_agg(r) from (select status_code,timed_out,count(*) as responses,max(created) as latest from net._http_response where created>now()-interval '6 hours' group by status_code,timed_out order by status_code) r)
)) as access_readiness;
