# Roadmap

## Milestone 0 — foundation

- [x] Product specification, architecture, backend decision, design language, security notes, testing plan
- [x] XcodeGen project with app, Live Activity extension, and unit-test targets
- [x] Shared models, service protocols, seeded local backend
- [x] CI-ready build and test commands

Exit: a clean checkout generates, builds, and tests without private credentials.

## Milestone 1 — local vertical slice

- [x] Demo identity and seeded circle
- [x] Create/join circle by code
- [x] Today screen with prompt state and configurable countdown
- [x] Typed and speech-transcribed capture
- [x] In-app system camera capture and ready state
- [x] Atomic local submission and today-unlock behavior
- [x] Multi-lane historical timeline with missed indicators
- [x] Local ActivityKit start/update/end
- [x] Owner schedule/time-zone/name/late-post settings
- [x] Multiple memberships, global circle switching, and owner-safe leave flow
- [x] Global user settings with account-wide Bible translation
- [x] Optional scripture tagging and per-user public-domain translation
- [x] Scrollable joined-at-aware timeline, media detail, and text/voice responses

Exit: the complete product loop works in simulator/device against deterministic seeded data.

## Milestone 2 — production backend (implementation complete)

- [x] Add checked-in local Supabase CLI configuration and environment templates
- [x] Add initial migrations, constraints, RLS, storage policies, and RPCs
- [x] Integrate Sign in with Apple through Supabase Auth
- [x] Add the Supabase repository for bootstrap, circles, settings, timeline, submissions, media, scripture, and responses
- [x] Add RLS-safe realtime refreshes and short-lived signed audio/video URLs
- [x] Add device, push-to-start, and per-activity update-token registration
- [x] Add the Edge Function for scheduling, claims, APNs alerts, Live Activity start/update/end, and prompt closure
- [x] Document hosted deployment and two-device acceptance testing

Code exit: a configured build is ready for two physical devices in one circle to post and see gated updates securely. Credentialed deployment and the physical-device acceptance run remain release-environment operations; see `MILESTONE_2_RUNBOOK.md`.

## Milestone 3 — push and resilience

- [x] Register notification, push-to-start, and ActivityKit update tokens
- [x] Implement production APNs alert and Live Activity payload delivery
- [ ] Add structured APNs delivery observability and invalid-token revocation
- [ ] Retry/idempotency, offline drafts, upload recovery, and reconciliation
- [ ] Evaluate iOS 18 broadcast channels per circle

Exit: randomized prompts reliably open/close across devices without relying on the app being foregrounded.

## Milestone 4 — release readiness

- [ ] Accessibility audit: VoiceOver, Dynamic Type, contrast, Reduced Motion
- [ ] Privacy manifest, retention controls, account deletion, export path
- [ ] Abuse reporting and member removal
- [ ] Load, battery, network, media, and push failure testing
- [ ] App Store assets, review notes, and TestFlight cohort

Exit: release candidate meets App Review, privacy, reliability, and accessibility requirements.
