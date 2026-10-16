-- Disposable only: generated ten-year sparse/dense fixtures and read benchmarks.
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
do $$
declare u uuid:=gen_random_uuid(); sparse uuid:=gen_random_uuid(); dense uuid:=gen_random_uuid();
  d date:='2025-11-05'; p uuid; n integer; account uuid; bounded_plan json; reference_plan json;
  bounded_result jsonb; reference_result jsonb; candidate uuid; label text;
begin
  for n in 1..20 loop
    account:=case when n=1 then u else gen_random_uuid() end;
    insert into auth.users(id) values(account);
    insert into public.profiles(id,display_name) values(account,'Sparse ten-year fixture');
    if n=1 then
      insert into public.circles(id,name,owner_id,time_zone) values
        (sparse,'Sparse benchmark',u,'UTC'),(dense,'Dense benchmark',u,'UTC');
      insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
        values(sparse,d-3650,'daily',(d-3650)::timestamptz+interval '12 hours',
          (d-3650)::timestamptz+interval '12 hours 10 minutes','closed') returning id into p;
    end if;
    insert into public.circle_members(circle_id,user_id,role,joined_at)
      values(sparse,account,'member',(d-3650)::timestamptz);
    insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
      values(p,account,'typed','Sparse fixture',false,(d-3650)::timestamptz+interval '12 hours 1 second');
  end loop;
  insert into public.circle_members(circle_id,user_id,role,joined_at) values(dense,u,'owner',(d-3650)::timestamptz);
  with prompts as (
    insert into public.daily_prompts(circle_id,local_date,kind,starts_at,ends_at,state)
    select dense,d-i,'daily',(d-i)::timestamptz+interval '12 hours',
      (d-i)::timestamptz+interval '12 hours 10 minutes','closed' from generate_series(0,3650) i returning id,starts_at
  ) insert into public.blessings(prompt_id,author_id,capture_mode,body,is_late,submitted_at)
    select id,u,'typed','Dense fixture',false,starts_at+interval '1 second' from prompts;
  perform set_config('request.jwt.claim.sub',u::text,true);
  assert (select days=3651 and on_time_streak_days=3651 from manna_private.circle_streaks_at(dense,d::timestamptz+interval '13 hours') where member_id=u);
  foreach candidate in array array[sparse,dense] loop
    label:=case when candidate=sparse then '20-member sparse' else 'one-member dense' end;
    select jsonb_agg(to_jsonb(r) order by member_id) into bounded_result
      from manna_private.circle_streaks_at(candidate,d::timestamptz+interval '13 hours') r;
    select jsonb_agg(to_jsonb(r) order by member_id) into reference_result
      from pg_temp.unbounded_streaks(candidate,d::timestamptz+interval '13 hours') r;
    assert bounded_result=reference_result,'Ten-year bounded/reference results differ';
    execute format('explain (analyze,buffers,timing off,format json) select * from manna_private.circle_streaks_at(%L,%L)',
      candidate,d::timestamptz+interval '13 hours') into bounded_plan;
    execute format('explain (analyze,buffers,timing off,format json) select * from pg_temp.unbounded_streaks(%L,%L)',
      candidate,d::timestamptz+interval '13 hours') into reference_plan;
    raise notice '% EXPLAIN ANALYZE: bounded % ms, unbounded % ms, output rows %',label,
      bounded_plan->0->>'Execution Time',reference_plan->0->>'Execution Time',bounded_plan->0->'Plan'->>'Actual Rows';
  end loop;
end;
$$;
rollback;
