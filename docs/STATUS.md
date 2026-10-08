# Project status

## 2026-10-08 custom circle reminder thumbnail

- Daily and end-of-day reminder alerts use the circle's custom photo as their optional right attachment. Default-circle reminders have no right image; the duplicate manna-logo attachment is removed.
- Peer blessing alerts retain their attached photo/video thumbnail and existing privacy rules. Notification payload tests and dispatcher type checking pass. Deployment and physical-device presentation remain pending.

## 2026-10-08 Today scroll stability

- The Today scroll container no longer lives inside the once-per-second timer. Its bounded daily feed uses persistent, exactly sized cards rather than recycled lazy height estimates, and unchanged feed inputs skip timer-driven recomputation.
- The local-demo regression verifies a long blessing, peer scripture/response content, resting bottom position across several timer ticks, repeated up/down scrolling, and preservation of a response draft. The focused simulator test passes.

## 2026-10-07 timeline frozen-layer repair

- The member row is now a compact fixed header outside the two-axis content scroller, preventing tall section-header sizing and content painting above the pinned row.
- Member icons scroll horizontally across the header's full width; the date-strip mask no longer cuts through avatars or names.
- Date labels now render in a viewport-fixed overlay, using row anchors only for vertical alignment. They cannot drift horizontally, even during a right-edge rubber-band gesture, and sit eight points before the vertical divider. The opaque strip covers the complete leading gutter so cards cannot peek around its left edge.
- A continuous vertical divider extends below the header's horizontal separator. Only the name's line height scales with Dynamic Type, keeping the fixed profile row compact without shrinking its text.
- All eight local-demo UI tests pass; the final date-layout adjustment also passes its focused timeline regression. Exported screenshots confirm compact header placement, clipping after vertical scrolling, and divider-aligned dates. The signed Release device build passes.

## 2026-10-07 notification identity and title revision

- Peer blessing titles now say “New blessing in [circle name]”, while response titles use the circle name. Existing locked/unlocked message copy and scripture references are unchanged.
- The extension combines the locally selected manna logo with a small circular sender avatar in the lower-left area. iOS still owns and displays the separate app-icon badge at the lower right; it cannot be replaced.
- Right-hand attachments now contain only blessing photos or video frames. Text/audio blessings without photos and response alerts have no right attachment; sender profile photos arrive in a separate identity field instead. Locked alerts retain their media privacy gate.
- Avatar and attachment downloads run in parallel with bounded timeouts and size checks, and identity avatars are downsampled before rendering. Timeout/failure still falls back to the ordinary alert through the existing single-delivery bridge.
- Physical-device presentation remains pending a build containing the updated notification extension.
- All 80 app/domain tests and both APNs payload contract checks pass, including logo-plus-avatar rendering and media-free response alerts. Dispatcher type checking and the signed Release device build pass. `dispatch-prompts` version 15 is deployed; a new app/TestFlight build is required for the new notification-extension presentation.

## 2026-10-07 About heading refinement

- The About/onboarding wordmark now sits above the single word “circle” in the same system serif family at regular weight, avoiding a repeated “manna” name below the logo.
- Onboarding's fixed bottom bar now anchors Back to the left and Continue to the right, with the minimum tap area inside each styled button rather than an invisible full-width wrapper.

## 2026-10-07 end-of-day blessings

- Circles now schedule an independent end-of-day prompt at an owner-selected circle-local time, defaulting to 10:00 p.m. and constrained to the tail of the random daily range or later.
- Today presents an untimed end-of-day share card and mixes unlocked daily/end-of-day blessings by recency. Timeline groups both in one day row with the end-of-day event above the random event, while each prompt keeps its own submission privacy gate.
- The five-hour entry window closes earlier when the next daily prompt starts. Timely entry grants still permit a later upload, including after midnight.
- User settings expose a separate end-of-day reminder switch per circle. The scheduler sends one normal APNs alert only to opted-in members and never starts a Live Activity for this prompt kind.
- All 78 app/domain tests and eight UI tests pass in local-demo mode. The signed Release device build, notification/Live Activity payload checks, and dispatcher type checking pass. Transactional hosted SQL regressions also pass and leave no test users or circles behind.
- Migration `202610070008_end_of_day_blessings.sql` is deployed and `dispatch-prompts` version 14 is active. Hosted schema lint has no errors; the once-per-minute scheduler is enabled and its latest five HTTP responses are 200, including runs after deployment. Two-account physical-device push/media acceptance remains pending.

## 2026-10-07 scripture markers and multilingual versions

- Verse previews and blessing-detail passages now prefix every verse with its superscript verse number instead of flattening a range into unmarked prose.
- Migration `202610070007_expand_bible_versions.sql` expands the hosted profile constraint and update RPC to the same 20 free translations offered by the client, resolving rejected non-English selections.
- The migration is deployed and the hosted schema passes error-level lint.
- Both the live Midvash catalog and an actual two-verse passage were checked for every configured translation slug; all 20 currently return verse text through the provider.

## 2026-10-07 frozen timeline axes

- The Timeline date column now counter-scrolls horizontally, keeping the day visible while member lanes move; the member header remains pinned vertically.
- Leading and inter-column padding are tighter, and the pinned member row uses less top spacing plus an opaque high-priority surface so cards no longer peek above it.
- The local-demo UI test verifies both the fixed day-column position and the pinned member header.

## 2026-10-07 native video presentation

- Inline videos now size themselves from the asset's transformed presentation dimensions, preserving portrait, landscape, and rotated source aspect ratios.
- Redundant custom video playheads were removed from inline and full-screen playback; Apple's native video controls remain responsible for seeking.

## 2026-10-07 square profile and circle photos

- Profile and circle photo selection now uses a single circular crop preview with simultaneous two-finger zoom and drag; the former arrows and zoom slider are removed.
- The client always writes a square JPEG before upload, and profile/circle photo surfaces use fill framing so the saved crop is presented consistently.

## 2026-10-07 cancellation-safe scrolling

- Cancellation-shaped transport errors produced when lazy Today cards leave the screen are now treated as normal lifecycle cancellation, including Swift's compact `CancellationError` description.
- Realtime subscriptions apply the same cancellation filter, so scrolling away from response and scripture loaders cannot surface an internal Swift error alert.

## 2026-10-07 startup onboarding navigation

- First launch now moves through four explicit pages—About, Appearance, App Icon, and Widget—with progress, persistent bottom navigation, and a Back action on every page after Welcome.
- App-icon selection has its own spacious one-column layout and renders the actual cream and midnight app-icon artwork instead of generated monograms. Automatic shows both real variants together.
- The new widget page explains active-prompt and rotating-blessing behavior and gives the accurate iOS Home Screen steps; iOS does not offer an API for apps to install widgets automatically.

## 2026-10-07 notification media and Live Activity state

- Blessing and response alerts use the circle name as the title and compact “name - message” copy after the recipient is allowed to view it. Blessing scripture references occupy a second line without including verse text; the pre-submission privacy gate remains intact.
- Communication alerts use the recipient's selected manna logo as the left sender image. Their rich thumbnail prioritizes a generated video first frame, an attached blessing photo, then the sender profile photo. Response alerts use the responder profile photo when available.
- The lock-screen Live Activity now shows the circle name, “What has blessed you today”, and a smaller live countdown followed by “to respond”; submitted state changes immediately to “Blessing submitted”. Dynamic Island code is unchanged.
- Submission marks the local Live Activity complete before a fallible timeline refresh, and the server's per-user update remains role-agnostic. Timeline response-preview cancellation is silent when rows scroll off-screen. Blessing detail uses a fixed compact close control whether or not Edit is still available.

## 2026-10-07 photo resize and circle-photo upload policy

- Profile and circle photo selection now opens the same aspect-preserving resize editor before save. The complete image is visible by default; pinch/drag gestures, a zoom slider, and directional buttons produce a JPEG with a 1024-pixel maximum side and accessible non-drag controls. Photo previews use aspect fit so no portion is silently cropped.
- The top circle selector now presents names without repeated people icons in either its label or menu rows.
- Circle-photo Storage writes use a server-authorized ownership predicate and require the canonical `<circle-id>/circle.jpg` path, resolving owner uploads that were rejected while preserving private member reads. Migration `202610070006_circle_photo_storage_policy.sql` is deployed and the hosted schema passes error-level lint.
- Circle creation accepts an optional resized photo alongside its initial settings. Circle Settings uses one top-right Save action for schedule and photo changes, and Cancel confirms before discarding edits.
- Blessing details use a compact close icon beside the time-limited Edit action instead of rendering an oversized Done control after editing expires.

## 2026-10-07 circle photo placement

- Circle photos now replace the seven-dot identity mark on the Circle page. The global circle dropdown presents names without circle photos or people icons.

## 2026-10-07 warning-free notification extension

- The notification service now crosses Apple's legacy Intents and UserNotifications callbacks through a locked, single-delivery bridge. Swift 6 no longer reports non-Sendable captures, and timeout/donation completion races cannot invoke the content handler twice.
- iPad declares all four orientations, retaining multitasking support and removing Xcode's full-screen orientation diagnostic. Clean simulator and signed generic-device builds pass; all 68 domain tests and six UI tests pass in separate phases.

## 2026-10-07 streamlined blessing cards

- Today cards no longer label the main content “Reflection” or “Transcript”; content, scripture, existing responses, and the response composer now share one panel without a “Responses” heading.
- Timeline previews remain heading-free, while blessing details retain their surrounding media and scripture context.

## 2026-10-07 circle activity notifications

- User settings now expose one activity-notification toggle per joined circle. It controls peer blessing alerts and response-thread alerts, defaults on, and is stored on the membership.
- Blessing inserts and response inserts transactionally create server-only outbox events. The dispatcher applies today's visibility gate per recipient, notifies the blessing author and prior responders without echoing to the sender, and uses idempotent APNs collapse identifiers.
- The notification service uses Apple's communication-notification presentation with a sender profile image and circle group image when available. iOS remains responsible for the exact compact-banner arrangement.
- Migration `202610070005_circle_activity_notifications.sql` is deployed and `dispatch-prompts` version 12 is active. A signed Release device build accepts the communication-notification entitlement; two-account production APNs presentation remains pending.

## 2026-10-07 circle photos

- Circle owners can choose, replace, or remove a downsampled private circle photo from Circle settings. Members see it in the Circle-page identity position, while the global circle switcher retains its generic group icon.
- Hosted photos use a dedicated private `circle-photos` bucket with owner-only writes and member-only reads; migration `202610070004_circle_photos.sql` is deployed.
- The photo data is also available to the notification delivery path as the circle/group image. Hosted upload, signed-URL refresh, and notification appearance still need physical-device acceptance.

## 2026-10-07 ten-minute blessing edits

- Authors can edit a blessing's text or transcript and optional scripture tag for ten minutes after the server-authored submission time; attached audio, video, and photos remain unchanged.
- The local demo and hosted RPC enforce the same author-only, global deadline, including a closed exact ten-minute boundary. Timeline, Today, deep-linked detail, and widget state update after a successful edit.
- Migration `202610070003_blessing_edits.sql` is deployed; signed two-account acceptance remains pending.

## 2026-10-07 circle creation defaults

- New circle forms now default the daily random blessing range to noon–10:00 p.m. in the selected circle time zone and enable late blessings by default.
- Existing circles are unchanged; owners can continue to adjust both values in circle settings.

## 2026-10-07 future Timeline prompt filtering

- Timeline repositories now exclude prompts whose circle-local date is after the viewed/current circle day. Tomorrow's server-precreated scheduling row can no longer fall through to a false “Missed this day” event.
- Regression coverage renders the local timeline from the preceding day and verifies that no future prompt event is emitted.

## 2026-10-07 universal invitations, widget header, and Live Activity lifetime

- Circle sharing now sends `https://manna-circle.micahlai.com/join/<code>` instead of a bare code. The production website serves the matching Apple App Site Association file and a custom-scheme fallback; the app persists an incoming invitation through sign-in/onboarding and presents the prefilled join flow.
- The hosted `join_circle` RPC now validates invitation codes without resetting an existing member's role or join date. Migration `202610070002_universal_circle_invites.sql` is deployed and the hosted schema passes error-level lint.
- Prompt local dates are now materialized in each circle's configured time zone, preventing a newly created circle's blessing from appearing under the prior day in western time zones.
- Home Screen blessing widgets no longer show a capture/quotation glyph. The compact 2×2 family stacks the circle name below the member name and reserves the top-right logo area.
- Live Activities now carry an explicit terminal dismissal timestamp. A submitted blessing remains for three minutes after submission; a no-late prompt remains for three minutes after its entry deadline; a late-enabled prompt remains active until that member submits or a newer prompt replaces it. The hosted dispatcher is deployed with the same start/update/end contract.
- Circle switching retries three transient transport cancellations and replaces Swift's internal cancellation text with a stable app message while leaving the current circle visible until the destination context is complete.
- The signed generic-device build, all 63 Debug domain tests, all 59 Release domain tests, and all 6 UI tests pass. Universal Link handoff from Messages, the exact three-minute ActivityKit presentation, late-activity replacement, and cross-account switching still require signed physical-device validation.

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
- `dispatch-prompts` version 9 is active with the mutable-content alert payload and prompt-specific capture route. A Release archive and App Store Connect export succeeded with production APNs, the Live Activity/widget extension, and the signed `app.manna-circle.ios.notification-service` extension; the export validator also confirmed the bundled notification logo. The branded alert still needs presentation validation on a physical TestFlight device.

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
- Non-failing diagnostics remain to review: App Group preferences access from the unit-test host, two sub-second launch-hang reports during extended UI-test launch, and Xcode's missing-debugger-version log from the UI test runner.

## 2026-10-06 hosted scheduler and release archive validation

- Supabase Cron now invokes `dispatch-prompts` once per minute with a server-only project credential. Three consecutive hosted calls returned HTTP 200 after the dispatcher RPC and least-privilege table grants deployed.
- Interrupted prompts are reclaimable after five minutes while their response window is still open. The hosted recovery path reclaimed a real stuck prompt, moved it to `open`, and returned a structured delivery outcome instead of leaving it in `dispatching`.
- That recovered dispatch reached APNs: 2 of 8 Sandbox alert/Live Activity requests were accepted across four registered device rows, while 6 failed with `TooManyProviderTokenUpdates`. This proves the scheduler, Edge Function, and APNs provider connection are live and identified stateless-runtime JWT rotation as the partial-delivery cause.
- Migration `202610060009` and `dispatch-prompts` version 6 now atomically reuse one server-only APNs provider JWT for 45 minutes across Edge Function runtimes. The cache table is unreadable to app users and directly unreadable even to `service_role`; only its service-role RPC can return the short-lived token. A post-cooldown APNs dispatch remains to be observed.
- Invalid alert and push-to-start tokens are now cleared when APNs returns a permanent token error; registrations are revoked only when neither token remains. The latest partial-failure run did not classify any stored token as permanently invalid.
- All migrations through `202610060010` match the linked hosted project, and `dispatch-prompts` version 9 is active.
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

Last updated: 2026-10-07

## 2026-10-07 prompt synchronization and timeline privacy

- The selected circle now reloads its server-authored prompt and timeline whenever the app becomes active, receives a realtime update, handles a Live Activity deep link, or is pulled to refresh.
- Same-circle Live Activity routes no longer skip prompt refresh, preventing Today from remaining in the waiting state after a notification has opened the sharing window.
- Local and hosted timeline adapters now consistently lock every current-day peer lane until the viewer shares; contextual labels distinguish the viewer's available window from a peer's available window.
- Regression tests cover same-circle capture deep links and current-prompt peer locking.

## 2026-10-07 timeline voice playback

- Timeline voice recordings from private hosted storage are downloaded to a local CAF cache before AVPlayer prepares them, avoiding unreliable direct streaming of signed audio URLs.
- Passive timeline loading no longer activates the device audio session, and unavailable duration metadata no longer makes an otherwise playable recording fail.
- Playback state remains active while AVPlayer is buffering, retry replaces the cached download, and a generated CAF regression test verifies preparation and duration discovery.

## 2026-10-07 Live Activity countdown epoch fix

- Live Activity deadlines now use an explicit Unix-seconds wire format matching APNs instead of synthesized `Date` decoding, which previously interpreted server timestamps from Apple's 2001 reference epoch and displayed a countdown roughly 31 years too large.
- The decoder remains compatible with already-created local activities that used the prior reference-date representation, and expired countdown ranges clamp to zero.
- Regression tests cover APNs decoding, Unix encoding, and legacy local-state decoding.

## 2026-10-07 notification launch and release safeguards

- Notification-response routing now uses the completion-handler delegate API, acknowledges the system callback immediately, and transfers only the parsed route onto the main actor. This avoids the async Objective-C bridge that appeared in the physical-device notification crash reports.
- A notification or Live Activity route received during cold launch is retained until bootstrap completes, then refreshes the selected circle and opens Today capture instead of being lost against uninitialized state.
- The APNs Live Activity payload now has a standalone, executable contract test that verifies Unix-second deadlines and exact content-state fields for start, update, and end events.
- TestFlight preparation runs the APNs payload contract plus the domain suite in both Debug and Release, including expired-deadline and cold-notification-launch regressions.

## 2026-10-07 entry-deadline semantics

- The configured deadline now controls when a member may enter capture. Opening capture first requests a server-timestamped entry grant; once granted, text, voice, video, photo, and scripture submission may finish after the deadline even when late entry is disabled.
- Capture freezes the granted prompt, so a composition completed after midnight remains attached to the original circle day and appears in that day's Timeline row with the normal late indicator.
- Natural prompt claims now author the shared start and deadline from actual server dispatch time, preserving the complete owner-configured entry duration despite minute-level scheduler latency. Prompts missed by more than five minutes close without sending stale alerts.
- Foreground notification delivery refreshes the selected circle without requiring a banner tap, and opening Today performs a fresh circle load before rendering its entry action.
- Migration `202610070001` is applied to the linked hosted project, and the hosted `public` schema passes Supabase's error-level lint. A new TestFlight client build is still required to call the entry-grant RPC before presenting capture.

## 2026-10-07 notification prompt routing

- Hosted bootstrap and circle refresh now select the prompt for the circle's current local date instead of the latest stored date. This prevents tomorrow's pre-created prompt from replacing today's open prompt when an alert arrives.
- Alert, widget, and Live Activity capture routes now include the exact prompt identifier. Notification taps can therefore select the originating circle and prompt before requesting a server-authored entry grant, including when another circle is selected in the app.
- Capture entry no longer performs a second client-clock deadline veto. The server entry-grant RPC is authoritative, while old circle-only deep links remain compatible by refreshing the current local-date prompt.
- Hosted logs for the reported failure contained no `begin_blessing_entry` request, confirming the rejection occurred in the stale client prompt path before the RPC. Regression coverage now includes exact widget routing and cross-circle prompt deep links.

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
- Fifty-eight Debug domain tests, 54 Release domain tests, and six UI tests pass. The latest Release domain and UI passes ran separately on an iPhone 17e simulator, avoiding Xcode's worker-handoff stall; the six UI tests also pass through an authorized automation session on a signed iPhone 14 Pro running iOS 26.6.2. Current UI coverage includes the all-settings creation form, owner invite-code rotation and force-notification flow, Today and Timeline scrolling, dark appearance, accessibility-size text, and text/voice-versus-video photo attachment availability.
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
