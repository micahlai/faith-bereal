# App Store privacy answers — current 0.5.3 candidate

Initial availability: United States only. Intended users: 13+. The age rating questionnaire must still accurately declare user-generated content and messaging; a rating is not age verification or parental consent. Under-13 signup/use is not supported. Do not expand countries or lower ages without reviewing the applicable privacy/child-safety requirements.

## Answers for the current implementation

Data collected: **Yes**. Data used for tracking: **No**. All categories below are linked to the authenticated account unless noted. No advertising, data-broker sharing, or cross-company tracking is implemented; no ATT prompt should be added merely for first-party reliability diagnostics.

| Apple category | Data | Purpose |
|---|---|---|
| Contact Info → Name | Apple full name where supplied, editable profile name | App functionality |
| Contact Info → Email Address | Apple identity/relay email retained in Auth for existing or supplied identities; not shared with circle peers | App functionality |
| Identifiers → User ID | Account identifier, circle/account associations | App functionality; analytics only when optional diagnostics are enabled |
| Identifiers → Device ID | Installation identifier and push/activity registrations | App functionality |
| User Content → Photos or Videos | Profile/circle photos, blessing photos/video/previews | App functionality |
| User Content → Audio Data | Submitted voice blessings/responses/video audio | App functionality |
| User Content → Other User Content | Posts, transcripts, Bible references, replies, report reasons/details, circle names/settings | App functionality |
| Sensitive Info | Faith-related posts and Bible references can reveal religious/philosophical beliefs; posts may also voluntarily contain other sensitive information | App functionality |
| Diagnostics → Performance Data | Opt-in timing/size metrics | Analytics; app functionality |
| Diagnostics → Other Diagnostic Data | Opt-in error categories and short codes, build and session identifier | Analytics; app functionality |

Do not claim “Data Not Collected,” “not linked,” or that a random session code makes the account-linked reports anonymous. Optional diagnostics are disclosed even though users can decline. Operational IP/request logging at Supabase, Cloudflare and Apple must be reconciled against their active service settings; do not add precise/coarse location collection merely because an IP exists without assessing actual use. Support received outside the app and occasional user-initiated support may have separate Apple disclosure exceptions; inspect the actual final questionnaire rather than guessing.

## Saved App Store Connect result

On November 2, 2026, the owner confirmed Apple's final accuracy/compliance attestation. The ten categories above were configured as account-linked, with no tracking; User ID and both diagnostic categories include analytics as well as app functionality. The responses were **published**, replacing the incorrect “Data Not Collected” declaration. App Store Connect confirmed “Published a few seconds ago by Micah Lai.” The production privacy URL is `https://manna-circle.micahlai.com/privacy`. The release draft was changed to **0.5.0**, its support URL saved, and availability restricted to **United States only**. This does not submit or release the app. Local proof is in `build/app-store-privacy-published.png`, `build/app-store-version05.png`, and `build/app-store-us-only.png`.

Read-only Chrome verification on November 3 confirms the same ten published account-linked categories/purposes and privacy URL, plus United States-only availability. The current audit also found an omitted direct Bible-text API provider in the privacy inventory; reconcile that request path and API-specific practices before treating the inventory as complete. See the newest [release audit](RELEASE_CHECKLIST.md).

## Submission verification

- Compare these answers to the generated Xcode privacy report, app/extension/SDK manifests, provider configuration and public policy.
- Privacy policy URL: the production website's `/privacy`; accessible before account sign-in and in User settings.
- Reconcile actual first-party account collection and third-party processors (Supabase/Cloudflare/Apple). Cloudflare R2 is a server provider, not a bundled iOS SDK.
- Store purpose strings describe optional, point-of-use access. Photo selection uses the system picker; Photos add permission is only for export.
- Complete these answers in App Store Connect and verify the saved result before submission. The saved/published result above was verified in the actual App Store Connect UI; reconcile it again if practices change.
- The current signed candidate is **0.5.3 (50)** for the app and both extensions. The published-answer record describes the saved App Store Connect state on November 2 and its November 3 read-only confirmation; it does not certify a selected build or reconcile the differing draft/TestFlight/local versions.

## Retention rollout gate

The owner approved and the app/backend implement 30-day removal of blessing audio/video and response audio, retaining text/transcripts/Bible references/photos. Production cleanup remains intentionally disabled pending actual updated-build availability plus 72 hours. The public policy discloses that pause and saving limits. Publication of privacy answers does not activate deletion. Record availability and complete the guarded rollout in [MEDIA_RETENTION.md](MEDIA_RETENTION.md); account-requested deletion is separate.
