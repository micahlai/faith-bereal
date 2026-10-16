-- SAFE hosted postflight: one random fixture circle and random accounts only.
-- No dispatch/Storage calls, global counts/deletes, migration edits, or fixture
-- identifiers/content in results. Real notification-outbox inserts are part of
-- this same uncommitted transaction, invisible to workers, and roll back.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts=on;
set local lock_timeout='2s';
set local statement_timeout='20s';

create or replace function pg_temp.expect_hosted_streak(c uuid,u uuid,at_time timestamptz,g integer,t integer)
returns void language plpgsql as $$
begin
  assert (select days=g and on_time_streak_days=t
    from manna_private.circle_streaks_at(c,at_time) where member_id=u),
    'Unexpected synthetic streak count';
end;
$$;

do $$
declare u uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
  d date:='2025-11-05'; p uuid; i integer; denied boolean;
begin
  assert has_function_privilege('authenticated','public.circle_streaks(uuid)','execute');
  assert not has_function_privilege('anon','public.circle_streaks(uuid)','execute');
  assert not has_schema_privilege('authenticated','manna_private','usage');
  assert not has_function_privilege('authenticated','manna_private.circle_streaks_at(uuid,timestamptz)','execute');

  insert into auth.users(id,raw_user_meta_data) values
    (u,'{"full_name":"Synthetic streak member"}'),(outsider,'{"full_name":"Synthetic streak outsider"}');
  -- The real auth trigger may already have created each required profile.
  insert into public.profiles(id,display_name,time_zone) values
    (u,'Synthetic streak member','UTC'),(outsider,'Synthetic streak outsider','UTC')
    on conflict(id) do update set display_name=excluded.display_name,time_zone=excluded.time_zone;
  -- Direct operator fixture insert avoids create_circle's current-day scheduled
  -- prompts. All currently required circle fields/checks are supplied explicitly.
  insert into public.circles(id,name,owner_id,invite_code_hash,time_zone,window_start,window_end,
    response_window_minutes,allow_late_blessings,repeat_window_minutes,end_of_day_time)
    values(c,'Synthetic streak postflight',u,extensions.crypt('STREAKTEST',extensions.gen_salt('bf',4)),
      'UTC','12:00','20:00',10,true,120,'22:00');
  insert into public.circle_members(circle_id,user_id,role,joined_at)
    values(c,u,'owner','2025-10-01');
  perform set_config('request.jwt.claims','{}',true);
  perform set_config('request.jwt.claim.sub',u::text,true);
  for i in 0..4 loop
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,response_window_minutes,state)
      values(c,d-i,'daily',(d-i)::timestamptz+interval '12 hours',
        (d-i)::timestamptz+interval '12 hours 10 minutes',10,'closed') returning id into p;
    insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
      values(p,u,'typed','Synthetic streak postflight',i>=3,(d-i)::timestamptz+interval '13 hours');
    if i<=2 then insert into public.blessing_entry_grants(prompt_id,user_id,entered_at)
      values(p,u,(d-i)::timestamptz+interval '12 hours 1 second'); end if;
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,response_window_minutes,state)
      values(c,d-i,'end_of_day',(d-i)::timestamptz+interval '22 hours',
        (d-i+1)::timestamptz+interval '5 hours',420,'closed');
  end loop;
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-05 13:00Z',5,3);
  assert (select on_time_days=3 and on_time_today from
    manna_private.circle_streaks_at(c,'2025-11-05 13:00Z') where member_id=u);
  -- Pending entry without a completed post preserves both counts only until
  -- the random deadline; general then waits for the actual evening cutoff.
  select id into p from public.daily_prompts where circle_id=c and local_date=d and kind='daily';
  delete from public.blessings where author_id=u and prompt_id=p;
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-05 12:09:59Z',4,2);
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-05 12:10Z',4,0);
  assert (select next_update_at='2025-11-06 05:00Z'::timestamptz from
    manna_private.circle_streaks_at(c,'2025-11-05 12:10Z') where member_id=u);
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-06 04:59:59Z',4,0);
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-06 05:00Z',0,0);
  select id into p from public.daily_prompts where circle_id=c and local_date=d and kind='end_of_day';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Synthetic evening completion',false,'2025-11-05 22:01Z');
  insert into public.blessing_entry_grants(prompt_id,user_id,entered_at) values(p,u,'2025-11-05 22:00:01Z');
  perform pg_temp.expect_hosted_streak(c,u,'2025-11-05 22:01Z',5,0);

  -- The public API is actually called as the application role. It uses real
  -- server time; fixture-time overrides remain available only to the operator.
  execute 'set local role authenticated';
  assert (select count(*)=1 from public.circle_streaks(c)), 'Synthetic member missing from public RPC';
  denied:=false;
  begin perform manna_private.circle_streaks_at(c,'2025-11-05 13:00Z');
    exception when insufficient_privilege then denied:=true; end;
  assert denied,'Application role could override streak time';
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin perform public.circle_streaks(c); raise exception 'Synthetic outsider accepted';
    exception when others then assert sqlerrm='circle membership required','Unexpected outsider rejection'; end;
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.circle_streaks(c); raise exception 'Unauthenticated fixture accepted';
    exception when others then assert sqlerrm='circle membership required','Unexpected anonymous rejection'; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',u::text,true);
  update public.circle_members set removed_at=clock_timestamp() where circle_id=c and user_id=u;
  execute 'set local role authenticated';
  begin perform public.circle_streaks(c); raise exception 'Synthetic removed member accepted';
    exception when others then assert sqlerrm='circle membership required','Unexpected removed-member rejection'; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$$;
rollback;
