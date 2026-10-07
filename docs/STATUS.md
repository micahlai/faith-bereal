# Project status

## 2026-10-07 loading-screen branding

- The in-app startup/loading screen now uses the transparent adaptive manna wordmark instead of the generic circle-grid symbol.
- The wordmark automatically selects dark lettering on light surfaces and cream lettering on dark surfaces while retaining an explicit accessibility label.

## 2026-10-06 Xcode Cloud release configuration

- Xcode Cloud archive actions now validate the workflow's secret `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` variables and materialize the ignored `Configuration/Secrets.xcconfig` inside the temporary checkout.
- The generated URL uses xcconfig-safe syntax, secret values are never printed, and non-archive actions retain Debug/local-demo behavior.
- The script is locally verified with an isolated mock Xcode Cloud checkout; the first real cloud archive and TestFlight distribution remain to be run.

## 2026-10-06 widget, Live Activity, and notification branding

- The Home Screen widget now keeps the adaptive transparent manna wordmark in its top-right corner without adding duplicate accessibility speech.
- The lock-screen and Dynamic Island Live Activity surfaces use the same light/dark wordmark instead of the generic circle-grid symbol.
- Remote alerts opt into a notification service extension that attaches the full square manna logo. The small notification icon remains the iOS-controlled app icon.
- The generated project builds with the app, Live Activity/widget extension, and notification service extension embedded. All 46 domain/unit tests and all 6 UI tests pass on an iPhone 17e simulator; an earlier iPhone 17 Pro run hit an Xcode test-worker startup stall before tests materialized.
- `dispatch-prompts` version 8 is active with the mutable-content alert payload. A Release archive and App Store Connect export succeeded with production APNs, the Live Activity/widget extension, and the signed `app.manna-circle.ios.notification-service` extension; the export validator also confirmed the bundled notification logo. The branded alert still needs presentation validation on a physical TestFlight device.

## 2026-10-06 circle creation settings and invite rotation

- Circle creation now collects the complete owner configuration before any circle is saved: name, time zone, daily random range, response duration, late-post policy, and repeat window.
- Local and hosted creation paths schedule the current local-day prompt from those initial settings. The server remains authoritative for hosted prompt timing, while the creator's first-day exception permits sharing at any time on that circle-local day.
- Owners can regenerate a circle's invite code from settings after a destructive confirmation. Rotation leaves current members in place and invalidates the prior code immediately.
- The simulator suite now passes 52 tests: 46 domain/unit tests and 6 UI tests, including initial-setting persistence, current-day prompt creation, owner authorization, old-code invalidation, the full creation form, and the rotation confirmation flow.
- Migration `202610060010_circle_creation_settings_and_code_rotation.sql` is deployed. Hosted creation and rotation still require two-account acceptance.
- App and extension identifiers now share the required `app.manna-circle.ios` prefix, and App Store Connect export signing succeeded for the app, Live Activity/widget extension, and notification service extension. The Supabase Apple provider still needs to accept `app.manna-circle.ios` before the next hosted sign-in pass.

## 2026-10-06 physical-device build and test pass

- Generated the Xcode project, then built and ran the complete test plan on a USB-connected iPhone 14 Pro running iOS 26.6.2.
- All 47 tests passed on-device: 43 domain/unit tests and 4 UI tests, including owner force-local-prompt, photo availability by capture mode, Today/Timeline scrolling with the pinned member header, and largest-text dark mode.
- The ordinary hosted-configuration app was installed and launched after the suite, and its process remained running on the phone.
- The pass does not exercise real microphone/camera capture, hosted media upload, remote APNs presentation, or Live Activity presentation. Those remain part of the manual two-account physical-device acceptance matrix.
- Non-failing diagnostics remain to review: the orientation declaration warning, App Group preferences access from the unit-test host, two sub-second launch-hang reports during extended UI-test launch, and Xcode's missing-debugger-version log from the UI test runner.

## 2026-10-06 hosted scheduler and release archive validation

- Supabase Cron now invokes `dispatch-prompts` once per minute with a server-only project credential. Three consecutive hosted calls returned HTTP 200 after the dispatcher RPC and least-privilege table grants deployed.
- Interrupted prompts are reclaimable after five minutes while their response window is still open. The hosted recovery path reclaimed a real stuck prompt, moved it to `open`, and returned a structured delivery outcome instead of leaving it in `dispatching`.
- That recovered dispatch reached APNs: 2 of 8 Sandbox alert/Live Activity requests were accepted across four registered device rows, while 6 failed with `TooManyProviderTokenUpdates`. This proves the scheduler, Edge Function, and APNs provider connection are live and identified stateless-runtime JWT rotation as the partial-delivery cause.
- Migration `202610060009` and `dispatch-prompts` version 6 now atomically reuse one server-only APNs provider JWT for 45 minutes across Edge Function runtimes. The cache table is unreadable to app users and directly unreadable even to `service_role`; only its service-role RPC can return the short-lived token. A post-cooldown APNs dispatch remains to be observed.
- Invalid alert and push-to-start tokens are now cleared when APNs returns a permanent token error; registrations are revoked only when neither token remains. The latest partial-failure run did not classify any stored token as permanently invalid.
- All migrations through `202610060010` match the linked hosted project, and `dispatch-prompts` version 8 is active.
- The TestFlight candidate workflow runs the local unit and UI suites in separate Xcode phases, archives a hosted Release build, exports an App Store Connect IPA, and rejects missing production APNs, debugging entitlement, Sign in with Apple, App Group, extension signatures, or notification-logo resources. The merged branded build 2 completed the full workflow and passed the expanded validator.

## 2026-10-06 media playback and notification registration

- Voice recording now uses a speaker-safe play-and-record session, the microphone output format, visible write-failure detection, and empty-file validation for both blessings and responses.
- Voice recordings have an accessible play/pause control, elapsed and total time, and a seekable playhead in capture previews, blessing details, and response history.
- Video playback now activates the correct shared audio-session mode, reports load failures, exposes a playhead, and includes a dedicated full-screen player.
- Device registration retries transient server failures three times in the current session, reports APNs registration failures separately, and never registers an empty token set.
- Hosted device registration now preserves an existing APNs or Live Activity token when its counterpart arrives separately; migration `202610060005` is deployed.
- The current source builds, all 52 simulator tests pass, and a local-demo simulator launch renders successfully. The previously completed 47-test plan passed on the paired iPhone 14 Pro; the six newly added UI tests and three newly added domain tests have not yet been rerun there.

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
- Widget snapshots now use an atomic file in the shared App Group container for reliable app-to-extension delivery on physical devices, with the former shared-defaults value retained as a migration fallback.
- Circle switching now loads the destination context and timeline before changing visible state, retries one transient cancellation, and silently handles task cancellation instead of exposing Swift’s internal cancellation error.
- Forced prompts now remain open and return delivery counts when every APNs request fails (for example because an app reinstall invalidated a device token). Individual APNs failures are logged and summarized on the prompt instead of turning the owner action into an opaque HTTP 502.

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
- Forty-six domain tests and six UI tests pass on the simulator. The earlier 43-domain/4-UI plan also passed on a signed iPhone 14 Pro running iOS 26.6.2. Current UI coverage adds the all-settings creation form and owner invite-code rotation to Today, Timeline scrolling, dark appearance, accessibility-size text, text/voice-versus-video photo attachment availability, and the local owner force-notification flow.
- Simulator UI reviewed in light mode and on a small iPhone in dark mode with accessibility-size text; scroll clearance and Reduce Motion behavior were corrected from that pass.
- Supabase schema includes auth profiles, private circles, membership join dates, configurable schedules, gated blessings, responses, scripture references, device/activity tokens, private media policies, realtime publication, and transactional RPCs.
- Native Sign in with Apple and the production Supabase repository compile behind the existing service protocols. Blank configuration safely falls back to the local demo in Debug, while Release now fails before compilation without valid hosted Supabase values and production APNs settings.
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
- The hosted Supabase project is linked and migrations through `202610060010` are applied. The database reports `ACTIVE_HEALTHY`, and the owner-only prompt, settings, membership, and invite-code RPCs are deployed. Ownership transfer, repeat blessings, member removal, blessing-photo persistence, forced prompt delivery, circle creation settings, and code rotation remain subject to two-account/physical-media acceptance. Local client credentials are stored only in the ignored `Configuration/Secrets.xcconfig` file.
- The Supabase Apple provider was validated for the former native bundle ID `app.blessingcircle.ios`. A signed physical-device flow completed Apple token exchange, profile bootstrap, membership loading, device registration, and circle creation against the hosted project on 2026-10-05. The provider and Apple Developer configuration must now be updated for `app.manna-circle.ios` before hosted sign-in is considered valid again.
- After the `202609300002` circle backfill deployed, the physical-device client loaded circles, profiles, memberships, and prompts without the prior missing-field decoding failure.
- Circle settings expose a confirmed owner-only force-notification action. Local demo mode restarts the timer/capture/Live Activity flow; hosted mode calls an owner-authorized server RPC and is designed to dispatch real APNs alerts and Live Activity start requests to every registered member device.
- The hosted `dispatch-prompts` Edge Function is active with a Sandbox & Production APNs key and required project secrets. Its unauthenticated boundary returns 401 as expected, the once-per-minute scheduler is active, and one recovery dispatch received partial APNs acceptance. On-device presentation and Production/TestFlight token delivery remain unvalidated.

## In progress — not yet validated

- Validating deployed migration `202610060010`, including full-setting circle creation, same-day prompt generation, owner-only code rotation, and old-code rejection with two accounts.
- Updating the Supabase Sign in with Apple provider for `app.manna-circle.ios`, then revalidating native sign-in. Distribution signing for the app and both extensions now succeeds.
- Validating the deployed schema, RLS policies, storage, realtime, RPCs, and Edge Function against two physical-device accounts.
- Validating migrations `202609300001` through `202609300004` with two accounts and real text/voice photo uploads.
- Validating one post-cooldown dispatch through the durable APNs provider-token cache, then confirming alert plus Live Activity presentation on physical devices.
- The owner force-notification client and server code are deployed, but cross-account delivery remains unvalidated until the two-account physical-device acceptance pass.
- Running the physical-device Apple signing, APNs, and two-account acceptance matrix.
- Completing Milestone 4 work that depends on hosted Supabase, Apple Developer capabilities, physical devices, and final distribution assets.

## Not yet production-ready

- The Supabase deployment is a configuration checkpoint only and has not passed the acceptance matrix.
- App Store distribution export now has production APNs, Sign in with Apple, the shared App Group, no debugging entitlement, and both signed extensions; App Store Connect upload and installation from TestFlight remain unvalidated.
- Remote push-to-start Live Activities have a running scheduler and partial APNs acceptance, but still require physical-device presentation plus update/end verification.
- Widget App Group signing and on-device refresh cadence still require Apple Developer capability and physical-device validation.
- Customer-facing privacy copy, moderation flows, account deletion/export, App Store screenshots/metadata, and installed TestFlight validation remain incomplete.

## Next operational task

Resume the hosted two-account and physical-device acceptance matrix in `docs/MILESTONE_2_RUNBOOK.md`, then implement the remaining deletion/export and moderation release blockers.
