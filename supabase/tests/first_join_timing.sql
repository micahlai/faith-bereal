-- Rollback-only; no remote notifications or Storage operations.
begin;
set local plpgsql.check_asserts=on;
do $$
declare v_user uuid:=gen_random_uuid(); v_peer uuid:=gen_random_uuid(); v_circle public.circles;
  v_today public.daily_prompts; v_welcome uuid; v_start timestamptz:=clock_timestamp()+interval '1 hour';
begin
  insert into auth.users(id,email,raw_user_meta_data) values(v_user,v_user::text||'@example.invalid','{}'),(v_peer,v_peer::text||'@example.invalid','{}');
  insert into public.profiles(id,display_name) values(v_user,'Welcome regression'),(v_peer,'Existing member') on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  v_circle:=public.create_circle('Temporary welcome regression',upper(left(replace(gen_random_uuid()::text,'-',''),10)),
    'UTC',time '12:00',time '22:00',10,false,120,time '22:00');
  update public.daily_prompts set starts_at=v_start,ends_at=v_start+interval '10 minutes' where circle_id=v_circle.id and kind='daily' returning * into strict v_today;
  insert into public.circle_members(circle_id,user_id,role,joined_at) values(v_circle.id,v_peer,'member',clock_timestamp()-interval '3 days');
  execute 'set local role authenticated';
  v_welcome:=public.first_join_blessing_prompt(v_circle.id);
  assert v_welcome is not null;
  execute 'reset role';
  assert (select local_date=v_today.local_date-1 from public.daily_prompts where id=v_welcome);
  assert public.prompt_accepts_entry(v_welcome,v_user,clock_timestamp());
  assert not public.prompt_accepts_entry(v_welcome,v_peer,clock_timestamp());
  assert not public.prompt_accepts_entry(v_today.id,v_user,clock_timestamp());
  assert not public.prompt_accepts_entry(v_welcome,v_user,v_start);
  -- Join-day sharing opens for today's prompt only after its notification.
  assert public.prompt_accepts_entry(v_today.id,v_user,v_start+interval '11 minutes') =
    ((v_start+interval '11 minutes')::date=v_today.local_date);
  update public.circles set allow_late_blessings=true where id=v_circle.id;
  assert not public.prompt_accepts_entry(v_welcome,v_peer,clock_timestamp());
  assert not public.nudge_window_is_open(v_welcome,v_peer,clock_timestamp());
  assert not public.prompt_accepts_entry(v_today.id,v_user,(v_today.local_date+1)::timestamptz+interval '1 day');
  assert (select ends_at-starts_at=interval '7 hours' and response_window_minutes=420 from public.daily_prompts where circle_id=v_circle.id and kind='end_of_day');
  assert not has_function_privilege('anon','public.first_join_blessing_prompt(uuid)','execute');
  assert not has_function_privilege('anon','public.daily_prompt_entry_cutoff(uuid)','execute');
  assert not has_function_privilege('authenticated','public.daily_prompt_entry_cutoff(uuid)','execute');
  update public.circles set time_zone='America/New_York' where id=v_circle.id;
  update public.daily_prompts set local_date=date '2026-11-01', starts_at=timestamptz '2026-11-01 16:50:00Z',
    ends_at=timestamptz '2026-11-01 17:00:00Z' where id=v_today.id;
  assert public.daily_prompt_entry_cutoff(v_today.id)=timestamptz '2026-11-02 05:00:00Z';
  update public.circles set allow_late_blessings=false where id=v_circle.id;
  assert public.daily_prompt_entry_cutoff(v_today.id)=timestamptz '2026-11-01 17:00:00Z';
end;
$$;
rollback;
