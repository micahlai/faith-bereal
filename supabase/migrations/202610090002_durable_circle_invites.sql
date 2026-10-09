-- Codes were previously returned only to the creating/joining client; a hash
-- cannot be recovered after relaunch. Keep recoverable codes in a private table,
-- never in the publicly queried circle row. No code is rotated by this migration.
create schema if not exists manna_private;
revoke all on schema manna_private from public, anon, authenticated;
create table manna_private.circle_invite_codes (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9]{4,32}$')
);
alter table manna_private.circle_invite_codes enable row level security;
revoke all on manna_private.circle_invite_codes from public, anon, authenticated;

create function public.circle_invite_code(p_circle_id uuid, p_known_code text default null)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_hash text;
  v_code text := upper(trim(p_known_code));
  v_saved text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_circle_member(p_circle_id) then raise exception 'circle membership required'; end if;
  select invite_code_hash into v_hash from public.circles where id = p_circle_id for share;
  -- Opportunistically backfill an old circle using a still-valid known code.
  if v_code ~ '^[A-Z0-9]{4,32}$' and crypt(v_code, v_hash) = v_hash then
    insert into manna_private.circle_invite_codes(circle_id, code) values(p_circle_id, v_code)
      on conflict(circle_id) do update set code = excluded.code;
  end if;
  select code into v_saved from manna_private.circle_invite_codes where circle_id = p_circle_id;
  if crypt(v_saved, v_hash) = v_hash then return v_saved; end if;
  return null;
end;
$$;
revoke all on function public.circle_invite_code(uuid, text) from public, anon;
grant execute on function public.circle_invite_code(uuid, text) to authenticated;

-- Wrap the existing implementations to preserve their exact scheduling,
-- authorization, rate-limit, and membership semantics without duplicating them.
alter function public.create_circle(text, text, text, time, time, integer, boolean, integer, time)
  set schema manna_private;
revoke all on function manna_private.create_circle(text, text, text, time, time, integer, boolean, integer, time)
  from public, anon, authenticated;
create function public.create_circle(
  p_name text, p_invite_code text, p_time_zone text, p_window_start time, p_window_end time,
  p_response_window_minutes integer, p_allow_late_blessings boolean,
  p_repeat_window_minutes integer, p_end_of_day_time time
) returns public.circles language plpgsql security definer set search_path = public, pg_temp as $$
declare v_circle public.circles;
begin
  v_circle := manna_private.create_circle(p_name, p_invite_code, p_time_zone, p_window_start, p_window_end,
    p_response_window_minutes, p_allow_late_blessings, p_repeat_window_minutes, p_end_of_day_time);
  perform public.circle_invite_code(v_circle.id, upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g')));
  return v_circle;
end;
$$;
revoke all on function public.create_circle(text, text, text, time, time, integer, boolean, integer, time)
  from public, anon;
grant execute on function public.create_circle(text, text, text, time, time, integer, boolean, integer, time)
  to authenticated;

alter function public.regenerate_circle_invite_code(uuid, text) set schema manna_private;
revoke all on function manna_private.regenerate_circle_invite_code(uuid, text) from public, anon, authenticated;
create function public.regenerate_circle_invite_code(p_circle_id uuid, p_invite_code text)
returns public.circles language plpgsql security definer set search_path = public, pg_temp as $$
declare v_circle public.circles;
begin
  v_circle := manna_private.regenerate_circle_invite_code(p_circle_id, p_invite_code);
  perform public.circle_invite_code(v_circle.id, upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g')));
  return v_circle;
end;
$$;
revoke all on function public.regenerate_circle_invite_code(uuid, text) from public, anon;
grant execute on function public.regenerate_circle_invite_code(uuid, text) to authenticated;

alter function public.join_circle(text) set schema manna_private;
revoke all on function manna_private.join_circle(text) from public, anon, authenticated;
create function public.join_circle(p_invite_code text)
returns public.circles language plpgsql security definer set search_path = public, pg_temp as $$
declare v_circle public.circles;
begin
  v_circle := manna_private.join_circle(p_invite_code);
  perform public.circle_invite_code(v_circle.id, p_invite_code);
  return v_circle;
end;
$$;
revoke all on function public.join_circle(text) from public, anon;
grant execute on function public.join_circle(text) to authenticated;

comment on function public.circle_invite_code(uuid, text) is
  'Active-member-only code recovery; valid known codes backfill legacy circles. Never rotates a code.';
