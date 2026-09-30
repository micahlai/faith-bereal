# Local failure and edge-case matrix

This matrix records deterministic checks that do not require an Apple Developer account, physical device, or hosted Supabase project. It complements—not replaces—the production acceptance matrix in `MILESTONE_2_RUNBOOK.md`.

| Area | Local evidence | Remaining release evidence |
| --- | --- | --- |
| Blank backend configuration | App composition falls back to the local repository; every simulator test command explicitly blanks Supabase variables | Misconfigured production build must fail visibly without leaking credentials |
| Duplicate blessing | Repository test rejects a second post for the same user and prompt | Database uniqueness/RPC behavior under two concurrent clients |
| Prompt boundaries | Tests cover start/end exclusivity, late policy, circle-local day rollover, and Today states | Server clock skew and scheduler/retry behavior |
| Current-day privacy | Tests cover peer locking before submission and historical visibility | RLS checks with two hosted accounts and realtime inserts |
| Repeat blessing expiry | Tests cover target-circle time window, source submission time, and circle/user exclusions | Cross-device clock and hosted transaction behavior |
| Media persistence | A test verifies captured video is copied out of temporary storage | Permission denial/recovery, audio interruptions, background upload, expired URLs, and cleanup on devices |
| Widget content | Tests cover active-prompt priority, unseen/current-day rotation, prior-day fallback, empty state, and prompt-boundary refresh | App Group signing, system refresh cadence, memory/battery impact, and deep links on devices |
| Responsive UI | UI tests launch the local Today flow and exercise the scrollable Timeline header; an accessibility-size dark-mode launch is included | iPad split view, landscape, physical-device VoiceOver, Increased Contrast, and media controls |
| Push and Live Activities | Payload models and local ActivityKit lifecycle compile | APNs delivery, invalid-token revocation, retry/idempotency, lock screen, and Dynamic Island |

## Commands

Use the commands in `TESTING.md` with blank `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. A passing simulator run is evidence only for the local column above.

## Release rule

Do not close the roadmap's load/battery/network/media/push item until the remaining release evidence has been collected from the signed release candidate and hosted backend.
