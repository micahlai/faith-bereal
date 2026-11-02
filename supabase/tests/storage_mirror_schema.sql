create role anon;
create role authenticated;
create role service_role;
create schema storage;
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text not null, name text not null,
  version text, metadata jsonb, last_accessed_at timestamptz,
  is_delete_marker boolean, archived_at timestamptz,
  unique(bucket_id,name)
);
