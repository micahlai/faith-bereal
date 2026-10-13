-- Rollback-only metadata/authorization check. No notifications or Storage API.
begin;
set local plpgsql.check_asserts=on;
do $$
declare v_user uuid:=gen_random_uuid(); v_new uuid:=gen_random_uuid(); v_outsider uuid:=gen_random_uuid();
  v_circle public.circles; v_other public.circles; v_day date:=(clock_timestamp() at time zone 'UTC')::date; v_prompt uuid; v_count integer; i integer;
begin
  insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@example.invalid','{}'::jsonb
    from unnest(array[v_user,v_new,v_outsider]) id;
  insert into public.profiles(id,display_name) values(v_user,'Streak regression'),(v_new,'New streak member'),(v_outsider,'Outsider') on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  v_circle:=public.create_circle('Streak regression',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
    'UTC',time '12:00',time '22:00',10,true,120,time '22:00');
  v_other:=public.create_circle('Other streak circle',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
    'UTC',time '12:00',time '22:00',10,true,120,time '22:00');
  update public.circle_members set joined_at=now()-interval '30 days' where circle_id=v_circle.id;
  insert into public.circle_members(circle_id,user_id,role,joined_at) values(v_circle.id,v_new,'member',now());
  foreach i in array array[0,1,2,4] loop
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,response_window_minutes,state)
      values(v_circle.id,v_day-i,'daily',(v_day-i)::timestamptz+interval '12 hours',
        (v_day-i)::timestamptz+interval '12 hours 10 minutes',10,'closed')
      on conflict(circle_id,local_date,kind) do update set state='closed' returning id into v_prompt;
    insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late) values(v_prompt,v_user,'typed','Fixture',i=1);
    if i=1 then insert into public.blessings(prompt_id,author_id,capture_mode,body) values(v_prompt,v_new,'typed','Welcome'); end if;
  end loop;
  select id into v_prompt from public.daily_prompts where circle_id=v_circle.id and local_date=v_day and kind='end_of_day';
  insert into public.blessings(prompt_id,author_id,capture_mode,body) values(v_prompt,v_user,'typed','Second same day');
  execute 'set local role authenticated';
  select days into v_count from public.circle_streaks(v_circle.id) where member_id=v_user;
  assert v_count=3;
  assert (select on_time_days=2 and on_time_today from public.circle_streaks(v_circle.id) where member_id=v_user);
  execute 'reset role';
  update public.blessings set is_late=true where author_id=v_user and prompt_id in (
    select id from public.daily_prompts where circle_id=v_circle.id and local_date=v_day);
  insert into public.blessing_entry_grants(prompt_id,user_id,entered_at)
    select id,v_user,starts_at+interval '1 second' from public.daily_prompts
      where circle_id=v_circle.id and local_date=v_day and kind='daily';
  execute 'set local role authenticated';
  assert (select on_time_days=2 and on_time_today from public.circle_streaks(v_circle.id) where member_id=v_user);
  assert (select days=0 from public.circle_streaks(v_circle.id) where member_id=v_new);
  assert (select days=0 from public.circle_streaks(v_other.id) where member_id=v_user);
  perform set_config('request.jwt.claim.sub',v_outsider::text,true);
  begin perform public.circle_streaks(v_circle.id); raise exception 'outsider accepted';
    exception when others then assert sqlerrm='circle membership required',sqlerrm; end;
  execute 'reset role';
  assert not has_function_privilege('anon','public.circle_streaks(uuid)','execute');
end;
$$;
rollback;
