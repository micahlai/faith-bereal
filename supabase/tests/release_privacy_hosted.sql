-- Operator-only, against the migrated hosted schema. Every fixture rolls back.
-- No Edge dispatch, Storage API, downloads, or real account data is touched.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local time zone 'UTC';
set local plpgsql.check_asserts=on;
do $$
declare
  viewer uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  c public.circles; daily public.daily_prompts; evening public.daily_prompts;
  historical uuid; daily_post public.blessings; evening_post public.blessings; old_post public.blessings;
  own_post public.blessings; photo text; old_photo text; denied boolean;
begin
  insert into auth.users(id,raw_user_meta_data) values(viewer,'{}'),(peer,'{}'),(outsider,'{}');
  insert into public.profiles(id,display_name)
    select id,'Release privacy fixture' from unnest(array[viewer,peer,outsider]) id on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  c:=public.create_circle('Release privacy fixture',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
    'UTC','12:00','22:00',10,true,120,'22:00');
  insert into public.circle_members(circle_id,user_id,role,joined_at)
    values(c.id,peer,'member',now()-interval '3 days');
  update public.circle_members set joined_at=now()-interval '3 days' where circle_id=c.id;
  update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes',state='open'
    where circle_id=c.id and kind='daily' returning * into strict daily;
  update public.daily_prompts set starts_at=now()-interval '30 seconds',ends_at=now()+interval '7 hours'-interval '30 seconds',state='open'
    where circle_id=c.id and kind='end_of_day' returning * into strict evening;
  insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,kind,state)
    values(c.id,current_date-1,now()-interval '1 day',now()-interval '1 day'+interval '10 minutes',10,'daily','closed')
    returning id into historical;

  photo:=c.id::text||'/'||daily.id::text||'/'||peer::text||'/photo-previewed-fixture.jpg';
  old_photo:=c.id::text||'/'||historical::text||'/'||peer::text||'/photo-previewed-fixture.jpg';
  perform set_config('request.jwt.claim.sub',peer::text,true);
  perform public.begin_blessing_entry(daily.id);
  daily_post:=public.submit_text_blessing(daily.id,'typed','Synthetic daily peer',null,photo);
  perform public.begin_blessing_entry(evening.id);
  evening_post:=public.submit_text_blessing(evening.id,'typed','Synthetic evening peer');
  insert into public.blessings(prompt_id,author_id,capture_mode,body,photo_path,submitted_at)
    values(historical,peer,'typed','Synthetic historical peer',old_photo,now()-interval '1 day') returning * into old_post;
  insert into public.blessing_responses(blessing_id,author_id,mode,body)
    values(daily_post.id,peer,'typed','Synthetic locked response'),(old_post.id,peer,'typed','Synthetic historical response');
  insert into storage.objects(bucket_id,name) values
    ('blessing-media',photo),('blessing-media',photo||'.preview.jpg'),('blessing-media',old_photo);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  assert (select count(*)=1 from public.blessings where id=old_post.id), 'History unavailable before sharing';
  assert (select count(*)=0 from public.blessings where id in (daily_post.id,evening_post.id)), 'Peer content unlocked early';
  assert (select count(*)=0 from public.blessing_responses where blessing_id=daily_post.id), 'Locked response leaked';
  assert (select count(*)=1 from public.blessing_responses where blessing_id=old_post.id), 'Historical response unavailable';
  assert (select count(*)=0 from storage.objects where bucket_id='blessing-media' and name in (photo,photo||'.preview.jpg')), 'Locked photo leaked';
  assert (select count(*)=1 from storage.objects where bucket_id='blessing-media' and name=old_photo), 'Historical photo unavailable';

  perform public.begin_blessing_entry(daily.id);
  own_post:=public.submit_text_blessing(daily.id,'typed','Synthetic viewer submission');
  assert (select count(*)=1 from public.blessings where id=daily_post.id), 'Daily peer did not unlock';
  assert (select count(*)=0 from public.blessings where id=evening_post.id), 'Daily submission unlocked evening peer';
  assert (select count(*)=1 from public.blessing_responses where blessing_id=daily_post.id), 'Response did not unlock';
  assert (select count(*)=2 from storage.objects where bucket_id='blessing-media' and name in (photo,photo||'.preview.jpg')), 'Photo and preview did not unlock';
  denied:=false;
  begin
    perform public.submit_text_blessing(daily.id,'typed','Synthetic duplicate');
  exception when others then
    assert sqlerrm='already submitted',sqlerrm;
    denied:=true;
  end;
  assert denied,'Server accepted a duplicate submission';

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  assert (select count(*)=0 from public.circles where id=c.id), 'Outsider read circle';
  assert (select count(*)=0 from public.blessings where id in (daily_post.id,evening_post.id,old_post.id,own_post.id)), 'Outsider read blessings';
  assert (select count(*)=0 from public.blessing_responses where blessing_id in (daily_post.id,old_post.id)), 'Outsider read responses';
  assert (select count(*)=0 from storage.objects where bucket_id='blessing-media' and name in (photo,photo||'.preview.jpg',old_photo)), 'Outsider read media';

  execute 'reset role';
  update public.circle_members set removed_at=now() where circle_id=c.id and user_id=viewer;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  assert (select count(*)=0 from public.blessings where id in (daily_post.id,evening_post.id,old_post.id,own_post.id)), 'Removed member retained blessing access';
  assert (select count(*)=0 from public.blessing_responses where blessing_id in (daily_post.id,old_post.id)), 'Removed member retained responses';
  assert (select count(*)=0 from storage.objects where bucket_id='blessing-media' and name in (photo,photo||'.preview.jpg',old_photo)), 'Removed member retained media access';
  execute 'reset role';
end;
$$;
rollback;
