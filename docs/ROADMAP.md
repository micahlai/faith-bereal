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
- [x] Today screen with prompt state and ten-minute countdown
- [x] Typed and speech-transcribed capture
- [x] In-app system camera capture and ready state
- [x] Atomic local submission and today-unlock behavior
- [x] Multi-lane historical timeline with missed indicators
- [x] Local ActivityKit start/update/end

Exit: the complete product loop works in simulator/device against deterministic seeded data.

## Milestone 2 — production backend

- [ ] Provision Supabase environments and local CLI configuration
- [ ] Apply migrations, constraints, RLS, storage policies, and RPCs
- [ ] Integrate Sign in with Apple through Supabase Auth
- [ ] Replace local services with Supabase implementations
- [ ] Add realtime updates and signed video URLs
- [ ] Build Edge Functions for invite joining, media finalize, prompt scheduling, and APNs delivery

Exit: two physical devices in one circle can post and see gated updates securely.

## Milestone 3 — push and resilience

- [ ] Register notification, push-to-start, and ActivityKit update tokens
- [ ] Production APNs provider integration and delivery observability
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
