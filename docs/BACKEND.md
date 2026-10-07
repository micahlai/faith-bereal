# Backend and data model

## Recommended stack

- Supabase Auth with Sign in with Apple
- Postgres with Row Level Security
- Supabase Realtime for unlocked feed refreshes
- Supabase Storage for private video and thumbnails
- Edge Functions for privileged commands and APNs provider calls
- `pg_cron` + `pg_net` for minute-level scheduling
- APNs token authentication for alerts and ActivityKit pushes

## Tables

### `profiles`

`id`, `display_name`, `avatar_path`, `time_zone`, `bible_version_id`, `created_at`, `deleted_at`

### `circles`

`id`, `name`, `owner_id`, `invite_code_hash`, `time_zone`, `window_start`, `window_end`, `response_window_minutes`, `allow_late_blessings`, `repeat_window_minutes`, `created_at`

Only a hash of the normalized invite code is stored. Joining happens through a security-definer RPC that rate-limits attempts.

`create_circle` accepts the complete owner-selected configuration and transactionally inserts the owner membership plus the current local-day prompt. Prompt timing is server-authored from that initial range and duration, so creation settings take effect immediately without a client-side follow-up update.

`regenerate_circle_invite_code` is owner-only and replaces the stored hash in one update. The former code becomes invalid immediately; existing memberships are unchanged.

### `circle_members`

`circle_id`, `user_id`, `role`, `joined_at`, `removed_at`

Unique active membership per circle/user pair.

`leave_circle` marks a membership removed. When the departing member owns the circle, the RPC transfers ownership to the earliest-joined active member; if nobody remains, it deletes the circle transactionally.

### `daily_prompts`

`id`, `circle_id`, `local_date`, `starts_at`, `ends_at`, `response_window_minutes`, `state`, `dispatch_key`, `created_at`

Unique `(circle_id, local_date)`. `ends_at` is constrained to the response duration snapshotted from its circle when the prompt is created.

The random timestamp is a dispatch target. `claim_due_prompts` replaces `starts_at` and `ends_at` with the actual server claim time and the snapshotted duration before APNs delivery, so minute-level scheduler latency never consumes the member's entry window. Scheduled prompts missed by more than five minutes are closed without sending a stale alert.

### `blessing_entry_grants`

`prompt_id`, `user_id`, `entered_at`

Unique `(prompt_id, user_id)`. The `begin_blessing_entry` RPC inserts this server-timestamped grant only while entry is allowed. Submission RPCs accept either a currently open prompt or an existing grant, allowing a composer opened on time to finish after the deadline or midnight while retaining the original `prompt_id` and timeline date.

### `blessings`

`id`, `prompt_id`, `author_id`, `capture_mode`, `body`, `audio_path`, `video_path`, `thumbnail_path`, `photo_path`, `submitted_at`, `is_late`, scripture book/chapter/start/end fields, `created_at`

Unique `(prompt_id, author_id)`. Voice and video transcripts are stored in `body`. Typed and voice blessings may reference one private photo; video blessings cannot. Scripture text is never persisted; it is rendered from the viewer's selected public-domain translation.

### `blessing_responses`

`id`, `blessing_id`, `author_id`, `mode`, `body`, `audio_path`, `submitted_at`

Responses are circle-scoped through their parent blessing and support only typed or transcribed voice media.

### `device_registrations`

`id`, `user_id`, `installation_id`, `apns_token`, `push_to_start_token`, `environment`, `last_seen_at`, `revoked_at`

Tokens are encrypted or protected by restricted server-only access. Users cannot read other users' registrations.

### `activity_registrations`

`id`, `prompt_id`, `user_id`, `activity_id`, `push_token`, `environment`, `created_at`, `ended_at`

Used for per-device Live Activity updates. A future `broadcast_channel_id` can replace fan-out for iOS 18+ circles.

## Visibility enforcement

RLS policy logic for `blessings` should require active circle membership and then allow either:

```text
prompt.local_date < viewer_local_today
OR blessing.author_id = auth.uid()
OR viewer has a blessing for prompt.id
```

Because “today” varies by circle time zone and policy expressions should stay auditable, production should expose a stable security-barrier view or RPC such as `visible_timeline(circle_id)` rather than duplicating the rule in every client query.

## Storage layout

```text
blessing-media/{circle_id}/{prompt_id}/{author_id}/original.mov
blessing-media/{circle_id}/{prompt_id}/{author_id}/thumbnail.jpg
blessing-media/{circle_id}/{prompt_id}/{author_id}/photo-{id}.jpg
blessing-media/{circle_id}/{prompt_id}/{author_id}/voice-{id}.caf
blessing-media/{circle_id}/{prompt_id}/{author_id}/responses/{blessing_id}/{id}.caf
avatars/{user_id}/avatar.jpg
```

Objects are private. Signed read URLs are short-lived and issued only after the same timeline-visibility check.

## Environment and secrets

The iOS app receives only the Supabase project URL and publishable key through an untracked `.xcconfig`. Service role, APNs `.p8` key, key ID, team ID, and app bundle ID stay in Edge Function secrets/Vault.

## Local setup

The ordered executable schema is in `supabase/migrations`; the APNs dispatcher is at `supabase/functions/dispatch-prompts/index.ts`. See `docs/MILESTONE_2_RUNBOOK.md` for hosted deployment.

```sh
npx supabase start
npx supabase db reset
cp supabase/.env.example supabase/.env.local
npx supabase functions serve dispatch-prompts --env-file supabase/.env.local
```

Do not use the example values outside local development. Hosted deployment also needs a once-per-minute Cron/`pg_net` call to the function. Authenticate that server-only call either with `x-dispatch-secret` sourced from Vault or the Supabase dashboard's server secret `apikey`; never put either credential in the app.

The migrations deliberately revoke direct writes to circles, memberships, prompts, blessings, and responses. Clients use transactional RPCs so deadlines, membership, uniqueness, path ownership, and server timestamps cannot be bypassed by a modified app. Realtime tables are published, but RLS remains the read boundary.

## Source references

- Apple ActivityKit documentation: https://developer.apple.com/documentation/activitykit
- Apple remote Live Activity updates: https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications
- Apple Speech framework: https://developer.apple.com/documentation/speech
- Supabase Swift SDK: https://supabase.com/docs/reference/swift/introduction
- Supabase scheduled functions: https://supabase.com/docs/guides/functions/schedule-functions
