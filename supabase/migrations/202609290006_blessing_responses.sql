create type public.response_mode as enum ('typed', 'voice');

create table public.blessing_responses (
  id uuid primary key default gen_random_uuid(),
  blessing_id uuid not null references public.blessings(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  mode public.response_mode not null,
  body text not null check (char_length(body) between 1 and 600),
  audio_path text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    (mode = 'typed' and audio_path is null)
    or (mode = 'voice' and audio_path is not null)
  )
);

create index blessing_responses_blessing_time_idx
  on public.blessing_responses (blessing_id, submitted_at);

alter table public.blessing_responses enable row level security;

create policy "responses follow blessing visibility"
on public.blessing_responses for select to authenticated
using (
  exists (
    select 1
    from public.blessings b
    where b.id = blessing_id
      and public.can_view_blessing(b.prompt_id, b.author_id)
  )
);

create or replace function public.submit_blessing_response(
  p_blessing_id uuid,
  p_mode public.response_mode,
  p_body text,
  p_audio_path text default null
)
returns public.blessing_responses
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_blessing public.blessings;
  v_prompt public.daily_prompts;
  v_response public.blessing_responses;
  v_body text := trim(p_body);
  v_expected_prefix text;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if char_length(v_body) not between 1 and 600 then raise exception 'response must be 1 to 600 characters'; end if;

  select b.* into v_blessing
  from public.blessings b
  where b.id = p_blessing_id;
  if v_blessing.id is null
    or not public.can_view_blessing(v_blessing.prompt_id, v_blessing.author_id, v_user_id) then
    raise exception 'blessing not found';
  end if;

  select * into v_prompt from public.daily_prompts where id = v_blessing.prompt_id;
  if not public.is_circle_member(v_prompt.circle_id, v_user_id) then
    raise exception 'circle membership required';
  end if;

  v_expected_prefix := v_prompt.circle_id::text || '/' || v_prompt.id::text || '/'
    || v_user_id::text || '/responses/' || v_blessing.id::text || '/';
  if p_mode = 'typed' and p_audio_path is not null then raise exception 'text responses cannot include audio'; end if;
  if p_mode = 'voice' and (p_audio_path is null or p_audio_path not like v_expected_prefix || '%') then
    raise exception 'invalid response audio path';
  end if;

  insert into public.blessing_responses (blessing_id, author_id, mode, body, audio_path)
  values (p_blessing_id, v_user_id, p_mode, v_body, p_audio_path)
  returning * into v_response;
  return v_response;
end;
$$;

revoke all on function public.submit_blessing_response(uuid, public.response_mode, text, text)
  from public, anon;
grant execute on function public.submit_blessing_response(uuid, public.response_mode, text, text)
  to authenticated;
revoke insert, update, delete on public.blessing_responses from authenticated;

drop policy if exists "media owners upload to prompt path" on storage.objects;
create policy "media owners upload to prompt path"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'blessing-media'
  and (storage.foldername(name))[3] = auth.uid()::text
  and public.is_circle_member(public.try_uuid((storage.foldername(name))[1]))
  and (
    public.prompt_accepts_submission(
      public.try_uuid((storage.foldername(name))[2]),
      auth.uid(),
      clock_timestamp()
    )
    or (
      (storage.foldername(name))[4] = 'responses'
      and exists (
        select 1
        from public.blessings b
        where b.id = public.try_uuid((storage.foldername(name))[5])
          and b.prompt_id = public.try_uuid((storage.foldername(name))[2])
          and public.can_view_blessing(b.prompt_id, b.author_id)
      )
    )
  )
);

alter publication supabase_realtime add table public.blessing_responses;
