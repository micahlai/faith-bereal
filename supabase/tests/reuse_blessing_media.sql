-- Transactional local/hosted RPC checks; no Storage writes or dispatcher calls.
begin;
set local plpgsql.check_asserts = on;
do $$
declare
  v_user uuid := gen_random_uuid(); v_peer uuid := gen_random_uuid(); v_outsider uuid := gen_random_uuid();
  v_source_circle public.circles; v_target_circle public.circles;
  v_source_prompt public.daily_prompts; v_target_prompt public.daily_prompts;
  v_source public.blessings; v_copy public.blessings;
  v_mode public.capture_mode; v_prefix text; v_error text;
begin
  insert into auth.users(id, email, raw_user_meta_data)
    select id, id::text || '@example.invalid', '{"name":"Reuse regression"}'::jsonb
    from unnest(array[v_user,v_peer,v_outsider]) id;
  insert into public.profiles(id,display_name) values(v_user,'Reuse regression'),(v_peer,'Reuse peer'),(v_outsider,'Outsider')
    on conflict(id) do nothing;
  foreach v_mode in array array['typed','voice','video']::public.capture_mode[] loop
    perform set_config('request.jwt.claim.sub',v_user::text,true);
    v_source_circle := public.create_circle('Temporary reuse source',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
      'UTC',time '12:00',time '22:00',10,true,120,time '22:00');
    v_target_circle := public.create_circle('Temporary reuse target',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
      'UTC',time '12:00',time '22:00',10,true,120,time '22:00');
    insert into public.circle_members(circle_id,user_id,role,joined_at)
      values(v_target_circle.id,v_peer,'member',now()-interval '2 days');
    update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes',state='open'
      where circle_id=v_source_circle.id and kind='daily' returning * into strict v_source_prompt;
    update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes',state='open'
      where circle_id=v_target_circle.id and kind='daily' returning * into strict v_target_prompt;
    v_prefix := v_source_circle.id::text || '/' || v_source_prompt.id::text || '/' || v_user::text || '/';
    if v_mode='video' then
      v_source := public.finalize_video_blessing(v_source_prompt.id,v_prefix||'movie.mov','Thankful',v_prefix||'frame.jpg',
        'psalms','Psalms',23,1,2);
    else
      v_source := public.submit_text_blessing(v_source_prompt.id,v_mode,'Thankful',
        case when v_mode='voice' then v_prefix||'audio.caf' else null end,v_prefix||'photo.jpg',
        'psalms','Psalms',23,1,2);
    end if;
    execute 'set local role authenticated';
    v_copy := public.repeat_blessing(v_source.id,v_target_prompt.id);
    assert v_copy.id<>v_source.id and v_copy.prompt_id=v_target_prompt.id;
    assert v_copy.capture_mode=v_mode and v_copy.body=v_source.body;
    assert v_copy.audio_path is not distinct from v_source.audio_path;
    assert v_copy.video_path is not distinct from v_source.video_path;
    assert v_copy.photo_path is not distinct from v_source.photo_path;
    assert v_copy.thumbnail_path is not distinct from v_source.thumbnail_path;
    assert v_copy.scripture_verse_end=2 and v_copy.repeated_from_blessing_id=v_source.id;
    begin
      perform public.repeat_blessing(v_source.id,v_target_prompt.id);
      raise exception 'duplicate accepted';
    exception when others then get stacked diagnostics v_error=message_text; assert v_error='already submitted',v_error; end;
    perform set_config('request.jwt.claim.sub',v_peer::text,true);
    assert not public.can_read_blessing_media(coalesce(v_copy.video_path,v_copy.photo_path));
    perform public.submit_text_blessing(v_target_prompt.id,'typed','Peer shared');
    assert public.can_read_blessing_media(coalesce(v_copy.video_path,v_copy.photo_path));
    if v_mode='voice' then assert public.can_read_blessing_media(v_copy.audio_path); end if;
    if v_mode='video' then assert public.can_read_blessing_media(v_copy.thumbnail_path); end if;
    perform set_config('request.jwt.claim.sub',v_outsider::text,true);
    assert not public.can_read_blessing_media(coalesce(v_copy.video_path,v_copy.photo_path));
    begin
      perform public.repeat_blessing(v_source.id,v_target_prompt.id);
      raise exception 'other author accepted';
    exception when others then get stacked diagnostics v_error=message_text; assert v_error='blessing or prompt not found',v_error; end;
    execute 'reset role';
    update public.circle_members set removed_at=now() where circle_id=v_target_circle.id and user_id=v_peer;
    perform set_config('request.jwt.claim.sub',v_peer::text,true);
    assert not public.can_read_blessing_media(coalesce(v_copy.video_path,v_copy.photo_path));
  end loop;
  assert not has_function_privilege('anon','public.repeat_blessing(uuid,uuid)','execute');
  assert not has_function_privilege('anon','public.can_read_blessing_media(text)','execute');
end;
$$;
rollback;
