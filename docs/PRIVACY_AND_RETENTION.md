# Privacy and retention plan

Last updated: 2026-09-30

## Principles

- manna circle does not track users or use data for advertising.
- Circle content is private to current members and is used only for app functionality.
- The app stores a Bible reference, never a copied verse text, with a blessing.
- Service-role, APNs, and Apple private keys never ship in the app.

## Data inventory

| Data | Purpose | Storage | Planned retention |
| --- | --- | --- | --- |
| Name, user ID, Bible-version preference | Account and personalized scripture display | Supabase Auth/profile | Until account deletion completes |
| Circle membership and join date | Access control and accurate Timeline history | Supabase database | Until the user leaves or account/circle deletion completes |
| Blessing text/transcripts and scripture references | Core private-circle history | Supabase database | Until account/circle deletion; per-post deletion policy still requires a product decision |
| Voice, video, and optional blessing photos | Playback or display for the selected capture mode | Private Supabase Storage | Same as the parent blessing; abandoned upload cleanup must be automated |
| Text/voice responses | Circle conversation | Supabase database/private storage | Same as the parent blessing |
| APNs, push-to-start, and activity tokens | Notifications and Live Activities | Supabase database | Replaced on rotation; invalid and stale tokens must be revoked |
| Local capture files | Recording, preview, and upload staging | App cache | Remove after successful upload or abandonment cleanup |
| Widget snapshot and recently shown IDs | Widget display and variety | App Group UserDefaults | Replaced on refresh; cleared at sign-out |

## Export contract

The eventual export must contain the profile, circle memberships, authored blessings, scripture references, authored responses, timestamps, and signed links or packaged copies of retained media. It must not expose other members’ private content beyond data already visible to the requester.

## Deletion contract

Account deletion must be initiated in-app, reauthenticate when required, remove or anonymize authored relational data according to the final group-history policy, delete owned storage objects, revoke device/activity tokens, clear local caches and App Group snapshots, and report completion or a retryable failure. Database cascades alone are insufficient because Storage objects require explicit cleanup.

## Validation still required

- Approve per-post and departed-member history retention policy.
- Implement and validate export and account-deletion server operations against two hosted accounts.
- Validate private Storage cleanup, abandoned upload cleanup, token revocation, and deletion completion timing.
- Reconcile this manifest and plan with App Store Connect privacy answers before submission.
