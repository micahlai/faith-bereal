-- Private moderation records; no report content or reporter identity is exposed to peers.
create table manna_private.user_blocks (
  blocker uuid not null references auth.users(id) on delete cascade,
  blocked uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker,blocked), check(blocker<>blocked)
);
create table manna_private.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid references auth.users(id) on delete set null,
  blessing_id uuid references public.blessings(id) on delete set null,
  response_id uuid references public.blessing_responses(id) on delete set null,
  reason text not null check(reason in ('harassment','sexual','hate','violence','privacy','spam','other')),
  detail text not null default '' check(char_length(detail)<=1000),
  status text not null default 'open' check(status in ('open','dismissed','hidden')),
  created_at timestamptz not null default now(), resolved_at timestamptz,
  check (not (blessing_id is not null and response_id is not null))
);
create index content_reports_open on manna_private.content_reports(created_at) where status='open';
create unique index content_report_blessing_once on manna_private.content_reports(reporter,blessing_id) where blessing_id is not null;
create unique index content_report_response_once on manna_private.content_reports(reporter,response_id) where response_id is not null;
create table manna_private.hidden_content (
  blessing_id uuid primary key references public.blessings(id) on delete cascade,
  hidden_at timestamptz not null default now()
);
create table manna_private.hidden_responses (
  response_id uuid primary key references public.blessing_responses(id) on delete cascade,
  hidden_at timestamptz not null default now()
);
create table manna_private.suspended_users (
  user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
create table manna_private.account_deletions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  apple_revoked boolean not null default false,
  last_error text check(last_error in ('apple','storage','mirror','database','auth')),
  attempts integer not null default 0,
  last_attempt_at timestamptz
);
revoke all on all tables in schema manna_private from public,anon,authenticated;
alter table manna_private.user_blocks enable row level security;
alter table manna_private.content_reports enable row level security;
alter table manna_private.hidden_content enable row level security;
alter table manna_private.hidden_responses enable row level security;
alter table manna_private.suspended_users enable row level security;
alter table manna_private.account_deletions enable row level security;

create function public.account_is_active(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from public.profiles p where p.id=p_user and p.deleted_at is null) and not exists(select 1 from manna_private.account_deletions d where d.user_id=p_user)
 and not exists(select 1 from manna_private.suspended_users s where s.user_id=p_user);
$$;
create function public.safety_can_interact(p_author uuid,p_viewer uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$
 select public.account_is_active(p_author) and public.account_is_active(p_viewer) and not exists(
 select 1 from manna_private.user_blocks b where (b.blocker=p_author and b.blocked=p_viewer) or (b.blocker=p_viewer and b.blocked=p_author));
$$;
-- Keep the current daily/evening/history authorization intact underneath safety.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('public.can_view_blessing(uuid,uuid,uuid)'::regprocedure);
 definition:=replace(definition,'public.can_view_blessing(', 'manna_private.can_view_blessing_before_safety(');
 execute definition;
end $$;
revoke all on function manna_private.can_view_blessing_before_safety(uuid,uuid,uuid) from public,anon,authenticated;
create or replace function public.can_view_blessing(p_prompt_id uuid,p_author_id uuid,p_viewer_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author_id,p_viewer_id)
 and not exists(select 1 from public.blessings b join manna_private.hidden_content h on h.blessing_id=b.id where b.prompt_id=p_prompt_id and b.author_id=p_author_id)
 and manna_private.can_view_blessing_before_safety(p_prompt_id,p_author_id,p_viewer_id);
$$;
-- RLS expressions use definer helpers so private tables remain ungranted.
create function public.response_is_safe(p_id uuid,p_author uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author) and not exists(select 1 from manna_private.hidden_responses h where h.response_id=p_id);
$$;
create policy "safety response visibility" on public.blessing_responses as restrictive for select to authenticated using(public.response_is_safe(id,author_id));
create policy "active account storage" on storage.objects as restrictive for all to authenticated
 using(public.account_is_active() and (bucket_id<>'avatars' or public.safety_can_interact(public.try_uuid((storage.foldername(name))[1]))))
 with check(public.account_is_active());
-- Block all direct table activity by deletion/suspension identities, including old JWTs.
do $$ declare t record; begin
 for t in select tablename from pg_tables where schemaname='public' and rowsecurity loop
 execute format('create policy "active account access" on public.%I as restrictive for all to authenticated using(public.account_is_active()) with check(public.account_is_active())',t.tablename);
 end loop;
end $$;
-- Security-definer mutation RPCs bypass RLS. Write triggers enforce suspension/deletion as well.
create function manna_private.reject_inactive_write() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and not public.account_is_active() then raise exception 'Account is unavailable' using errcode='42501'; end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
do $$ declare t record; begin
 for t in select tablename from pg_tables where schemaname='public' and rowsecurity loop
 execute format('create trigger reject_inactive_write before insert or update or delete on public.%I for each row execute function manna_private.reject_inactive_write()',t.tablename);
 end loop;
end $$;

create function public.set_user_block(p_user uuid,p_blocked boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.account_is_active() or p_user=auth.uid() or p_user is null then raise exception 'Invalid block'; end if;
 if p_blocked then
  if not exists(select 1 from public.circle_members a join public.circle_members b on a.circle_id=b.circle_id where a.user_id=auth.uid() and b.user_id=p_user and a.removed_at is null and b.removed_at is null) then raise exception 'No shared circle'; end if;
  insert into manna_private.user_blocks(blocker,blocked) values(auth.uid(),p_user) on conflict do nothing;
 else delete from manna_private.user_blocks where blocker=auth.uid() and blocked=p_user;
 end if;
end $$;
create function public.my_blocked_users() returns table(user_id uuid,display_name text) language sql stable security definer set search_path='' as $$
 select b.blocked,p.display_name from manna_private.user_blocks b join public.profiles p on p.id=b.blocked where b.blocker=auth.uid() and public.account_is_active();
$$;
create function public.report_content(p_blessing uuid default null,p_response uuid default null,p_reason text default 'other',p_detail text default '') returns uuid
language plpgsql security definer set search_path='' as $$
declare v_author uuid; v_prompt uuid; result uuid;
begin
 if not public.account_is_active() or (p_blessing is null)=(p_response is null) then raise exception 'Invalid report'; end if;
 if (select count(*) from manna_private.content_reports where reporter=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'Report limit reached. Contact support.'; end if;
 if p_blessing is not null then select author_id,prompt_id into v_author,v_prompt from public.blessings where id=p_blessing;
 else select r.author_id,b.prompt_id into v_author,v_prompt from public.blessing_responses r join public.blessings b on b.id=r.blessing_id where r.id=p_response;
 end if;
 if v_author is null or v_author=auth.uid() or not public.can_view_blessing(v_prompt,case when p_response is null then v_author else (select b.author_id from public.blessings b join public.blessing_responses r on r.blessing_id=b.id where r.id=p_response) end) then raise exception 'Content unavailable'; end if;
 insert into manna_private.content_reports(reporter,blessing_id,response_id,reason,detail) values(auth.uid(),p_blessing,p_response,p_reason,coalesce(p_detail,''))
 on conflict do nothing returning id into result;
 return result;
end $$;
-- A conservative text filter runs server-side before publishing. Reports and human
-- review still cover contextual abuse and media; do not claim automated media AI.
create function manna_private.filter_published_text() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.body ~* '(kill[[:space:]]+yourself|child[[:space:]]+porn|nigg(er|a)|faggot)' then
 raise exception 'This text cannot be posted. Review the community rules.' using errcode='22023'; end if;
 return new;
end $$;
create trigger filter_published_text before insert or update of body on public.blessings for each row execute function manna_private.filter_published_text();
create trigger filter_response_text before insert or update of body on public.blessing_responses for each row execute function manna_private.filter_published_text();

create function public.moderation_inbox(p_limit integer default 50) returns setof manna_private.content_reports
language sql security definer set search_path='' as $$ select * from manna_private.content_reports where status='open' order by created_at limit greatest(1,least(p_limit,100)); $$;
create function public.resolve_content_report(p_report uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare r manna_private.content_reports;
begin
 select * into strict r from manna_private.content_reports where id=p_report for update;
 if p_action not in ('dismiss','hide','suspend') then raise exception 'Invalid moderation action'; end if;
 if p_action in ('hide','suspend') then
  if r.blessing_id is not null then insert into manna_private.hidden_content(blessing_id) values(r.blessing_id) on conflict do nothing;
  elsif r.response_id is not null then insert into manna_private.hidden_responses(response_id) values(r.response_id) on conflict do nothing; end if;
 end if;
 if p_action='suspend' then
  insert into manna_private.suspended_users(user_id)
  select author_id from public.blessings where id=r.blessing_id union select author_id from public.blessing_responses where id=r.response_id on conflict do nothing;
 end if;
 update manna_private.content_reports set status=case when p_action='dismiss' then 'dismissed' else 'hidden' end,resolved_at=now() where id=r.id;
end $$;

revoke all on all functions in schema manna_private from public,anon,authenticated;
revoke all on function public.account_is_active(uuid),public.safety_can_interact(uuid,uuid),public.response_is_safe(uuid,uuid),public.set_user_block(uuid,boolean),public.my_blocked_users(),public.report_content(uuid,uuid,text,text),public.moderation_inbox(integer),public.resolve_content_report(uuid,text) from public,anon;
revoke all on function public.moderation_inbox(integer),public.resolve_content_report(uuid,text) from authenticated;
grant execute on function public.account_is_active(uuid),public.safety_can_interact(uuid,uuid),public.response_is_safe(uuid,uuid),public.set_user_block(uuid,boolean),public.my_blocked_users(),public.report_content(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.moderation_inbox(integer),public.resolve_content_report(uuid,text) to service_role;
notify pgrst,'reload schema';

-- Media is withheld from peers until a human reviewer approves it. This provides
-- pre-publication filtering without claiming an unimplemented image/audio model.
create table manna_private.media_review_queue (
 id uuid primary key default gen_random_uuid(),
 blessing_id uuid references public.blessings(id) on delete cascade,
 response_id uuid references public.blessing_responses(id) on delete cascade,
 created_at timestamptz not null default now(),
 check((blessing_id is null)<>(response_id is null)),
 unique(blessing_id),unique(response_id)
);
alter table manna_private.media_review_queue enable row level security;
revoke all on manna_private.media_review_queue from public,anon,authenticated;
create function manna_private.queue_media_review() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='blessings' then
  if new.audio_path is not null or new.video_path is not null or new.photo_path is not null then
   insert into manna_private.media_review_queue(blessing_id) values(new.id) on conflict do nothing;
   insert into manna_private.hidden_content(blessing_id) values(new.id) on conflict do nothing;
  end if;
 elsif new.audio_path is not null then
  insert into manna_private.media_review_queue(response_id) values(new.id) on conflict do nothing;
  insert into manna_private.hidden_responses(response_id) values(new.id) on conflict do nothing;
 end if;
 return null;
end $$;
create trigger queue_blessing_media_review after insert or update of audio_path,video_path,photo_path on public.blessings for each row execute function manna_private.queue_media_review();
create trigger queue_response_media_review after insert or update of audio_path on public.blessing_responses for each row execute function manna_private.queue_media_review();
-- Authors may view their own pending media, with the usual membership gate.
create or replace function public.can_view_blessing(p_prompt_id uuid,p_author_id uuid,p_viewer_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author_id,p_viewer_id)
 and (not exists(select 1 from public.blessings b join manna_private.hidden_content h on h.blessing_id=b.id where b.prompt_id=p_prompt_id and b.author_id=p_author_id)
   or (p_author_id=p_viewer_id and exists(select 1 from public.blessings b join manna_private.media_review_queue q on q.blessing_id=b.id where b.prompt_id=p_prompt_id and b.author_id=p_author_id)))
 and manna_private.can_view_blessing_before_safety(p_prompt_id,p_author_id,p_viewer_id);
$$;
create or replace function public.response_is_safe(p_id uuid,p_author uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.safety_can_interact(p_author) and (not exists(select 1 from manna_private.hidden_responses h where h.response_id=p_id)
 or (p_author=auth.uid() and exists(select 1 from manna_private.media_review_queue q where q.response_id=p_id)));
$$;
create function public.media_review_inbox(p_limit integer default 50) returns setof manna_private.media_review_queue
language sql security definer set search_path='' as $$ select * from manna_private.media_review_queue order by created_at limit greatest(1,least(p_limit,100)); $$;
create function public.resolve_media_review(p_review uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare q manna_private.media_review_queue;
begin
 select * into strict q from manna_private.media_review_queue where id=p_review for update;
 if p_approve then
  delete from manna_private.hidden_content where blessing_id=q.blessing_id and not exists(
   select 1 from manna_private.content_reports r where r.blessing_id=q.blessing_id and r.status='hidden');
  delete from manna_private.hidden_responses where response_id=q.response_id and not exists(
   select 1 from manna_private.content_reports r where r.response_id=q.response_id and r.status='hidden');
 end if;
 delete from manna_private.media_review_queue where id=q.id;
end $$;
revoke all on function manna_private.queue_media_review(),public.media_review_inbox(integer),public.resolve_media_review(uuid,boolean) from public,anon,authenticated;
grant execute on function public.media_review_inbox(integer),public.resolve_media_review(uuid,boolean) to service_role;
-- Restricted reads close response-audio paths, including hidden/pending responses.
create function public.media_is_safe(p_bucket text,p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select case when p_bucket='blessing-media' then public.safety_can_interact(public.try_uuid((storage.foldername(p_name))[3]))
 and not exists(select 1 from public.blessing_responses r where r.audio_path=p_name and not public.response_is_safe(r.id,r.author_id))
 else true end;
$$;
revoke all on function public.media_is_safe(text,text) from public,anon;
grant execute on function public.media_is_safe(text,text) to authenticated,service_role;
create policy "safe media reads" on storage.objects as restrictive for select to authenticated using(public.media_is_safe(bucket_id,name));
notify pgrst,'reload schema';
