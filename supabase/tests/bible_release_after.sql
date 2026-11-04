do $$
declare f record; supported text[]:=array['web','bsb','asv','ylt','dra','bbe','geneva1599','rvr1909','svd','synodal','luth1912','riveduta'];
begin
 for f in select * from manna_private.bible_release_migration_fixture loop
  assert (select bible_version_id=case when f.version=any(supported) then f.version else 'web' end from public.profiles where id=f.id), 'Removed preference was not migrated or supported preference changed';
 end loop;
end $$;
delete from auth.users where id in(select id from manna_private.bible_release_migration_fixture);
drop table manna_private.bible_release_migration_fixture;
