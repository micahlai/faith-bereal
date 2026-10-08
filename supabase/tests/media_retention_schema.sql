-- Minimal disposable PostgreSQL schema for the real retention migration.
-- Never run this fixture against Supabase or another existing database.
create role anon;
create role authenticated;
create role service_role;
create type public.capture_mode as enum ('typed', 'voice', 'video');
create type public.response_mode as enum ('typed', 'voice');
create table public.blessings (
  id uuid primary key default gen_random_uuid(),
  capture_mode public.capture_mode not null,
  body text not null,
  audio_path text, video_path text, thumbnail_path text, photo_path text,
  submitted_at timestamptz not null default now(),
  constraint blessings_capture_payload_valid check (
    (capture_mode = 'typed' and audio_path is null and video_path is null)
    or (capture_mode = 'voice' and audio_path is not null and video_path is null)
    or (capture_mode = 'video' and audio_path is null and video_path is not null and photo_path is null)
  )
);
create table public.blessing_responses (
  id uuid primary key default gen_random_uuid(),
  blessing_id uuid not null references public.blessings(id),
  mode public.response_mode not null, body text not null,
  audio_path text, submitted_at timestamptz not null default now(),
  constraint blessing_responses_check check (
    (mode = 'typed' and audio_path is null) or (mode = 'voice' and audio_path is not null)
  )
);
