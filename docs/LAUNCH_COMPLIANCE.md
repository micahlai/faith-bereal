# 0.5.0 launch privacy and safety

Initial launch: **United States only, ages 13+**, as selected by the owner. Do not intentionally admit under-13 users; investigate actual-knowledge reports through the privacy contact. The first launch asks for age confirmation and acknowledgement of data use before app bootstrap/sign-in. It does not collect a birth date or establish independently verified age. Apple's age-rating questionnaire remains separate and must reflect the actual user-generated content features; do not equate a product age rule with a completed legal review.

| Area | Implementation / evidence | Remaining acceptance |
| --- | --- | --- |
| Public policy | https://manna-circle.micahlai.com/privacy, website footer, launch screen and offline User settings policy | Update the version-qualified website notice when 0.5.0 is distributed |
| Diagnostics | Off by default in 0.5.0, fresh consent replaces legacy default-on state; account-linked reports, opt-out clears unsent queue; existing 14-day hosted cleanup | Essential provider logs are separate; do not describe reports as anonymous |
| App Store labels | Ten account-linked categories, no tracking; published in App Store Connect after owner confirmed final attestation; policy URL saved | Reconcile whenever collection changes |
| Cloudflare | Fresh original/copy/replacement/delete validation; Supabase still supplies every app read. R2 private, no public reader | Existing media not backfilled; mirror does not reduce Supabase read egress yet |
| Account deletion | Reauthenticate same Apple identity, exchange code/verify Apple subject/revoke token, durable DB request, remove active access/content/tokens, transfer leadership, Storage API cleanup, wait for mirror deletion, then Auth deletion. Hashed random receipt survives Auth removal; completion requires persisted cleanup verification. Local drafts/archives/caches/widget/Live Activity cleanup | Actual Apple consent/code exchange/revocation must be tested on a physical device with a disposable Apple-linked account. Synthetic recent-session Auth acceptance verified real Supabase and R2 physical absence, ownership transfer, stale-JWT write denial, peer preservation and receipt completion |
| Reports / blocks | Server-authorized reports, mutual active-content and notification blocking, local archive purge limited to blocked content; private operator inbox, hide/suspend; new photo/audio/video human review, limited phrase filter | Micah accepted daily review and urgent action within 24 hours. Operator coverage is an ongoing obligation. Existing media is not requeued; phrase filters cannot recognize all contextual abuse. Earlier signed links/downloads can persist |
| Permissions | Point-of-use camera/mic/Speech; editable transcription may use Apple servers; system photo picker, Photos add permission on export; typed alternative on denial. Usage strings and privacy manifest updated | Physical denial/re-enable, capture/export and VoiceOver matrix still required |
| Notification privacy | Generic new alert title/body; **sender name/photo and circle-name custom fields also removed**, preventing the extension from restoring sensitive previews. Blocked senders filtered. Payload contract passes | Old delivered alerts remain; widgets/Live Activities can display content. Physical production APNs visual acceptance remains |
| ATT / encryption | No ads/IDFA/tracking SDK integration found in app source; tracking false in manifest. No ATT prompt added. Standard transport encryption, private access controls, no end-to-end encryption claim; non-exempt encryption declaration false | Reassess for any future SDK/ad/custom-crypto changes |

## Deletion operations

The Apple `.p8` remains outside Git/app resources. Server secrets hold its private key plus client/team/key identifiers; the service signs a fresh five-minute client token instead of relying on an expiring six-month secret. Local credentials were checked with an intentionally invalid Apple authorization code (Apple returned `invalid_grant`); that is not proof of a completed real-user revocation.

Cloudflare's existing minute Worker calls the protected cleanup processor after mirror work. A dedicated processor credential is stored in Supabase, Wrangler and local macOS Keychain, never the client. Jobs retry with bounded claims, failures isolated per account, and no content/credential logging. Do not delete an Auth account manually as a substitute for verified storage cleanup. Lost-completion recovery only confirms receipts whose cleanup was verified before Auth removal. A failed/outage request stays pending, not falsely complete.

Migrations `202611020002`–`004` were deployed after full disposable migration-chain tests and rollback-only hosted trials. Exact source hashes match migration history. Worker version `6e793c00-cf85-4b33-9d01-028eff87598d` has copying and account cleanup enabled. Actual scheduled invocation was observed with outcome `ok`. Synthetic acceptance fixtures and their failed-attempt remnants were removed; no real user was deleted or blocked. Moderation instructions: [MODERATION.md](MODERATION.md).

## Retention proposal — not implemented

The owner requested a proposal only. `MEDIA_RETENTION_ENABLED` remains untouched/off. Current client 30-day media expiry and Help promises do not establish server deletion and remain a public-release blocker. Website/support policy now discloses this mismatch honestly; that does not activate cleanup.

Before changing behavior:

1. Choose an explicit schedule for each category: audio/video/response audio, photos/previews, text/transcripts, drafts/abandoned uploads, diagnostics, moderation/security records, receipts, and departed-member history. Confirm whether the existing 30-day audio/video plan is actually desired.
2. Verify actual Supabase/Cloudflare backup and provider-log behavior and access; state active-service deletion separately from backup aging. Do not invent a backup erasure deadline or claim that exported copies can be recalled.
3. Define the timer source, grace periods, retry/outage treatment, legal/security exceptions, and what “deletion completed” means. Decide what users should see while media cleanup is pending.
4. Implement only after approval, with an inventory/dry run and disposable end-to-end tests proving original, mirror, previews and metadata deletion without harming retained history or saved copies.
5. Update Help, warning labels, policy, support copy and App Store disclosures together, monitor actual completion, and promise only what the deployed system demonstrably does.

An App Store public release remains blocked on this decision/implementation and physical-device acceptance; the existence of a policy or published labels is not certification of every applicable US law.

## Candidate verification record

- Full Debug: 356 tests passed; final Debug archive suite: 20 passed, including the subsequently added blocked-content preservation regression. Final Release: 353 passed, zero failures/skips. Successful evidence: `build/Compliance05UnitClean.xcresult`, `build/Compliance05ArchiveSafety.xcresult`, `build/Compliance05ReleaseVerified.xcresult`.
- Four launch/diagnostic UI cases passed in `build/Compliance05UIAccepted.xcresult`; normal/largest-dark settings and policy screenshots inspected. Existing UI fixtures explicitly skip onboarding; the privacy test exercises the real gate and off-by-default toggle. Earlier pre-start simulator stalls, stale launch arguments and a build-database lock are superseded, not passing evidence.
- Full disposable SQL migration chain plus hosted rollback trials passed; lifecycle Edge tests4/4 and Worker tests12/12 passed. Generic notification and Live Activity payload contracts pass. Hosted migration hashes match exact checked-in source. Live copy/replacement/delete evidence is in `build/cloudflare-revalidation/result.json`; account deletion evidence is in `build/compliance05-live/result.json`.
- Signed device archive and distribution-export validation pass. App, notification service and widget/Live Activity extension all declare0.5.0(47), production APNs/no debugging entitlement and valid privacy manifests/signatures. IPA: `build/TestFlight-0.5.0-47/manna circle.ipa`; SHA-256 `86a88d1f8763f7059f07325b3d64d41c280a63d6e51ccb44f0fdee83e520b5b5`. No TestFlight upload or App Review submission was performed; build47 availability in App Store Connect remains unverified.
- `MEDIA_RETENTION_ENABLED` was rechecked through its secret digest and remains false. The final source scan found no embedded private keys/JWTs. The Apple `.p8` file's permissions were restricted to its owner.
