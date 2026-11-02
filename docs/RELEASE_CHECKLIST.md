# Release checklist

This checklist separates work that can be proven locally from work that needs production Apple or Supabase access.

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
