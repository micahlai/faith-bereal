-- Extend scheduling without re-sending old reminders or changing entry grants.
do $$
declare v_function record; v_definition text;
begin
  for v_function in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','manna_private') and p.proname in
      ('create_circle','update_circle_settings','ensure_tomorrow_prompts','force_circle_prompt') loop
    v_definition:=pg_get_functiondef(v_function.oid);
    if strpos(v_definition,'interval ''5 hours''')>0 then
      v_definition:=replace(v_definition,'interval ''5 hours''','interval ''7 hours''');
      v_definition:=regexp_replace(v_definition,'\m300\M','420','g');
      execute v_definition;
    end if;
  end loop;
end;
$$;
update public.daily_prompts set ends_at=starts_at+interval '7 hours',response_window_minutes=420
where kind='end_of_day';
