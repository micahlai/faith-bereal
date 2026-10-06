grant execute on function public.ensure_tomorrow_prompts() to service_role;
grant execute on function public.claim_due_prompts(integer) to service_role;

comment on function public.ensure_tomorrow_prompts() is
  'Creates tomorrow prompts for the privileged APNs dispatcher.';

comment on function public.claim_due_prompts(integer) is
  'Atomically claims due prompts for the privileged APNs dispatcher and retries interrupted, still-open dispatches.';
