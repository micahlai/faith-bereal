# Project status

## 2026-10-24 display consistency and durable offline identities — in verification

- Separate branch `codex/offline-polish`: the black-background photo viewer no longer overrides app appearance; attached photos use aspect-preserving layout with width/height caps. Timeline remembers List/Threads across tab changes and relaunch, and List omits thread lines/markers.
- Profile/circle photos move from purgeable cache to protected Application Support without a seven-day expiry; fresh metadata warms all known identity photos without waiting for their views. Display metadata also persists without age expiry. Cached identity survives a failed offline session refresh, offline circle switches stay local, and known circle names/photos load before archived Timeline installation so startup no longer flashes Saved circle. Unknown archive-only circles use Circle. Explicit sign-out still clears outgoing identity copies; cached metadata grants no mutation or peer-content privileges.
- Help/spec and regression tests accompany the changes. Initial full unit verification passed the new storage/loading/layout checks but found a changed Help phrase assertion, an existing midnight-dependent Timeline fixture and an intermittent audio export-duration result; verification is continuing.
- [Offline capture/video plan](OFFLINE_CAPTURE_AND_VIDEO_PLAN.md) records the user's chosen ten-minute daily entry grace and a durable explicit-send queue design. These are planned changes: capture still requires server entry and video remains 30 seconds. The plan evaluates 90-second media costs and a proposed byte budget; no hosted migration/deployment or release is included.

## 2026-10-24 device-registration RPC failure — server fix deployed

- The focused three-hour API Gateway search found 14 build-42 HTTP 404s, all for `register_device`, including the two October 25 00:06:24 UTC failures matching the received diagnostics. The client synthesizes optional-token encoding by omitting absent fields, but the hosted function required all four argument names. An anonymous synthetic API probe reproduced `PGRST202` for APNs-only arguments; adding the missing argument as explicit null reached the expected authorization denial. The absent shared-circle-settings function is a separate pending feature, not the endpoint behind these correlated failures.
- Migration `202610240001_device_registration_optional_tokens.sql` is deployed alone at 2026-10-25 01:47:18 UTC (October 24, 6:47 p.m. Pacific). An exact predecessor-body/argument check and bounded transaction protect the change; recorded migration contents match the checked-in file. Optional token defaults let installed clients register either token first. The environment remains mandatory through an explicit null guard, authentication and restricted execution remain enforced, and null/blank tokens preserve existing values. The API schema cache was reloaded. No unrelated pending migration was deployed.
- The client now explicitly encodes unavailable tokens as JSON null for compatibility with strict four-argument servers. Help and the product spec explain independent alert/Live Activity readiness, reopening to retry, and iOS delivery limits. This client change needs a future distributed build; the server compatibility fix already benefits installed builds when they retry. No TestFlight archive/upload is included.
- Verification: the new SDK HTTP regression first failed with `PGRST202` and now passes; all 37 focused repository/Help tests pass (`build/RPCRegistrationFocusedAccepted.xcresult`). Disposable PostgreSQL reproduces the original named-argument failure and passes partial/null/blank/replacement token preservation, both arrival orders, environment/account isolation, revocation recovery, missing-environment rejection, and anonymous/missing-identity denial. The same random-fixture checks pass against hosted schema before deployment in a rolled-back trial and after deployment with all fixture writes rolled back; no push is sent. Live anonymous API checks for APNs-only, Live-Activity-only, and explicit-null payloads now all reach HTTP 401 / `42501`, confirming argument resolution while preserving access denial. Physical-device retry and actual push delivery remain field acceptance work. Earlier simulator attempts stalled before executing tests and were stopped; accepted runs use clean disposable simulators.

- Final verification: all 343 Debug unit tests pass (`build/RPCRegistrationCleanFinal.xcresult`), and the hosted-configured Release arm64 simulator build passes (`build/RPCRegistrationRelease.xcresult`). The first complete full-suite run found one unrelated Timeline fixture seeded at exactly local midnight; looking backward crossed into the prior calendar day. Its fixed local-noon seed preserves the scheduled/privacy assertions and passes in the final full run. Only this task's four disposable verification simulators were removed. Unrelated project-generator formatting was restored.

## 2026-10-24 traffic and database diagnostic follow-up

- Live dashboard check at approximately 6:40 p.m. Pacific: September 30–October 30 uncached egress is 6.476/5 GB, cached egress 2.108/5 GB, average Storage 0.247/1 GB, and database usage 0.043/0.5 GB. The egress grace-period warning through November 17 remains. The daily service chart includes cached bytes; subtracting the separate cache chart gives approximately 66/49/99 MB uncached on October 22/23/24 UTC. That recent pace projects to roughly 2.2 GB per 30 days, with hourly reporting lag and variable activity. It is encouraging, not proof of sustainable usage at larger scale or a reversal of the current cumulative overage. PostgREST alone accounts for roughly 35–38 MB/day on those dates, so moving media alone would leave meaningful API traffic.
- Read-only hosted snapshot at 2026-10-25 01:36:32 UTC: 7 client connections of 60, one active (the operator query), zero lock waits and zero idle transactions. Received build-42 coverage now spans October 22 22:45:36–October 25 00:06:33 UTC: six participating accounts, 29 sessions, 30 reports and 1,496 records. All 318 recorded signing operations succeeded, with no connection-limit-classified event in this build. Earlier build-41 reports contain ten connection-limit-classified Storage signing 429s, most recently October 22 18:43:48 UTC. The original issue has improved in the newest sample; intermittent saturation is not proven eliminated by an idle snapshot or opt-in/bounded reports. Receipt dates are not incident dates.
- Build 42 still records 51 RPC `PGRST202` failures through October 25 00:06:24 UTC, one RPC timeout and one lost connection. `PGRST202` identifies a missing/stale function signature rather than pool exhaustion. The client RPC-name/catalog comparison confirms `set_circle_member_changes` remains absent, but generic RPC telemetry does not establish that it caused these particular events. Two `54000` diagnostic-upload failures are consistent with the deployed uploader's explicit rate guard. Visible bootstrap median/p95 are 5.17/25.22 seconds across 30 recorded spans, including two failures; user-facing startup is not fully healthy yet. Signing calls per reported session are lower on build 42 (318/29) than build 41 (1,689/22), without a controlled same-workload comparison.
- Recommendation: resolve/identify the recurring RPC mismatch and validate several more representative days before treating the incident as closed. Cloudflare R2 remains a possible future private-media cost/scaling option, not a demonstrated database-connection fix or an urgent migration at the recent byte rate. Keep server authorization and today's visibility gate intact in any storage change. Supabase already supplies a Storage CDN; its documented private signed-URL cache keys vary with each token, so merely adding a proxy does not guarantee useful cache reuse. No production settings/schema/data mutation, load test, client change, or release was performed; only diagnostic project notes were updated.

## 2026-10-22 traffic reduction — implemented and verified

- Saved audio/video/photos and response audio now resolve from the account's existing archive before private link signing. Authorized content still comes from fresh database reads. Unsaved played audio/video, opened full photos, and small photo previews share a protected account-scoped disk cache (seven days, 256 MB total, 128 MB per file); renewed tokens reuse immutable bytes and concurrent downloads coalesce. A later Save copies cached bytes into its permanent archive. Temporary downloads can be evicted and are cleared on sign-out; completed saves remain separate. Explicit playback Retry replaces the temporary recording only.
- History pages now cover seven complete calendar days. Widget and automatic-saving workers share recent authorized pages rather than fetching entire histories separately; unchanged complete automatic archives skip response-body reads. Visible appearance refreshes coalesce for 15 seconds, optional page reads for 60 seconds, and unchanged widget writes for one minute. Explicit refresh/content changes remain fresh, and account/circle generations fence late results.
- Automatic saving still requires opt-in. Its new defaults are Wi-Fi only and the last seven days; older history is a separate opt-in, added one older page per circle per worker pass. A failed batch retains its cursor for retry. Network policy applies to each automatic network download and active-app Wi-Fi recovery resumes queued work. Manual Save/Play still work on cellular. Accessibility layouts place switches beneath full-width labels. Help and the product spec explain temporary versus permanent storage and these limits.
- New photos include a 480-pixel preview; scrolling never downloads the full remote photo, which opens on tap. Older photos without a preview show an Open photo placeholder. Identity-photo caching ignores renewed tokens and observes metadata version changes. All new video uploads, including restored/imported sources, export network-optimized MP4 capped at 720p; prior uploads are unchanged. Existing AAC/M4A voice compression and offline saved Timeline behavior remain intact.
- Hosted migration `202610220001_photo_previews.sql` is deployed alone after an exact predecessor-body check in a bounded transaction with recorded migration history. It extends existing media authorization to the matching preview path, preserving prompt/membership privacy and supporting reused blessings. Local Storage/SQL checks and rollback-only hosted locked/unlocked/reused/outsider checks pass; catalog confirms authenticated execution and anonymous denial. No unrelated pending migration was deployed.
- The investigation's October 22 dashboard snapshot remains cumulative: uncached 6.278/5 GB, cached 2.086/5 GB. October 20/21 uncached traffic was approximately 224.1/55.6 MB, with 13/12 reported sessions and 7/2 new posts. Their average projects to roughly 4.2 GB per 30 days, but activity fell substantially from October 17's 30 sessions/15 posts. This does not isolate the earlier fixes' benefit or establish sustainable traffic at equal usage. The current feature needs a new distributed client build before production byte savings can be measured; Wi-Fi-only saving shifts network choice rather than reducing server bytes on its own.


- Verification: all 341 Debug unit tests pass (`build/TrafficReductionFinalUnitsAccepted.xcresult`), including one actual download across Play → Save and a permanent copy surviving temporary-cache removal, signing suppression, cache renewal/relaunch/coalescing/expiry/account fences, unchanged-archive read suppression, Wi-Fi/manual-save/history controls, and real photo/video export fixtures. Four focused UI flows pass (`build/TrafficReductionUI.xcresult`): settings persistence, automatic keep/cancel, photo zoom, and saved legacy blessing/response playback offline after cold launch/relaunch. The stacked largest-text layout passes in `build/TrafficSavingLayoutAccepted.xcresult`; screenshots were inspected. A final rerun also logs success for the controls after main-thread network notification delivery; interruption prevented its result bundle from finalizing. The combined unit/UI attempt stalled before tests and was superseded by separate passing runs. The hosted-configured Release simulator arm64 build passes (`build/TrafficReductionRelease.xcresult`). Only this task’s disposable verification simulator was removed. No TestFlight archive/upload, Git commit, or push is included.

## 2026-10-20 automatic saved Timeline and bandwidth investigation — locally verified, unpushed

- Removed the separate Saved on this device menu and reader. Completed archives now populate the ordinary Timeline automatically before session refresh, including cold launch/relaunch with no valid session or circle metadata. Ordinary detail/cards use saved responses/counts without repository calls while offline. Saved circles switch locally; generic identity labels cover missing metadata. Historic copies supplement online pages and deduplicate as refresh/paging returns server cards. Local media keeps priority.
- Offline presentation grants no live membership or write access: editing/responding/sharing remain gated. Account changes, explicit sign-out, and late startup results remain fenced. Old archives lack prompt dates/time zones; unpaired peer copies use a conservative 26-hour age boundary, while same-prompt own saves permit the corresponding peer copy. Help and spec explain this restriction and missing identity/media limits.
- The current Chrome dashboard shows uncached egress 6.087/5 GB, cached egress 2.074/5 GB, average Storage 0.186/1 GB, and database 0.039/0.5 GB for September 30–October 30. The quota warning/grace period through November 17 persists. Cumulative usage does not reverse after a client fix. Read-only database check at 2026-10-20 03:59 UTC: 17 client connections of 60, one active (the operator query), zero lock waits/idle transactions. This snapshot does not prove absence of intermittent saturation.
- Latest received build-40 sample covers 03:55:12–23 UTC: 92 successful signing SDK operations and no reported connection-limit failure, but one RPC PGRST202 remains. The signing burst is still a pressure risk; demand loading/local reuse reduces byte downloads but has not eliminated signing operations. Function-name catalog comparison finds `set_circle_member_changes` absent (the shared-settings migration is pending); generic RPC diagnostics do not prove this is the function behind that particular runtime error. Older build-38 data includes a Storage signing 429 at October 19 21:27:19 UTC. Build-39 diagnostics include three delayed audio failures at 01:56:29–31 UTC and offline/lost-network errors; the diagnostic uploader's 54000 rate guard is confirmed deployed. No hosted change or load/stress traffic was performed.
- All 328 Debug unit tests pass (`build/AutomaticSavedTimelineHistory.xcresult`), including zero idle downloads, one Play download/replay reuse, zero saved-playback downloader calls, immutable archive reuse across changed links/relaunch, request batching, automatic offline Timeline/scope/privacy/local responses, and online saved-history refresh/paging deduplication. The initial 326-test run near midnight had four unrelated date-window failures; the subsequent complete 327/328-test runs pass. The normal/largest-dark offline cold-launch/relaunch UI flow passes with both legacy saved recordings playing from ordinary Timeline detail (`build/AutomaticSavedTimelineUIAccepted.xcresult`, final banner rerun `build/AutomaticSavedTimelineAccessibleFinal.xcresult`). Timeline/detail screenshots were inspected; the oversized accessibility status banner was shortened and stacked. The final Release simulator arm64 build passes. Only this task’s disposable simulator was removed. A concurrent build attempt hit Xcode’s build-database lock and was superseded by the passing sequential UI rerun. No commit, push, hosted mutation, or TestFlight upload was performed.

## 2026-10-19 legacy saved voice playback and offline archive — locally verified, unpushed

- A real CAF recording renamed to the historical saved `.data` filename reproduces “This recording couldn’t be loaded” without any server request. The player now identifies the CAF header and stages the same local bytes with `.caf`; the original archive remains intact. New saved blessing/response CAF files retain `.caf`. This is a confirmed local reproduction matching the reported saved-recording symptom, not device-level proof for the owner's build-39 incident; received build-39 reports had no audio/playback event identifying that incident.
- Completed archives restore from the last locally signed-in account before session refresh or repository bootstrap, including without circle metadata. Saved on this device opens a separate read-only reader from the app menu and from loading/failed/sign-in presentations. It reads saved text, Bible references, audio/video/photos and responses without backend calls or remote media. Missing files remain unavailable; Bible passage downloads and live Today/Timeline content still require a connection. A different account or successful explicit sign-out clears archive presentation; late bootstrap results cannot restore it. Offline archives never grant live membership or mutation access.
- All 326 Debug unit tests pass (`build/OfflineSavedMediaClean.xcresult`), including the formerly failing local CAF reproduction, new CAF extensions, unavailable session/no metadata, suspended server startup, cross-account isolation, explicit sign-out and late-result fencing. The first reproduction failed as expected; compile checks and a stalled test-host run were superseded by the clean run. The offline UI flow passes cold launch and relaunch at normal and largest dark text sizes (`build/OfflineSavedArchiveUI.xcresult`), playing both the saved blessing and response from legacy local files with no valid session or circle metadata. Screenshots were inspected. Release simulator arm64 build passes. Help, product spec, and testing notes describe the offline entry point and limits. No server mutation or TestFlight upload is included.

## 2026-10-19 media demand loading, voice compression, and saved-file reuse — locally verified, unpushed

- Audio and video players prepare only after Play (or explicit full-screen opening/retry), rather than downloading/reading remote media when their view appears. Idle Play remains enabled; preparation shows loading feedback. Explicit manual/automatic saving still downloads media for the archive.
- Every completed voice recording, including single-segment capture and restored drafts, exports AAC in M4A. Mixed input routes retain their combined duration. Failed/cancelled exports and stale assembly results clean up their generated output. Previously uploaded CAF recordings are unchanged.
- Archive refreshes reuse each existing immutable audio/video/photo/response file even when a fresh remote URL is supplied or the remote source is absent. Reopening the store preserves the same files; only newly added response media downloads. Responses already on screen resolve newly saved local audio reactively. Saved blessing media continues to win for playback, viewing, and Photos exports before and after server expiry without changing visibility rules.
- Debug passes all 321 unit tests (`build/MediaDemandDebugFinal.xcresult`), including download-on-Play/replay, local-only voice playback, changed-link/relaunch archive download counts, one-new-response-only download, saved audio/video/photo/response resolution before/after expiry, AAC output/size/duration, and Help. The saving keep/cancel flow passes on a clean disposable simulator (`build/MediaDemandUIIsolated.xcresult`); Help navigation passes in `build/MediaDemandUI.xcresult`. Saving/Help screenshots were inspected. Earlier saving UI attempts opened stale Welcome state; the explicit local fixture, cold launch, and clean installation pass. The initial unit host startup and one intermediate UI run were interrupted and superseded by these runs. Release simulator build passes for arm64 with the hosted configuration. Help, product spec, and testing guidance are updated. No hosted schema/data change, TestFlight archive/upload, Git commit, or push is included.

## 2026-10-16 loading presentation and photo person picker — locally verified, unpushed

- The page loading indicator uses the surrounding canvas color with contrasting secondary text. List/Threads hide the response line when the count is zero; positive counts and overlapping responder photos remain. The List-only person picker shows actual profile photos with initials as fallback, and retains the selected photo beside the name. Choices have 44-point targets, selected-state accessibility, and bounded scrolling at large text sizes and in landscape.
- Startup restores cached identity before diagnostics setup. Fresh authorized basic metadata now displays and persists before the first blessing page finishes, fixing a gap where a failed/stalled first page left the next launch without saved basics. Content actions remain gated until that page succeeds; sign-out and late results remain fenced. Blessings still need fresh server reads/media links. This change does not establish the cause or elimination of a device's minute-long content load.
- Debug passes all 316 domain tests, including three new first-page cache regressions, startup diagnostics, Help, and color contrast (`build/SmallUIPolishDebug.xcresult`). All five focused UI flows pass across final batches: normal/largest-dark/landscape photo filtering and normal/largest-dark cached loading (`build/SmallUIPolish.xcresult`, `build/SmallUIPolishAccepted.xcresult`). Screenshot review confirms background continuity, legible status text, actual picker/selected photos, and initials fallback. Initial largest-cache and landscape-response failures were scroll-test overshoot; bounded reversible drags pass their final reruns without changing production scrolling. Changes are committed locally. No server change, TestFlight archive/upload, or push is included.

## 2026-10-16 Timeline client optimization and person filters — locally verified, unpushed

- Timeline defaults to List for all text sizes. The wide, thin labeled layout control sits in a pinned bar below circle navigation and switches List/Threads with a 44-point touch target. Accessibility sizes give the person filter a full-width row. List offers All/person filtering, keeps the choice through mode changes/refresh/paging, and clears it across account/circle/time-zone changes or removed people. Threads always shows every member and has no person filter.
- List builds chronological per-person indexes on page changes. Threads prepares its rows only while active, precomputes event order and notification times, isolates scroll geometry, and looks up only visible date anchors. Both layouts show response counts plus slightly overlapping unique responder photos. Visible cards batch lightweight response identity rows, without fetching response bodies or signing audio. Bounded short-lived summaries coalesce requests and invalidate on refreshed Timeline data/response submission, with account/circle generation fencing.
- Final Debug passes all 313 domain tests, including seven filter tests and eight response-summary tests. All five distinct focused UI flows pass across final batches: normal filters, landscape filters, largest-dark filters with Reduce Motion, Threads resizing/event-only List, and pinned Threads member/date headers. Final largest-text screenshot review confirms full-width readable filtering and three responses with two overlapping photos. Results are `build/TimelineOptimizationDebugFinal.xcresult`, `build/TimelineFilterNormal.xcresult`, `build/TimelineFilterUIAccepted.xcresult`, `build/TimelineLargestReadable.xcresult`, and the passing pinned-header case in `build/TimelinePinnedControlsUI.xcresult`. Earlier UI failures exposed the native navigation-menu touch target and inherited accessibility identifiers, then saved-circle/stale-onboarding fixture isolation; they are superseded by these checks. An initial full Debug run hit the existing intermittent voice-segment duration test; it passes in the final full run, with audio assembly unchanged. Release passes all 309 domain tests (`build/TimelineOptimizationRelease.xcresult`, active simulator architecture). The 85-card batching fixture uses three requests; this is a request-contract check, not a field-latency or device frame-rate claim. Only this task’s disposable simulators were removed. Changes are committed locally; no server schema, archive/upload, or push is part of this change.

## 2026-10-15 independent streak windows and recording playback diagnostics — locally verified, unpushed

- Overall streaks count either random or evening sharing once per circle-local day. Consecutive on-time streaks count random blessings only, using entry before the deadline even when sending finishes later. Each count resolves independently when its window closes; unfinished and overnight windows retain the preceding run. Posting/reusing refreshes streak metadata, and server-authored deadlines schedule visible-circle refreshes. Today/Timeline show the overall count, blue only when both consecutive counts match; Circle shows each positive count separately. The animated popup includes both counts, including zero. At accessibility sizes Circle places the pills below the identity on the right, leaving room for names; popup descriptions wrap fully and choose the available side of the flame.
- Migration `202610150002_independent_streak_deadlines.sql` is deployed with recorded history after a predecessor-body check and bounded transaction. Its authenticated member-only wrapper returns six fields, including the next deadline; the operator clock helper remains private. Actual hosted preflight/postflight fixtures roll back. Disposable normal/reverse migration-order, authorization, deadline, DST, and reference-equivalence suites pass. The separate shared-circle-settings migration remains undeployed; its pending streak block now preserves an already deployed six-field successor. A sparse ten-year/20-member fixture measured 1.176 ms for the bounded candidate versus 696.654 ms for an unbounded reference; a dense 3,651-day run preserved all days (22.554 versus 21.830 ms). These are disposable fixture comparisons, not hosted latency claims.
- Build 33 did not capture the cause of “This recording couldn’t be loaded.” Its failed RPC occurred October 15 at 6:37:10 p.m. Eastern, received at 6:42:24 p.m. A later aggregate check found four additional media-link signing failures at 6:48:15–22 p.m., received at 7:45:52 p.m.; these can affect media access, but the old payloads lack codes or action identity proving playback causality or connection exhaustion. The next client captures safe remote-voice HTTP/transport and asset/player/audio-session/local-staging failures through existing diagnostic categories. Recording contents, raw errors, and media links stay excluded. Refreshed links now replace stale player URLs, downloaded M4A keeps its extension, and cancellation/late async results cannot start an empty player or replace a newer recording. These fixes and diagnostics require a new client build; the original device failure's cause remains unconfirmed.
- Final full domain runs pass 297 Debug and 293 Release tests, including eight playback regressions and posting/reuse refresh coverage. Three focused streak UI cases pass together on a small phone at normal/largest dark sizes and landscape; the final accessibility-row adjustment also passes its focused rerun. Popup and Circle screenshots were visually inspected, correcting clipped popup text/placement and crowded names. The three existing photo UI cases pass across focused batches. Results: `build/StreakPlaybackFinalDebug.xcresult`, `build/StreakPlaybackFinalRelease.xcresult`, `build/StreakPopupPlacement.xcresult`, and `build/StreakAccessibilityFinal.xcresult`. Earlier UI failures in `StreakPresentationUI`, `StreakSmallPhoneUI`, `StreakSmallPhoneUIFinal`, and `StreakSmallPhoneUIAccepted` are superseded by those passes; bounded bidirectional scrolling fixed the test harness, and the popup fixes address actual layout failures. The voice assembly test now finalizes and validates its synthetic source files before export, with production assembly unchanged. Only this task’s disposable simulators were removed. Changes are committed locally; no new TestFlight archive/upload or Git push is included.

## 2026-10-15 diagnostic error visibility and cached circle loading — locally verified, unpushed

- Added sanitized error source/code and connection-limit classification to failed backend calls, plus Speech/audio setup/recognition failures. Raw messages, transcripts, URLs, credentials, and NSError userInfo are not uploaded. Diagnostic-upload failures are queued directly once per source/code/category until recovery, without instrumenting the transport itself. Pending failures precede routine samples and survive routine-sample queue pressure; prepared retry IDs/payloads remain unchanged. Foreground/new-failure attempts and bounded one-minute backlog retries reduce delay while preserving server quotas and ordinary five-minute collection.
- Startup and circle switching display account-scoped saved circle/member/streak metadata immediately with a persistent loading/error indicator and Retry. Protected metadata and bounded identity-photo bytes expire after seven days and clear on sign-out. Photo refreshes use fresh verified metadata. Cached invites/permissions cannot authorize capture, reuse, settings, responses, or pagination; blessings/prompts are fetched under current server authorization. Late bootstrap/leave/switch results cannot restore another account's content. Failed switches restore the original circle. Foreground refreshes coalesce; optional widget/automatic-saving work waits for visible loading. Failed/cancelled live subscriptions are removed from the client registry.
- Diagnostic-only migration `202610150001_backend_diagnostic_errors.sql` is deployed after matching the existing validator's body hash, in a bounded transaction with recorded migration history. Catalog confirms new metadata/upload categories, RLS, authenticated-only ingestion, no client private-table/prune access, and the existing single hourly cleanup. Disposable old/new payload/security/retention/quota/concurrent-ingestion regressions and actual hosted rollback verification pass; retained reports remain nine after the rollback. The separate shared-circle-settings migration remains undeployed.
- Live build-33 collection now contains four batches/400 records, including seven failed records: two media-signing URL timeouts and their two stage records, one failed RPC, and widget/automatic-saving stage failures. These are overlapping records, not seven independent incidents. The latest event is October 14 at 10:14:17 p.m. Eastern; latest receipt is October 15 at 4:35:55 p.m. Eastern. The reported approximately 2 a.m. incident is not covered by that event range, and legacy records do not identify a connection-limit service code.
- Debug passes 268 domain tests and Release passes all 264; the final focused loading/account-scope/Help check passes 42. All nine distinct focused UI cases pass across final batches: cached loading at normal/largest dark text sizes, circle switching/privacy, three attached-photo/streak flows, default-on/opt-out persistence, and diagnostics screens at normal/largest dark text sizes. Loading and diagnostic screenshots were visually inspected. Results are `build/DiagnosticCacheDebugFinal.xcresult`, `build/DiagnosticCacheRelease.xcresult`, `build/DiagnosticCacheScopeAccepted.xcresult`, `build/DiagnosticCacheUI.xcresult`, `build/DiagnosticCacheUIAccepted.xcresult`, `build/DiagnosticConsentVerified.xcresult`, and `build/DiagnosticConsentLargestIsolated.xcresult`; the UI bundles contain earlier failed cases superseded by the focused passing runs. Test scrolling now uses the settings sheet's own navigation bar, bounded gestures with a held endpoint, and keyboard clearance; a clean local app installation resolves the stale onboarding test instance. Earlier verification exposed an interrupted-switch rollback issue and stale async scope gaps, which were fixed; isolated loading tests disable notification prompts/optional background readers. Existing uploaded builds do not gain the new collection/loading code. The original device connection-limit cause still requires reproduction with the next client. No new archive/upload, Git commit, or push has been performed for this change.

## 2026-10-14 shared circle settings and streak popup — locally verified, unpushed

- Added the leader-only, default-off Anyone can make circle changes switch. When enabled, current members may edit general circle settings, photos, invitations, forced notifications, and other nonleader members. Permission changes and ownership transfer remain leader-only; self-removal uses Leave circle. Fresh server authorization and circle-row locks enforce revocation, including an edit waiting while permission is disabled.
- Tapping a streak flame opens a small animated icon-anchored popover with red consecutive-day and blue consecutive timely-entry counts. The blue run is independent of the normal run and breaks on late entry or a gap; today's unfinished day preserves yesterday's counts. Existing streak metadata fields remain compatible, with the new `on_time_streak_days` field for the popup. Profile and circle photos no longer enlarge; only attached blessing photos open the zoom viewer.
- Migration `202610140001_shared_circle_settings.sql` and disposable SQL/Storage tests are prepared locally. Permission boundaries, outsider/removed-member denial, protected leader/self removal, canonical photo paths, consecutive streak cases, and concurrent revocation pass. Hosted deployment has not been performed. The previous build-32 IPA does not contain these follow-up changes; no new archive, commit, or push was performed.
- Full domain runs pass 226 Debug and 222 Release tests. After correcting a success alert that dismissed Circle settings, the final eight permission-domain regressions pass. All seven distinct focused UI cases pass across the final batches: leader permission enable/disable and reopen persistence at normal/largest dark text sizes, member editing/read-only boundaries, attached-photo zoom and horizontal stability at normal/largest dark text sizes, and the icon-anchored streak popup with identity photos excluded. The photo test now waits until Send is above the keyboard rather than relying solely on XCTest's hittability report. Normal/largest-text settings, photo viewer, feed, and popup screenshots were visually inspected. Results are `build/SharedSettingsDebugAccepted.xcresult`, `build/SharedSettingsRelease.xcresult`, `build/SharedSettingsPostUI.xcresult`, `build/SharedSettingsUIFinal.xcresult` (four permission cases pass), and `build/SharedSettingsPhotoFinal.xcresult` (all three photo/popup cases pass). Only the disposable verification simulator was removed. Hosted shared permissions and complete mixed-streak timely counts require the prepared migration before distribution.

## 2026-10-14 v0.2.2 (32) field-testing follow-up — verified and exported

- A single flame now represents the circle streak: blue if every day in its current run had timely entry, red if the run includes a late entry. Entering before the deadline remains the criterion even when sending finishes afterward. Verification symbols are removed. Today/Timeline use a smaller photo-overlay pill without moving names; Circle People retains its larger trailing pill.
- This field-testing build sets `MANNA_DIAGNOSTICS_DEFAULT_ENABLED=true` for new account/device queues. Explicit choices and legacy saved off settings are preserved. Settings and Help disclose the default and opt-out. Default activation/session persistence fails closed, including summary refresh, with an explicit retry path. Startup restores the account's collection setting from local cached identity before the first session validation/refresh; that auth operation is now measured without using cached identity to authorize content.
- Displayed blessing/profile/circle photos have a full-screen native pinch/pan/double-tap viewer plus accessible zoom/reset/movement and Close photo controls. Existing editing/menu/card actions are preserved. Today is constrained to the viewport and has horizontal bounce disabled while retaining vertical scrolling and refresh. Local-only synthetic photo fixtures exercise the photo privacy gate and viewer without hosted traffic.
- Real build-31 collection is working: the latest read-only check confirms three batches containing 243 records from one account, last received at 2:48:12 p.m. Eastern, with no recorded backend failures. Errors before diagnostics was enabled cannot be collected retroactively. Exact service-error text/codes and Apple Speech/audio failures remain outside the current payload; a voice-panel error can differ from a concurrent backend alert. A 2:33 p.m. snapshot showed 28/60 database connections, 2 active and no idle transactions; it does not exclude transient or smaller pool saturation.
- Debug passes 215 app/domain tests and Release passes 211. All nine distinct focused UI cases pass across the final batches/reruns: draft recovery, Today vertical/horizontal stability, pinned Timeline, default-on/opt-out persistence, normal/largest-text diagnostics screens, and three photo-viewer flows. Normal/largest-text photo and streak screenshots were visually inspected; actual accessibility trees confirm one profile-photo action plus the separate full streak description. A post-change focused domain run passes 29 tests. The test harness now terminates the unit-test app host before UI launch to avoid a stale onboarding instance. Hosted-configured archive `build/Manna-0.2.2-32.xcarchive` and distribution export `build/TestFlight-0.2.2-32/manna circle.ipa` succeed. Export validation confirms production APNs, no debugging entitlement, Sign in with Apple, Universal Links, shared App Group, both signed extensions and artwork. The app and both extensions are v0.2.2 (32), and the exported app has the default-on diagnostics flag. Only the disposable verification simulator was removed. No App Store Connect upload was performed. No backend schema, pool capacity, media encoding, or Apple Speech lifecycle change is included in this follow-up.

## 2026-10-14 v0.2.2 (31) field-testing candidate — verified and exported

- The owner confirmed latest TestFlight v0.2.1/build 30 and requested v0.2.2/build 31 after the UI adjustments. Project version/build are updated. Blue flame/timely-entry pills overlay the top-right of Today/Timeline photos without adding layout width; Circle People rows show streaks on the right. Timeline date strips show only random notification times while preserving evening posts and sent timestamps.
- User settings adds default-off, persistent per-account/device Share diagnostic data. Typed metrics enter a protected, backup-excluded queue capped at 1,000 records, with stable 100-record retry batches and session/build separation. Foreground uploads run about every five minutes or through Send diagnostics now. Opt-out drops unsent records and cancels where possible; an in-flight request may finish. Storage failures pause collection, and delayed events/acknowledgements cannot re-enable it or cross accounts. The uploader pins the original account's JWT and never instruments its own requests.
- Hosted migration `202610130002_backend_diagnostics.sql` is deployed. Private reports are account-linked with closed payload validation, serialized per-account quotas, exact retry idempotency, and 14-day retention/hourly bounded cleanup. Client/peer reads, direct writes, anonymous ingestion, and client cleanup calls are denied. Disposable security/concurrent-ingestion regressions and the actual hosted rollback-only suite pass. Hosted catalog confirms the migration, RLS, grant boundaries, one active hourly cleanup, and zero retained test reports.
- Help, privacy manifest, guide tests, product spec, and [tester/operator instructions](TESTFLIGHT_FIELD_TESTING.md) describe consent, account association, payload exclusions, queue limits, retries, and retention. App Store Connect privacy answers still need matching declarations before wider distribution. Diagnostic SDK-call counts include retries within duration; they are not physical HTTP attempts or full device/capture latency measurements.
- Today now uses one draft-aware sharing action per daily/evening prompt: the primary Share button changes to Continue for its matching eligible local draft, restoring unsent changes without a separate draft button. Server entry checks and account/circle/prompt isolation remain enforced; regression coverage includes each independent prompt and closed no-late entry despite an old grant.
- Final Debug passes all 206 app/domain tests; Release passes all 202 (four tests are Debug-only). The full isolated simulator UI suite passes all 23 tests, including draft relaunch/recovery and diagnostics consent persistence. Earlier UI failures came from shared draft fixtures and a composer scroll gesture; isolated fixtures and an outer-edge gesture fix pass together. Screenshot review found that the largest-text streak pill covered its photo; only the secondary pill is now capped at XX Large while retaining the full VoiceOver label. Both rebuilt normal/largest-text screen checks pass and were visually inspected. Result bundles are `build/FieldDebugAccepted.xcresult`, `build/FieldReleaseAccepted.xcresult`, and `build/FieldUIIsolatedFinal.xcresult`; final screenshots are under `build/FieldScreensCapNormal` and `build/FieldScreensCapLargest`. APNs payload contracts and privacy manifest validation pass.
- Hosted-configured archive `build/Manna-0.2.2-31.xcarchive` and distribution export `build/TestFlight-0.2.2-31/manna circle.ipa` succeed. The export validator confirms production APNs, no debugging entitlement, Sign in with Apple, Universal Links, shared App Group, both signed extensions, and notification logos. The app and both extensions are v0.2.2 (31). Only the disposable verification simulator was removed. No App Store Connect upload or tester assignment has been performed. Media compression and physical multi-account field acceptance remain pending.

## 2026-10-13 circle-specific streaks, Timeline, and draft recovery

- Completed the requested client batch in individual feature commits: welcome blessings display on their actual sent day without consuming that day's regular prompt; List contains chronological actual events only; unstarted prompts have no Timeline placeholder; the frozen date strip shows actual notification times. Compact, lazily rendered Threads supports pinch and accessible menu resizing, with fourteen-day history pages and account/circle/time-zone isolation. Older widget links still resolve permitted details outside loaded pages.
- Streaks are specific to each circle and its calendar: regular or evening counts once per day, late counts, and gaps break the run. Welcome posts do not count as regular/evening shares. The flame count is independent of loaded Timeline history; separate recognition rewards timely entry even if completion comes later. Profile photos now accompany responses.
- Blessing drafts checkpoint text, scripture, mode, and private media by account/circle/prompt, survive relaunch, and offer Continue on Today only while server entry remains allowed. Successful sending or the next circle-local day removes recovery copies; midnight does not remove working media from an already-open composer. Voice recording holds the screen awake only while recording. Setup saving copy clearly distinguishes 30-day audio/video expiry from retained text/photos and explains manual saving when automatic saving is off.
- Customer Help, guide tests, product spec, and test guidance reflect these behaviors. The UI/UX review favored native resizing controls alongside pinch, semantic text sizes, and an event-only accessible List. Screenshot inspection also corrected wrapping in the narrow notification-time strip and stacked submission time/status at accessibility sizes; affected screen tests were rerun.
- All **155 app/domain tests pass**. The final focused simulator batch passes draft relaunch/send, largest-text Timeline List, resizing/event-only List, and pinned member/date headers (4 tests). An earlier five-test batch also passed setup/back/widget guidance and Help; this is six distinct focused UI tests across the batches, not a full UI-suite or device acceptance pass.
- Disposable database regressions pass, including streak isolation, distinct-day/late counts, timely entry, membership authorization, welcome timing, reuse, invitations, Storage visibility, and nudges. A late-day run exposed a test fixture's implicit session-time-zone assumption; regression fixtures now explicitly use UTC. Hosted rollback-only streak preflight and postflight checks pass; migration `202610130001_circle_streaks.sql` is deployed. Existing dispatcher code was unchanged.
- Hosted-configured signed Release device build succeeds. Its local development signature uses development APNs and `get-task-allow=true`; this is not a distribution/TestFlight export. No phone installation or TestFlight upload was performed. Physical microphone checkpoints, wake behavior, interrupted media recovery/playback, and real multi-account notification acceptance remain pending a new client build. Media cleanup was not activated.

## 2026-10-13 backend optimization — first measurement/request-reduction slice

- The owner authorized starting the [backend optimization plan](BACKEND_OPTIMIZATION_PLAN.md), with separate regression, simulator, and review subagents. The connection error reportedly affects startup/sign-in, circle switching/Timeline, and media sending. Modest compression remains gated on physical-device comparison review.
- The first slice reuses circle metadata within a single fresh load, removing the repeated circle/member/profile/invite/streak fetch before Timeline. Content is still fetched under server authorization every time; no persistent authorization or blessing-content cache was added. Offline adapter fixtures compare seven page requests with two when supplied fresh metadata, excluding signing traffic. This is a request-count result, not a hosted latency or connection-exhaustion benchmark.
- Account/circle/time-zone generations reject delayed results even after leaving and returning to the same IDs. Interrupted switching preserves the previous selection and restores realtime. Help and its guide tests explain switch recovery.
- Opt-in `MANNA_BACKEND_DIAGNOSTICS=1` adds stage timing and sanitized Supabase SDK-operation records to local OSLog. Disabled by default, with no remote telemetry exporter. The payload contains closed categories, UTC time, durations, available payload/returned-data sizes, success HTTP status and numeric URL transport errors; content, IDs, URLs, credentials, and error descriptions are excluded. Field setup/limits are in [TESTING](TESTING.md#backend-diagnostics-capture).
- Final simulator build and all **181 app/domain tests pass**, including 12 diagnostics tests on real localhost SDK reads/uploads/signing, 9 delayed-result scope tests, 4 metadata-reuse adapter tests, and the updated Help guide. An initial delegate-based recorder failed async completion tests; the final recorder explicitly measures SDK operations, with each record including retry duration rather than pretending to count every HTTP attempt. All five focused simulator UI tests pass together against the final build: startup/circle switching/share/privacy, draft relaunch/send, setup Back/widget guide, largest-text Timeline List, and resizing/event-only List. Earlier simulator attempts exposed test-launch/scroll-gesture issues that were corrected before the final passing batch. Local opt-in app launch emitted sanitized stage logs; hosted field error reproduction and physical media acceptance remain pending.
- A prior read-only snapshot showed 28 connections against a configured maximum of 60, with 2 active, 19 idle, and no idle transactions. It was not captured during the error and cannot rule out bursts or a smaller service/pool limit. A failing timestamp and exact service code remain needed. No hosted infrastructure deployment, pool/compute/index/retention or media-encoding change has been performed. Bounded widget/archive traversal, refresh coalescing, signing batching, field latency/memory measurement, and media comparisons remain later plan work.

## 2026-10-12 verification and deployment

- All 138 app/domain tests pass in the local simulator backend. Four focused simulator UI tests pass together: six-step setup/profile editing and Back navigation, Help navigation, text/voice-only photo attachment, and Today bottom-scroll stability. The first Help batch attached to a pre-existing onboarding instance; explicit termination/isolation fixed the test launch, and its standalone and combined reruns pass. This is not a full UI-suite or physical-device acceptance pass.
- The hosted-configured Release device build succeeds. The app and widget/Live Activity extension have the same signed App Group. Automatic local signing uses development APNs and `get-task-allow=true`; this build is not a distribution-exported TestFlight IPA. No phone installation or TestFlight upload was performed.
- Disposable PostgreSQL regressions, hosted rollback-only welcome/evening/nudge/reuse/invite/character-limit checks, both notification payload contracts, and dispatcher type checking pass. Hosted migrations `202610120001`–`202610120004` and `dispatch-prompts` version 20 are deployed; the once-per-minute scheduler remains active. Test users, posts, and notification events roll back.
- `MEDIA_RETENTION_ENABLED` is still false (its metadata digest matches false); the media deletion queue is empty. Cleanup was not enabled. Physical microphone pause/resume, route changes, actual affected-device widgets, and APNs/Live Activity presentation remain release acceptance tasks for a new client build.

## October 12 scheduled-start race

- Welcome and evening entry use the authored notification start, not an elapsed scheduled target. Hosted prompt models preserve scheduled state; a delayed scheduler cannot open today's composer or prematurely close the welcome/evening prompt. First-day capture uses the same policy as timeline/server entry instead of an unconditional bypass.
- Additional hosted/local regressions cover the scheduled-to-started transition. Customer Help explains that planned time and actual opening can differ.

## October 12 late Live Activity cutoff

- Both local ActivityKit starts and remote start/update/end payloads use a circle-time-zone entry cutoff, with three-minute terminal dismissal. Server authorization rejects expired past-day entry even when an old Live Activity is still visible; existing capture grants remain valid.
- DST and cross-midnight deadline tests cover the cutoff. Migration and dispatcher are deployed; real APNs/lock-screen lifecycle needs device confirmation.

## October 12 widget reliability

- Precompute the next 24 hours of sharing start/end boundaries and blessing rotations, rather than depending on one WidgetKit refresh being delivered on time.
- Shared snapshots remain readable after first unlock; refresh requests coalesce, account changes fence off stale writes, and transient network failures do not erase the last usable data.
- Boundary and customer-guide tests added. Individual affected devices still require installation and validation; this is not a guarantee of background refresh timing.

## 2026-10-12 notification-aware welcome blessing

- The server materializes/selects yesterday's welcome prompt for same-day joiners before today's notification start; afterward the current-day prompt is used. Welcome entry respects the circle's calendar, ends at today's start or local midnight, and entry grants preserve the original day through later submission. Timeline includes an actual welcome post even when its prompt date precedes the membership marker. Migration deployed and verified with rollback-only hosted tests.
- Ordinary daily late entry and nudges cannot bypass the circle-day boundary through a stale Live Activity link; timely capture grants remain valid. Tests cover calendar/DST, welcome date, and timeline preservation.

## 2026-10-12 segmented voice and build-27 crash

- The supplied build-27 crash aborts in AVAudioEngine InstallTapOnNode from SpeechTranscriber.start. Every segment now creates a fresh engine, uses the hardware tap format, guards pending permission requests, and serializes recorder ownership across blessing/response composers. Physical route-change verification remains required.
- Pause/continue retains edited transcript and prior segments, merging into one M4A for playback/upload; CAF single segments remain compatible. Both upload paths send the matching audio MIME type. Sending is gated while merging; failed merges never silently send only the final segment. Synthetic different-sample-rate merge and reset regressions added.

## 2026-10-12 seven-hour evening entry

- Evening entry lasts seven hours after the server notification start, still closing at the next random blessing if earlier. Existing evening rows and all scheduling/settings/force paths are extended without sending reminders again; already granted compositions can still finish later. Migration deployed and verified with rollback-only hosted tests.

## 2026-10-12 account presentation

- New-account setup includes Your profile after Welcome, using the same native profile editor and square photo crop as User settings. Continue can keep the current profile; Apple does not provide a photo.

- Sign-in uses the adaptive manna wordmark and lighter circle heading. Sign out is available only in User settings, including accounts without a circle. Customer Help follows the new location. Combined build/UI verification follows the remaining changes below.

## 2026-10-09 gentle circle nudges

- Today exposes named Nudge controls only after the viewer submits for that exact random/end-of-day prompt, for current members who have not shared and can still enter. First-day exceptions and retained entry grants never open nudges before the prompt starts or after the evening/no-late cutoff.
- Server-authorized nudges enter the existing notification outbox with one event per recipient/prompt across all senders. Before APNs, the dispatcher rechecks membership, entry timing, recipient completion, and the ordinary circle-activity preference. Alerts contain sender identity and a reminder only, route to the exact Today prompt, never start a Live Activity, and use APNs expiration zero to avoid storing offline reminders past the window.
- Help and user settings describe the shared switch and rate limit. Local mode validates rules but sends no remote alert. The UI/UX review kept reminders secondary to sharing, with named native controls, progress/disabled feedback, semantic colors, and 44-point targets.
- All 123 app/domain tests, isolated SQL/Storage-policy regressions, hosted rollback-only RPC regressions, both APNs payload contracts, dispatcher type checking, and the signed hosted Release device build pass. Hosted migrations `202610090001`–`202610090004` and dispatcher version 18 are deployed. The final forward migration specifically excludes first-day entry exceptions from nudges; hosted queue/dispatch tests cover this boundary too. No temporary regression circles or media deletion queue entries remain. `MEDIA_RETENTION_ENABLED=false` remains explicitly set; no cleanup was activated.
- The initial 17-test simulator UI batch passed 15, including the new nudge flow, but failed initial navigation in the accessibility audit and a composer scroll in its text editor. App tests subsequently passed all 123 on a clean disposable simulator after the existing test-runner stall. Focused reruns pass the accessibility audit and nudge flow; the existing long-text composer test remains failing at Send-button reachability. Experimental test gestures did not resolve it and were discarded. This is not a full UI-suite pass. No phone installation, TestFlight upload, or real two-account APNs delivery was performed; updated client presentation/reuse needs a new build.

## 2026-10-09 scheduled Timeline state

- Local and hosted timelines share a status policy: an unstarted prompt without an early post says Waiting for notification, never You can still share or Missed. Actual early peer posts remain locked; the explicit first-day sharing exception remains available.
- Future calendar-day prompts remain excluded. Current open/late states, expired no-late states, independent evening privacy, and historical visibility are unchanged.
- Initial verification passed all 119 app/domain tests, including all-format reuse, invite-cache recreation/isolation, scheduled/current/deadline status boundaries, first-day exception, and Help guides. Combined verification now passes all 123 and the signed Release build; see the nudge rollout above for UI/hosted results.

## 2026-10-09 durable invitations

- App updates/relaunches no longer lose invite codes: the client keeps stable account/circle-isolated hints, verified against the current server hash on every load. New create/join/explicit-rotation transactions store a recoverable code in a private, non-exposed table for active-member-only lookup.
- No existing circle is rotated. A valid known legacy code backfills its private record. Lost hash-only codes require an existing valid join link or one deliberate owner regeneration. Removed members/outsiders cannot recover codes; stale hints cannot overwrite the new code after rotation.
- Cache relaunch/isolation tests and local/hosted transactional SQL checks pass for creation, recovery, old-code invalidation, owner-only rotation, member lookup, removal, and unchanged join dates. The durable-invitation migration is deployed without changing any existing code.

## 2026-10-09 reuse retains media

- Reuse preserves typed/voice/video format, audio, photo, video, thumbnail, and scripture. Capture previews the complete original blessing; responses remain on the original. Each repeat gets a new target prompt, submission time, and privacy gate.
- The RPC reuses private paths without uploading again; Storage reads recognize visible receiving-circle blessing references. The retention worker already protects paths still referenced by younger posts. Author, entry, reuse-window, and duplicate guards remain enforced.
- Local app/domain coverage and local/hosted transactional SQL checks pass for all formats, media preservation, duplicate/other-author rejection, and peer/outsider/removed-member access. Actual Storage SELECT policy checks pass in the isolated PostgreSQL fixture. The migration is deployed; physical playback acceptance remains pending a new client build.

## 2026-10-08 doubled blessing character limit

- Blessing text and voice/video transcripts now allow 1,200 characters instead of 600, including ten-minute edits. Capture counters/clamping, edit validation, local submission, and hosted pre-upload validation share one policy. Unicode-scalar counting matches PostgreSQL and truncation preserves complete emoji/accent graphemes. Response limits are unchanged at 600.
- A forward migration widens the blessings table constraint and all three submit/finalize/edit RPCs while preserving entry, ownership, duplicate-submission, media-path, and edit-window guards. Customer Help explains the new limit and counters.
- All 112 app/domain tests, the focused composer UI test (1,201-character input capped at 1,200 and successfully shared), the isolated PostgreSQL migration/transactional length regression, and the signed hosted Release build pass. Both pending migrations (`202610080001` retention schema and `202610080002` length limit) are deployed to linked Supabase. Hosted transactional RPC checks pass for all three capture modes at 600/601/1,199/1,200, rejected 1,201-character submissions/edits, preserved duplicate rejection, and anonymous execute denial; all fixtures and queued events roll back. Catalog checks confirm 1,200 on the blessing table/all three RPCs and 600 on responses. No phone installation or TestFlight upload was performed.

## 2026-10-08 full sender photo in notifications

- Peer blessing and response alerts now fill the main left identity image with the sender's profile photo rather than compositing a small avatar over the manna logo. A centered square crop preserves proportions, bounded to 256 pixels; missing/invalid photos retain the selected-logo fallback. A valid photo no longer depends on loading a logo resource.
- Titles, message bodies, scripture references, privacy gates, right-side photo/video attachments, reminder images, and Live Activities are unchanged. iOS still owns its small app-icon badge.
- Customer Help and notification image regressions cover full-image crop, logo fallback, and missing-image behavior. All 108 local app/domain tests and the signed hosted Release build pass. Actual remote-notification appearance requires a new phone/TestFlight build and remains pending; no hosted deployment, phone installation, or TestFlight upload was performed.

## 2026-10-08 accessibility baseline

- Timeline adds a single-column List, selected automatically for VoiceOver and accessibility text sizes, with a toolbar choice to return to Threads. Dates scroll with their sections in List; the existing compact frozen Threads header is unchanged. Spoken cards include author, circle-local day, capture type, full text/transcript, scripture, and late status.
- Photo cropping now has menu and VoiceOver zoom/movement/reset alternatives while preserving simultaneous pinch/drag and square output. Verse cells scale, retain the native Start/End alternatives, and distinguish selection with traits and borders. Countdown text and circle-creation navigation adapt at accessibility text sizes.
- Orange foreground and filled-action colors are separate, selected verse text uses the correct light/dark contrast pair, primary buttons use solid fills, and Increased Contrast strengthens card boundaries. Help gains an Accessibility topic explaining alternatives and media limitations.
- All 106 app/domain tests and all 15 local-demo UI tests pass. Coverage includes actual compiled-asset contrast across light/dark and normal/high contrast, guide content, native hit-region/description audits, manual/automatic Timeline List selection, largest-text dark/landscape layouts, and existing sharing/saving/circle regressions. The signed hosted Release device build passes; it was not deployed or uploaded to TestFlight.
- This is not a claim of all nine App Store labels. Timed video captions and narrated audio descriptions are not implemented. The small-phone native contrast audit still flags the Share button despite its passing numeric color pair; rendered contrast and full physical-device/iPad common-task acceptance remain pending. See `docs/ACCESSIBILITY_AUDIT.md`.

## 2026-10-08 automatic private saving

- Account setup adds a Local Saving step, and User settings exposes Automatically save locally. The preference and archives are account-isolated on this device; it is opt-in and does not change server retention or privacy gates.
- While open/refreshing, manna archives visible blessings across all joined circles. Automatic copies refresh for new responses and edits with atomic manifests and reuse of downloaded media; manual saves remain snapshots. Individual Unsave prevents an automatic re-save. Download errors remain in Settings rather than creating scrolling alerts.
- Turning off pauses downloads and offers Keep all, Keep only my blessings, Keep none, or an individually selectable list. Kept copies become ordinary manual saves; existing manual saves are never removed. Expired-media removal requires a permanent-loss warning, and Cancel resumes automatic saving.
- Retention is 30 days, with Timeline warnings during days 28–30. Its hosted migration is installed; `MEDIA_RETENTION_ENABLED=false` is explicitly set and the deletion queue is empty. Cleanup stays disabled until the save-capable TestFlight build is available, as explicitly selected by the owner. Storage acceptance and physical-device verification remain pending.
- All 104 app/domain tests pass, including legacy-manifest compatibility and damaged-preference startup recovery. Focused small-phone checks pass for saving choices/Cancel, five-step onboarding, and largest-text dark/landscape setup. The UI/UX review led to adaptive stacked navigation at accessibility sizes so Back/Continue labels never split.
- The final full local-demo simulator suite passes all 13 UI tests, including Today scroll stability, guided circle creation, Help, and Save/Unsave. The signed hosted Release device build, dispatcher type check, both APNs payload contracts, and isolated 30-day SQL retention regression pass. These checks do not substitute for physical-device media/push acceptance or a TestFlight upload.

## 2026-10-08 guided circle creation

- Circle creation is a full-screen nine-step flow with progress, Back/Continue controls, and focused explanations for name, optional photo, time zone, random range, entry duration, late sharing, evening time, and reuse window.
- Each relevant step validates before continuing; going Back preserves the chosen values. The final review shows every setting, and the sole create action still applies them transactionally from the circle's first day.
- Simulator coverage passes for name validation, backward navigation, all steps/defaults, review, and creation into the new circle.

## 2026-10-08 customer Help

- The hamburger menu opens Help in both joined-circle and no-circle states. Nine illustrated, plain-language topics cover sharing, evening reflections, circles, Timeline, responses, saved media/expiry, Bible tags, notifications/widgets, and personal settings.
- A Topics menu switches directly between features without accumulating navigation screens. Dynamic Type and semantic colors reuse the native design system; topic steps remain vertically readable instead of relying on wide diagrams.
- Guide completeness, retention/privacy explanation, and entry-deadline wording tests pass. Simulator topic navigation passes. `AGENTS.md` requires future customer-visible changes to update the relevant Help topic and guide tests.

## 2026-10-08 30-day media cleanup

- A service-role-only retention function detaches audio/video and video-thumbnail references exactly 30 days after each submission, preserving text, references, photos, and response rows. A private deletion queue retries actual Storage API removals; shared media is protected while a younger blessing still references it.
- The scheduler processes bounded cleanup batches only with `MEDIA_RETENTION_ENABLED=true`. Migration installation does not delete historical data. The owner chose activation **after the save-capable TestFlight build is available**; cleanup remains disabled until then. Retention was extended to 30 days before deployment, and final-two-day warnings now start at day 28.
- The real migration and transactional regression pass against an isolated local PostgreSQL fixture, including timestamp boundaries, response-specific dates, repeat-path safety, client denial, and idempotent queue retries. Dispatcher type checking and APNs payload contracts pass. The hosted migration is installed without running cleanup; the Edge Function secret is explicitly false and the queue is empty. Hosted Storage deletion acceptance remains pending; no dispatcher deployment or cleanup activation was performed during this database rollout.

## 2026-10-08 private saved blessings

- Save/Unsave blessing stores a complete available blessing snapshot and its current responses in account-isolated Application Support storage, including photo/audio/video and response audio. All requested files must download before Saved appears; partial failures leave no archive.
- Relative media paths survive app-container changes; archives are protected and excluded from backup. They remain private to this account/device and do not affect peer access, hosted retention, or current-day sharing gates.
- Timeline labels show Saved or a final-48-hour media-expiry warning above each blessing. Saved files are used for playback after remote expiry. The first save explains device-only behavior; removing an archive containing expired media requires a permanent-loss warning.
- Local archive reload, video/voice/response preservation, account isolation, exact 28/30-day boundaries, partial failure, and privacy tests pass. The focused first-save/unsave UI flow passes. The current combined suite has 96 passing app/domain tests; physical-device media acceptance remains pending.

## 2026-10-08 photo and video export

- Visible blessing photos and videos can be exported to Photos from Today and blessing details, regardless of author, using add-only permission, progress, success/error confirmation, and Settings recovery for denied access.
- Downloaded temporary files are cleaned up after success/failure; local originals are preserved. All 86 app/domain tests pass including six new export permission, routing, and cleanup tests. Physical-device Photos acceptance remains pending.

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
