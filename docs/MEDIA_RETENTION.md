# Media retention and private saved blessings

## Contract

- Blessing audio/video and response audio reach their removal date 30 × 24 hours after their own server `submitted_at`, not the circle day or prompt start. Keep text, transcripts, Bible references, photos/previews, and response rows in circle history. Removal of audio/video includes its video thumbnail; it does not target attached photos.
- The owner selected **audio/video only**, **automatic saving on for new users**, existing explicit choices unchanged, and cleanup starting **three days after the updated 0.5.1 build is actually available to users**. Availability has not been recorded; production cleanup remains disabled. Do not substitute an export, source commit or App Store draft date for actual distribution.
- Saving does not extend server retention or anyone else's access. Each account has a private device archive separate from Photos exports. Completed saves use protected Application Support, relative media paths, atomic manifests and no cloud/device backup. They survive relaunch, but not uninstall/device loss. They have no automatic age limit and can grow indefinitely.
- The default automatic pass checks bounded, keyset pages across every joined circle. It includes all currently retained recordings, older parents with recent response audio, and older recordings still offered during the launch grace period. There is no seven-day media-saving cutoff. `Include older history` additionally pages older text/photos. Hosted reads use caller RLS; saving does not unlock current peer posts, blocked content or another circle.
- Automatically refreshed archives include available responses and reuse complete, nonempty local files. Missing/zero-length files and unavailable active recordings cannot be reported as complete. Response bodies are paged past the server's 1,000-row limit. Failed saves preserve the previous archive and retry on refresh; Wi-Fi policy applies to automatic network copies. Manual review saves can use cellular.
- An enabled preference is not a delivery guarantee. The app must be open, connected through a permitted network, and have enough storage before server cleanup. A device that never reconnects cannot receive every recording. Server cleanup does **not** wait for per-device acknowledgements. Settings surfaces waiting/error states; this limitation is explicit in Help/policy.
- Users with automatic saving off see a pinned Timeline reminder. It opens a scrollable review across all circles for unsaved recording media due within three days, including voice responses on older posts. Still-available overdue media is also offered during launch grace, labeled as past its 30-day limit. Save individually or save all listed; incomplete checks/errors never claim everything is saved. The account/device `Show Timeline expiry reminder` setting hides/restores it without changing retention. The review remains available in settings.
- Cards show saved status and expiry information, without individual Save/Unsave buttons. Turning automatic saving off still offers all/mine/none/selected keep choices over automatic archives; preserved manual copies remain. Expired local-copy removal requires confirmation.
- User settings estimates bytes in completed archives for this account (media plus records), excluding temporary media caches, drafts and Photos exports. It refreshes on opening and after saves/removals.
- Online access is governed by fresh membership/prompt rules. Completed archives supplement ordinary offline Timeline for the last signed-in account; they grant no live membership or write access and remain isolated across accounts.

## Hosted cleanup and launch gates

Never remove bytes by directly deleting `storage.objects` metadata. The service-only transactional queue clears expired recording references and preserves retained history. Shared repeat paths remain while an unexpired reference needs them. The scheduler removes queue paths through the Supabase Storage API, which retires private R2 generations through the existing durable mirror queue. `acknowledge_media_deletions` retains the receipt until source metadata is absent **and every mirror generation is acknowledged deleted**. Failures retry; physical removal can be later than the target date. Clearing a recording must not requeue an unchanged, already-reviewed photo or undo an independent moderation hold.

Installing migrations does not start historical cleanup. `dispatch-prompts` requires BOTH:

1. `MEDIA_RETENTION_ENABLED=true`.
2. `MEDIA_RETENTION_START_AT` set to a valid UTC ISO timestamp with seconds, at or before the current time.

Leave the flag false and start date unset until actual updated-build availability is verified. Record `available_at`, calculate `available_at + 72 hours`, set the UTC start gate, then enable the flag only under that approved schedule. No date has been invented or configured. Removing either gate pauses new batches, but cannot recover already removed recordings. Monitor the deletion queue, R2 failures and provider source absence after activation; alert/act on persistent failures. Backups, provider logs, exported copies and other members' device archives are separate from active-service recording removal. Do not claim a guaranteed backup erasure deadline.

Migrations: original queue `202610080001`, paged inventory `202611020005`, physical two-store acknowledgement and moderation-safe cleanup `202611020006`. Private R2 storage is a copy of Supabase uploads; app reads still use Supabase, and this feature does not claim to fix its egress usage.

## Verification

- `bash Scripts/test-media-retention.sh`: disposable original retention constraints, exact boundaries, shared repeat paths, queue retries and retained history.
- `bash Scripts/test-launch-compliance.sh`: the entire migration chain plus access/deletion safety, inventory page 41/client page 40 continuation, older-parent response inclusion, outsider denial, unchanged-photo moderation and acknowledgement gating/idempotency.
- `npx -y deno test supabase/functions/dispatch-prompts/media-retention.test.ts`: missing/invalid start gates and exact activation boundary.
- `SavedBlessingStoreTests`: defaults and existing opt-outs, three-day boundary, missing/empty file failure, account-scoped storage bytes, full-window/old-parent auto and manual rescue, archive reload after actual source-file removal, partial failures and privacy fences.
- `BackendOptimizationTests`: actual SDK inventory continuation and 1,001-response paging with injected transport; not proof of hosted RLS by itself.
- Retention UI: pinned reminder while scrolling, review/manual save-all, reminder setting, storage estimate, existing off/keep choices and normal/largest dark layouts. Local fixtures never authenticate against hosted users.
- Hosted acceptance uses tiny valid recordings in a disposable account and circle, verifies matching Supabase/R2 bytes, locks and asserts the oldest selected rows are **only fixture rows before committing any queue mutation**, then uses Storage API deletion and verifies both providers, preserved text/photo and local acceptance copies. It never enables global cleanup or backdates mirror leases.
