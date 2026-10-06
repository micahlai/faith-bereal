# Project status

## 2026-10-06 profiles, onboarding, and join-day access

- User settings now support changing the profile name and choosing a private profile photo; Apple’s first-authorization name remains the initial name, while initials are used until a photo is chosen because Sign in with Apple does not provide profile photos.
- Profile photos are downsampled to a 1024-pixel JPEG before upload, and hosted avatar uploads fail with a clear timeout instead of leaving Profile Save spinning indefinitely.
- The authenticated role now has the column-level `display_name` and `avatar_path` update grant required by the existing self-only profile RLS policy.
- First launch now introduces manna circle, asks for appearance and Home Screen icon preferences, and then enters a focused join/create experience. Accounts with no circle remain in that experience, and About remains available from the app menu.
- A member may share against the current circle-day prompt at any time on the local calendar day they join. This exception is enforced by the local repository, hosted submission RPC gate, and private media-upload policy dependency—not only by the UI.
- Simulator UI tests can bypass the one-time onboarding with `BLESSING_CIRCLE_SKIP_ONBOARDING=1` while ordinary local-demo launches continue to exercise onboarding.

## 2026-10-06 physical-device speech callback fix

- Device crash reports from both blessing and response recording confirmed a Swift 6 executor trap on `RealtimeMessenger.mServiceQueue` inside the audio tap.
- Audio tap and Speech framework callbacks are now created in a nonisolated factory. They move only Sendable transcript/error values onto the main actor, while real-time audio buffers remain entirely off the main actor.
- Failed audio-engine startup now removes its installed tap and clears the partial recording instead of leaving a poisoned recorder lifecycle.
- Audio and photo uploads now use the Supabase data-upload API so their declared MIME type is preserved. The private media bucket also accepts octet-stream for the SDK’s streamed video-upload path.

## 2026-10-05 invite-code display fix

- Newly created and newly joined circle codes now survive the immediate hosted circle refresh instead of being replaced by the server's intentionally code-free circle row.
- Later settings and membership refreshes preserve a code already known to the client, and sharing is disabled when no code is available.

## 2026-10-05 product rename

- Renamed the public brand to **manna**, with **manna circle** as the full product name and **manna circle - daily blessings** as the fullest App Store name.
- Updated in-app branding, Apple permission copy, widget metadata, release documentation, and generated bundle metadata while retaining existing bundle identifiers and deep links for compatibility.
- Reworked the adaptive color system from `logo/logo1.png`: warm cream and charcoal surfaces now frame a dark-orange primary accent, while purple remains a supporting scripture accent.
- Added a User Settings app-icon preference with Automatic, Cream, and Midnight manna logo choices backed by native alternate app icons.

## 2026-10-05 media activation crash fix

- Fixed a Swift 6 actor-isolation crash when the Speech framework returned authorization on a background queue by moving permission callbacks through a nonisolated service boundary.
- Fixed the physical-device video camera crash by validating movie capture support and configuring the picker media type before selecting video capture mode.
- Photo and video camera permission requests now share the same concurrency-safe authorization path.

## 2026-10-05 Live Activity reliability

- Live Activities are restored into app state after relaunch and tracked independently by prompt instead of through one transient in-memory reference.
- Local developer previews start without requiring a remote ActivityKit push token; hosted prompts still request one for server updates.
- The developer control now reports whether the activity started, was already active, is disabled in Settings, or failed with an ActivityKit error.
- Starting the app now uses the actually selected circle's prompt when deciding which Live Activity to show.

Last updated: 2026-10-06

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
- Thirty-eight domain tests and four UI tests pass on the simulator; the prior 32-domain/3-UI suite also passed on a signed iPhone 14 Pro running iOS 26.6.2. The UI coverage includes Today, Timeline scrolling, dark appearance, accessibility-size text, text/voice-versus-video photo attachment availability, and the local owner force-notification flow.
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
- The hosted Supabase project is linked and migrations through `202610050001` are applied. The database reports `ACTIVE_HEALTHY`, and the new owner-only `force_circle_prompt` RPC is deployed. Ownership transfer, repeat blessings, member removal, blessing-photo persistence, and forced prompt delivery remain subject to two-account/physical-media acceptance. Local client credentials are stored only in the ignored `Configuration/Secrets.xcconfig` file.
- The Supabase Apple provider is enabled for native bundle ID `app.blessingcircle.ios`. A signed physical-device flow completed Apple token exchange, profile bootstrap, membership loading, device registration, and circle creation against the hosted project on 2026-10-05.
- After the `202609300002` circle backfill deployed, the physical-device client loaded circles, profiles, memberships, and prompts without the prior missing-field decoding failure.
- Circle settings expose a confirmed owner-only force-notification action. Local demo mode restarts the timer/capture/Live Activity flow; hosted mode calls an owner-authorized server RPC and is designed to dispatch real APNs alerts and Live Activity start requests to every registered member device.
- The hosted `dispatch-prompts` Edge Function is active with a Sandbox & Production APNs key and required project secrets. Its unauthenticated boundary returns 401 as expected; physical-device delivery and the once-per-minute scheduler remain unvalidated.

## In progress — not yet validated

- Validating the deployed schema, RLS policies, storage, realtime, RPCs, and Edge Function against two physical-device accounts.
- Validating migrations `202609300001` through `202609300004` with two accounts and real text/voice photo uploads.
- Scheduling `dispatch-prompts` once per minute and validating remote notification and Live Activity delivery.
- The owner force-notification client and server code are deployed, but cross-account delivery remains unvalidated until the two-account physical-device acceptance pass.
- Running the physical-device Apple signing, APNs, and two-account acceptance matrix.
- Completing Milestone 4 work that depends on hosted Supabase, Apple Developer capabilities, physical devices, and final distribution assets.

## Not yet production-ready

- The Supabase deployment is a configuration checkpoint only and has not passed the acceptance matrix.
- The signed development profile includes Sign in with Apple, development APNs, and the shared App Group; release/distribution provisioning remains unvalidated.
- Remote push-to-start Live Activities require scheduler setup and physical-device delivery verification.
- Widget App Group signing and on-device refresh cadence still require Apple Developer capability and physical-device validation.
- Customer-facing privacy copy, moderation flows, account deletion/export, final App Store assets, and TestFlight validation remain incomplete.

## Next operational task

Resume the hosted two-account and physical-device acceptance matrix in `docs/MILESTONE_2_RUNBOOK.md`, then implement the remaining deletion/export and moderation release blockers.
