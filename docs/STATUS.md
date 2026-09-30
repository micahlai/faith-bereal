# Project status

Last updated: 2026-09-30

## Current phase

Milestone 2 — production backend deployed; end-to-end validation pending.

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
- Multiple circles are loaded and switched globally; user settings live behind the hamburger menu, and circle settings include a confirmed leave flow with owner handoff.
- Today now has three date-aware states per active circle: waiting for the notification, the active response timer, and the current user's complete shared blessing until the circle's next local day.
- After the current user shares, Today expands into the full visible current-prompt feed with member identity, media or transcript, scripture, and responses.
- A small/medium WidgetKit widget shares App Group snapshots, prioritizes active prompts across circles, rotates visible blessings at a user-selected interval, and deep-links to Today or blessing detail.
- Timeline uses pinned member headers and synchronized day rows, with 15-line previews, join boundaries, late state, and avatar-only response previews.
- Response history remains visible on blessing details, while composition is limited to Today and current-day Timeline details.
- The Bible selector now offers verified public-domain versions across 12 popularity-ordered language groups; only the reference remains stored with a blessing.
- Milestone 3.5 has domain coverage plus a local-only simulator UI test for Today launch and the pinned Timeline member header.
- The local accessibility pass corrected light-mode accent contrast, added non-drag verse controls, and added largest-text dark-mode UI coverage; physical-device VoiceOver/media checks remain open.
- App and widget privacy manifests plus a retention/export/deletion contract are checked in; hosted deletion, export, and Storage cleanup remain unimplemented and unvalidated.
- The hosted Supabase project is linked and migrations `202609290001` through `202609290009` have been applied. Local client credentials are stored only in the ignored `Configuration/Secrets.xcconfig` file.

## In progress — not yet validated

- Validating the deployed schema, RLS policies, storage, realtime, RPCs, and Edge Function against two physical-device accounts.
- Completing Apple Developer capability and Supabase Apple-provider configuration; simulator logs currently reject the app as an invalid Sign in with Apple client because the generated provisioning profile lacks the requested entitlement.
- Running the physical-device Apple signing, APNs, and two-account acceptance matrix.
- Milestone 3.5 client expansion on `codex/client-expansion`, using the local demo backend for capture repair, ownership transfer, repeat blessings, Today/Timeline changes, appearance, and Bible translation expansion.

## Not yet production-ready

- The Supabase deployment is a configuration checkpoint only and has not passed the acceptance matrix.
- Sign in with Apple and APNs capabilities are not present in the generated provisioning profile.
- The Supabase Apple authentication provider is not yet confirmed enabled.
- Remote push-to-start Live Activities require server/APNs setup and physical-device verification.
- Widget App Group signing and on-device refresh cadence still require Apple Developer capability and physical-device validation.
- Privacy copy, moderation flows, account deletion, and App Store materials remain incomplete.

## Next operational task

Complete and verify Milestone 3.5 locally. Hosted Supabase and Apple signing work remains isolated on the `supabase` baseline and can resume through `docs/MILESTONE_2_RUNBOOK.md` after the client changes stabilize.
