# Supabase and Cloudflare dual storage

## Current contract

Supabase remains the source of truth for uploads, file paths, signed reads, and authorization. The iOS app and local demo use their existing services. A successful upload does not wait for Cloudflare. This phase mirrors **object storage only**, not Postgres, Auth, text, or realtime.

Migration `202611020001_storage_mirror.sql` observes committed Storage API inserts, replacements, moves, archive/delete markers, and deletions in the private `blessing-media`, `avatars`, and `circle-photos` buckets. It records a durable job in the same transaction. Last-access timestamp updates do not copy a file again. Existing files are not automatically queued.

A private scheduled Cloudflare Worker claims at most five jobs each minute, streams originals from authenticated Supabase Storage into a private R2 bucket, and acknowledges the lease. No HTTP media, upload, or administrative endpoint exists. `workers.dev` and preview URLs are disabled. Do not enable public bucket access or attach a public/custom domain.

Every source generation has an independent opaque `v1/{job UUID}` R2 key. The private ledger maps the source bucket/path/version to that key; a path alone is not an R2 key. New generations cannot overwrite older/newer generations. A retry checks R2 first so an acknowledged-lost successful PUT does not download Supabase bytes again. R2 PUT is atomic; successful writes are checked against source Content-Length. This is a transfer check, not an independently calculated content hash or an end-to-end encryption scheme.

Replacements/deletions retire earlier generations. Retirement cleanup waits at least 30 minutes after the last copy claim, then removes their R2 bytes. This covers copies that finish after a source change, including a Worker crash between PUT and acknowledgement. Claims last 20 minutes; stale tokens cannot acknowledge a later claim. **This design requires the scheduled-only Worker invocation limit of 15 minutes.** Do not invoke `runMirror` from an unbounded HTTP/service/workflow handler or shorten these intervals. If Cloudflare changes that bound, revisit the fencing design before rollout. Scheduled limits: [Cloudflare documentation](https://developers.cloudflare.com/workers/runtime-apis/handlers/scheduled/).

Failures retry indefinitely, with exponential delay from one minute to six hours. There is no silently discarded dead-letter state. Source 404s remain retryable until a later source mutation retires the generation; persistent source/storage/configuration failures require operator investigation. Failure records contain closed error categories, not response bodies or user media. Deleted-job metadata receipts are purged in bounded batches after seven days. Active/current mappings remain for the eventual read migration. At five jobs per minute the nominal maximum is 7,200 jobs/day, with lower throughput during failures/large uploads; monitor backlog before increasing concurrency.

This phase adds one Supabase outbound transfer per newly copied file, plus retry traffic when copying fails before PUT. It does **not** reduce existing Supabase read/database bandwidth. Later authorized R2 reads are a separate change that must preserve the daily/evening submission gate, membership checks, signed-link lifetime, and historical access. R2 egress has no charge, while storage and operations have separate allowances/prices: [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

## Secrets and privacy

`SUPABASE_SERVICE_ROLE_KEY` is a Cloudflare Worker secret. It bypasses Supabase RLS and must never enter app configuration, source control, logs, URLs, or a browser-facing response. Worker deployment access must be limited to trusted operators. `SUPABASE_URL` identifies the existing HTTPS `*.supabase.co` project; arbitrary/custom origins are intentionally rejected. R2 uses the native server binding, so the app needs no R2 credentials. Outbound redirects are manual and rejected by status, preventing credential forwarding. The worker streams files rather than buffering the full original in memory, accepts at most 512 MiB, and uses request timeouts.

Copying to R2 introduces Cloudflare as a media processor. Update and publish the actual privacy policy and reconcile App Store privacy answers before wider distribution. R2 copies follow actual Supabase Storage deletions with the retirement delay above; disabled/stalled workers delay deletion, so account-deletion completion must verify both stores. This does not activate the existing disabled 30-day media-retention job. Operational/server access is possible; content is not end-to-end encrypted.

## Verification

```sh
bash Scripts/test-storage-mirror.sh
cd cloudflare/storage-mirror
npm ci
npm run check
npm test
npm run build
npm audit
```

The SQL harness uses an isolated socket-only temporary Postgres database and the actual migration. It covers restricted grants, observed/ignored mutations, replacement during copy, generation-specific cleanup, duplicate claims, expired-token fencing, retry backoff, bounded/idempotent backfill, archive/delete markers, and receipt pruning. Worker tests bundle the actual implementation into local workerd/Miniflare, mock only Supabase HTTP, and use a real local R2 binding to check bytes, retry reuse, replacement, idempotent deletion, retry categories, origin/path/key checks, disabled behavior, and private HTTP behavior. There is no new app behavior or required client release.

## Deployment and acceptance

Use the isolated `codex/cloudflare-dual-storage` worktree. Install the pinned dependencies above. Cloudflare Wrangler stores its OAuth credential encrypted with a key in macOS Keychain. R2 must be activated by the account holder; do not accept billing/agreement steps on their behalf.

1. Run local verification. Confirm all three Supabase buckets are private, Storage's required columns exist, no conflicting mirror deployment exists, and hosted migration history matches. Use a short lock/statement timeout for the migration. Trial the exact migration inside a rollback-only hosted transaction first; it must not upload/download/delete real media or dispatch notifications.
2. Create the private `manna-private-media-mirror` R2 bucket. Review jurisdiction/location requirements before selecting a location. Keep public access, custom domains, lifecycle expiry, and CORS off. `wrangler r2 bucket create manna-private-media-mirror` creates the bucket; verify its access settings.
3. Deploy `cloudflare/storage-mirror/wrangler.jsonc` with `MIRROR_ENABLED=false` (the checked-in default). Set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` with `wrangler secret bulk` over stdin; do not print them or store a tracked secret file. Deploy only this Worker; do not change the existing APNs scheduler.
4. Apply only the mirror migration and record its exact SQL in Supabase migration history transactionally. Do not push unrelated migrations. Check RPC execution is denied to anonymous/authenticated roles and available to service_role. PostgREST must reload the function signatures.
5. Upload an explicitly disposable synthetic image through the Storage API under a random avatar path with the server credential. Never use a real customer's path. Enable the worker with `wrangler deploy --var MIRROR_ENABLED:true`, leaving the committed default disabled for future review. Observe `storage_mirror_status()` and verify copied R2 bytes against the fixture. Replace the synthetic source and verify a new key; delete the fixture through the Storage API; allow retirement grace and verify both R2 copies are removed. Remove only this synthetic fixture. Test temporary failure/recovery in staging/local fixtures rather than breaking production secrets.
6. Verify another ordinary authenticated upload, signing/read, and deletion still obeys the existing Storage policies. Record deployment IDs, migration time, proof, queue depth, and actual activation state in STATUS. Test on an installed app when available. Monitor oldest pending/failure counts, Cloudflare invocation errors, both providers' usage, and retirement completion. Do not declare the bandwidth issue solved by mirroring.

`select * from public.storage_mirror_status();` is service-only and returns counts without paths or account IDs. A failure/oldest-pending alert needs an external monitoring channel; none is configured automatically by this feature.

## Backfill and eventual cutover

Backfill is opt-in because reading the existing media library spends Supabase bandwidth. The service-only `backfill_storage_mirror(p_after uuid, p_limit integer)` scans up to 500 Storage rows (100 by default), locks selected source rows until enqueue commits, and returns `next_cursor`, `scanned`, `enqueued`. Start with null cursor, persist each returned cursor, stop when scanned is zero. Retries are idempotent. Do not use offset pagination, enqueue the entire library in one transaction, or use direct SQL to delete Storage metadata. [Supabase Storage schema rules](https://supabase.com/docs/guides/storage/schema/design).

Before cutover, finish bounded backfill, validate source-version/size/checksum coverage, resolve failed and retired jobs, implement an authenticated R2 reader with the full current visibility rules, test expired links/removal/account deletion, and keep an explicit rollback route. No read cutover or existing-media backfill is part of enabling new-upload mirroring.

## Pause and rollback

Redeploy with `MIRROR_ENABLED=false` to pause claiming. Queued work persists and resumes after re-enabling; reads/uploads still use Supabase. Disabling the worker also pauses R2 deletions. To stop enqueueing during an incident, remove only the `enqueue_storage_mirror` trigger after pausing and reviewing the lost-change/backfill implications; do not drop the ledger or bucket while copy leases may be running. Preserve at least 30 minutes from the final copy claim before orphan cleanup. Never delete original Supabase objects as a rollback step. Re-enabling after missed source deletions requires reconciliation before read cutover.
