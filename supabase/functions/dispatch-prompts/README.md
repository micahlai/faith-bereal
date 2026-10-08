# dispatch-prompts

Invoke this function once per minute from Supabase Cron/`pg_net`. Authenticate with either the Vault-held `DISPATCH_SECRET` in `x-dispatch-secret` or the Supabase dashboard's server secret `apikey`; do not schedule it with an end-user JWT or expose either server credential to the app.

The app may also invoke the function with its normal user bearer token and `{ "action": "force", "circle_id": "…" }`. That path calls the owner-only `force_circle_prompt` RPC before dispatching. Never use `DISPATCH_SECRET` in the app.

It idempotently creates tomorrow’s prompt for every circle, atomically claims due prompts, reclaims interrupted prompts after five minutes while their window remains open, sends a privacy-safe standard alert and push-to-start Live Activity request to active devices, and updates active Live Activities with response counts and per-user completion. Submitted activities end with a three-minute dismissal grace period. No-late activities end three minutes after the entry deadline; late-enabled activities remain open until that member submits or a newer prompt replaces them. Standard alerts set `mutable-content` so the bundled notification service extension can apply the locally selected manna logo and download short-lived images. Activity alerts send `sender_avatar_url` separately for a small profile-photo inset within the left logo. Only unlocked blessing photo/video thumbnails are sent in `rich_media_url` for the right attachment; profile photos and responses never fall back into that slot. Blessing titles are “New blessing in [circle]” and response titles are “[circle]”. Locked recipients receive neither blessing copy nor attached blessing media. A server-only database cache reuses each APNs provider JWT for 45 minutes across stateless function runtimes, avoiding Apple's provider-token update throttle. Permanent APNs device-token errors clear the affected device token and revoke a registration only when no alert or push-to-start token remains.

The scheduler also creates and claims an independent `end_of_day` prompt at each circle's configured local time. It sends one ordinary alert to members with `notify_on_end_of_day` enabled, routes directly to that prompt's composer, and never starts or updates a Live Activity for it. Its entry window lasts five hours from dispatch or until the next daily random prompt starts, whichever comes first. Prompt alerts use a dispatch-key collapse identifier so interrupted dispatch retries do not create multiple pending reminders. Peer blessing and response alerts retain the separate circle-activity preference and use the visibility gate of their own prompt.

Before production:

Audio/video cleanup is gated by `MEDIA_RETENTION_ENABLED=true` and stays disabled for rollout. After the save-capable TestFlight build is available and disposable-object acceptance passes, the scheduler queues media 30 days after submission and removes Storage bytes with retry-safe batches. Text, photos, and references are retained. See `docs/MEDIA_RETENTION.md`; migration installation alone does not delete historical files.

1. Configure all values shown in `supabase/.env.example` as function secrets.
2. Enable Push Notifications, Time Sensitive Notifications, and Live Activities for the signed app target.
3. Verify ActivityKit’s generated JSON keys against a physical-device push-to-start capture before enabling production APNs.
4. Add durable delivery receipts/metrics; structured function logs and prompt failure summaries are not a substitute for release observability.
5. Schedule this function at least once per minute so response counts, close events, and prompt dispatch stay timely, then verify the resulting `net._http_response` rows are 2xx.
