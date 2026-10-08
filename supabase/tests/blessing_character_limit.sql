begin;
do $$
declare
  v_user uuid := gen_random_uuid();
  v_circle uuid := gen_random_uuid();
  v_prompt uuid;
  v_length integer;
  v_mode public.capture_mode;
  v_prefix text;
  v_blessing public.blessings;
  v_body text;
  v_error text;
begin
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  foreach v_mode in array array['typed', 'voice', 'video']::public.capture_mode[] loop
    foreach v_length in array array[600, 601, 1199, 1200] loop
      v_prompt := gen_random_uuid();
      insert into public.daily_prompts values
        (v_prompt, v_circle, now() - interval '1 minute', now() + interval '9 minutes');
      v_prefix := v_circle::text || '/' || v_prompt::text || '/' || v_user::text || '/';
      v_body := repeat('a', v_length);
      if v_mode = 'video' then
        v_blessing := public.finalize_video_blessing(v_prompt, v_prefix || 'video.mov', v_body);
      else
        v_blessing := public.submit_text_blessing(v_prompt, v_mode, v_body,
          case when v_mode = 'voice' then v_prefix || 'voice.caf' else null end);
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
          perform public.finalize_video_blessing(v_prompt, v_prefix || 'video.mov', repeat('a', 1201));
        else
          perform public.submit_text_blessing(v_prompt, v_mode, repeat('a', 1201));
        end if;
        raise exception 'oversized submission accepted';
      exception when others then
        get stacked diagnostics v_error = message_text;
        assert v_error in ('blessing must be 1 to 1200 characters', 'transcript must be 1 to 1200 characters'), v_error;
      end;
    end loop;
  end loop;

  -- Multi-scalar emoji use the same boundary as the client policy.
  v_prompt := gen_random_uuid();
  insert into public.daily_prompts values
    (v_prompt, v_circle, now() - interval '1 minute', now() + interval '9 minutes');
  v_blessing := public.submit_text_blessing(v_prompt, 'typed', repeat('👨‍👩‍👧‍👦', 171));
  assert char_length(v_blessing.body) = 1197;
  begin
    perform public.update_blessing(v_blessing.id, repeat('👨‍👩‍👧‍👦', 172));
    raise exception 'oversized emoji edit accepted';
  exception when others then
    get stacked diagnostics v_error = message_text;
    assert v_error = 'blessing must be 1 to 1200 characters', v_error;
  end;
  begin
    perform public.submit_text_blessing(v_prompt, 'typed', null);
    raise exception 'null text accepted';
  exception when others then
    get stacked diagnostics v_error = message_text;
    assert v_error = 'blessing must be 1 to 1200 characters', v_error;
  end;
  -- Check that the table itself rejects bypassing the RPC with a longer body.
  begin
    update public.blessings set body = repeat('x', 1201) where id = v_blessing.id;
    raise exception 'oversized direct write accepted';
  exception when check_violation then null;
  end;
  insert into public.blessing_responses(body) values(repeat('r', 600));
  begin
    insert into public.blessing_responses(body) values(repeat('r', 601));
    raise exception 'response limit unexpectedly changed';
  exception when check_violation then null;
  end;
  assert has_function_privilege('authenticated', 'public.update_blessing(uuid,text,text,text,integer,integer,integer)', 'execute');
  assert not has_function_privilege('anon', 'public.update_blessing(uuid,text,text,text,integer,integer,integer)', 'execute');
  assert not has_function_privilege('anon', 'public.submit_text_blessing(uuid,public.capture_mode,text,text,text,text,text,integer,integer,integer)', 'execute');
  assert not has_function_privilege('anon', 'public.finalize_video_blessing(uuid,text,text,text,text,text,integer,integer,integer)', 'execute');
end;
$$;
rollback;
