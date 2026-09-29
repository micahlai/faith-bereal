# Project status

Last updated: 2026-09-29

## Current phase

Milestone 0 — foundation.

## Completed

- Product behavior and the current-day visibility rule are specified.
- Supabase selected as the production backend; rationale and data model documented.
- Apple platform constraints for ActivityKit, APNs, Speech, and camera capture recorded.
- Visual direction, semantic palette, accessibility baseline, and primary screen structure defined.
- Repository operating guide and staged delivery roadmap added.

## In progress

- Generating the SwiftUI app, ActivityKit extension, and unit-test targets.
- Implementing the first local vertical slice.

## Not yet production-ready

- Supabase resources are not provisioned and no credentials are present.
- Sign in with Apple capabilities and APNs entitlements require an Apple Developer team.
- Remote push-to-start Live Activities require server/APNs setup and physical-device verification.
- Privacy copy, moderation flows, account deletion, and App Store materials remain incomplete.

## Next implementation task

Finish the local vertical slice, then implement the SQL migration and Supabase service adapter behind the existing service protocols.

