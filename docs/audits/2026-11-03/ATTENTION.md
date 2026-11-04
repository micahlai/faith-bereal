# Attention and changes before public launch

Audit date: November 3, 2026. Baseline: c44c1cc, local signed 0.5.3 (50). Public submission remains on hold. This list distinguishes demonstrated mismatches, operational work, decisions and missing acceptance; an untested flow is not automatically a broken feature.

## Backend capacity and operations

- [ ] Resolve the prior-cycle Supabase overage and November 17 restriction warning. Select a capacity plan for up to 100 active users; the current Free allowance does not fit the illustrative media workload.
- [ ] Measure real bytes/post, unique downloads, active days and peak concurrent submissions in staging. One 5 MB recording/user/day would produce 15 GB/month per provider and approximately 150 GB Supabase recording egress with nine peer downloads/post plus the mirror copy. This is a scenario, not measured usage.
- [ ] Establish database backups, retained-media recovery points and a tested restore procedure. The dashboard lists no database backups. R2 copies propagate deletions and do not back up the database.
- [ ] Align the global 50 MB upload cap, 75 MiB bucket/local configuration, client byte-size preflight, failure messages and recovery. The largest current media object is 47.4 MB. Update matching Help/tests if customer behavior changes.
- [ ] Investigate/monitor downstream dispatch timeouts: two of 360 retained HTTP calls timed out while all cron jobs reported success. No stuck/overdue prompt was found. Add external alerts for dispatch/APNs errors, quota pressure, oldest mirror/deletion retries and retention failures.
- [ ] Record actual updated-build availability, then schedule the approved +72-hour retention grace. Keep cleanup disabled until the gate is satisfied; export/upload alone is not availability. Verify source/R2 cleanup and retry monitoring after activation.
- [ ] Complete abandoned-upload cleanup and separate retention schedules for backups, provider logs and safety records. Photos/text and permanent device archives are unbounded; account for their growth.
- [ ] Decide whether historical R2 backfill is needed and document its scope. Only nine current desired mirror jobs are represented; all app reads still use Supabase. Moving reads to R2 would be separate authorization-sensitive work, not an assumed bandwidth saving.

## Privacy, safety and content

- [ ] Review the Bible API's specific privacy/logging practices; add the direct provider to the public/in-app inventory where appropriate. Requests expose passage/translation and ordinary network metadata, without app account tokens or post bodies.
- [x] Review Bible edition rights and reconcile Content Rights: owner chose Yes, saved/verified in Chrome. The 0.6.0 candidate retains 12 public-domain editions; [evidence and exclusions](../../BIBLE_CONTENT_RIGHTS.md).
- [ ] Integrate/release that catalog, deploy its preference migration and update the public provider disclosure. Older installed builds keep their prior catalog until updated.
- [ ] Reassess Messaging/Chat = No against text/voice replies and Apple's definitions. Check the saved age answers and older-OS rating against the actual 13+ admission flow; keep intended US-only availability.
- [ ] Assess limited phrase filtering and immediate unscreened photo/audio/video publication against Apple's UGC requirements. Report/block/contact and daily operator review already exist; determine whether additional filtering is needed and demonstrate operator response. Mandatory prepublication approval was removed by the owner and is not proposed for reinstatement here.
- [ ] Reconcile the final candidate, public policy, in-app Help/inventory and published privacy answers. Finish or explicitly resolve the project's promised user-data export and per-post/departed-member history policy. Export is a project commitment, not a universal App Store requirement.

## App Store submission inputs

- [ ] Resolve version/build provenance: draft 0.5.0, uploaded TestFlight 0.5.3 (49), locally validated 0.5.3 (50). Choose the exact review candidate, install it through TestFlight and select it in the matching release draft.
- [ ] Supply required iPhone/iPad screenshots; checked slots were empty. Marketing header/search creative does not replace app screenshots.
- [ ] Complete description, keywords, copyright, primary category, pricing schedule and review contact/notes. Confirm final name/subtitle, URLs and release notes.
- [ ] Prepare a safe reviewer sign-in/circle path with controllable prompt timing and clear instructions. The local demo does not establish production behavior for App Review.
- [ ] Validate Apple-silicon Mac availability or choose the intended scope. Confirm iPad support and the actual Vision Pro availability state. Coordinate automatic release-after-approval with retention availability/grace scheduling.
- [ ] Artwork remains paused. Search creative was uploaded; the final safe-header replacement was not verified. Check its state only when artwork work resumes. Preserve current local originals/previews and Chrome evidence.

## Frontend automation and physical acceptance

- [ ] Add UI coverage for report reasons/details/send/failure/cancel, block/unblock, deletion acknowledgement/pending/status/error/retry and largest-text layouts. In particular, inspect the unscrolled account-deletion-pending screen on a small phone; this is a source-review risk, not a demonstrated failure.
- [ ] Complete one uninterrupted isolated full UI run and investigate the intermittent large-text photo-reveal assertion. All 47 existing cases have passing observations across runs; the original run still contains one failure and an interrupted final case. Do not report it as a single clean suite.
- [ ] Test real Apple sign-in/cancellation/reauthentication/revocation/deletion with a disposable physical Apple-linked account, including both-provider absence and completion state.
- [ ] Test two installed accounts through join/leave/removal/ownership transfer, shared settings, daily/evening locks, peer unlock after own post, responses/media, report/block, realtime and stale/offline recovery.
- [ ] Test camera/microphone/Speech/Photos denial and recovery; real capture/transcription/playback/export; interruptions/backgrounding; poor connectivity, oversized/failed uploads, low storage and automatic-save limits.
- [ ] Verify production push privacy/delivery, notification denial, ready-circle badges, Live Activity start/update/end, widget refresh/deep links and real invite Universal Links on devices.
- [ ] Resolve the rendered Share-button contrast finding and complete VoiceOver, largest text, Reduce Motion, iPad/split view, landscape and supported iOS acceptance. Current native audits check hit regions/descriptions and do not prove rendered contrast.
- [ ] For external coverage, prepare a separate signed synthetic-data XCUITest app/runner for a real-device service such as BrowserStack, with accessibility and visual checks. No external service signup, upload or paid run has occurred.

Evidence and limits: [release checklist](../../RELEASE_CHECKLIST.md), [backend report](BACKEND_READINESS.md), [frontend report](FRONTEND_READINESS.md), and aggregate-only [backend evidence](backend-evidence/). Large Xcode result bundles and raw logs remain local under build/.
