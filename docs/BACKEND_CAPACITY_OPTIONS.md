# 0.6.0 capacity direction and backup options

Planning record, November 3, 2026; target up to 100 active users. These are recommendations. This work does not activate a backup schedule, provision a provider, move media, deploy a Worker or change retention.

## Media in Cloudflare, structured data in Supabase

Yes: private Cloudflare R2 for photo/video/audio bytes, with Supabase for authentication, profiles, circles, prompts, posts, text/transcripts, references, authorization, moderation, metadata and cleanup state. Keep a media record in Supabase with object key, owner/circle/prompt relationship, kind, byte size, MIME type, checksum and lifecycle state. Database references to media remain structured data.

The current deployment mirrors new media to R2 but serves app reads from Supabase. Mirroring alone does not reduce Supabase download traffic and propagates deletion, so it is not an independent backup.

Required implementation and acceptance before a cutover:

1. A Cloudflare authorization service verifies the caller's Supabase identity and caller-scoped database permissions before issuing short-lived upload/read access. It must preserve membership, exact-prompt sharing, block and account-deletion rules. Never embed an R2 secret or Supabase administrative key in the client, expose a public bucket, or accept only possession of an object key as authorization.
2. Upload intent validates supported type/byte limit, writes a pending media record, and verifies uploaded bytes/checksum/metadata before finalizing the authorized post. Failed/interrupted/unclaimed uploads need bounded cleanup. Download URLs are bearer capabilities until expiry; keep expiry short and test account/block transitions honestly.
3. File bytes travel directly to/from R2 or its Worker. Proxying bytes through Supabase still incurs its transfer allowance. Support audio/video range requests, previews, avatar/notification media, offline/device saves, deletion retries and retention in both adapters.
4. Inventory/backfill existing objects with checksums; retain compatibility for installed old clients. Stage new writes, verified fallback reads and then read cutover with a rollback plan. Only remove old bytes after verified new-build availability, adoption, recovery and the existing retention/grace gates. Never turn cleanup on merely because this plan exists.
5. Test unauthorized/locked/blocked/deleted reads, renewed links, concurrent upload completion, network failure and two-account media flows on the actual candidate. Reconcile privacy/provider disclosures with actual requests and locations.

[R2 Standard pricing](https://developers.cloudflare.com/r2/pricing/) includes 10 GB-month storage, 1 million Class A and 10 million Class B operations monthly, with free Internet egress. Standard storage above the free allowance is $0.015/GB-month; Worker execution and operations have their own allowances. At a steady 15 GB retained volume, 5 GB above the free allowance is about $0.075/month for storage alone, before billing rounding, photos, responses, backups, operations or Workers. This is not an all-in forecast. The illustrative 15 GB volume assumes 100 daily users × one 5 MB recording × 30 retained days; current cleanup is paused, so storage will grow unless retention is actually deployed and activated. Measure real behavior before choosing capacity.

[Presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/) remain usable by any holder until expiry. Choosing R2 does not remove the need for server authorization or instantly revoke already-issued URLs. Keep backup credentials and any bucket-lock policy separate from live media deletion.

## Free-plan database backup choices

[Supabase Free has no automatic database backup](https://supabase.com/kb/faqs/platform/free-plan-backups). Recommended starting point: a daily scheduled encrypted logical export with an on-demand trigger, an offsite copy and a measured restore drill. Daily cadence can lose up to the time since the last successful backup; it is not point-in-time recovery.

| Option | Fit / limit |
| --- | --- |
| Linux GitHub Actions job in a private repository + encrypted files in a separate R2 backup bucket | Low-maintenance starting point while the account's runner/storage/operation allowances fit. R2's 10 GB free storage is shared with media, not a new allowance per bucket. Keep encrypted data out of repository history and ordinary build artifacts. |
| Encrypted copy on a local computer/external disk plus a second provider | Independent recovery if the hosting account/provider is unavailable. Requires a reliable machine and a completed-copy check; a powered-off laptop is not a daily schedule. |
| Backblaze B2 for a second encrypted offsite copy | [Pricing](https://www.backblaze.com/cloud-storage/pricing/) offers a free starting allowance; verify the account's current free limits, requests and download terms before activation. Use provider/account separation when possible. |
| Paid Supabase backup/PITR | Easier managed recovery when budget permits; evaluate retention, recovery objectives and independent copies. Not a free-plan feature. |

Use the [official Supabase backup/restore flow](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) for roles, schema and data. The [CLI dump default](https://supabase.com/docs/reference/cli/supabase-db-dump) is not a complete project export; managed schemas and custom Auth/Storage changes need deliberate handling. Prove restore of Auth identities, application/private schemas, constraints, RLS, functions, triggers, grants, sequences and caller isolation in a disposable environment. Keep the Edge/Worker source and an encrypted inventory of provider settings/secrets separately recoverable, without committing credentials.

[Database backups do not contain Storage file bytes](https://supabase.com/docs/guides/platform/backups). Back up retained media and the matching database asset references with an independent recovery policy. Decide backup expiry and how deleted-account records age out of backups; restoration must not silently reactivate deleted accounts/content.

Compress and encrypt before upload; keep the decryption key separately recoverable. Start with 30 rotating daily copies and four weekly copies only if measured compressed sizes fit; record successful-completion time, checksums and manifest counts, alert on missing/stale backups, and restore monthly plus before risky migrations. Export traffic still counts toward database/provider egress; the dashboard's database size is not the wire size of a dump.

[GitHub scheduled workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule) can be delayed or dropped and run from the default branch; use a non-peak minute, manual trigger and stale-backup monitoring. Its [included usage](https://docs.github.com/en/billing/concepts/product-billing/github-actions) depends on account/runner. This plan does not create an account, accept terms, transmit live database data or assume recurring jobs are already working.
