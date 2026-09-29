create extension if not exists pgcrypto with schema extensions;

create type public.member_role as enum ('owner', 'member');
create type public.capture_mode as enum ('typed', 'voice', 'video');
create type public.prompt_state as enum ('scheduled', 'dispatching', 'open', 'closed', 'failed');
create type public.push_environment as enum ('sandbox', 'production');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  avatar_path text,
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  owner_id uuid not null references public.profiles(id),
  invite_code_hash text not null,
  time_zone text not null default 'UTC',
  window_start time not null default '08:00',
  window_end time not null default '20:00',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (window_end > window_start)
);

create table public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'member',
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (circle_id, user_id)
);

create table public.daily_prompts (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  local_date date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  state public.prompt_state not null default 'scheduled',
  dispatch_key uuid not null default gen_random_uuid(),
  dispatched_at timestamptz,
  closed_at timestamptz,
  failure_reason text,
  created_at timestamptz not null default now(),
  unique (circle_id, local_date),
  check (ends_at = starts_at + interval '10 minutes')
);

create table public.blessings (
  id uuid primary key default gen_random_uuid(),
  prompt_id uuid not null references public.daily_prompts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  capture_mode public.capture_mode not null,
  body text,
  video_path text,
  thumbnail_path text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (prompt_id, author_id),
  check (body is null or char_length(body) between 1 and 600),
  check (
    (capture_mode in ('typed', 'voice') and body is not null and video_path is null)
    or
    (capture_mode = 'video' and body is null and video_path is not null)
  )
);

create table public.device_registrations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  installation_id uuid not null,
  apns_token text,
  push_to_start_token text,
  environment public.push_environment not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, installation_id, environment)
);

create table public.activity_registrations (
  id uuid primary key default gen_random_uuid(),
  prompt_id uuid not null references public.daily_prompts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  activity_id text not null,
  push_token text not null,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  unique (prompt_id, user_id, activity_id)
);

create table public.invite_join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded boolean not null
);

create index circle_members_active_user_idx
  on public.circle_members (user_id, circle_id) where removed_at is null;
create index daily_prompts_due_idx
  on public.daily_prompts (starts_at) where state = 'scheduled';
create index daily_prompts_close_idx
  on public.daily_prompts (ends_at) where state in ('open', 'dispatching');
create index blessings_prompt_idx on public.blessings (prompt_id, submitted_at);
create index device_registrations_active_user_idx
  on public.device_registrations (user_id) where revoked_at is null;
create index activity_registrations_active_prompt_idx
  on public.activity_registrations (prompt_id) where ended_at is null;
create index invite_join_attempts_rate_idx on public.invite_join_attempts (user_id, attempted_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger circles_set_updated_at
before update on public.circles
for each row execute function public.set_updated_at();

create or replace function public.is_circle_member(p_circle_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = p_circle_id
      and cm.user_id = p_user_id
      and cm.removed_at is null
  );
$$;

create or replace function public.has_submitted(p_prompt_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.blessings b
    where b.prompt_id = p_prompt_id and b.author_id = p_user_id
  );
$$;

create or replace function public.can_view_blessing(
  p_prompt_id uuid,
  p_author_id uuid,
  p_viewer_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(bool_or(
    public.is_circle_member(p.circle_id, p_viewer_id)
    and (
      p_author_id = p_viewer_id
      or p.local_date < (now() at time zone c.time_zone)::date
      or public.has_submitted(p.id, p_viewer_id)
    )
  ), false)
  from public.daily_prompts p
  join public.circles c on c.id = p.circle_id
  where p.id = p_prompt_id;
$$;

create or replace function public.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

alter table public.profiles enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.daily_prompts enable row level security;
alter table public.blessings enable row level security;
alter table public.device_registrations enable row level security;
alter table public.activity_registrations enable row level security;
alter table public.invite_join_attempts enable row level security;

create policy "profiles read self or circle peers"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or exists (
    select 1
    from public.circle_members mine
    join public.circle_members peer on peer.circle_id = mine.circle_id
    where mine.user_id = auth.uid()
      and mine.removed_at is null
      and peer.user_id = profiles.id
      and peer.removed_at is null
  )
);

create policy "profiles update self"
on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

create policy "circles read members"
on public.circles for select to authenticated
using (public.is_circle_member(id));

create policy "members read circle members"
on public.circle_members for select to authenticated
using (public.is_circle_member(circle_id));

create policy "prompts read members"
on public.daily_prompts for select to authenticated
using (public.is_circle_member(circle_id));

create policy "blessings enforce gated reads"
on public.blessings for select to authenticated
using (public.can_view_blessing(prompt_id, author_id));

create policy "devices own rows"
on public.device_registrations for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "activities own rows"
on public.activity_registrations for all to authenticated
using (user_id = auth.uid()) with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.daily_prompts p
    where p.id = prompt_id and public.is_circle_member(p.circle_id)
  )
);

create or replace function public.create_circle(
  p_name text,
  p_invite_code text,
  p_time_zone text default 'UTC'
)
returns public.circles
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g'));
  v_circle public.circles;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'invalid circle name'; end if;
  if char_length(v_code) not between 6 and 10 then raise exception 'invalid invite code'; end if;
  perform 1 from pg_timezone_names where name = p_time_zone;
  if not found then raise exception 'invalid time zone'; end if;

  insert into public.circles (name, owner_id, invite_code_hash, time_zone)
  values (trim(p_name), v_user_id, crypt(v_code, gen_salt('bf', 10)), p_time_zone)
  returning * into v_circle;

  insert into public.circle_members (circle_id, user_id, role)
  values (v_circle.id, v_user_id, 'owner');
  return v_circle;
end;
$$;

create or replace function public.join_circle(p_invite_code text)
returns public.circles
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(p_invite_code, '[^A-Z0-9]', '', 'g'));
  v_circle public.circles;
  v_attempts integer;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select count(*) into v_attempts
  from public.invite_join_attempts
  where user_id = v_user_id and attempted_at > now() - interval '15 minutes';
  if v_attempts >= 10 then raise exception 'too many attempts'; end if;

  select c.* into v_circle
  from public.circles c
  where c.invite_code_hash = crypt(v_code, c.invite_code_hash)
  order by c.created_at desc
  limit 1;

  insert into public.invite_join_attempts (user_id, succeeded)
  values (v_user_id, v_circle.id is not null);
  if v_circle.id is null then raise exception 'invalid invite code'; end if;

  insert into public.circle_members (circle_id, user_id, role, joined_at, removed_at)
  values (v_circle.id, v_user_id, 'member', now(), null)
  on conflict (circle_id, user_id) do update
    set role = 'member', joined_at = now(), removed_at = null;
  return v_circle;
end;
$$;

create or replace function public.submit_text_blessing(
  p_prompt_id uuid,
  p_mode public.capture_mode,
  p_body text
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_body text := trim(p_body);
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if p_mode not in ('typed', 'voice') then raise exception 'invalid capture mode'; end if;
  if char_length(v_body) not between 1 and 600 then raise exception 'blessing must be 1 to 600 characters'; end if;

  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.is_circle_member(v_prompt.circle_id, v_user_id) then
    raise exception 'prompt not found';
  end if;
  if clock_timestamp() < v_prompt.starts_at or clock_timestamp() >= v_prompt.ends_at then
    raise exception 'response window is closed';
  end if;

  insert into public.blessings (prompt_id, author_id, capture_mode, body, submitted_at)
  values (p_prompt_id, v_user_id, p_mode, v_body, clock_timestamp())
  returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

create or replace function public.finalize_video_blessing(
  p_prompt_id uuid,
  p_video_path text,
  p_thumbnail_path text default null
)
returns public.blessings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_prompt public.daily_prompts;
  v_blessing public.blessings;
  v_expected_prefix text;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  select * into v_prompt from public.daily_prompts where id = p_prompt_id for update;
  if v_prompt.id is null or not public.is_circle_member(v_prompt.circle_id, v_user_id) then
    raise exception 'prompt not found';
  end if;
  if clock_timestamp() < v_prompt.starts_at or clock_timestamp() >= v_prompt.ends_at then
    raise exception 'response window is closed';
  end if;

  v_expected_prefix := v_prompt.circle_id::text || '/' || p_prompt_id::text || '/' || v_user_id::text || '/';
  if p_video_path not like v_expected_prefix || '%' then raise exception 'invalid video path'; end if;
  if p_thumbnail_path is not null and p_thumbnail_path not like v_expected_prefix || '%' then
    raise exception 'invalid thumbnail path';
  end if;

  insert into public.blessings (
    prompt_id, author_id, capture_mode, video_path, thumbnail_path, submitted_at
  ) values (
    p_prompt_id, v_user_id, 'video', p_video_path, p_thumbnail_path, clock_timestamp()
  ) returning * into v_blessing;
  return v_blessing;
exception when unique_violation then
  raise exception 'already submitted';
end;
$$;

create or replace function public.register_device(
  p_installation_id uuid,
  p_apns_token text,
  p_push_to_start_token text,
  p_environment public.push_environment
)
returns public.device_registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.device_registrations;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into public.device_registrations (
    user_id, installation_id, apns_token, push_to_start_token, environment, last_seen_at, revoked_at
  ) values (
    auth.uid(), p_installation_id, nullif(p_apns_token, ''), nullif(p_push_to_start_token, ''),
    p_environment, now(), null
  )
  on conflict (user_id, installation_id, environment) do update set
    apns_token = excluded.apns_token,
    push_to_start_token = excluded.push_to_start_token,
    last_seen_at = now(),
    revoked_at = null
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.ensure_tomorrow_prompts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.circles;
  v_date date;
  v_seconds integer;
  v_start_local timestamp;
  v_count integer := 0;
begin
  for c in select * from public.circles loop
    v_date := (now() at time zone c.time_zone)::date + 1;
    v_seconds := floor(random() * extract(epoch from (c.window_end - c.window_start)))::integer;
    v_start_local := v_date + c.window_start + make_interval(secs => v_seconds);
    insert into public.daily_prompts (circle_id, local_date, starts_at, ends_at)
    values (
      c.id,
      v_date,
      v_start_local at time zone c.time_zone,
      (v_start_local at time zone c.time_zone) + interval '10 minutes'
    )
    on conflict (circle_id, local_date) do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.claim_due_prompts(p_limit integer default 100)
returns setof public.daily_prompts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with claimed as (
    select p.id
    from public.daily_prompts p
    where p.state = 'scheduled' and p.starts_at <= now()
    order by p.starts_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.daily_prompts p
  set state = 'dispatching', dispatched_at = now(), failure_reason = null
  from claimed
  where p.id = claimed.id
  returning p.*;
end;
$$;

revoke all on function public.ensure_tomorrow_prompts() from public, anon, authenticated;
revoke all on function public.claim_due_prompts(integer) from public, anon, authenticated;
grant execute on function public.create_circle(text, text, text) to authenticated;
grant execute on function public.join_circle(text) to authenticated;
grant execute on function public.submit_text_blessing(uuid, public.capture_mode, text) to authenticated;
grant execute on function public.finalize_video_blessing(uuid, text, text) to authenticated;
grant execute on function public.register_device(uuid, text, text, public.push_environment) to authenticated;

revoke insert, update, delete on public.blessings from authenticated;
revoke insert, update, delete on public.daily_prompts from authenticated;
revoke insert, update, delete on public.circles from authenticated;
revoke insert, update, delete on public.circle_members from authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'blessing-media',
  'blessing-media',
  false,
  78643200,
  array['video/quicktime', 'video/mp4', 'image/jpeg']
)
on conflict (id) do nothing;

create policy "media owners upload to prompt path"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'blessing-media'
  and (storage.foldername(name))[3] = auth.uid()::text
  and public.is_circle_member(public.try_uuid((storage.foldername(name))[1]))
  and exists (
    select 1 from public.daily_prompts p
    where p.id = public.try_uuid((storage.foldername(name))[2])
      and p.circle_id = public.try_uuid((storage.foldername(name))[1])
      and now() >= p.starts_at and now() < p.ends_at
  )
);

create policy "media reads follow blessing visibility"
on storage.objects for select to authenticated
using (
  bucket_id = 'blessing-media'
  and public.can_view_blessing(
    public.try_uuid((storage.foldername(name))[2]),
    public.try_uuid((storage.foldername(name))[3])
  )
);

alter publication supabase_realtime add table public.daily_prompts;
alter publication supabase_realtime add table public.blessings;

