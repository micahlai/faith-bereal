-- Read-only deployment/retention verification; never returns diagnostic payloads or auth IDs.
select
  exists(select 1 from supabase_migrations.schema_migrations where version='202610130002') as migration_applied,
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='manna_private' and c.relname='backend_diagnostic_reports') as row_security,
  has_function_privilege('authenticated','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','execute') as member_ingest,
  has_function_privilege('anon','public.ingest_backend_diagnostics(uuid,uuid,integer,jsonb)','execute') as anon_ingest,
  has_function_privilege('authenticated','public.prune_backend_diagnostics()','execute') as member_prune,
  has_schema_privilege('authenticated','manna_private','usage') as member_private_schema,
  (select count(*) from cron.job where jobname='prune-backend-diagnostics' and active and schedule='17 * * * *') as active_cleanup_jobs,
  (select count(*) from manna_private.backend_diagnostic_reports) as report_count;
