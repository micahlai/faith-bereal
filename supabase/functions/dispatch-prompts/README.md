# dispatch-prompts

Invoke this function once per minute from Supabase Cron/`pg_net`. Send the Vault-held `DISPATCH_SECRET` in `x-dispatch-secret`; do not schedule it with an end-user JWT.

It idempotently creates tomorrow’s prompt for every circle, atomically claims due prompts, sends a privacy-safe standard alert and push-to-start Live Activity request to active devices, and closes expired database prompts.

Before production:

1. Configure all values shown in `supabase/.env.example` as function secrets.
2. Enable Push Notifications, Time Sensitive Notifications, and Live Activities for the signed app target.
3. Verify ActivityKit’s generated JSON keys against a physical-device push-to-start capture before enabling production APNs.
4. Add delivery receipts/metrics and prune invalid tokens when APNs returns `410`.
5. Send an explicit end event to every `activity_registrations.push_token`; database closure alone does not dismiss a remote Live Activity.

