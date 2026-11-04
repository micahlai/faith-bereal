-- Direct nudges are independent of per-circle scheduled/activity preferences.
-- Keep current-member, same-prompt, sharing-window and submission checks.
create or replace function public.nudge_is_deliverable(p_notification_id uuid)
returns boolean language sql security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.circle_notification_outbox n
    join public.blessings b on b.id=n.blessing_id and b.prompt_id=n.prompt_id
    join public.daily_prompts p on p.id=n.prompt_id
    join public.circle_members cm on cm.circle_id=p.circle_id and cm.user_id=n.recipient_id
    where n.id=p_notification_id and n.event_type='member_nudged'
      and cm.removed_at is null
      and b.author_id<>n.recipient_id and public.is_circle_member(p.circle_id,b.author_id)
      and clock_timestamp()>=p.starts_at
      and public.nudge_window_is_open(p.id,n.recipient_id,clock_timestamp())
      and not public.has_submitted(p.id,n.recipient_id));
$$;
revoke all on function public.nudge_is_deliverable(uuid) from public,anon,authenticated;
grant execute on function public.nudge_is_deliverable(uuid) to service_role;
