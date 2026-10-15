-- Disposable fixture additions ONLY; never load against a hosted database.
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
alter table public.daily_prompts add column dispatch_key uuid;
alter table public.daily_prompts add column dispatched_at timestamptz;
alter table public.daily_prompts add column failure_reason text;
grant insert, update, delete on storage.objects to authenticated;
grant usage on schema public, extensions to authenticated;
-- Mirror the circles read policy/grant; direct updates remain ungranted.
alter table public.circles enable row level security;
create policy "circles read members" on public.circles for select to authenticated
  using (public.is_circle_member(id));
grant select on public.circles to authenticated;
