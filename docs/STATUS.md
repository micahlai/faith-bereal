# Project status

Last updated: 2026-09-29

## Current phase

Milestone 1 — local vertical slice.

## Completed

- Product behavior and the current-day visibility rule are specified.
- Supabase selected as the production backend; rationale and data model documented.
- Apple platform constraints for ActivityKit, APNs, Speech, and camera capture recorded.
- Visual direction, semantic palette, accessibility baseline, and primary screen structure defined.
- Repository operating guide and staged delivery roadmap added.
- XcodeGen project builds an iOS app, Live Activity extension, and unit-test target.
- Local circle join/create, typed/voice/video capture, today countdown, gating, and timeline UI implemented.
- ActivityKit local start/update UI and deep-link route implemented.
- Four domain tests pass on an iPhone 17 Pro simulator.
- Initial Supabase schema includes account profiles, private circles, membership, prompts, gated blessings, device/activity tokens, private media policies, and transactional RPCs.
- APNs Edge Function type-checks and covers daily scheduling, atomic prompt claims, alerts, and push-to-start payloads.

## In progress

- Deploying and exercising the Supabase migration/RLS policies against a provisioned project.
- Sign in with Apple production adapter and remote APNs token registration.

## Not yet production-ready

- Supabase resources are not provisioned and no credentials are present.
- Sign in with Apple capabilities and APNs entitlements require an Apple Developer team.
- Remote push-to-start Live Activities require server/APNs setup and physical-device verification.
- Privacy copy, moderation flows, account deletion, and App Store materials remain incomplete.

## Next implementation task

Implement the SQL migration and production service adapter behind the existing service protocols, then verify access with two physical-device accounts.
