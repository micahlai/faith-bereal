-- Against a migrated hosted schema; all fixtures and queued events roll back.
-- No dispatch/cleanup function or Storage API is invoked.
begin;
set local plpgsql.check_asserts = on;
do $$
declare
  v_user uuid := gen_random_uuid();
  v_circle public.circles;
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_mode public.capture_mode;
  v_length integer;
  v_prefix text;
  v_error text;
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values(v_user, v_user::text || '@example.invalid', '{"name":"Length test"}');
  insert into public.profiles(id, display_name) values(v_user, 'Length test')
  on conflict(id) do nothing;
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  foreach v_mode in array array['typed', 'voice', 'video']::public.capture_mode[] loop
    foreach v_length in array array[600, 601, 1199, 1200] loop
      v_circle := public.create_circle(
        'Temporary length regression', upper(left(replace(gen_random_uuid()::text, '-', ''), 10)),
        'UTC', time '12:00', time '22:00', 10, true, 120, time '22:00');
      update public.daily_prompts set starts_at = now() - interval '1 minute',
        ends_at = now() + interval '9 minutes', state = 'open'
      where circle_id = v_circle.id and kind = 'daily' returning * into strict v_prompt;
      v_prefix := v_circle.id::text || '/' || v_prompt.id::text || '/' || v_user::text || '/';
      if v_mode = 'video' then
        v_blessing := public.finalize_video_blessing(v_prompt.id, v_prefix || 'fixture.mov', repeat('a', v_length));
      else
        v_blessing := public.submit_text_blessing(v_prompt.id, v_mode, repeat('a', v_length),
          case when v_mode = 'voice' then v_prefix || 'fixture.caf' else null end);
      end if;
      assert char_length(v_blessing.body) = v_length;
      v_blessing := public.update_blessing(v_blessing.id, repeat('b', 1200));
      assert char_length(v_blessing.body) = 1200;
      begin
        perform public.update_blessing(v_blessing.id, repeat('b', 1201));
        raise exception 'oversized edit accepted';
      exception when others then
        get stacked diagnostics v_error = message_text;
        assert v_error = 'blessing must be 1 to 1200 characters', v_error;
      end;
      begin
        if v_mode = 'video' then
          perform public.finalize_video_blessing(v_prompt.id, v_prefix || 'fixture.mov', repeat('a', 1201));
        else
          perform public.submit_text_blessing(v_prompt.id, v_mode, repeat('a', 1201));
        end if;
        raise exception 'oversized submission accepted';
      exception when others then
        get stacked diagnostics v_error = message_text;
        assert v_error in ('blessing must be 1 to 1200 characters', 'transcript must be 1 to 1200 characters'), v_error;
      end;
      begin
        if v_mode = 'video' then
          perform public.finalize_video_blessing(v_prompt.id, v_prefix || 'fixture.mov', repeat('a', 1200));
        else
          perform public.submit_text_blessing(v_prompt.id, v_mode, repeat('a', 1200),
            case when v_mode = 'voice' then v_prefix || 'fixture.caf' else null end);
        end if;
        raise exception 'duplicate accepted';
      exception when others then
        get stacked diagnostics v_error = message_text;
        assert v_error = 'already submitted', v_error;
      end;
    end loop;
  end loop;
  assert not has_function_privilege('anon',
    'public.submit_text_blessing(uuid,public.capture_mode,text,text,text,text,text,integer,integer,integer)', 'execute');
  assert not has_function_privilege('anon',
    'public.finalize_video_blessing(uuid,text,text,text,text,text,integer,integer,integer)', 'execute');
  assert not has_function_privilege('anon',
    'public.update_blessing(uuid,text,text,text,integer,integer,integer)', 'execute');
end;
$$;
rollback;
