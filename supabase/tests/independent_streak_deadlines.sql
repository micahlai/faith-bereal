-- Disposable/rollback-only regressions. Clock overrides are private operator
-- calls; the client RPC always uses server time and has no clock parameter.
begin;
set local time zone 'UTC';
set local plpgsql.check_asserts=on;
do $$
declare definition text;
begin
  definition:=replace(pg_get_functiondef('manna_private.circle_streaks_at(uuid,timestamptz)'::regprocedure),
    'manna_private.circle_streaks_at','pg_temp.unbounded_streaks');
  assert position('generate_series(b.floor::timestamp' in definition)>0;
  definition:=replace(definition,'generate_series(b.floor::timestamp','generate_series(m.joined_day::timestamp');
  execute definition;
end;
$$;
create function pg_temp.expect_streak(c uuid,u uuid,at_time timestamptz,g integer,t integer) returns void
language plpgsql as $$
declare actual record;
begin
  select * into actual from manna_private.circle_streaks_at(c,at_time) where member_id=u;
  assert actual.days=g and actual.on_time_streak_days=t,
    format('at %s expected %s/%s, got %s/%s',at_time,g,t,actual.days,actual.on_time_streak_days);
  assert (select to_jsonb(r) from manna_private.circle_streaks_at(c,at_time) r where member_id=u)
    =(select to_jsonb(r) from pg_temp.unbounded_streaks(c,at_time) r where member_id=u),
    'Bounded calendar differs from the unbounded reference';
end;
$$;
do $$
declare u uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); newcomer uuid:=gen_random_uuid();
  c uuid:=gen_random_uuid(); dst uuid:=gen_random_uuid(); partial uuid:=gen_random_uuid();
  d date:='2026-11-05'; p uuid; i integer;
begin
  insert into auth.users(id) values(u),(outsider),(newcomer);
  insert into public.profiles(id) values(u),(outsider),(newcomer);
  insert into public.circles(id,name,owner_id,time_zone,window_start,window_end,response_window_minutes,
    allow_late_blessings,repeat_window_minutes,end_of_day_time)
    values(c,'Independent streak fixture',u,'UTC','12:00','20:00',10,true,120,'22:00'),
      (dst,'DST fixture',u,'America/New_York','12:00','20:00',10,true,120,'22:00'),
      (partial,'Missing window fixture',u,'UTC','12:00','18:00',10,true,120,'19:00');
  insert into public.circle_members(circle_id,user_id,role,joined_at) values
    (c,u,'owner','2026-10-01'),(c,newcomer,'member','2026-11-05'),(dst,u,'owner','2026-10-01'),
    (partial,u,'owner','2026-10-01');
  perform set_config('request.jwt.claim.sub',u::text,true);
  for i in 0..4 loop
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
      values(c,d-i,'daily',(d-i)::timestamptz+interval '12 hours',
        (d-i)::timestamptz+interval '12 hours 10 minutes','closed') returning id into p;
    insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
      values(p,u,'typed','Fixture',i>=3,(d-i)::timestamptz+interval '13 hours');
    -- Legacy timely flag and actual entry grants both work, even if sending finishes late.
    if i<=2 then insert into public.blessing_entry_grants(prompt_id,user_id,entered_at)
      values(p,u,(d-i)::timestamptz+interval '12 hours 1 second'); end if;
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
      values(c,d-i,'end_of_day',(d-i)::timestamptz+interval '22 hours',
        (d-i+1)::timestamptz+interval '5 hours','closed');
  end loop;
  perform pg_temp.expect_streak(c,u,'2026-11-05 13:00Z',5,3);
  -- Two posts still earn exactly one authored day; evening cannot repair timely history.
  select id into p from public.daily_prompts where circle_id=c and local_date=d-3 and kind='end_of_day';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Evening',false,'2026-11-02 22:01Z');
  insert into public.blessing_entry_grants values(p,u,'2026-11-02 22:00:01Z');
  perform pg_temp.expect_streak(c,u,'2026-11-05 13:00Z',5,3);
  -- Future dated posts and pre-membership content do not count.
  insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
    values(c,d+1,'daily','2026-11-06 12:00Z','2026-11-06 12:10Z','scheduled') returning id into p;
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Future',false,'2026-11-06 12:01Z');
  select id into p from public.daily_prompts where circle_id=c and local_date=d-1 and kind='daily';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,newcomer,'typed','Before membership',false,'2026-11-04 12:01Z');
  perform pg_temp.expect_streak(c,newcomer,'2026-11-05 13:00Z',0,0);
  perform pg_temp.expect_streak(c,u,'2026-11-05 13:00Z',5,3);
  -- Remove today's completion. Both counts hold before the random deadline;
  -- only timely resets at exactly that deadline, despite a timely entry grant.
  delete from public.blessings where author_id=u and prompt_id in
    (select id from public.daily_prompts where circle_id=c and local_date=d);
  perform pg_temp.expect_streak(c,u,'2026-11-05 12:09:59Z',4,2);
  perform pg_temp.expect_streak(c,u,'2026-11-05 12:10Z',4,0);
  assert (select next_update_at='2026-11-05 12:10Z'::timestamptz from
    manna_private.circle_streaks_at(c,'2026-11-05 12:09:59Z') where member_id=u);
  assert (select next_update_at='2026-11-06 05:00Z'::timestamptz from
    manna_private.circle_streaks_at(c,'2026-11-05 12:10Z') where member_id=u);
  -- A completed evening blessing restores/extends general only.
  select id into p from public.daily_prompts where circle_id=c and local_date=d and kind='end_of_day';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Evening only',false,'2026-11-05 22:01Z');
  perform pg_temp.expect_streak(c,u,'2026-11-05 22:01Z',5,0);
  perform pg_temp.expect_streak(c,u,'2026-11-06 00:01Z',5,0);
  delete from public.blessings where prompt_id=p and author_id=u;
  -- Yesterday's unfinished evening remains pending across midnight, then resets.
  perform pg_temp.expect_streak(c,u,'2026-11-05 23:59:59Z',4,0);
  perform pg_temp.expect_streak(c,u,'2026-11-06 04:59:59Z',4,0);
  perform pg_temp.expect_streak(c,u,'2026-11-06 05:00Z',0,0);
  -- Next random notification can end evening earlier than seven hours.
  update public.daily_prompts set starts_at='2026-11-06 04:00Z',ends_at='2026-11-06 04:10Z',state='closed'
    where circle_id=c and local_date=d+1 and kind='daily';
  perform pg_temp.expect_streak(c,u,'2026-11-06 03:59:59Z',4,0);
  perform pg_temp.expect_streak(c,u,'2026-11-06 04:00Z',0,0);
  delete from public.blessings where prompt_id in (select id from public.daily_prompts where circle_id=c and local_date=d+1);
  delete from public.daily_prompts where circle_id=c and local_date=d+1;
  -- The original authored date still receives a late-finished, timely-entry post.
  select id into p from public.daily_prompts where circle_id=c and local_date=d and kind='daily';
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Finished after midnight',true,'2026-11-06 05:01Z');
  perform pg_temp.expect_streak(c,u,'2026-11-06 05:01Z',5,3);
  -- Grant deadline is exclusive; legacy is_late=false cannot override a late grant.
  update public.blessing_entry_grants set entered_at='2026-11-05 12:10Z' where prompt_id=p and user_id=u;
  perform pg_temp.expect_streak(c,u,'2026-11-06 05:01Z',5,0);
  -- Welcome/pre-notification content does not earn the regular day.
  update public.blessings set submitted_at='2026-11-05 11:59Z',is_late=false where prompt_id=p and author_id=u;
  perform pg_temp.expect_streak(c,u,'2026-11-06 05:01Z',0,0);
  -- A planned notification that never started has no authoritative early cutoff.
  update public.daily_prompts set state='scheduled' where id=p;
  perform pg_temp.expect_streak(c,u,'2026-11-05 13:00Z',4,2);
  perform pg_temp.expect_streak(c,u,'2026-11-06 00:00Z',4,0);
  assert (select next_update_at='2026-11-06 00:00Z'::timestamptz from
    manna_private.circle_streaks_at(c,'2026-11-05 13:00Z') where member_id=u);
  update public.daily_prompts set state='closed' where id=p;
  -- A missing authored day is a real gap, not a compressed list of posted dates.
  delete from public.blessings where prompt_id=p and author_id=u;
  delete from public.blessing_entry_grants where prompt_id=p;
  delete from public.daily_prompts where id=p;
  perform pg_temp.expect_streak(c,u,'2026-11-07 00:00Z',0,0);
  -- DST fall-back: 22:00 EDT + seven elapsed hours is 04:00 EST.
  for i in 0..1 loop
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
      values(dst,date '2026-10-30'+i,'end_of_day',
        ((date '2026-10-30'+i)+time '22:00') at time zone 'America/New_York',
        (((date '2026-10-30'+i)+time '22:00') at time zone 'America/New_York')+interval '7 hours','closed') returning id into p;
    if i=0 then insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
      values(p,u,'typed','DST previous day',false,'2026-10-31 02:01Z'); end if;
  end loop;
  perform pg_temp.expect_streak(dst,u,'2026-11-01 08:59:59Z',1,0);
  perform pg_temp.expect_streak(dst,u,'2026-11-01 09:00Z',0,0);
  -- Spring-forward is also seven elapsed hours: 22:00 EST closes 06:00 EDT.
  update public.circle_members set joined_at='2026-01-01' where circle_id=dst;
  for i in 0..1 loop
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
      values(dst,date '2026-03-06'+i,'end_of_day',
        ((date '2026-03-06'+i)+time '22:00') at time zone 'America/New_York',
        (((date '2026-03-06'+i)+time '22:00') at time zone 'America/New_York')+interval '7 hours','closed') returning id into p;
    if i=0 then insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
      values(p,u,'typed','Spring previous day',false,'2026-03-07 03:01Z'); end if;
  end loop;
  perform pg_temp.expect_streak(dst,u,'2026-03-08 09:59:59Z',1,0);
  perform pg_temp.expect_streak(dst,u,'2026-03-08 10:00Z',0,0);
  -- Missing evening retains midnight as the general fallback. Conversely a
  -- real evening cutoff is authoritative even if random never dispatched.
  insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
    values(partial,'2026-11-04','end_of_day','2026-11-04 19:00Z','2026-11-04 20:00Z','closed') returning id into p;
  insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    values(p,u,'typed','Partial windows previous day',false,'2026-11-04 19:01Z');
  insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
    values(partial,d,'daily','2026-11-05 12:00Z','2026-11-05 12:10Z','closed');
  perform pg_temp.expect_streak(partial,u,'2026-11-05 13:00Z',1,0);
  assert (select next_update_at='2026-11-06 00:00Z'::timestamptz from
    manna_private.circle_streaks_at(partial,'2026-11-05 13:00Z') where member_id=u);
  update public.daily_prompts set state='scheduled' where circle_id=partial and local_date=d;
  insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
    values(partial,d,'end_of_day','2026-11-05 19:00Z','2026-11-05 20:00Z','closed');
  perform pg_temp.expect_streak(partial,u,'2026-11-05 19:59:59Z',1,0);
  perform pg_temp.expect_streak(partial,u,'2026-11-05 20:00Z',0,0);
  execute 'set local role authenticated';
  assert (select count(*)=2 from public.circle_streaks(c)), 'authenticated wrapper returns current members only';
  execute 'reset role';
  -- Current-member authentication on both wrapper and private operator helper.
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin perform public.circle_streaks(c); raise exception 'outsider accepted';
    exception when others then assert sqlerrm='circle membership required',sqlerrm; end;
  perform set_config('request.jwt.claim.sub',u::text,true);
  update public.circle_members set removed_at=now() where circle_id=c and user_id=u;
  begin perform public.circle_streaks(c); raise exception 'removed member accepted';
    exception when others then assert sqlerrm='circle membership required',sqlerrm; end;
  assert not has_function_privilege('anon','public.circle_streaks(uuid)','execute');
  assert has_function_privilege('authenticated','public.circle_streaks(uuid)','execute');
  assert not has_schema_privilege('authenticated','manna_private','usage');
  assert not has_function_privilege('authenticated','manna_private.circle_streaks_at(uuid,timestamptz)','execute');
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.circle_streaks(dst); raise exception 'anonymous accepted';
    exception when others then assert sqlerrm='circle membership required',sqlerrm; end;
end;
$$;
rollback;
