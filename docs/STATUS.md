# Project status

## 2026-10-05 media activation crash fix

- Fixed a Swift 6 actor-isolation crash when the Speech framework returned authorization on a background queue by moving permission callbacks through a nonisolated service boundary.
- Fixed the physical-device video camera crash by validating movie capture support and configuring the picker media type before selecting video capture mode.
- Photo and video camera permission requests now share the same concurrency-safe authorization path.

## 2026-10-05 Live Activity reliability

- Live Activities are restored into app state after relaunch and tracked independently by prompt instead of through one transient in-memory reference.
- Local developer previews start without requiring a remote ActivityKit push token; hosted prompts still request one for server updates.
- The developer control now reports whether the activity started, was already active, is disabled in Settings, or failed with an ActivityKit error.
- Starting the app now uses the actually selected circle's prompt when deciding which Live Activity to show.

Last updated: 2026-10-05

## Current phase

Milestone 3.5 is complete against the local repository. Milestone 4 release-readiness work is in progress; Apple-account, physical-device, and hosted-backend acceptance remains pending.

## Completed

- Product behavior and the current-day visibility rule are specified.
- Supabase selected as the production backend; rationale and data model documented.
- Apple platform constraints for ActivityKit, APNs, Speech, and camera capture recorded.
- Visual direction, semantic palette, accessibility baseline, and primary screen structure defined.
- Repository operating guide and staged delivery roadmap added.
- XcodeGen project builds an iOS app, Live Activity extension, and unit-test target.
- Local circle join/create, typed/voice/video capture, today countdown, gating, and timeline UI implemented.
- ActivityKit local start/update UI, deep-link route, remote push-to-start/update/end, and token registration implemented.
- Thirty-three domain tests and four UI tests pass on the simulator; the prior 32-domain/3-UI suite also passed on a signed iPhone 14 Pro running iOS 26.6.2. The UI coverage includes Today, Timeline scrolling, dark appearance, accessibility-size text, text/voice-versus-video photo attachment availability, and the local daily-blessing debug control.
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
- Draft App Review notes and a release checklist now separate locally verified behavior from release-environment evidence and outstanding safety work.
- The local failure matrix covers deterministic prompt, visibility, repeat, media, widget, and UI edges; signed-device load/battery/network/media/push evidence remains open.
- Circle owners can remove another active member through a confirmed settings action; the server-authorized RPC is deployed but awaits two-account validation. Abuse reporting remains open.
- Typed and voice blessings can include one optional captured or uploaded photo, persisted locally and represented by a private `photo_path` in the production adapter; video blessings cannot add a separate photo.
- The hosted Supabase project is linked and migrations through `202609300004` are applied. Ownership transfer, repeat blessings, member removal, and blessing-photo persistence remain subject to two-account/physical-media acceptance. Local client credentials are stored only in the ignored `Configuration/Secrets.xcconfig` file.
- The Supabase Apple provider is enabled for native bundle ID `app.blessingcircle.ios`. A signed physical-device flow completed Apple token exchange, profile bootstrap, membership loading, device registration, and circle creation against the hosted project on 2026-10-05.
- After the `202609300002` circle backfill deployed, the physical-device client loaded circles, profiles, memberships, and prompts without the prior missing-field decoding failure.
- Debug builds expose native User Settings controls for a local push-style notification and a daily-blessing test. Local demo mode supports the full reset/timer/capture/Live Activity flow; hosted mode is a non-submittable timer/Live Activity preview so server-authored prompt timing and hosted data remain protected. Release builds contain neither control.

## In progress — not yet validated

- Validating the deployed schema, RLS policies, storage, realtime, RPCs, and Edge Function against two physical-device accounts.
- Validating migrations `202609300001` through `202609300004` with two accounts and real text/voice photo uploads.
- Configuring APNs provider secrets, deploying and scheduling `dispatch-prompts`, and validating remote notification and Live Activity delivery. No Edge Function is currently deployed.
- Running the physical-device Apple signing, APNs, and two-account acceptance matrix.
- Completing Milestone 4 work that depends on hosted Supabase, Apple Developer capabilities, physical devices, and final distribution assets.

## Not yet production-ready

- The Supabase deployment is a configuration checkpoint only and has not passed the acceptance matrix.
- The signed development profile includes Sign in with Apple, development APNs, and the shared App Group; release/distribution provisioning remains unvalidated.
- Remote push-to-start Live Activities require APNs secrets, Edge Function deployment/scheduling, and physical-device delivery verification.
- Widget App Group signing and on-device refresh cadence still require Apple Developer capability and physical-device validation.
- Customer-facing privacy copy, moderation flows, account deletion/export, final App Store assets, and TestFlight validation remain incomplete.

## Next operational task

Resume the hosted two-account and physical-device acceptance matrix in `docs/MILESTONE_2_RUNBOOK.md`, then implement the remaining deletion/export and moderation release blockers.
