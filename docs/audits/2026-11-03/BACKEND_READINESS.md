# Backend readiness — November 3, 2026

**Hold public launch.** Live operations are healthy in the inspected interval; capacity, recovery and physical acceptance remain open. See `docs/RELEASE_CHECKLIST.md` for the complete compliance audit and source links.

## Verified without production mutations

- Hosted migration 202611020008; all inspected ordinary tables have RLS. Private schema and 12 administrative functions deny ordinary roles. All three media buckets are private. One post per prompt/author is enforced by a unique database constraint.
- Actual storage: 577,878,779 bytes / 140 objects. Media median 2,881,525 bytes; p95 12,789,376; maximum 47,424,738. Dashboard average 0.556 GB is a different time-window measure.
- No pending account deletions, media deletion queue, open reports, mirror failures or diagnostics older than 14 days. Nine current mirrored jobs do not represent complete historical backfill.
- Last day: 1,440 successful dispatch cron jobs, 24 pruning jobs. Last six hours: 358 HTTP 200, two HTTP timeouts. Follow-up shows no overdue scheduled or active stale dispatch prompts, no recorded failures on ten prompts started in the preceding day, and 18/18 APNs requests accepted in the successful-response sample. Device delivery is unproven.
- Retention activation digest matches false; start date absent. No secret value exposed and no cleanup activated.

## Required before public launch

1. Resolve Supabase prior-cycle overage / November 17 restriction warning. Free storage/egress is unsuitable for the illustrated 100-active-user media model: 15 GB new recordings/provider/month and approximately 150 GB Supabase recording egress before other traffic. Confirm measured cohort behavior and staging peaks before choosing headroom.
2. Establish independent database/media recovery points and test restore. Dashboard shows no database backups; synchronized R2 copies propagate deletion and are not a database backup or historical recovery point.
3. Align effective global 50 MB and bucket 75 MiB limits with client preflight and failed-upload recovery. Largest actual object is already near the effective cap.
4. Add external quota, dispatch, oldest-retry/deletion and mirror alerts. Successful cron scheduling alone misses HTTP timeouts and application-level failures.
5. Verify the updated build's actual availability, then preserve its approved 72-hour retention grace. Complete separate abandoned-upload, provider-log and backup-retention schedules.
6. Finish physical Apple revocation/deletion, installed two-account privacy/report/block, permission recovery and production notification acceptance.

Local verification: 378 Debug and 372 Release unit tests passed, complete disposable SQL launch/migration chain passed, Worker type-check/12 tests/dry build/full dependency audit passed, five lifecycle/retention Edge tests passed, three notification/badge contracts and signed IPA validation passed. Local tests do not certify the distinct uploaded TestFlight build 0.5.3 (49).

Evidence: aggregate-audit.json, access-audit.json, dispatch-audit.json, retention-gates.json and corresponding read-only SQL files in this directory. No customer content, identifiers, tokens or error bodies were exported.
