# v0.2.2 (31) field testing

Build 30 was v0.2.1. This candidate combines request reduction, multi-user diagnostic collection, blue streak pills, Circle People streaks, random-only Timeline notification times, and one draft-aware sharing button.

## Tester setup

1. Install v0.2.2 (31) from TestFlight when available and sign in normally.
2. Open the app menu → User settings → Field testing and enable **Share diagnostic data**. It defaults off per account/device. No Xcode environment variable is needed for TestFlight.
3. Reproduce startup, circle switching, Timeline, and typed/photo/voice/video sending with ordinary bounded interactions. Note the exact visible error code and UTC timestamp when an error occurs.
4. Leave manna open, or choose **Send diagnostics now** in User settings. One batch sends at most 100 records. Automatic uploads run about every five minutes while active and try on foreground return. A failed send keeps the same batch for retry. It does not change sharing or show scrolling alerts.
5. Confirm Last sent updates. Relaunch after opting in to capture restored-session startup. Sign-in before restoring consent is outside the collector's scope. Toggle off when finished; this stops collection, cancels uploads where possible, and drops unsent records. An already accepted/in-flight request may still finish.

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

Use failed UTC minutes to correlate with Supabase Auth, Storage, API/pool, locks, connection counts, and query logs. SDK-operation durations include adaptation/retries and do not count physical HTTP attempts. Upload payload size is the source size, not proven bytes transferred. Many SDK errors hide HTTP status, so request the exact visible service code separately. Startup spans begin after cached-session lookup and restoring consent and end when the model is ready; they are not first-frame/full cold-launch latency. Realtime sockets, automatic auth refresh, playback, scripture reads, and archive downloads are outside operation counting.

## Candidate release

Verified on 2026-10-14: all 206 Debug and 202 Release domain tests, the full 23-test simulator UI suite, both final normal/largest-text screenshot checks, hosted SQL security checks, APNs payload contracts, and privacy manifest validation pass. Screenshots were visually reviewed.

The hosted-configured archive is `build/Manna-0.2.2-31.xcarchive`; the validated distribution export is `build/TestFlight-0.2.2-31/manna circle.ipa`. The app and both extensions are v0.2.2 (31), distribution-signed with production APNs and no debugging entitlement. `Scripts/validate-testflight-export.sh` passes. IPA SHA-256: `0e9452dc543bf0c93993ade0f3dc48299d4cf9ba001de341006e7abaab4fc59c`. Build artifacts are ignored by Git and remain in this workspace.

The privacy manifest declares account-linked performance/diagnostic data for functionality and analytics; update corresponding App Store Connect privacy answers before wider distribution. See [Apple privacy manifest guidance](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest).

An exported IPA is not an App Store Connect upload or a processed TestFlight build. Confirm processing and assign the candidate to the intended small cohort before wider distribution. Physical microphone/video recovery, real multi-user media/privacy/APNs acceptance, and compression comparisons remain device work. No media compression or cleanup-retention setting was changed by this candidate.
