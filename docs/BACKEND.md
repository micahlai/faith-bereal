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

`id`, `display_name`, `avatar_path`, `time_zone`, `created_at`, `deleted_at`

### `circles`

`id`, `name`, `owner_id`, `invite_code_hash`, `time_zone`, `window_start`, `window_end`, `created_at`

Only a hash of the normalized invite code is stored. Joining happens through a security-definer RPC that rate-limits attempts.

### `circle_members`

`circle_id`, `user_id`, `role`, `joined_at`, `removed_at`

Unique active membership per circle/user pair.

### `daily_prompts`

`id`, `circle_id`, `local_date`, `starts_at`, `ends_at`, `state`, `dispatch_key`, `created_at`

Unique `(circle_id, local_date)`. `ends_at` is constrained to ten minutes after `starts_at`.

### `blessings`

`id`, `prompt_id`, `author_id`, `capture_mode`, `body`, `video_path`, `thumbnail_path`, `submitted_at`, `created_at`

Unique `(prompt_id, author_id)`. Text is required for typed/voice modes; video metadata is required for video mode.

### `device_registrations`

`id`, `user_id`, `installation_id`, `apns_token`, `push_to_start_token`, `environment`, `last_seen_at`, `revoked_at`

Tokens are encrypted or protected by restricted server-only access. Users cannot read other users' registrations.

### `activity_registrations`

`id`, `prompt_id`, `user_id`, `activity_id`, `push_token`, `created_at`, `ended_at`

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
avatars/{user_id}/avatar.jpg
```

Objects are private. Signed read URLs are short-lived and issued only after the same timeline-visibility check.

## Environment and secrets

The iOS app receives only the Supabase project URL and publishable key through an untracked `.xcconfig`. Service role, APNs `.p8` key, key ID, team ID, and app bundle ID stay in Edge Function secrets/Vault.

## Source references

- Apple ActivityKit documentation: https://developer.apple.com/documentation/activitykit
- Apple remote Live Activity updates: https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications
- Apple Speech framework: https://developer.apple.com/documentation/speech
- Supabase Swift SDK: https://supabase.com/docs/reference/swift/introduction
- Supabase scheduled functions: https://supabase.com/docs/guides/functions/schedule-functions

