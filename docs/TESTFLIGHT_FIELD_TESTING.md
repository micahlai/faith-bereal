# v0.2.2 field testing

Build 30 was v0.2.1. Build 31 added request reduction, multi-user diagnostic collection, Circle People streaks, random-only Timeline notification times, and one draft-aware sharing button. Build 32 adds one smaller red/blue flame (blue for timely entry on every day in the current run), full-screen photo enlargement/zoom, fixed-horizontal Today, and field-build default-on collection.

## Tester setup

1. Install v0.2.2 (32) from TestFlight when available and sign in normally.
2. Open the app menu → User settings → Field testing and check **Share diagnostic data**. Build 32 defaults on for a new account/device. Explicit choices and legacy saved off settings remain unchanged, so enable it manually if it is off and you want to participate. You can disable it at any time. No Xcode environment variable is needed for TestFlight.
3. Reproduce startup, circle switching, Timeline, and typed/photo/voice/video sending with ordinary bounded interactions. Note the exact visible error code and UTC timestamp when an error occurs.
4. Leave manna open, or choose **Send diagnostics now** in User settings. One batch sends at most 100 records. Automatic uploads run about every five minutes while active and try on foreground return. A failed send keeps the same batch for retry. It does not change sharing or show scrolling alerts.
5. Confirm Last sent updates. Relaunch with collection enabled to capture restored-session startup, including the initial auth session validation/refresh. First sign-in without a cached account remains outside the collector's scope. Earlier failures before enabling collection cannot be recovered retroactively. Toggle off when finished; this stops collection, cancels uploads where possible, and drops unsent records. An already accepted/in-flight request may still finish.

Reports contain a random session code, app build, UTC timings, SDK-operation categories/outcomes, available payload/returned-data sizes, available success HTTP status, and numeric URL transport codes. The server links reports to the signed-in account for access control and per-account limits. Reports exclude blessing text, recordings, photos, names, media paths, signed URLs, credentials, and error descriptions. They are **not anonymous** and cannot be read by other circle members.

The protected device queue caps at 1,000 records, drops oldest pending records under pressure while preserving an in-flight retry, and discards records older than 13 days when collection is next used. Files are excluded from backup. Checkpoints coalesce over two seconds, so a crash can lose that recent tail. The server retains accepted reports for 14 days with hourly scheduled cleanup in bounded passes; there can be a short cleanup lag. Server limits are one new batch per minute and 100 new batches per account per rolling 24 hours. Exact retries remain idempotent. Sustained all-day use may reach the quota; queued samples retry later within their expiry period.

Local demo exercises consent/queue controls but has no remote uploader. TestFlight uses the hosted project. No service-role or Apple/APNs secret is embedded in the app.

## Operator collection

Migration `202610130002_backend_diagnostics.sql` is deployed. The authenticated-only ingestion RPC derives identity from the JWT, validates every key/type/range, and writes into a private non-exposed table. Anonymous calls, direct client reads/writes, and client cleanup calls are denied. Collector uploads are uninstrumented to prevent feedback loops. The uploader pins the original account's captured JWT, so account changes cannot relabel old queues.

Read summaries through the linked project:

```sh
npx --no-install supabase db query --linked --file supabase/queries/backend_diagnostics_summary.sql
```

The result contains participation totals by build, median/p95 timing and failure totals by category, and failure counts grouped by UTC minute. Empty arrays mean no matching reports yet. These summaries return no customer names, raw account IDs, or blessing content. Raw report access is limited to project operators.

Check deployment and retention without returning diagnostic content:

```sh
npx --no-install supabase db query --linked --file supabase/tests/backend_diagnostics_hosted_status.sql
```

Expect migration/RLS/member_ingest true; anon_ingest/member_prune/member_private_schema false; one active hourly cleanup job. `report_count` should increase after real opted-in testers send. Security verification creates transaction-scoped test accounts/reports and rolls them back.

Use failed UTC minutes to correlate with Supabase Auth, Storage, API/pool, locks, connection counts, and query logs. SDK-operation durations include adaptation/retries and do not count physical HTTP attempts. Upload payload size is the source size, not proven bytes transferred. Many SDK errors hide HTTP status, so request the exact visible service code separately. In build 32, startup spans begin after reading local cached identity and restoring the collection setting, before initial session validation/refresh, and end when the model is ready; they are not first-frame/full cold-launch latency. Realtime sockets, automatic background auth refresh, playback, scripture reads, archive downloads, and local Apple Speech/audio errors are outside operation counting. A voice-panel error and a concurrent backend alert may have different sources. The payload reports failures, not exact Postgres/API messages or service codes.

## Verified build 31 release

Verified on 2026-10-14: all 206 Debug and 202 Release domain tests, the full 23-test simulator UI suite, both final normal/largest-text screenshot checks, hosted SQL security checks, APNs payload contracts, and privacy manifest validation pass. Screenshots were visually reviewed.

The hosted-configured archive is `build/Manna-0.2.2-31.xcarchive`; the validated distribution export is `build/TestFlight-0.2.2-31/manna circle.ipa`. The app and both extensions are v0.2.2 (31), distribution-signed with production APNs and no debugging entitlement. `Scripts/validate-testflight-export.sh` passes. IPA SHA-256: `0e9452dc543bf0c93993ade0f3dc48299d4cf9ba001de341006e7abaab4fc59c`. Build artifacts are ignored by Git and remain in this workspace.

The privacy manifest declares account-linked performance/diagnostic data for functionality and analytics; update corresponding App Store Connect privacy answers before wider distribution. See [Apple privacy manifest guidance](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest).

An exported IPA is not an App Store Connect upload or a processed TestFlight build. Confirm processing and assign the candidate to the intended small cohort before wider distribution. Physical microphone/video recovery, real multi-user media/privacy/APNs acceptance, and compression comparisons remain device work. No media compression or cleanup-retention setting was changed by this candidate.

## Build 32 follow-up

Verified on October 14: 215 Debug and 211 Release domain tests, nine distinct focused UI cases across final batches/reruns, a 29-test focused domain check after accessibility changes, and normal/largest-text screenshot and accessibility-tree review all pass. The hosted-configured archive is `build/Manna-0.2.2-32.xcarchive`; the validated distribution IPA is `build/TestFlight-0.2.2-32/manna circle.ipa`. The app and both extensions are v0.2.2 (32). Distribution validation confirms production APNs and no debugging entitlement. SHA-256: `98095747dd53be2e8134220d91fce9968290d90aaeb8611bca6a4fb56f02c2a8`. No App Store Connect upload has been performed.

The exported app Info.plist sets `MANNA_DIAGNOSTICS_DEFAULT_ENABLED=true`; this controls the new-account default while stored choices remain authoritative. Testers can turn sharing off in User settings. Build 32 adds default-policy/session-persistence and early-auth-failure regressions plus photo/streak/scroll UI checks. Build-31 artifacts remain unchanged. Upload/process and assign build 32 to the intended cohort before device acceptance.

Collection receipt confirmed on October 14: the latest read-only check shows build 31 sent three batches/243 records from one account, last received at 2:48:12 p.m. Eastern, with no recorded backend failures. This proves ingestion for opted-in use, not reproduction or resolution of the reported connection error.

## Next client: error visibility and cached loading (local changes)

The pending client records sanitized backend/Speech/audio failure sources, bounded structured service/numeric codes, and a closed connection-limit category. It never uploads raw error messages, Speech transcripts, NSError userInfo, media, tokens, or URLs. An unknown error source/code stays unknown rather than forwarding arbitrary strings. Diagnostic-upload failures are retained directly once per source/code/category until a successful send; the transport remains uninstrumented, avoiding recursive reports.

Pending failures precede routine samples and survive routine-sample queue pressure. An already prepared report stays byte-for-byte stable for exact retries. Upload attempts occur on foreground activation and new captured failures subject to spacing; a backlog/failure retries about once a minute while active, ordinary samples about every five minutes. Server quotas remain one new batch per minute and 100 per account/day. Each manual send still sends one batch. Event timestamp ranges and receipt ranges are reported separately so a recent upload of old events is never mistaken for coverage of a recent incident.

Migration `202610150001_backend_diagnostic_errors.sql` is deployed. The validator accepts the new fields/request kinds and retains compatibility with older payloads; RLS, restricted grants, quotas, and the existing hourly cleanup remain in place. Historical builds cannot recover unrecorded errors. The original reported connection failure is not yet proven resolved on a physical device.

Startup/switching show saved circle/member/streak identity immediately with a persistent loading indicator; blessings and permissions still fetch under fresh server authorization. Protected metadata and bounded profile/circle photo bytes expire after seven days, are excluded from backups, and clear on sign-out. Photos refresh only from verified metadata. This display cache does not include blessing content or entry grants. Interrupted switching restores the previous circle; Retry refreshes the displayed circle, and selecting the destination again retries switching. Repeated foreground refreshes coalesce; failed live subscriptions are removed and optional widget/automatic-saving work waits for the visible page. No new TestFlight archive/upload is included in this change.

Local verification passes 268 Debug/264 Release domain tests, 42 final focused scope/loading/Help checks, and nine distinct focused UI cases across final batches/reruns. Normal/largest-text loading and diagnostic screenshots were reviewed. See STATUS.md for result bundles and superseded test-harness failures. The client remains uncommitted/unpushed and needs a new build before these changes can collect field data.
