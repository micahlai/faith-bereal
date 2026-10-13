# Backend optimization proposal — awaiting approval

Updated October 13, 2026. The owner reports slow photo/voice/video sending, slow startup and circle switching, and an error described as “too many connections issued to the database.” Modest media compression is acceptable only after comparison tests. Broader optimization has not been authorized to start.

## Evidence and uncertainty

- One read-only hosted snapshot showed `max_connections=60`, 28 connections, 2 active, 19 idle, and no idle-in-transaction sessions. This was not captured during the reported failure. It neither proves nor rules out transient exhaustion or saturation of a smaller service/pool limit.
- The client uses Supabase APIs, not one direct PostgreSQL connection per phone. Auth, Storage, API requests, and background work can still contend for database capacity. The exact failing service, error code, and time are needed before attributing the error to a specific pool. See [Supabase connection terminology](https://supabase.com/docs/guides/troubleshooting/supavisor-and-connection-terminology-explained-9pr_ZO).
- The requested Timeline feature now loads fourteen-day pages. Widget and automatic-saving workers still load broader histories. Several media/avatar signing calls and response fetches occur independently; request traces are needed to quantify duplication before changing these paths.
- Circle-specific streak metadata is a separately requested feature. Its October 13 migration adds one authorized summary RPC; it does not change connection configuration, compute, indexes, retention, or media encoding.

## Proposed sequence

1. **Measure the failing paths.** Capture per-stage timings and request counts for cold/warm startup, repeated circle switching, and representative media submissions. Separate permission/capture/encoding/upload/finalize/refresh time. Correlate a timestamped connection error with Auth, Storage, API/pool, database activity, locks, and query durations. Use test fixtures and bounded traffic, never a production stress test. Logs must exclude content, tokens, signed URLs, and personal information.
2. **Reduce duplicate work.** Based on measurements, coalesce overlapping circle refreshes, cap concurrent requests, cache account-scoped metadata with explicit invalidation, and batch/cache authorized media signing where supported. Defer nonessential widget/archive work until the visible screen is ready. Bound automatic-saving history traversal without omitting eligible media. Preserve prompt freshness, privacy gates, circle/account cancellation isolation, and submission idempotency.
3. **Compare media options.** Use the same representative photos, speech, and video clips to compare current versus modest JPEG resizing/quality, AAC speech encoding, and a bounded video export. Report bytes, encoding time, upload time, total send time, visual/speech quality, and peak memory on a physical phone. Preserve aspect ratio, orientation, transcript, audio/video sync, and originals until successful submission. Compression is adopted only after the comparisons are reviewed; smaller files alone do not establish a fix for connection exhaustion.
4. **Tune proven database bottlenecks.** Only if traces and safe query plans justify it, propose specific indexes, query/RLS changes, or appropriate pooling changes. Inspect existing pool allocations and compute capacity before recommending paid capacity. Do not blindly raise connection limits, kill sessions, change compute, or introduce schema/index changes under this unapproved proposal.
5. **Validate and stage the rollout.** Compare median/tail startup, switch, and send times against baseline, with request counts, bytes, memory, and error rates. Test two-account privacy, retries, offline recovery, drafts, media reuse, local saves, and fresh notification boundaries. Commit changes separately; release through a small TestFlight cohort before wider rollout.

## Decisions needed

- Approve the measurement and request-reduction phases first. Compression remains gated on comparison results, as requested.
- Identify where the connection error appeared (startup/sign-in, circle switch, Timeline, or upload), its approximate time/time zone, and exact error code if available. Work can begin with measurements while gathering this evidence.

No broader optimization code or infrastructure change is included in this proposal. The requested client Timeline improvements and streak-support migration are tracked separately in STATUS.
