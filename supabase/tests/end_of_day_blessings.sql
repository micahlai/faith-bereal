-- Runs inside a transaction against a migrated schema; all fixtures are rolled back.
begin;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_peer uuid := gen_random_uuid();
  v_circle public.circles;
  v_daily public.daily_prompts;
  v_evening public.daily_prompts;
  v_next_daily public.daily_prompts;
  v_at timestamptz := clock_timestamp();
  v_previous_date date := (clock_timestamp() at time zone 'UTC')::date - 1;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_owner, v_owner::text || '@example.invalid', '{"name":"Evening Owner"}'),
         (v_peer, v_peer::text || '@example.invalid', '{"name":"Evening Peer"}');
  insert into public.profiles (id, display_name)
  values (v_owner, 'Evening Owner'), (v_peer, 'Evening Peer')
  on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  v_circle := public.create_circle(
    'End of day test', 'TESTEOD1', 'UTC', time '12:00', time '22:00',
    10, true, 120, time '22:00'
  );
  if v_circle.end_of_day_time <> time '22:00' then
    raise exception 'creation lost end-of-day setting';
  end if;
  if (select count(*) from public.daily_prompts where circle_id = v_circle.id) <> 2 then
    raise exception 'creation must schedule both prompt kinds';
  end if;
  select * into strict v_daily from public.daily_prompts
  where circle_id = v_circle.id and kind = 'daily';
  select * into strict v_evening from public.daily_prompts
  where circle_id = v_circle.id and kind = 'end_of_day';
  if v_evening.ends_at - v_evening.starts_at <> interval '5 hours' then
    raise exception 'end-of-day must last five hours';
  end if;

  insert into public.circle_members (circle_id, user_id, role)
  values (v_circle.id, v_peer, 'member');
  update public.circle_members set joined_at = v_at - interval '3 days'
  where circle_id = v_circle.id;

  -- An active previous-day evening prompt remains gated after midnight.
  update public.daily_prompts
  set local_date = v_previous_date, starts_at = v_at - interval '2 hours',
      ends_at = v_at + interval '3 hours', state = 'open'
  where id = v_evening.id returning * into v_evening;
  update public.daily_prompts
  set local_date = v_previous_date, starts_at = v_at - interval '3 hours',
      ends_at = v_at - interval '3 hours' + interval '10 minutes', state = 'closed'
  where id = v_daily.id returning * into v_daily;

  insert into public.blessings (prompt_id, author_id, capture_mode, body)
  values (v_daily.id, v_owner, 'typed', 'Daily fixture'),
         (v_evening.id, v_peer, 'typed', 'Evening fixture');
  if public.can_view_blessing(v_evening.id, v_peer, v_owner) then
    raise exception 'daily submission must not unlock active previous-day evening content';
  end if;
  if not public.prompt_accepts_entry(v_evening.id, v_owner, v_at) then
    raise exception 'active evening entry was rejected';
  end if;
  if public.prompt_accepts_entry(v_evening.id, v_owner, v_evening.starts_at - interval '1 second') then
    raise exception 'evening opened before its start';
  end if;
  if public.prompt_accepts_entry(v_evening.id, v_owner, v_evening.ends_at) then
    raise exception 'late sharing must not extend the evening deadline';
  end if;

  perform public.begin_blessing_entry(v_evening.id);
  if not public.prompt_accepts_submission(v_evening.id, v_owner, v_evening.ends_at + interval '1 hour') then
    raise exception 'timely entry grant must survive the deadline';
  end if;
  insert into public.blessings (prompt_id, author_id, capture_mode, body)
  values (v_evening.id, v_owner, 'typed', 'My evening fixture');
  if not public.can_view_blessing(v_evening.id, v_peer, v_owner) then
    raise exception 'evening submission must unlock evening content';
  end if;

  insert into public.daily_prompts (
    circle_id, local_date, kind, starts_at, ends_at, response_window_minutes
  ) values (
    v_circle.id, v_previous_date + 1, 'daily', v_at + interval '1 hour',
    v_at + interval '1 hour 10 minutes', 10
  ) returning * into v_next_daily;
  if public.prompt_accepts_entry(v_evening.id, v_peer, v_next_daily.starts_at) then
    raise exception 'next daily prompt must close evening entry early';
  end if;
  if not public.prompt_accepts_entry(v_daily.id, v_peer, v_at) then
    raise exception 'evening start must not terminate late daily entry';
  end if;

  perform public.update_end_of_day_notifications(v_circle.id, false);
  if (select notify_on_end_of_day from public.circle_members
      where circle_id = v_circle.id and user_id = v_owner) then
    raise exception 'evening preference did not persist';
  end if;
  if not (select notify_on_circle_activity from public.circle_members
          where circle_id = v_circle.id and user_id = v_owner) then
    raise exception 'evening preference changed activity alerts';
  end if;

  begin
    perform public.update_circle_settings(
      v_circle.id, v_circle.name, 'UTC', time '12:00', time '22:00',
      10, true, 120, time '21:59'
    );
    raise exception 'invalid end-of-day time was accepted';
  exception when others then
    if sqlerrm <> 'end-of-day time must follow the random range' then raise; end if;
  end;

  if has_function_privilege('anon',
      'public.create_circle(text,text,text,time,time,integer,boolean,integer,time)', 'execute') then
    raise exception 'anonymous access to create RPC';
  end if;
end $$;

rollback;
