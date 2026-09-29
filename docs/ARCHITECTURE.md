# Architecture

## System shape

```text
SwiftUI app + ActivityKit extension
        |  Supabase Swift SDK / HTTPS / Realtime
        v
Supabase Auth ---- Postgres + RLS ---- Storage
                           |
                     Edge Functions
                           |
                 Cron ----+---- APNs
```

## Client layers

- `App`: composition root, environment dependencies, deep-link routing.
- `Features`: onboarding, circle, today/capture, and timeline screens.
- `Domain`: immutable app models and visibility/deadline rules.
- `Services`: protocols plus local and Supabase-backed implementations.
- `DesignSystem`: semantic colors, typography, spacing, and shared controls.
- `LiveActivity`: shared attributes and the widget extension UI.

The app uses one `AppModel` on the main actor for session and navigation state. Services are injected as protocols so previews and unit tests never require a network or Apple credentials.

## Backend choice

Supabase is the recommended production backend because the core model is relational and authorization-heavy: memberships, one-post-per-prompt constraints, current-day visibility, and administrative roles all map directly to Postgres constraints and Row Level Security. Realtime supports unlocked timeline updates, Storage handles video, Auth supports Sign in with Apple, Cron selects moments, and Edge Functions hold APNs credentials.

CloudKit remains a viable all-Apple alternative, but server-authored randomized schedules, invite-code transactions, cross-record authorization, operational querying, and APNs provider work are less direct. Firebase provides excellent iOS push integration, including Live Activities through FCM, but enforcing the visibility rule and relational uniqueness is clearer in Postgres/RLS.

## Server-authoritative flow

1. A cron job calls `schedule-daily-prompts` for circles whose next local day needs a prompt.
2. A database transaction chooses a random instant inside the circle window and inserts one prompt.
3. A dispatcher finds prompts entering their start minute and calls `start-prompt` exactly once.
4. `dispatch-prompts` sends a standard alert and ActivityKit push-to-start payload through APNs. For initial release, tokens are per device; iOS 18 broadcast channels are a scale optimization.
5. The app registers the push-to-start token and every remotely/local-started ActivityKit update token. The dispatcher updates response counts and per-user completion, then sends an explicit end event.
6. The app privately uploads voice/video media and invokes an atomic submission RPC containing only the selected scripture reference, never scripture text.
7. Supabase Realtime announces blessing, response, prompt, and membership changes. Clients refetch through RLS so unauthorized rows never become UI state.

## Reliability decisions

- All server commands accept idempotency keys.
- Prompt dispatch has `scheduled`, `dispatching`, `open`, `closed`, and `failed` states.
- Deadlines compare against database time, never the device clock.
- The unique key `(prompt_id, author_id)` rejects duplicate posts.
- Video uses a two-phase upload/finalize process; abandoned objects are garbage-collected.
- Push delivery is best effort; opening the app always fetches the authoritative prompt state.

## Platform constraints

- Live Activities require a widget extension and are updated by the app or ActivityKit pushes; the extension cannot fetch network data.
- ActivityKit payload static plus dynamic data must remain under Apple's 4 KB limit.
- Speech and camera permissions are requested only when a person chooses those modes.
- The app must continue to function when Live Activities are disabled.
