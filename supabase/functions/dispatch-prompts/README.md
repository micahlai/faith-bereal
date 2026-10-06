# dispatch-prompts

Invoke this function once per minute from Supabase Cron/`pg_net`. Authenticate with either the Vault-held `DISPATCH_SECRET` in `x-dispatch-secret` or the Supabase dashboard's server secret `apikey`; do not schedule it with an end-user JWT or expose either server credential to the app.

The app may also invoke the function with its normal user bearer token and `{ "action": "force", "circle_id": "…" }`. That path calls the owner-only `force_circle_prompt` RPC before dispatching. Never use `DISPATCH_SECRET` in the app.

It idempotently creates tomorrow’s prompt for every circle, atomically claims due prompts, reclaims interrupted prompts after five minutes while their window remains open, sends a privacy-safe standard alert and push-to-start Live Activity request to active devices, updates active Live Activities with response counts and per-user completion, and ends expired activities before closing their prompts. A server-only database cache reuses each APNs provider JWT for 45 minutes across stateless function runtimes, avoiding Apple's provider-token update throttle. Permanent APNs device-token errors clear the affected device token and revoke a registration only when no alert or push-to-start token remains.

Before production:

1. Configure all values shown in `supabase/.env.example` as function secrets.
2. Enable Push Notifications, Time Sensitive Notifications, and Live Activities for the signed app target.
3. Verify ActivityKit’s generated JSON keys against a physical-device push-to-start capture before enabling production APNs.
4. Add durable delivery receipts/metrics; structured function logs and prompt failure summaries are not a substitute for release observability.
5. Schedule this function at least once per minute so response counts, close events, and prompt dispatch stay timely, then verify the resulting `net._http_response` rows are 2xx.
