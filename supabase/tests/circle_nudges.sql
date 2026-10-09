-- Local/hosted transactional test. No APNs/dispatch/Storage side effects.
begin;
set local plpgsql.check_asserts=on;
do $$
declare
  v_sender uuid:=gen_random_uuid(); v_peer uuid:=gen_random_uuid(); v_second uuid:=gen_random_uuid();
  v_circle public.circles; v_prompt public.daily_prompts; v_kind text; v_event uuid; v_error text; v_next uuid;
begin
  insert into auth.users(id,email,raw_user_meta_data)
    select id,id::text||'@example.invalid','{"name":"Nudge regression"}'::jsonb from unnest(array[v_sender,v_peer,v_second]) id;
  insert into public.profiles(id,display_name) values(v_sender,'Nudge regression'),(v_peer,'Nudge peer'),(v_second,'Second sender')
    on conflict(id) do nothing;
  foreach v_kind in array array['daily','end_of_day'] loop
    perform set_config('request.jwt.claim.sub',v_sender::text,true);
    v_circle:=public.create_circle('Temporary nudge regression',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
      'UTC',time '12:00',time '22:00',10,false,120,time '22:00');
    insert into public.circle_members(circle_id,user_id,role,joined_at)
      values(v_circle.id,v_peer,'member',now()-interval '2 days'),(v_circle.id,v_second,'member',now()-interval '2 days');
    update public.daily_prompts set starts_at=now()-interval '1 minute',
      ends_at=now()+case when v_kind='daily' then interval '9 minutes' else interval '299 minutes' end,state='open'
      where circle_id=v_circle.id and kind::text=v_kind returning * into strict v_prompt;
    execute 'set local role authenticated';
    begin
      perform public.nudge_circle_member(v_prompt.id,v_peer);
      raise exception 'unshared sender accepted';
    exception when others then get stacked diagnostics v_error=message_text; assert v_error='Share your blessing before nudging',v_error; end;
    perform public.submit_text_blessing(v_prompt.id,'typed','Shared');
    assert public.nudge_circle_member(v_prompt.id,v_peer);
    assert not public.nudge_circle_member(v_prompt.id,v_peer);
    perform set_config('request.jwt.claim.sub',v_second::text,true);
    perform public.submit_text_blessing(v_prompt.id,'typed','Second shared');
    assert not public.nudge_circle_member(v_prompt.id,v_peer);
    begin
      perform public.nudge_circle_member(v_prompt.id,v_second);
      raise exception 'self nudge accepted';
    exception when others then get stacked diagnostics v_error=message_text; assert v_error='A nudge requires two current circle members',v_error; end;
    execute 'reset role';
    select id into strict v_event from public.circle_notification_outbox where event_type='member_nudged'
      and prompt_id=v_prompt.id and recipient_id=v_peer;
    assert public.nudge_is_deliverable(v_event);
    update public.circle_members set notify_on_circle_activity=false where circle_id=v_circle.id and user_id=v_peer;
    assert not public.nudge_is_deliverable(v_event);
    update public.circle_members set notify_on_circle_activity=true,removed_at=now() where circle_id=v_circle.id and user_id=v_peer;
    assert not public.nudge_is_deliverable(v_event);
    update public.circle_members set removed_at=null where circle_id=v_circle.id and user_id=v_peer;
    -- Deadline checks cannot be bypassed by a sender's retained entry grant.
    update public.daily_prompts set starts_at=now()-case when v_kind='daily' then interval '11 minutes' else interval '301 minutes' end,
      ends_at=now()-interval '1 minute' where id=v_prompt.id;
    assert not public.nudge_is_deliverable(v_event);
    -- A newly joined recipient can post today outside the ordinary window,
    -- but that exception must not permit nudges after a no-late deadline.
    update public.circle_members set joined_at=now() where circle_id=v_circle.id and user_id=v_peer;
    assert not public.nudge_is_deliverable(v_event);
    perform set_config('request.jwt.claim.sub',v_sender::text,true);
    execute 'set local role authenticated';
    begin
      perform public.nudge_circle_member(v_prompt.id,v_peer);
      raise exception 'first-day recipient bypassed closed nudge window';
    exception when others then get stacked diagnostics v_error=message_text;
      assert v_error='This blessing entry window is closed',v_error; end;
    execute 'reset role';
    update public.circle_members set joined_at=now()-interval '2 days' where circle_id=v_circle.id and user_id=v_peer;
    update public.circles set allow_late_blessings=true where id=v_circle.id;
    if v_kind='daily' then assert public.nudge_is_deliverable(v_event);
    else assert not public.nudge_is_deliverable(v_event); end if;
    update public.daily_prompts set starts_at=now()+interval '1 minute',
      ends_at=now()+case when v_kind='daily' then interval '11 minutes' else interval '301 minutes' end where id=v_prompt.id;
    assert not public.nudge_is_deliverable(v_event);
    update public.daily_prompts set starts_at=now()-interval '1 minute',
      ends_at=now()+case when v_kind='daily' then interval '9 minutes' else interval '299 minutes' end where id=v_prompt.id;
    insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,kind,state)
      values(v_circle.id,v_prompt.local_date+1,now()-interval '30 seconds',now()+interval '570 seconds',10,'daily','open')
      returning id into v_next;
    if v_kind='end_of_day' then
      assert not public.nudge_is_deliverable(v_event);
    else
      update public.daily_prompts set starts_at=now()-interval '11 minutes',ends_at=now()-interval '1 minute' where id=v_prompt.id;
      assert not public.nudge_is_deliverable(v_event);
      update public.daily_prompts set starts_at=now()-interval '1 minute',ends_at=now()+interval '9 minutes' where id=v_prompt.id;
    end if;
    delete from public.daily_prompts where id=v_next;
    perform set_config('request.jwt.claim.sub',v_peer::text,true);
    perform public.submit_text_blessing(v_prompt.id,'typed','Recipient shared');
    assert not public.nudge_is_deliverable(v_event);
    perform set_config('request.jwt.claim.sub',v_sender::text,true);
    execute 'set local role authenticated';
    begin
      perform public.nudge_circle_member(v_prompt.id,v_peer);
      raise exception 'completed recipient accepted';
    exception when others then get stacked diagnostics v_error=message_text; assert v_error='This person already shared',v_error; end;
    execute 'reset role';
  end loop;
  assert not has_function_privilege('anon','public.nudge_circle_member(uuid,uuid)','execute');
  assert not has_function_privilege('authenticated','public.nudge_is_deliverable(uuid)','execute');
end;
$$;
rollback;
