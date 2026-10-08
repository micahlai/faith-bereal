alter table public.profiles
  drop constraint if exists profiles_bible_version_public_domain;

alter table public.profiles
  add constraint profiles_bible_version_public_domain check (
    bible_version_id = any (array[
      'web', 'bsb', 'kjv', 'asv', 'ylt', 'dra', 'bbe', 'geneva1599',
      'rvr1909', 'cuvs', 'cuv', 'svd', 'lsg', 'almeida-livre',
      'synodal', 'luth1912', 'kgy', 'vi1934', 'kor', 'riveduta'
    ])
  );

create or replace function public.update_bible_version(p_version_id text)
returns public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_version_id <> all (array[
    'web', 'bsb', 'kjv', 'asv', 'ylt', 'dra', 'bbe', 'geneva1599',
    'rvr1909', 'cuvs', 'cuv', 'svd', 'lsg', 'almeida-livre',
    'synodal', 'luth1912', 'kgy', 'vi1934', 'kor', 'riveduta'
  ]) then
    raise exception 'unsupported Bible version';
  end if;

  update public.profiles
  set bible_version_id = p_version_id
  where id = auth.uid()
  returning * into v_profile;
  return v_profile;
end;
$$;

revoke all on function public.update_bible_version(text) from public, anon;
grant execute on function public.update_bible_version(text) to authenticated;

comment on function public.update_bible_version(text) is
  'Stores one client-supported free Bible translation for the authenticated profile.';
