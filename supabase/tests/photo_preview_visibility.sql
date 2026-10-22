-- Rollback-only hosted/local helper test. No Storage objects, downloads, or dispatch.
begin;
set local statement_timeout = '10s';
set local plpgsql.check_asserts = on;
do $$
declare
  v_author uuid := gen_random_uuid(); v_peer uuid := gen_random_uuid(); v_outsider uuid := gen_random_uuid();
  v_source_circle public.circles; v_target_circle public.circles;
  v_source_prompt public.daily_prompts; v_target_prompt public.daily_prompts;
  v_source public.blessings; v_copy public.blessings; v_path text;
begin
  assert not has_function_privilege('anon', 'public.can_read_blessing_media(text)', 'EXECUTE');
  insert into auth.users(id) values(v_author),(v_peer),(v_outsider);
  insert into public.profiles(id,display_name) values(v_author,'Preview fixture'),(v_peer,'Preview peer'),(v_outsider,'Preview outsider') on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub',v_author::text,true);
  v_source_circle := public.create_circle('Preview source',upper(left(replace(gen_random_uuid()::text,'-',''),10)),'UTC',time '12:00',time '22:00',10,true,120);
  v_target_circle := public.create_circle('Preview target',upper(left(replace(gen_random_uuid()::text,'-',''),10)),'UTC',time '12:00',time '22:00',10,true,120);
  insert into public.circle_members(circle_id,user_id,role) values(v_target_circle.id,v_peer,'member');
  update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes',state='open'
    where circle_id=v_source_circle.id and kind='daily' returning * into strict v_source_prompt;
  update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes',state='open'
    where circle_id=v_target_circle.id and kind='daily' returning * into strict v_target_prompt;
  v_path := v_source_circle.id::text||'/'||v_source_prompt.id::text||'/'||v_author::text||'/photo-previewed-fixture.jpg';
  v_source := public.submit_text_blessing(v_source_prompt.id,'typed','Preview test',null,v_path);
  v_copy := public.repeat_blessing(v_source.id,v_target_prompt.id);
  perform set_config('request.jwt.claim.sub',v_peer::text,true);
  assert not public.can_read_blessing_media(v_path||'.preview.jpg'), 'Locked peer accessed preview';
  perform public.submit_text_blessing(v_target_prompt.id,'typed','Unlock preview fixture');
  assert public.can_read_blessing_media(v_path||'.preview.jpg'), 'Receiving-circle member cannot read reused preview';
  assert public.can_read_blessing_media(v_path), 'Original full photo behavior changed';
  assert not public.can_read_blessing_media(v_path||'.wrong-preview.jpg');
  perform set_config('request.jwt.claim.sub',v_outsider::text,true);
  assert not public.can_read_blessing_media(v_path||'.preview.jpg'), 'Outsider accessed preview';
end;
$$;
rollback;
