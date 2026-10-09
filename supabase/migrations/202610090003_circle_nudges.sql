alter table public.circle_notification_outbox add column recipient_id uuid references public.profiles(id) on delete cascade;
alter table public.circle_notification_outbox add column prompt_id uuid references public.daily_prompts(id) on delete cascade;
alter table public.circle_notification_outbox drop constraint circle_notification_outbox_event_type_check;
alter table public.circle_notification_outbox drop constraint circle_notification_outbox_check;
alter table public.circle_notification_outbox add constraint circle_notification_outbox_event_type_check
  check(event_type in ('blessing_shared','response_shared','member_nudged'));
alter table public.circle_notification_outbox add constraint circle_notification_outbox_payload_valid check (
  (event_type='blessing_shared' and response_id is null and recipient_id is null and prompt_id is null)
  or (event_type='response_shared' and response_id is not null and recipient_id is null and prompt_id is null)
  or (event_type='member_nudged' and response_id is null and recipient_id is not null and prompt_id is not null)
);
-- One reminder per recipient/prompt across all senders prevents pile-on spam.
create unique index circle_notification_outbox_nudge_idx
  on public.circle_notification_outbox(prompt_id,recipient_id) where event_type='member_nudged';

create function public.nudge_circle_member(p_prompt_id uuid,p_recipient_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user uuid:=auth.uid(); v_prompt public.daily_prompts; v_blessing uuid; v_count integer;
  v_now timestamptz:=clock_timestamp();
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_prompt from public.daily_prompts where id=p_prompt_id for update;
  if v_prompt.id is null or not public.is_circle_member(v_prompt.circle_id,v_user)
    or p_recipient_id=v_user or not public.is_circle_member(v_prompt.circle_id,p_recipient_id) then
    raise exception 'A nudge requires two current circle members';
  end if;
  select id into v_blessing from public.blessings where prompt_id=p_prompt_id and author_id=v_user;
  if v_blessing is null then raise exception 'Share your blessing before nudging'; end if;
  if v_now<v_prompt.starts_at or not public.prompt_accepts_entry(p_prompt_id,p_recipient_id,v_now) then
    raise exception 'This blessing entry window is closed';
  end if;
  if public.has_submitted(p_prompt_id,p_recipient_id) then raise exception 'This person already shared'; end if;
  insert into public.circle_notification_outbox(event_type,blessing_id,recipient_id,prompt_id)
    values('member_nudged',v_blessing,p_recipient_id,p_prompt_id) on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count=1;
end;
$$;
revoke all on function public.nudge_circle_member(uuid,uuid) from public,anon;
grant execute on function public.nudge_circle_member(uuid,uuid) to authenticated;

-- Re-check at dispatch: a queued reminder must not arrive for a closed window,
-- a completed recipient, a removed sender/member, or an opted-out recipient.
create function public.nudge_is_deliverable(p_notification_id uuid)
returns boolean language sql security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.circle_notification_outbox n
    join public.blessings b on b.id=n.blessing_id and b.prompt_id=n.prompt_id
    join public.daily_prompts p on p.id=n.prompt_id
    join public.circle_members cm on cm.circle_id=p.circle_id and cm.user_id=n.recipient_id
    where n.id=p_notification_id and n.event_type='member_nudged'
      and cm.removed_at is null and cm.notify_on_circle_activity
      and b.author_id<>n.recipient_id and public.is_circle_member(p.circle_id,b.author_id)
      and clock_timestamp()>=p.starts_at
      and public.prompt_accepts_entry(p.id,n.recipient_id,clock_timestamp())
      and not public.has_submitted(p.id,n.recipient_id));
$$;
revoke all on function public.nudge_is_deliverable(uuid) from public,anon,authenticated;
grant execute on function public.nudge_is_deliverable(uuid) to service_role;
