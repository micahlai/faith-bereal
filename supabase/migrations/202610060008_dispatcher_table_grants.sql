grant select on table public.circles to service_role;
grant select on table public.circle_members to service_role;
grant select on table public.blessings to service_role;
grant select on table public.daily_prompts to service_role;
grant select on table public.device_registrations to service_role;
grant select on table public.activity_registrations to service_role;

grant update (state, failure_reason, closed_at) on table public.daily_prompts to service_role;
grant update (apns_token, push_to_start_token, revoked_at) on table public.device_registrations to service_role;
grant update (ended_at) on table public.activity_registrations to service_role;

comment on table public.device_registrations is
  'Server-managed APNs and Live Activity tokens; clients register only through register_device().';
