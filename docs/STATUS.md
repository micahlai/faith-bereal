# Project status

Last updated: 2026-09-29

## Current phase

Milestone 2 — production backend implementation complete; credentialed deployment pending.

## Completed

- Product behavior and the current-day visibility rule are specified.
- Supabase selected as the production backend; rationale and data model documented.
- Apple platform constraints for ActivityKit, APNs, Speech, and camera capture recorded.
- Visual direction, semantic palette, accessibility baseline, and primary screen structure defined.
- Repository operating guide and staged delivery roadmap added.
- XcodeGen project builds an iOS app, Live Activity extension, and unit-test target.
- Local circle join/create, typed/voice/video capture, today countdown, gating, and timeline UI implemented.
- ActivityKit local start/update UI, deep-link route, remote push-to-start/update/end, and token registration implemented.
- Ten domain tests pass on an iPhone 17 Pro simulator.
- Simulator UI reviewed in light mode and on a small iPhone in dark mode with accessibility-size text; scroll clearance and Reduce Motion behavior were corrected from that pass.
- Supabase schema includes auth profiles, private circles, membership join dates, configurable schedules, gated blessings, responses, scripture references, device/activity tokens, private media policies, realtime publication, and transactional RPCs.
- Native Sign in with Apple and the production Supabase repository compile behind the existing service protocols; blank configuration safely falls back to the local demo.
- APNs Edge Function covers daily scheduling, atomic prompt claims, dynamic alert copy, and Live Activity start/update/end payloads.
- Circle owner settings, late indicators, Bible tagging/preview/version preference, drag verse selection, media detail, responses, and joined-circle timeline markers are implemented.

## In progress

- Deploying and exercising the migrations and Edge Function against the project owner's provisioned Supabase environment.
- Running the physical-device Apple signing, APNs, and two-account acceptance matrix.

## Not yet production-ready

- Supabase resources are not provisioned and no credentials are present.
- Sign in with Apple capabilities and APNs entitlements require an Apple Developer team.
- Remote push-to-start Live Activities require server/APNs setup and physical-device verification.
- Privacy copy, moderation flows, account deletion, and App Store materials remain incomplete.

## Next operational task

Follow `docs/MILESTONE_2_RUNBOOK.md` with Supabase access, an Apple Developer team, APNs key material, and two physical-device accounts. The current machine has no Docker daemon, Deno installation, Supabase access token, or project reference, so hosted mutation and device delivery were intentionally not attempted.
