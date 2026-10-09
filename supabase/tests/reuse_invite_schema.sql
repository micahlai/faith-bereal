-- Disposable local fixture ONLY. Loads the actual create/join/rotate/visibility
-- functions separately; the entry predicate here supplies an ordinary open gate.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;
create schema storage;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb);
create table public.profiles(id uuid primary key references auth.users(id), display_name text);
create type public.member_role as enum ('owner', 'member');
create type public.capture_mode as enum ('typed', 'voice', 'video');
create type public.response_mode as enum ('typed', 'voice');
create type public.prompt_state as enum ('scheduled', 'dispatching', 'open', 'closed', 'failed');
create table public.circles (
  id uuid primary key default gen_random_uuid(), name text, owner_id uuid references public.profiles,
  invite_code_hash text, time_zone text, window_start time, window_end time,
  response_window_minutes integer, allow_late_blessings boolean, repeat_window_minutes integer,
  end_of_day_time time, created_at timestamptz default now()
);
create table public.circle_members (
  circle_id uuid references public.circles on delete cascade, user_id uuid references public.profiles,
  role public.member_role, joined_at timestamptz default now(), removed_at timestamptz,
  primary key(circle_id, user_id)
);
create table public.invite_join_attempts(user_id uuid, attempted_at timestamptz default now(), succeeded boolean);
create table public.daily_prompts (
  id uuid primary key default gen_random_uuid(), circle_id uuid references public.circles on delete cascade,
  local_date date, starts_at timestamptz, ends_at timestamptz, response_window_minutes integer,
  state public.prompt_state default 'scheduled', closed_at timestamptz, kind text default 'daily',
  unique(circle_id, local_date, kind)
);
create table public.blessings (
  id uuid primary key default gen_random_uuid(), prompt_id uuid references public.daily_prompts,
  author_id uuid references public.profiles, capture_mode public.capture_mode,
  body text check(body is null or char_length(body) between 1 and 600),
  audio_path text, video_path text, thumbnail_path text, photo_path text,
  submitted_at timestamptz default now(), is_late boolean, edited_at timestamptz,
  scripture_book_slug text, scripture_book_name text, scripture_chapter integer,
  scripture_verse_start integer, scripture_verse_end integer,
  repeated_from_blessing_id uuid references public.blessings, unique(prompt_id, author_id),
  constraint blessings_capture_payload_valid check (
    (capture_mode = 'typed' and audio_path is null and video_path is null)
    or (capture_mode = 'voice' and audio_path is not null and video_path is null)
    or (capture_mode = 'video' and video_path is not null and audio_path is null and photo_path is null)
  )
);
create table public.blessing_responses (
  id uuid primary key default gen_random_uuid(), blessing_id uuid references public.blessings,
  mode public.response_mode, body text, audio_path text, submitted_at timestamptz default now(),
  constraint blessing_responses_check check (
    (mode = 'typed' and audio_path is null) or (mode = 'voice' and audio_path is not null)
  )
);
create function public.prompt_accepts_submission(uuid, uuid, timestamptz) returns boolean
language sql as $$ select exists(select 1 from public.daily_prompts p
  where p.id = $1 and public.is_circle_member(p.circle_id, $2) and $3 >= p.starts_at and $3 < p.ends_at) $$;
create table storage.objects(bucket_id text, name text);
alter table storage.objects enable row level security;
grant usage on schema storage, auth to authenticated;
grant select on storage.objects to authenticated;
create function storage.foldername(text) returns text[] language sql as $$ select string_to_array($1, '/') $$;
