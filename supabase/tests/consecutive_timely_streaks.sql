-- Rollback-only independent timely-run regression against the actual RPC.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts=on;
do $$
declare member uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); c public.circles;
  today date:=(clock_timestamp() at time zone 'UTC')::date; p uuid; i integer;
begin
  insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@example.invalid','{}'::jsonb
    from unnest(array[member,outsider]) id;
  insert into public.profiles(id,display_name) values(member,'Timely fixture'),(outsider,'Outsider');
  perform set_config('request.jwt.claim.sub',member::text,true);
  c:=public.create_circle('Timely run','TIMELY001','UTC','12:00','20:00',10,true,120,'22:00');
  update public.circle_members set joined_at=now()-interval '30 days' where circle_id=c.id;
  for i in 0..4 loop
    insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state,kind)
      values(c.id,today-i,(today-i)::timestamptz+interval '12 hours',
        (today-i)::timestamptz+interval '12 hours 10 minutes',10,'closed','daily')
      on conflict(circle_id,local_date,kind) do update set starts_at=excluded.starts_at, ends_at=excluded.ends_at, state='closed'
      returning id into p;
    insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late)
      values(p,member,'typed','Timely fixture',i=2);
  end loop;
  execute 'set local role authenticated';
  assert (select days=5 and on_time_days=4 and on_time_streak_days=2 and on_time_today
    from public.circle_streaks(c.id) where member_id=member), 'late day must break only the consecutive timely run';
  execute 'reset role';
  -- One timely evening entry can qualify the same day, without counting twice.
  insert into public.daily_prompts(circle_id,local_date,starts_at,ends_at,response_window_minutes,state,kind)
    values(c.id,today-2,(today-2)::timestamptz+interval '22 hours',(today-1)::timestamptz+interval '5 hours',420,'closed','end_of_day')
    returning id into p;
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late) values(p,member,'typed','Evening fixture',true);
  insert into public.blessing_entry_grants(prompt_id,user_id,entered_at) values(p,member,(today-2)::timestamptz+interval '22 hours 1 second');
  execute 'set local role authenticated';
  assert (select days=5 and on_time_streak_days=5 from public.circle_streaks(c.id) where member_id=member);
  execute 'reset role';
  -- A missing calendar day breaks both independent runs.
  delete from public.blessings where author_id=member and prompt_id in (
    select id from public.daily_prompts where circle_id=c.id and local_date=today-1);
  execute 'set local role authenticated';
  assert (select days=1 and on_time_streak_days=1 from public.circle_streaks(c.id) where member_id=member);
  execute 'reset role';
  -- Grace is yesterday only when today has not been shared.
  delete from public.blessings where author_id=member and prompt_id in (
    select id from public.daily_prompts where circle_id=c.id and local_date=today);
  execute 'set local role authenticated';
  assert (select days=0 and on_time_streak_days=0 from public.circle_streaks(c.id) where member_id=member);
  execute 'reset role';
  select id into p from public.daily_prompts where circle_id=c.id and local_date=today-1 and kind='daily';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late) values(p,member,'typed','Yesterday',false);
  execute 'set local role authenticated';
  assert (select days=4 and on_time_streak_days=4 and not on_time_today from public.circle_streaks(c.id) where member_id=member);
  execute 'reset role';
  -- Today's late share ends yesterday's timely run instead of applying grace.
  select id into p from public.daily_prompts where circle_id=c.id and local_date=today and kind='daily';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late) values(p,member,'typed','Today late',true);
  execute 'set local role authenticated';
  assert (select days=5 and on_time_streak_days=0 and not on_time_today from public.circle_streaks(c.id) where member_id=member);
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin perform public.circle_streaks(c.id); raise exception 'outsider accepted';
    exception when others then assert sqlerrm='circle membership required',sqlerrm; end;
  execute 'reset role';
  assert not has_function_privilege('anon','public.circle_streaks(uuid)','execute');
end;
$$;
rollback;
