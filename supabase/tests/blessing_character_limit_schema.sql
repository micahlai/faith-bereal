-- Disposable local fixture only; never run against an existing database.
create role anon;
create role authenticated;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create type public.capture_mode as enum ('typed', 'voice', 'video');
create table public.daily_prompts (
  id uuid primary key,
  circle_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null
);
-- The real entry policy is unchanged by the migration. This fixture supplies
-- an open-window predicate to exercise the actual RPCs and their length guards.
create function public.prompt_accepts_submission(uuid, uuid, timestamptz)
returns boolean language sql as $$
  select exists(select 1 from public.daily_prompts p
    where p.id = $1 and $2 = auth.uid() and $3 >= p.starts_at and $3 < p.ends_at)
$$;
create table public.blessings (
  id uuid primary key default gen_random_uuid(),
  prompt_id uuid not null references public.daily_prompts(id),
  author_id uuid not null,
  capture_mode public.capture_mode not null,
  body text,
  audio_path text, video_path text, thumbnail_path text, photo_path text,
  submitted_at timestamptz not null,
  is_late boolean not null,
  edited_at timestamptz,
  scripture_book_slug text, scripture_book_name text,
  scripture_chapter integer, scripture_verse_start integer, scripture_verse_end integer,
  unique(prompt_id, author_id),
  check(body is null or char_length(body) between 1 and 600)
);
create table public.blessing_responses (
  id uuid primary key default gen_random_uuid(),
  body text not null check(char_length(body) between 1 and 600)
);
