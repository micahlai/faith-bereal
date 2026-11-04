# Frontend functionality readiness — November 3, 2026

Status: original run was interrupted during case 47. Its log records 45 passed, 1 failed, and 1 unfinished; it is not a passing full-suite result. Focused unchanged-product rerun on a fresh small phone passed both selected cases; larger-device comparison also passed. The separate diagnostic reachability probe also passed.

## Scope and provenance

- App/source: 0.5.3 (50), baseline `c44c1cc1880201de9e3962a401bb6949fa037d5d`.
- Original run: `build/AppStoreReadinessNov03UI.xcresult`; log `build/app-store-readiness-nov03-ui.log`.
- Small-phone destination: iPhone 17e, iOS 26.5, `CC0C1981-1A4A-4567-8044-2375F9CE142C`.
- Existing Debug app and UI runner were built before this delegated audit. `baseline.json` records executable hashes and working-tree state; no production source or existing test changes are authorized or made here.
- Tests use Debug local-demo fixtures, blank simulator Supabase build settings and explicit local launch flags. No hosted calls, accounts, production mutations, notifications or artwork work were performed by this agent.
- No native-app screen sharing/control or screenshots were requested through computer-use tools. Existing XCUITest artifacts/logs are local test evidence.

## Functional coverage in the 47-case UI suite

| Area | Checks exercised | Limits |
| --- | --- | --- |
| Startup and privacy | Seven-step navigation/Back, age and data-use gates, policy navigation, diagnostics default off, persistence | Local fixture bypasses real Apple login and hosted bootstrap |
| Today/circle isolation | Switching circles, locked peers before own share, typed submission/unlock, draft resume/relaunch, 1,200-character limit | Does not exercise hosted two-account RLS/realtime or deadline races |
| Capture controls | Typed/voice optional photo controls, video excludes separate attachment | No physical camera recording, microphone/speech permission or denied/recovery acceptance |
| Timeline | List/Threads/filtering, layout preference persistence, pinned header, response counts, landscape, scrolling stability | No full iPad/split-view or older-OS matrix |
| Loading/offline | Cached metadata shell with disabled unauthorized actions; no cached blessing leak; tabs remain usable | Injected local load delays/failures, not real packet loss/airplane-mode transition |
| Media | Photo open/close, pinch/buttons/reset, no horizontal drift, appearance restoration; offline saved CAF blessing and response playback after relaunch | Offline playback checks player preparation/enabled seek controls; no human audio quality judgment; no camera/transcription end-to-end |
| Saving | Reminder pinned/hide; Save all; per-account storage estimate; keep selections, photo preview, Cancel preserves automatic saving; normal photo/voice/video/response review controls | Full video/voice capture not exercised; current save-review tests check video control existence rather than playing it |
| Circle administration | Create settings/review, owner force-local prompt, invite rotation, unsaved changes, permission sharing and read-only member settings | Hosted invitations, real universal links and actual ownership removal/deletion require installed/hosted acceptance |
| Accessibility | Native hit-region/description audit on Today/Timeline, selected 44-point controls, largest text/dark, Reduce Motion, landscape, anchored streak popovers | Native contrast audit deliberately excluded and remains manual; no complete VoiceOver task walkthrough, every-screen audit, or broad device matrix |
| Help/diagnostics | Help topic navigation, field-testing screens, explicit opt-in and relaunch persistence | Diagnostic fixtures do not prove hosted ingestion or privacy retention |

## Uncovered release-critical installed flows

No UITest currently invokes Safety → Report content, report reason/details/send/failure/cancel, Block user confirmation, mutual disappearance, Blocked users → Unblock, Delete account acknowledgement/Apple reauthentication, deletion accepted/pending/status/sign-out, or failed/retried deletion. Unit/SQL/backend evidence cannot substitute for these installed UI flows.

`AccountDeletionPendingView` is a substantial unscrolled `VStack`; explicitly check its complete content and actions at the largest accessibility text size on a small phone. This is a source-review risk, not a demonstrated failure.

Physical acceptance still needs Apple sign-in/cancellation/revocation, microphone/speech/camera/Photos permission denial and recovery, record/play/export after interruptions/backgrounding, low storage and failed upload recovery, live two-account locking/report/block behavior, APNs/Live Activity/badge permission and delivery, and real universal-link routing. Automatic UI tools cannot certify these without the appropriate devices/accounts/fixtures.

## Original run accounting

The original runner is no longer alive. The result bundle has no final `Info.plist` and cannot be read by `xcresulttool`; retain it as interrupted evidence rather than a valid completed bundle. The log and `original-completed-tests.json` preserve the 46 finished cases. `TimelineFilterUITests.testThreadsLayoutSurvivesTabChangesAndAppRelaunch` was interrupted after termination before its relaunch assertion. `SavingMenuUITests.testReviewCardsAtLargestDarkText` failed at `UITests/SavingMenuUITests.swift:127`, `Could not reveal saving.preview.photo`, before tapping the photo. The unchanged normal-text review and keep-copy photo preview cases passed. A focused rerun on a fresh iPhone 17e covers both unfinished/failed cases without rebuilding.

## Focused unchanged-product result

`SmallFocused.xcresult`: **2 passed, 0 failed, 0 skipped** on a new iPhone 17e/iOS 26.5. The exact existing largest-dark save-card review passed (111.898 seconds), including actual photo open/close, voice/video/response control reachability, Save all and disappearance of the reminder. Threads persistence passed (30.268 seconds), including app relaunch. The original photo failure is therefore **intermittent**, not a consistently reproduced functional failure. The original helper can make up to 60 long viewport drags and requires full-frame containment; source inspection suggests overscroll/oscillation as a hypothesis, but this has not yet been proven. Preserve the failing original log and do not count this rerun as a clean uninterrupted full-suite pass.

Across original log plus focused rerun, all 47 distinct existing UI cases now have a passing observation, with one original intermittent failure retained. These are local Debug fixture observations, not distribution-binary/real-account acceptance.

## Larger-device comparison

`LargeFocused.xcresult`: **1 passed, 0 failed, 0 skipped**. The exact existing largest-dark review case passed on a fresh iPhone 17 Pro Max/iOS 26.5 in 82.057 seconds using the same compiled app and original UI test runner. Thus the photo control has been demonstrated reachable/openable by the original test on both small and large phones. No persistent app defect has been established. Retain an intermittent automation/navigation issue for investigation rather than declaring the first failure fixed or asserting its root cause.

## Diagnostic probe and finding

`PhotoProbe.xcresult`: **1 passed, 0 failed, 0 skipped** (71.343 seconds). This is a separate diagnostic UI runner entirely under `build/frontend-readiness/`, not a replacement or modification of the existing suite. It launched the installed unchanged baseline app with the same synthetic save-menu fixture, largest accessibility text and dark appearance, logged the photo/viewport geometry, used smaller scroll gestures, required full containment, actually opened and closed the photo, and checked that pinned Save all remained hittable.

On the iPhone 17e, the photo eventually measured `(x:40, y:519, width:310, height:160)` within the usable vertical region `129...698.67`; it was hittable and the actual tap opened the photo viewer. Earlier at `y:832.67`, XCTest already called the below-viewport photo hittable, which supports retaining full-visibility checks. The probe demonstrates usable UI, not the cause of the original failure. No test expectation was weakened and no app/source/test repair was made.

**Disposition:** the original largest-dark save-card failure is an intermittent automation/navigation concern. It is not a reproducible app functionality defect on this evidence. There is no clean uninterrupted full-suite pass from this audit: the original run was interrupted and contains a real failed assertion. All 47 distinct existing cases have passing observations across the original completed cases and the two-case focused rerun, plus the independent larger-phone/probe passes.

## Recommended next acceptance

1. Add local UI fixtures/tests for report/block/unblock and deletion/pending/error screens, including largest text; preserve real Apple reauthentication as physical acceptance.
2. Run the current whole UI suite once to completion on an isolated simulator before release, retaining any intermittent failure for diagnosis. Do not simply retry failures until the result is presented as a single green suite.
3. Run installed, two-account real-device checks for capture/permissions, media interruption and export, privacy transitions, Apple revocation, push/Live Activities/badges, accessibility and universal links. Current automated evidence does not certify those flows.

## Evidence files

- `baseline.json`: source revision, baseline executable hashes and initial working-tree status.
- `original-completed-tests.json`: all 46 completed original log cases.
- `coverage-inventory.txt`: current 47-case UI test inventory.
- `SmallFocused.xcresult`, `small-focused.log`, `small-summary.json`, `small-photo-details.json`: exact two-case completion/retry.
- `LargeFocused.xcresult`, `large-focused.log`, `large-summary.json`: same original photo-review test on the larger phone.
- `PhotoProbe.xcresult`, `probe.log`, `probe-summary.json`, `probe-attachments/`: separate reachability evidence and accessibility hierarchy.
- `Probe.swift`, `project.yml`, `FrontendProbe.xcodeproj`: diagnostic runner only, not production changes.
