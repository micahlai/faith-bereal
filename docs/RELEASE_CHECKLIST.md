# Release checklist

This checklist separates work that can be proven locally from work that needs production Apple or Supabase access.

## November 3, 2026 — 0.5.3 (50) readiness audit

**Decision: hold public submission.** The signed candidate and local safety checks pass, but capacity, physical-device acceptance and submission inputs remain open. This section supersedes older open items where the later implementation is documented in [LAUNCH_COMPLIANCE.md](LAUNCH_COMPLIANCE.md). Audit baseline: `c44c1cc`; no customer behavior or hosted configuration is changed by this audit.

Consolidated work list: [everything needing attention or change](audits/2026-11-03/ATTENTION.md). Tracked [backend](audits/2026-11-03/BACKEND_READINESS.md) and [frontend](audits/2026-11-03/FRONTEND_READINESS.md) reports preserve the audit independently of ignored build output.

### Live capacity evidence

Read-only Chrome inspection of [organization usage](https://supabase.com/dashboard/org/pskrozhjtgvzbrrrzpbr/usage), current cycle October 30–November 30:

| Item | Observed usage / allowance |
| --- | --- |
| Uncached egress | 0.725 / 5 GB |
| Cached egress | 0.030 / 5 GB |
| File storage, average over period | 0.556 / 1 GB |
| Database | 0.050 / 0.5 GB |
| Monthly active users, including synthetic acceptance activity | 15 / 50,000 |
| Realtime peak connections | 4 / 200 |
| Edge invocations | 9,101 / 500,000 |

Previous-cycle summary still shows **6.913 GB uncached**, **2.173 GB cached**, and ten MAU. The dashboard still displays the **November 17, 2026** grace-period/restriction warning and says restricted requests return HTTP 402. Usage can lag by one hour. These are dashboard observations, not a load test or confirmation that restrictions will occur.

The [production overview](https://supabase.com/dashboard/project/lrdrodsgilmlzrynkiqx) reports Healthy, no advisor findings, 18/60 database connections, 4% CPU and 67% RAM. Its last-hour view shows 2,049 requests / 100% success. **Last backup: No backups.** A quiet healthy interval does not establish launch capacity, recovery capability or complete authorization coverage.

A subsequent read-only SQL snapshot through Chrome at **November 3, 10:25–10:27 PM Eastern** (November 4, 03:25–03:27 UTC) confirms hosted migration `202611020008`, **35,081,363 database bytes**, 23 connections and **577,878,779 stored object bytes / 140 objects**. `blessing-media` contains 127 objects / 574,913,369 bytes, median 2,881,525 bytes, p95 12,789,376 bytes, largest **47,424,738 bytes**. Object metadata is a point-in-time count, unlike the dashboard's period average; this small historical sample is not a representative per-user consumption forecast.

- No pending account deletions, queued media deletions, open reports or diagnostic reports older than 14 days. Mirror state: nine desired copied jobs, 17 deleted jobs, zero recorded failures/pending age. This does not mean all 140 current Storage objects are mirrored; historical backfill remains incomplete.
- Both database cron jobs are active. Last day: 1,440 dispatch scheduling jobs and 24 diagnostic-pruning jobs succeeded. However, the last six hours of retained HTTP responses contain **358 HTTP 200 and two timeouts / 360 calls**. Database cron success alone does not establish downstream dispatch success; these timeouts need external monitoring and missed-prompt/retry acceptance. No response bodies, headers, customer content or tokens were exported.
- Follow-up at 10:31 PM Eastern finds **zero overdue scheduled prompts**, **zero active stale dispatch claims**, and no recorded failure on ten prompts started in the preceding day. The six-hour successful-response sample contains one claimed prompt with **18/18 APNs requests accepted, zero errors/failures**. This limits the observed incident: there is no evidence here of a stuck prompt, but provider acceptance does not prove device display or account for timed-out calls. `build/backend-readiness/dispatch-audit.json` preserves these aggregates.
- All three buckets are private. All inspected ordinary tables in `public`, `manna_private` and `storage` have RLS enabled; ordinary `anon` / `authenticated` roles lack private-schema usage. All 12 inspected service-only mirror/deletion/moderation/badge functions deny execute to both ordinary roles and allow `service_role`. The database retains `UNIQUE (prompt_id, author_id)`. Catalog checks do not substitute for installed two-account policy acceptance.
- Fresh Chrome secret-digest inspection confirms `MEDIA_RETENTION_ENABLED` matches `false`, and `MEDIA_RETENTION_START_AT` is absent. No secret values were revealed or settings changed.

Aggregate-only evidence: `build/backend-readiness/aggregate-audit.json`, `access-audit.json` and `retention-gates.json`; accompanying SELECT queries are preserved. Only private audit scratch queries were used; their persistence was not verified. No production rows or configuration were changed.

The private `blessing-media` bucket has Public bucket **off**, a 75 MB bucket limit and restricted MIME types. However, [global Storage settings](https://supabase.com/dashboard/project/lrdrodsgilmlzrynkiqx/storage/files/settings) enforce **50 MB** on the Free plan. The effective maximum is therefore 50 MB, despite the checked-in 75 MiB bucket/local configuration. The upload path has no matching client byte-size preflight. Test oversized recording/photo failure and recovery; align effective limits and honest Help text in any resulting feature change. No bucket setting was saved.

Owner's launch target: **up to 100 active users**. Illustrative assumptions, not measured user behavior: one new 5 MB recording per active user per day, every day, distinct ten-person circles, nine peer-device downloads per post, 30 days, decimal MB/GB. This produces **15 GB of new recordings per 30 days in each provider**, **135 GB peer-download egress**, plus about **15 GB Supabase-to-R2 copy egress** before API traffic, photos, responses or repeat downloads. Count automatic saving and playback once when they reuse the same device copy. Multiple prompts/circle memberships can increase this. Photos/text and permanent device archives have no age cap; paused recording cleanup means hosted recording storage is not yet bounded by 30 days.

Supabase serves all current app reads. R2 mirroring is a second copy and adds source transfer; it is not a bandwidth cutover or a database backup. Existing media is not fully backfilled and deletions propagate to R2. Client protections include 720p video preparation, 480-pixel photo previews, AAC voice, demand playback, a 256 MiB/seven-day disposable recording cache and Wi-Fi-gated automatic saves. Those paths do not prove production byte savings. Permanent device saves remain separately unbounded.

- [ ] Resolve the live quota/grace warning and approve a capacity plan before public distribution. [Supabase Pro](https://supabase.com/pricing) currently starts at $25/month, with 100 GB file storage, 250 GB uncached and 250 GB cached egress; compute and other usage can change the bill. This audit does not purchase a plan or change spend controls.
- [ ] Measure a representative cohort's bytes per post, unique device download and active day; project the 100-user workload with headroom, including automatic saving, mirror reads, responses and multiple circles. Exercise peak simultaneous prompt/submission traffic in staging.
- [ ] Establish backup schedules and a tested restore procedure for database **and** retained media. [Supabase database backups](https://supabase.com/docs/guides/platform/backups) do not include Storage object bytes. R2's synchronized mirror is not an independent recovery point.
- [ ] Complete monitoring/alert coverage for quota pressure, failed/old mirror jobs, deletion/retention retries and dispatch failures. The code does not establish an external alert channel.

### Remaining launch acceptance

- [ ] Run disposable **physical** Sign in with Apple reauthentication, revocation, deletion and completion verification. Existing synthetic two-provider deletion acceptance is valuable but does not exercise real Apple consent/token exchange.
- [ ] Complete installed two-account privacy/report/block/moderation checks, camera/microphone/Speech/Photos denial/recovery, interrupted uploads, production APNs/badges/Live Activities/widgets and invite deep links.
- [ ] Resolve the outstanding rendered contrast finding and complete VoiceOver, large text, motion and supported iPad/orientation acceptance. The native automated accessibility test checks hit regions/descriptions; it does not establish that rendered contrast passes.
- [ ] Assess current limited phrase filtering and immediate, unscreened media publication against [App Review guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content). Reporting/blocking/contact and daily operator review exist; their presence does not prove sufficient filtering of photos/audio/video. This audit does not reinstate mandatory developer approval or claim Apple requires a particular screening vendor.
- [ ] Record actual updated-build availability and its approved +72-hour cleanup schedule. Retention is implemented and deliberately activation-gated; export is not availability. Verify rollout and failures under [MEDIA_RETENTION.md](MEDIA_RETENTION.md). Complete abandoned-upload cleanup and the separate backup/log retention schedules.
- [ ] Finalize candidate selection, screenshots, age questionnaire, reviewer access/contact/instructions and actual TestFlight install acceptance. A product 13+ rule is separate from Apple's questionnaire. Reconcile the published account-linked privacy answers with the candidate and live policy.

User data export and per-post/departed-member history policy remain project commitments. Do not label an in-app export as a universal Apple submission requirement. Current policy/support/Universal Links endpoints were fetched successfully over verified HTTPS in this audit; policy names Supabase, Cloudflare, Apple and the website host and explicitly discloses the paused retention rollout.

### App Store Connect inspection — November 3

Read-only compliance inspection in the owner's signed-in Chrome session; no compliance metadata, answers, binary or submission changed. Separately requested artwork work is paused:

- [x] Published privacy answers still contain the ten account-linked categories in APP_STORE_PRIVACY_LABELS.md, with the correct public policy URL. User ID/performance/other diagnostics include analytics purposes.
- [x] Availability is one country, **United States**, with 174 unavailable. Age rating shows **13+** globally on current operating systems; older-than-26 rating is displayed as 4+. A product age confirmation is not independent age verification.
- [ ] Release draft is still **0.5.0 / Prepare for Submission**, whereas the signed local candidate is **0.5.3 (50)**; **no build is selected**. Align the chosen release version/build before submission.
- [ ] TestFlight already lists **0.5.3 (49)**, Validated / Ready to Submit, in Internal, with nine invites, seven installs and ten sessions. Its metadata displays upload **November 2, 2026 at 11:02 PM**, iOS minimum 18.0 and non-exempt encryption No. This differs from the locally validated **0.5.3 (50)** IPA; local source/export tests cannot be asserted to certify the uploaded build's exact bytes/source. Reconcile build provenance and which candidate will be reviewed. This observed upload was not performed by this audit; older STATUS statements that nothing had been uploaded were true only at their recorded time. Upload time alone does not establish the approved retention availability milestone.
- [ ] The checked iPhone Dynamic Island and 13-inch iPad slots each show **0 screenshots**. Description, keywords, copyright, primary category, review credentials/contact/notes are blank. Pricing displays **Add Pricing**, without a starting schedule. Finish the required fields and a review-safe Apple-sign-in/prepared-circle path.
- [ ] Saved feature answers are UGC **Yes**, Social Media **Yes**, Messaging/Chat **No**, Age Assurance **No**, and social-media-disabled-for-under-13 **No**. Reassess messaging against text/voice responses and the current age controls against Apple's actual definitions. No answer was changed.
- [ ] Content Rights currently says the app does not contain/show/access third-party content. `BibleAPIService` directly fetches passage/translation paths from **api.midvash.com**. Reconcile the attestation and document rights/attribution for each offered translation; public-domain availability does not mean no third-party content is accessed. [Apple's content-rights field](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [provider terms](https://midvash.com/terms).
- [ ] The Bible API is absent from the in-app/public processor inventory. The request reveals requested translation/passage and ordinary network metadata to that provider; it sends no app account token or post body. Assess API-specific logs, privacy and license terms and update the policy/inventory/Help/tests together where needed. The provider's website/app analytics disclosures do not establish that those SDKs or trackers run in manna's JSON API client.
- [ ] Apple-silicon Mac availability is checked; validate that supported surface or explicitly choose the intended platform scope before release. The Vision Pro checkbox is also checked, but the page says the current 0.5.0 version is incompatible/unavailable there; do not claim tested Vision Pro support.

The saved release mode is **automatic after approval**. Recheck this against the actual recording-cleanup availability/grace schedule when preparing submission. This audit does not change it.

### Automated UI tooling

The repository currently defines **47 XCUITest cases**, including a native hit-region/description audit. These rely on **Debug-only local fixtures** and do not establish hosted multi-account authorization, real Apple revocation or production push delivery. There are no report/block/account-deletion UI flows in the current suite; backend tests do not fill that installed-client coverage gap. Do not upload the production store IPA with this fixture suite and assume it will use the local backend.

The delegated audit observes a pass for each of the 47 distinct cases across the original and focused runs. The original run completed 45 passes / one intermittent largest-dark save-photo reveal failure, then was interrupted during its final Threads persistence test. Exact focused small-phone reruns pass both cases; a larger-phone save-review comparison also passes. This is not an uninterrupted full-suite pass. Preserve the original failure and incomplete bundle; detailed classification and evidence are in `build/frontend-readiness/REPORT.md`.

A separate bounded small-phone diagnostic probe also passes actual full-visibility photo open/close and Save all reachability (`PhotoProbe.xcresult`, 1/1). It is additional evidence, not a 48th existing-suite case. No persistent functional defect or specific scroll-helper root cause was established. App and original test executable hashes remain unchanged; no production source or original test was edited.

- **Recommended:** [BrowserStack App Automate / XCUITest](https://www.browserstack.com/docs/app-automate/xcuitest/getting-started), with a separately signed device test app and paired test-runner bundle using synthetic accounts/data. Add [App Accessibility](https://www.browserstack.com/docs/app-accessibility/automated-tests/xcuit/getting-started/integrate-with-app-automate) for accessibility findings and [App Percy](https://www.browserstack.com/docs/app-percy) for visual comparisons. Reuse the native suite and extend the missing release flows.
- [Maestro](https://docs.maestro.dev/get-started/supported-platform/ios) offers readable simulator flows and cloud simulator runs. Its official iOS CLI does not yet support physical devices; it would add a second test suite here.
- [AWS Device Farm](https://docs.aws.amazon.com/devicefarm/latest/developerguide/test-types-ios-tests.html) is another real-device XCTest option. Device availability, platform behavior and any signing/entitlement changes need acceptance before relying on notification/Apple-auth tests.

No vendor automatically covers every state, visual issue or compliance obligation. Choose a matrix covering supported iOS versions, small/large iPhone and iPad, both appearances, largest text, onboarding, capture/playback, saving/offline, safety/deletion, and failure recovery. Real Apple/APNs acceptance still needs the release-entitled installed candidate. No third-party upload, paid service signup or external test run was performed.

Fresh verification results and result-bundle paths are recorded in [STATUS.md](STATUS.md).


## November 2, 2026 — 0.5.0 (47) compliance candidate

Current detail: [launch compliance and retention proposal](LAUNCH_COMPLIANCE.md). Older dated audit rows below are historical evidence, not the current implementation status.

- [x] US-only, 13+ launch documented and age/data-use acknowledgement added before normal sign-in/bootstrap. Actual App Store availability is United States only; age-rating questionnaire remains separate.
- [x] Publish the website privacy policy, link it in launch/settings, and make optional diagnostics default off with fresh consent for legacy queues.
- [x] Publish corrected App Store privacy labels after the owner's final attestation confirmation. Save policy/support URLs and change release draft to 0.5.0.
- [x] Deploy report/block/moderation; allow normal circle media publication without prior developer approval, retain explicit hides, verify server authorization and provide the private operator inbox. Owner accepted daily reviews and urgent action within 24 hours.
- [x] Deploy durable account deletion and verify synthetic two-account cleanup through actual Supabase Storage and R2, then Auth removal and completion receipt. Configure Apple server key without putting it in Git/app.
- [x] Revalidate Cloudflare copy/replace/delete; observe successful minute Worker execution with mirror and account cleanup enabled. Supabase remains the read provider.
- [x] Use generic alert envelopes, including removing private sender/photo/circle metadata. Update privacy manifests, Speech usage copy, Help and matching tests; retain typed/system-picker alternatives and no ATT prompt.
- [x] Build, export and validate the signed 0.5.0 (47) IPA; preserve 0.4.0 (46). No upload or App Review submission.
- [ ] Complete a physical disposable Apple-account reauthentication/revocation/deletion test plus camera/microphone/Speech/Photos denial/recovery, production notification privacy and accessibility acceptance.
- [ ] Decide and implement the truthful retention schedule; hosted age-based cleanup remains disabled, as instructed. Existing client/Help 30-day guarantees remain a release blocker.
- [ ] Complete remaining age-rating/review metadata, confirm build-number availability and install the uploaded candidate from TestFlight before public submission.

## November 1, 2026 — 0.4.0 (46) first public release audit

**Decision: not ready for public App Store submission.** The settings defect is fixed on the hosted database. The remaining items below require implementation or acceptance; a passing build does not close them.

- [x] Restore the shared-circle-settings server contract. Deploy only `202610140001` after checking the exact predecessor functions and running the new schema with rollback-only hosted fixtures. Postflight owner/member/removed-member/outsider checks pass; anonymous HTTP access is denied with `401 / 42501`. Local and hosted migration histories now match. Existing circles remain leader-only until their leader enables the switch.
- [x] Preserve current independent streak calculations, owner-only delegation/ownership transfer, private invitation implementation, canonical photo paths, and revoked-member denial. No synthetic fixture data remains. Actual Storage API photo deletion and two installed-device settings acceptance remain open.
- [x] Declare reviewed exempt encryption with `ITSAppUsesNonExemptEncryption=false`; require the declaration in distribution-export validation. Networking uses Apple's HTTPS implementation; sign-in/cache hashing uses CryptoKit. The pinned Supabase dependency's `Crypto` SHA-256 implementation delegates to CryptoKit on iOS. This is an export-documentation declaration, not a claim of end-to-end encryption. Reassess if cryptography or dependencies change. See [Apple's encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
- [x] Set the generated-project source of truth to 0.4.0 (46) for the app and both extensions. Previously, regeneration could undo the app target's manually set 0.3.1 version. Build 46 follows the latest observed diagnostic build, 45; App Store Connect must still confirm the next available build number before upload.
- [x] Check hosted schema with error-level lint; verify private Storage buckets, anonymous content-read denial, database post uniqueness, and current scheduler execution. These checks supplement, and do not replace, two-device privacy/realtime tests.
- [x] Run `release_privacy_hosted.sql` as the authenticated application role with random rollback-only fixtures: history remains visible before sharing; daily/evening peer content and responses stay locked independently; original/preview Storage metadata obeys the same gate; submission unlocks only its prompt; duplicate submission is rejected; outsider and removed-member reads return no rows. No dispatch or Storage API call occurs. This verifies SQL authorization, not installed-client authentication or already-issued signed-URL revocation.
- [x] Run local database regressions for permissions, revocation races, both migration orders, registration, diagnostics/quota concurrency, retention, streaks, invites/reused-media visibility, nudges, and character limits. Repair the fixed DST fixture's collision with its runtime welcome day without changing production behavior.
- [x] Pass both APNs payload contracts, dispatcher type checking, privacy/plist validation, and a tracked-app/config scan for embedded private keys or service credentials.
- [x] Repair required-reason declarations: app-container file timestamps used by caches/drafts (`C617.1`), a notification-extension manifest for shared/own-container preferences, and the widget's own-container fallback reason. Verify all three manifests and their reason codes in the rebuilt archive. Export validation now requires a manifest in every executable bundle. [Apple's required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- [x] Verify the public website and support page return HTTP 200, with a published support email. The Universal Links association returns HTTP 200 and names the correct team/app identifier and `/join/*` paths. No privacy-policy link was found on the home or support pages; final privacy-policy publication/linking and installed-device invitation routing remain open.
- [x] Pass 353 Debug/349 Release unit tests with no skips. Verify all 41 distinct UI flows across the full run and focused streak reruns. The first full UI run passes 39/41; stale saved Timeline layout/offscreen queries and an upper-left dismissal coordinate inside the largest-text popup are corrected in test setup, scoping, and dismissal waits. All three final streak cases pass. Review normal/largest-dark circle-settings screenshots. Results: `build/ReleaseAuditDebugFinal.xcresult`, `build/ReleaseAuditReleaseClean.xcresult`, `build/ReleaseAuditUI.xcresult`, `build/ReleaseAuditStreakFinal.xcresult`.

The signed **0.4.0 (46)** archive is `build/Manna-0.4.0-46.xcarchive`. After the account holder accepted Apple's updated Developer Program agreement, export succeeded to `build/TestFlight-0.4.0-46/manna circle.ipa`. Distribution validation passes: production APNs, debugging disabled, Sign in with Apple, App Groups/Universal Links, matching app/extension versions/builds, exemption declaration, all three privacy manifests, notification logos, and complete code signatures. IPA SHA-256: `15b9fc4317ba94ec691fbdce7b9e808994bdaeba2dd5bf492382e7bb35052926`. Nothing was uploaded or submitted.

### Bandwidth and reliability gate

The refreshed organization dashboard shows **0.162/5 GB uncached egress**, **0.014/5 GB cached egress**, **0.549/1 GB average Storage**, and **0.048/0.5 GB database usage** in the October 30–November 30 cycle. The completed previous-cycle totals are **6.913 GB uncached** and **2.173 GB cached**, with 10 monthly active users. The dashboard's previous-cycle view retains the current-cycle date header; the figures above come from the selected previous-cycle summary. Usage reporting can lag by an hour. [Organization usage](https://supabase.com/dashboard/org/pskrozhjtgvzbrrrzpbr/usage).

The previous-overage warning still names **November 17** as the possible restriction date and states restricted requests return HTTP 402. The low new-cycle total, with only two reported active users, is not a launch-capacity demonstration. Before public distribution, validate a representative cohort's daily media/API usage against the intended launch size and resolve the quota/grace-period risk with Supabase or an appropriate plan. No paid plan, pool limit, retention activation, or load test was changed in this audit. The subsequent separate [Cloudflare dual-storage rollout](CLOUDFLARE_STORAGE.md) is active for new media: Supabase still serves all app reads, so the mirror adds copy traffic and does not yet reduce Supabase read/database egress. Supabase counts outgoing API/database/storage traffic together; a media-provider move alone would not eliminate API traffic. See [Supabase's bandwidth guidance](https://supabase.com/docs/guides/storage/serving/bandwidth).

The read-only database snapshot has 16 client connections of 60, no lock waits, and about 32.7 MB in the current database. Actual stored object bytes are 561,753,821; dashboard figures use different measurement windows. Build 45's retained sample covers five accounts, 64 sessions, 78 reports, and 4,073 records; event times span October 25 09:16 through November 1 02:58 UTC, with later receipt times. No connection-limit-classified failures appear in this build's sample, but there are transport timeouts/lost connections, three audio failures, and one generic RPC rejection. The sample's visible startup median/p95 are **4.29/14.15 seconds** (56 spans, two failures), and circle refresh is **1.51/22.31 seconds** (53 spans, six failures). Reliability and startup remain acceptance work; these opt-in/bounded records do not prove saturation eliminated. No missing-signature event is recorded after the October 25 device-registration fix, but the missing settings contract was independently reproduced in the live catalog before this audit's deployment.

### Public-release blockers

- [ ] Implement in-app account deletion, including Sign in with Apple token revocation, owned content/media handling in both Supabase and Cloudflare, local/widget clearing, and retry/completion status. Live mirror acceptance confirmed that avatars currently lack client DELETE permission (HTTP success can mean zero objects removed); the privileged server deletion path and mirrored physical deletion passed only for disposable fixtures. Account export also remains a repository privacy commitment. [Apple's deletion requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- [ ] Implement user-generated-content reporting, abusive-user blocking, moderation handling/filtering, and a published support contact. Existing leader member removal alone is insufficient. [App Review guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
- [ ] Complete hosted Storage deletion acceptance and the retention rollout decision. `MEDIA_RETENTION_ENABLED` still matches `false`; no cleanup was activated. There are currently zero queued deletions and no audio/video objects older than 30 days. Do not promise completed physical deletion based solely on client expiry or SQL queue tests.
- [ ] Reconcile diagnostic collection (currently default-on in this field build), account association, media retention, and all third-party data use with a published privacy policy and App Store privacy answers.
- [ ] Verify two installed accounts through sign-in, join/leave/transfer/removal, shared settings on/off, locked/unlocked daily/evening posts, media/response privacy, realtime changes, offline recovery, and failed uploads.
- [ ] Verify physical camera/microphone/Speech interruptions and denial recovery, audio/video playback, production notification/Live Activity start/update/end, notification attachments, and widget deep links/refresh.
- [ ] Complete physical accessibility acceptance, including the outstanding rendered contrast finding, VoiceOver, large text, Reduce Motion, iPad/split view, and landscape. Do not claim unsupported accessibility features.
- [ ] Finalize 1.0 release/version choice, screenshots, support/privacy URLs, age rating, description/localization, review account/instructions, distribution entitlements, export-compliance answers, and TestFlight cohort acceptance. This audit does not upload or submit a release.

## v0.2.2 (31) field-testing candidate

- [x] Deploy the private authenticated diagnostics collector and verify its account isolation, validation, quotas, retry idempotency, and cleanup.
- [x] Verify default-off consent persistence and the single draft-aware Continue action in the full 23-test simulator UI suite.
- [x] Complete final Debug/Release suites (206/202 tests) and inspect both rebuilt normal/largest-text screenshot checks.
- [x] Export and validate the hosted-configured v0.2.2 (31) distribution IPA at `build/TestFlight-0.2.2-31/manna circle.ipa`.
- [ ] Upload/process in App Store Connect and assign the intended TestFlight cohort.
- [ ] Match App Store Connect privacy answers to the account-linked performance/diagnostic collection before wider distribution.
- [ ] Run physical multi-account media, privacy, notification, and failure-reproduction acceptance using [the field-testing instructions](TESTFLIGHT_FIELD_TESTING.md).

## v0.2.2 (32) follow-up

- [x] Implement single smaller red/blue streak flames, photo enlargement/zoom, and fixed-horizontal Today.
- [x] Default new field-test account/device queues to on, preserving saved opt-outs and disclosing the setting.
- [x] Pass 215 Debug and 211 Release domain tests, including default-policy, early startup session-failure, streak, and Help regressions.
- [x] Complete final Release and nine distinct focused changed-flow UI cases/screenshots, with final accessibility-tree verification.
- [x] Export and validate a distinct hosted-configured v0.2.2 (32) IPA with the default-on flag at `build/TestFlight-0.2.2-32/manna circle.ipa`.
- [ ] Upload/process and assign build 32 to the intended TestFlight cohort; reproduce failures after collection is enabled.

## Locally verifiable

- [x] App and widget compile with blank Supabase configuration.
- [x] Deterministic local repository remains available to previews, tests, and simulator UI tests.
- [x] Unit and UI coverage exercises the primary Today and Timeline paths.
- [x] Privacy manifests are included in the app, widget, and notification-service targets and pass `plutil` validation.
- [x] Adaptive wordmark assets compile into the widget/Live Activity extension, and the full notification logo compiles into the notification service extension.
- [x] Draft App Store review notes identify permissions, review flow, and blockers.
- [x] Supply the final app icon and adaptive transparent manna wordmarks.
- [ ] Capture release-candidate screenshots.
- [ ] Finalize customer-facing privacy policy, support page, store description, age rating, and localization.

## Apple Developer and physical-device validation

- [ ] Enable and validate Sign in with Apple, Push Notifications, Live Activities, and App Groups for release identifiers and profiles.
- [ ] Verify push-to-start/update/end, Dynamic Island, lock screen, notification privacy, and background behavior.
- [ ] Register and sign `app.manna-circle.ios.notification-service`, deploy the mutable-content alert payload, and verify the expanded notification logo on a TestFlight device.
- [ ] Verify camera, microphone, speech recognition, audio playback, video playback, denial/recovery, and interruption handling.
- [ ] Complete VoiceOver, Increased Contrast, Reduce Motion, Dynamic Type, orientation, iPad, and small-phone checks.
- [ ] Verify widget snapshot sharing, refresh cadence, and every deep-link destination.

## Hosted Supabase validation

- [ ] Complete the two-account acceptance matrix for authentication, circles, RLS, realtime, Storage, RPCs, and gating.
- [x] Deploy all database migrations through `202610060010` and confirm local/remote history matches.
- [x] Run the hosted dispatcher once per minute and verify consecutive HTTP 200 responses.
- [x] Recover a real interrupted dispatch and verify the prompt returns to `open`.
- [x] Diagnose the partial APNs result as provider-token rotation throttling and deploy a 45-minute server-only JWT cache.
- [ ] Verify a post-cooldown dispatch has no `TooManyProviderTokenUpdates`, observe alert/Live Activity presentation, and validate Production/TestFlight device tokens.
- [x] Deploy `dispatch-prompts` version 8 with the mutable-content alert required by the notification-logo extension.
- [ ] Exercise a permanent APNs token error and verify invalid-token cleanup plus delivery observability.
- [ ] Implement and validate account export, account deletion, media cleanup, and retention controls.
- [x] Implement owner-confirmed member removal in the client, local repository, and server RPC.
- [ ] Deploy and validate member removal with two hosted accounts; implement and validate abuse reporting.
- [ ] Exercise offline, slow-network, upload interruption, expired signed URL, and service-failure recovery.

## Distribution

- [x] Create a generic iOS Release archive and inspect its code signature and entitlements.
- [x] Export an App Store distribution archive and confirm production APNs, distribution provisioning, `get-task-allow = false`, both signed extensions, and the bundled notification logo.
- [ ] Upload to App Store Connect and resolve validation warnings.
- [ ] Run internal TestFlight, then the planned external cohort.
- [ ] Re-run the acceptance matrix on the candidate build.
- [ ] Complete App Store metadata, review credentials, privacy nutrition labels, and release notes.
