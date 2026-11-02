# Privacy and retention plan

Last updated: 2026-11-02

Current launch implementation and evidence: [LAUNCH_COMPLIANCE.md](LAUNCH_COMPLIANCE.md). Recording retention, saved-copy limits and activation gates: [MEDIA_RETENTION.md](MEDIA_RETENTION.md). Those documents contain the rollout and evidence details for the inventory below.

## Principles

- manna circle does not track users or use data for advertising.
- Circle content is private to current members and is used only for app functionality.
- The app stores a Bible reference, never a copied verse text, with a blessing.
- Service-role, APNs, and Apple private keys never ship in the app.

## Data inventory

| Data | Purpose | Storage | Retention / remaining limits |
| --- | --- | --- | --- |
| Name, user ID, Bible-version preference | Account and personalized scripture display | Supabase Auth/profile | Until account deletion completes |
| Circle membership and join date | Access control and accurate Timeline history | Supabase database | Until the user leaves or account/circle deletion completes |
| Blessing text/transcripts and scripture references | Core private-circle history | Supabase database | Until account/circle deletion; per-post deletion policy still requires a product decision |
| Blessing audio/video and response audio | Private playback | Supabase Storage and private Cloudflare R2 copies | Scheduled removal 30 × 24 hours after own server submission; launch grace and verified two-provider retries apply. See MEDIA_RETENTION.md |
| Optional blessing photos/previews | Display in circle history | Supabase Storage and private Cloudflare R2 copies | Retained with history until account/circle deletion; no 30-day photo expiry |
| Response text/transcripts | Circle conversation | Supabase database | Retained with history; response audio has its own 30-day clock |
| Permanent device saves | Private offline history/playback | Account-scoped protected Application Support, excluded from backup | No age expiry; lost on uninstall/device loss; explicit account cleanup and saved-copy removal choices apply |
| Optional diagnostic reports | Troubleshooting with consent | Supabase database | 14 days; off by default in 0.5.0; disabling discards unsent batches |
| APNs, push-to-start, and activity tokens | Notifications and Live Activities | Supabase database | Replaced on rotation; invalid and stale tokens must be revoked |
| Local circle/member display metadata and downloaded profile/circle photos | Show known circle identity during loading and offline | Account-scoped protected Application Support, excluded from backup | No age expiry; connected updates replace/remove photos and metadata, explicit sign-out clears outgoing identity copies; display data never grants server access |
| Local capture files | Recording, preview, and upload staging | App cache | Remove after successful upload or abandonment cleanup |
| Widget snapshot and recently shown IDs | Widget display and variety | App Group UserDefaults | Replaced on refresh; cleared at sign-out |

## Export contract

The eventual export must contain the profile, circle memberships, authored blessings, scripture references, authored responses, timestamps, and signed links or packaged copies of retained media. It must not expose other members’ private content beyond data already visible to the requester.

## Deletion contract

Account deletion must be initiated in-app, reauthenticate when required, remove or anonymize authored relational data according to the final group-history policy, delete owned storage objects, revoke device/activity tokens, clear local caches and App Group snapshots, and report completion or a retryable failure. Database cascades alone are insufficient because Storage objects require explicit cleanup.

## Validation still required

- Approve per-post and departed-member history retention policy.
- Implement user data export; account-deletion server operations passed disposable two-account acceptance, while real Apple revocation still needs physical acceptance.
- Private active-service Supabase/R2 recording cleanup passed synthetic acceptance. Automate abandoned-upload cleanup separately; verify physical Apple/APNs/token behavior and actual rollout completion.
- Reconcile this manifest and plan with App Store Connect privacy answers before submission.

## Cloudflare storage mirror

The separate dual-storage implementation adds Cloudflare R2 as a private server-side copy of Supabase media, avatars, and circle photos when enabled. Supabase remains the upload/read authority. Background copies retry; replacements and Storage API deletions retire R2 copies as soon as a completed copy is acknowledged, or after an in-flight-copy grace period of at least 30 minutes for ambiguous writes. A paused or failing mirror delays R2 deletion. Account deletion must verify both providers before reporting completion. No R2 read endpoint or end-to-end content encryption is added. The published public privacy policy names Cloudflare; published App Store labels cover the data categories. See [the contract and activation record](CLOUDFLARE_STORAGE.md); code presence alone does not mean hosted activation.
