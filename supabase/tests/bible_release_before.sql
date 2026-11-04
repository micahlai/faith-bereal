-- Disposable migration-chain fixture only. The hosted rollout must not run this file.
create table manna_private.bible_release_migration_fixture(id uuid primary key,version text);
insert into manna_private.bible_release_migration_fixture select gen_random_uuid(),v from unnest(array[
 'web','bsb','asv','ylt','dra','bbe','geneva1599','rvr1909','svd','lsg','synodal','luth1912','riveduta',
 'kjv','cuv','cuvs','almeida-livre','kgy','kor','vi1934']) v;
insert into auth.users(id,raw_user_meta_data) select id,'{}'::jsonb from manna_private.bible_release_migration_fixture;
update public.profiles p set bible_version_id=f.version from manna_private.bible_release_migration_fixture f where p.id=f.id;
