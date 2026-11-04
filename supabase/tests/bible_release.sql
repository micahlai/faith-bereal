begin;
do $$
declare viewer uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); version text; denied boolean; p public.profiles;
begin
 insert into auth.users(id,raw_user_meta_data) values(viewer,'{}'),(peer,'{}');
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 execute 'set local role authenticated';
 foreach version in array array['web','bsb','asv','ylt','dra','bbe','geneva1599','rvr1909','svd','synodal','luth1912','riveduta'] loop
  p:=public.update_bible_version(version); assert p.id=viewer and p.bible_version_id=version,'Supported version not saved for caller';
 end loop;
 foreach version in array array['lsg','kjv','cuv','cuvs','almeida-livre','kgy','kor','vi1934','niv','esv','','WEB'] loop
  denied:=false; begin perform public.update_bible_version(version); exception when others then denied:=true; end;
  assert denied,'Unsupported version accepted';
 end loop;
 denied:=false;begin perform public.update_bible_version(null);exception when others then denied:=true;end;
 assert denied,'NULL Bible version accepted';
 assert not has_function_privilege('anon','public.update_bible_version(text)','execute');
 execute 'reset role';
 assert (select bible_version_id='web' from public.profiles where id=peer),'Preference update changed another account';
 denied:=false;begin update public.profiles set bible_version_id='almeida-livre' where id=viewer;exception when check_violation then denied:=true;end;
 assert denied,'Direct write bypassed catalog constraint';
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.update_bible_version('web');exception when others then denied:=true;end;
 assert denied,'Identity-free update succeeded';
end $$;
rollback;
