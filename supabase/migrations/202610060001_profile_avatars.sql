alter table public.profiles
  add column if not exists avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5242880, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users update own avatar" on storage.objects;
create policy "users update own avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "circle members read avatars" on storage.objects;
create policy "circle members read avatars"
on storage.objects for select to authenticated
using (
  bucket_id = 'avatars'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
    select 1
    from public.circle_members viewer
    join public.circle_members owner
      on owner.circle_id = viewer.circle_id
     and owner.removed_at is null
    where viewer.user_id = auth.uid()
      and viewer.removed_at is null
      and owner.user_id::text = (storage.foldername(name))[1]
    )
  )
);
