-- A scheduled timestamp is only a target: the dispatcher authors the actual
-- common start when claiming a prompt. Do not close welcome/evening entry or
-- open today's composer during the scheduler's short pre-claim delay.
do $$
declare v_definition text; v_name text;
begin
  v_definition:=pg_get_functiondef('public.first_join_blessing_prompt(uuid)'::regprocedure);
  if strpos(v_definition,'if v_prompt.id is null or v_now>=v_prompt.starts_at then')=0 then
    raise exception 'unexpected welcome lookup definition';
  end if;
  v_definition:=replace(v_definition,'if v_prompt.id is null or v_now>=v_prompt.starts_at then',
    'if v_prompt.id is null or (v_prompt.state<>''scheduled'' and v_now>=v_prompt.starts_at) then');
  execute v_definition;
  foreach v_name in array array['public.prompt_accepts_entry(uuid,uuid,timestamp with time zone)',
    'public.nudge_window_is_open(uuid,uuid,timestamp with time zone)', 'public.can_view_blessing(uuid,uuid,uuid)'] loop
    v_definition:=pg_get_functiondef(v_name::regprocedure);
    v_definition:=regexp_replace(v_definition,'(newer\.kind\s*=\s*''daily'')',
      '\1 and newer.state<>''scheduled''','g');
    v_definition:=replace(v_definition,'p_at>=p.starts_at','p.state<>''scheduled'' and p_at>=p.starts_at');
    v_definition:=replace(v_definition,'and current_day.starts_at>p_at',
      'and (current_day.state=''scheduled'' or current_day.starts_at>p_at)');
    execute v_definition;
  end loop;
end;
$$;
