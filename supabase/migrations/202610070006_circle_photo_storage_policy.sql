create or replace function public.is_circle_owner(
  p_circle_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.circles c
    where c.id = p_circle_id
      and c.owner_id = p_user_id
  );
$$;

revoke all on function public.is_circle_owner(uuid, uuid) from public, anon;
grant execute on function public.is_circle_owner(uuid, uuid) to authenticated, service_role;

drop policy if exists "circle owners upload circle photos" on storage.objects;
create policy "circle owners upload circle photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'circle-photos'
  and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg')
  and public.is_circle_owner(public.try_uuid((storage.foldername(name))[1]))
);

drop policy if exists "circle owners update circle photos" on storage.objects;
create policy "circle owners update circle photos"
on storage.objects for update to authenticated
using (
  bucket_id = 'circle-photos'
  and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg')
  and public.is_circle_owner(public.try_uuid((storage.foldername(name))[1]))
)
with check (
  bucket_id = 'circle-photos'
  and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg')
  and public.is_circle_owner(public.try_uuid((storage.foldername(name))[1]))
);

drop policy if exists "circle owners delete circle photos" on storage.objects;
create policy "circle owners delete circle photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'circle-photos'
  and name = (public.try_uuid((storage.foldername(name))[1])::text || '/circle.jpg')
  and public.is_circle_owner(public.try_uuid((storage.foldername(name))[1]))
);

comment on function public.is_circle_owner(uuid, uuid) is
  'RLS-safe circle ownership predicate used by canonical circle-photo Storage policies.';
