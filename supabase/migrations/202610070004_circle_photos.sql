alter table public.circles
  add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('circle-photos', 'circle-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "circle owners upload circle photos" on storage.objects;
create policy "circle owners upload circle photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'circle-photos'
  and exists (
    select 1 from public.circles c
    where c.id = public.try_uuid((storage.foldername(name))[1])
      and c.owner_id = auth.uid()
  )
);

drop policy if exists "circle owners update circle photos" on storage.objects;
create policy "circle owners update circle photos"
on storage.objects for update to authenticated
using (
  bucket_id = 'circle-photos'
  and exists (
    select 1 from public.circles c
    where c.id = public.try_uuid((storage.foldername(name))[1])
      and c.owner_id = auth.uid()
  )
)
with check (
  bucket_id = 'circle-photos'
  and exists (
    select 1 from public.circles c
    where c.id = public.try_uuid((storage.foldername(name))[1])
      and c.owner_id = auth.uid()
  )
);

drop policy if exists "circle owners delete circle photos" on storage.objects;
create policy "circle owners delete circle photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'circle-photos'
  and exists (
    select 1 from public.circles c
    where c.id = public.try_uuid((storage.foldername(name))[1])
      and c.owner_id = auth.uid()
  )
);

drop policy if exists "circle members read circle photos" on storage.objects;
create policy "circle members read circle photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'circle-photos'
  and public.is_circle_member(public.try_uuid((storage.foldername(name))[1]))
);

create or replace function public.update_circle_photo(
  p_circle_id uuid,
  p_photo_path text default null
)
returns public.circles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_circle public.circles;
  v_expected_path text := p_circle_id::text || '/circle.jpg';
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select * into v_circle
  from public.circles
  where id = p_circle_id
  for update;

  if v_circle.id is null then raise exception 'circle not found'; end if;
  if v_circle.owner_id <> v_user_id then raise exception 'only the circle owner can update its photo'; end if;
  if p_photo_path is not null and p_photo_path <> v_expected_path then
    raise exception 'invalid circle photo path';
  end if;

  update public.circles
  set photo_path = p_photo_path
  where id = p_circle_id
  returning * into v_circle;
  return v_circle;
end;
$$;

revoke all on function public.update_circle_photo(uuid, text) from public, anon;
grant execute on function public.update_circle_photo(uuid, text) to authenticated;

comment on column public.circles.photo_path is
  'Private Storage path for the owner-managed circle photo.';
comment on function public.update_circle_photo(uuid, text) is
  'Sets or removes a circle photo after owner and canonical-path validation.';
