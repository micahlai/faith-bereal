# Testing strategy

## Commands

```sh
xcodegen generate
xcodebuild -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  SUPABASE_URL= SUPABASE_PUBLISHABLE_KEY= \
  build

xcodebuild -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  SUPABASE_URL= SUPABASE_PUBLISHABLE_KEY= \
  test
```

Pass `SUPABASE_URL= SUPABASE_PUBLISHABLE_KEY=` as **xcodebuild build-setting arguments**, not just shell environment assignments, on simulator build/test commands to force the normal blank-configuration fallback even when the ignored Secrets.xcconfig is present. The UI test also launches with `BLESSING_CIRCLE_FORCE_LOCAL=1`, so it never authenticates with or reads from hosted Supabase. Do not blank these settings for Release builds.
UI tests set `BLESSING_CIRCLE_SKIP_ONBOARDING=1` so established-screen coverage remains deterministic; omit it to verify the About → Your Profile → Appearance → App Icon → Local Saving → Widget → Join/Create first-run flow. Saving tests supply a unique `BLESSING_CIRCLE_SAVING_TEST_SESSION` in local Debug mode, isolating their temporary archives and preferences from normal simulator data.

## TestFlight candidate

Use an integer build number greater than the latest App Store Connect build:

```sh
TESTFLIGHT_BUILD_NUMBER=32 Scripts/prepare-testflight.sh
```

The workflow regenerates the project, runs the complete local-demo unit and UI suites as separate Xcode test phases on the reliable small-phone default, archives the hosted Release configuration, exports an App Store Connect IPA, and validates production APNs, `get-task-allow = false`, Sign in with Apple, the shared App Group, both embedded extension signatures, and the notification-logo resource. Separate phases avoid an Xcode worker handoff stall after ActivityKit unit coverage. Override the test device with `TESTFLIGHT_SIMULATOR_NAME='another installed simulator'` when needed. Release builds fail immediately when the hosted Supabase URL/key or production APNs setting is missing; Debug and simulator development retain the local-demo fallback.

### Xcode Cloud

Add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` to the workflow Environment section and mark both values as secret. For Xcode Cloud archive actions, `ci_scripts/ci_post_clone.sh` validates those variables and writes the ignored `Configuration/Secrets.xcconfig` into the temporary checkout using xcconfig-safe URL syntax. Non-archive actions do not create the file, preserving the local-demo behavior for Debug builds and tests. Xcode Cloud manages distribution signing and may send a successful archive to TestFlight through the workflow's distribution post-action.

## Owner force-notification control

The current circle owner has an **Owner testing** section in Circle settings:

- **Force blessing notification** immediately opens or restarts today's server-authored response window after confirmation.
- In hosted mode, the authenticated request is owner-authorized by the database and the Edge Function sends real APNs alerts and Live Activity start requests to every active registered device in that circle.
- In local demo mode, the same control restarts today's in-memory prompt, clears only the current local user's submission for that prompt, and starts a local Live Activity without contacting APNs.

Launch with `BLESSING_CIRCLE_FORCE_LOCAL=1` for the complete simulator flow. Real multi-account delivery requires a deployed `dispatch-prompts` function with APNs secrets and physical devices registered in the same hosted circle.

Use an available simulator name from `xcrun simctl list devices available` if the example device is unavailable.

## Unit tests

- Backend optimization fixtures inject an isolated HTTP transport/auth store and synthetic data. They compare metadata/page request counts, re-read content to unlock peers, propagate denied reads, and preserve local repository fallback behavior. They do not emulate server RLS or establish hosted latency improvement.
- Scope tests suspend reads and change account/circle/time zone away and back before delivery; stale results must never install. Interrupted switching restores the original realtime subscription. Diagnostics tests check a closed payload vocabulary, opt-in behavior, HTTP failure/cancellation classification, and exclusion of private URLs, headers, bodies, and error descriptions.

## Backend diagnostics capture

For v0.2.2 (32) field testers, Share diagnostic data defaults on for a new account/device. Explicit choices and legacy saved off settings are preserved. Check User settings → Field testing to verify the switch or disable sharing. The in-app setting persists without an Xcode environment variable, collects a bounded private queue, and uploads authenticated batches while active. Opt-out clears unsent metrics. See [tester setup, operator summaries, retention, and limits](TESTFLIGHT_FIELD_TESTING.md).

Add `MANNA_BACKEND_DIAGNOSTICS=1` to the Xcode Run scheme's environment variables only for optional local OSLog capture. Leave it absent for normal runs. This enables local OSLog events under subsystem `app.manna-circle.ios`, category `BackendPerformance`, prefix `backend_metric`. Use Console with the attached phone selected and filter to that category; retain only those event lines when preparing a performance comparison. The environment variable alone does not opt into remote collection or persist to TestFlight; the in-app switch controls remote sharing separately.

For local simulator stage capture after installation:

```sh
SIMCTL_CHILD_BLESSING_CIRCLE_FORCE_LOCAL=1 SIMCTL_CHILD_MANNA_BACKEND_DIAGNOSTICS=1 \
  xcrun simctl launch booted app.manna-circle.ios
xcrun simctl spawn booted log show --last 10m --style compact --info \
  --predicate 'subsystem == "app.manna-circle.ios" AND category == "BackendPerformance"'
```

Local mode has stage timings but no Supabase HTTP traffic. To reproduce the reported service error, use the hosted-configured measurement build on a phone. Record cold/warm startup, several sequential switches, and representative typed/photo/voice/video sends with UTC action/error timestamps. Use ordinary bounded interactions. Compare stage median/tail durations, SDK-operation category counts, payload/returned-data sizes, outcome/error counts, and widget/archive overlap under the same account/circle/media conditions. Stage spans can overlap; Operation records have no account/action identifier, so timestamp overlap is a correlation aid rather than exact attribution. Available success HTTP status/numeric transport codes do not include Postgres/API error bodies; obtain the exact service error separately before diagnosing pool exhaustion.

For a previously signed-in account, visible-startup timing begins after reading the local cached identity and restoring the collection setting, before the initial session validation/refresh, and ends when the model marks the screen ready; it is not first-frame/full cold-launch/permission/capture latency. Upload-preparation timing covers the prompt read; encoding/compression comparisons and peak memory remain physical-device work. Operation durations include SDK retries and auth adaptation; counts are logical SDK calls rather than physical HTTP attempts. Upload payload size is the original file/data size, not bytes proven to have transferred; database returned-data size excludes transport headers. The SDK consumes many error HTTP responses, so their status is unavailable; Auth/Storage/functions do not expose success status through these wrappers. The initial session validation/refresh is measured as an auth operation. Automatic background auth refresh, local cached-identity reads, realtime socket traffic, scripture fetching and archive network downloads are outside the operation counter. Remote audio/video playback downloads and temporary photo-cache misses are measured; cache hits generate no network request event; asset/player/audio-session/local staging failures add sanitized failure events. New voice recordings use AAC in M4A for both single and multiple segments; previously uploaded files are unchanged. These logs do not demonstrate a fix for database connection exhaustion.

## Traffic reduction verification (2026-10-22)

- `MediaDownloadCacheTests` checks persistent account separation, signed-token renewal, concurrent download coalescing, sign-out fencing, protected/no-backup storage, seven-day expiry, bounded eviction, and failed HTTP retries. A played-then-saved fixture rejects remote copying and verifies that its permanent archive survives temporary-cache removal. Playback fixtures check a reopened recording uses the disk cache and stages a separate playable local file. Permanent archives remain separate and win before any remote link signing.
- `BackendOptimizationTests` counts actual injected transport calls: repeated authorized pages reuse signing results, and complete saved media skips signing altogether. `IdentityPhotoCacheTests` checks token-only renewal versus changed photo metadata versions.
- `CachedCircleLoadingTests` checks shared bounded widget/saving reads, explicit fresh refresh, unchanged archived response-body suppression, missing-file retry, default Wi-Fi gating, manual saving on cellular, per-account options, older-history paging, and return-to-Wi-Fi recovery.
- `TrafficMediaPreparationTests` exports real synthetic 1080p video and confirms playable MP4 output capped at 720p with retained duration; photo previews fit within 480 pixels without replacing originals. Failed export retains the source. Physical-device quality, battery, and upload-size measurements remain field work.
- Four focused UI cases cover new switches/persistence at normal/largest dark text, keep-choice cancellation, photo zoom, and offline saved legacy audio after cold launch/relaunch. Inspect attachments for wrapping; accessibility switches stack below full-width labels.
- `Scripts/test-reuse-and-invites.sh` applies the photo-preview helper locally and verifies Storage visibility plus reused-preview access. `supabase/tests/photo_preview_visibility.sql` is a separate rollback-only hosted-safe helper test (no Storage API or dispatch); do not run the local Storage fixture scripts against hosted data.
- Request-count and media fixture checks establish these paths' behavior, not a measured reduction in production GB or sustainable usage at unchanged tester activity. Compare daily bytes per active session, played recording, and new post after distributing the next build.

## Domain coverage

- Timeline filtering checks List as the default, All/person indexes ordered by actual timestamps, joining events, exclusion of locked/missed/waiting/scheduled placeholders, missing/removed selections, and rebuilt older/new pages. Response-summary regressions check visible-card batching (40 IDs per query), duplicate responses versus unique authors, empty caching, retry/expiry/eviction, cancellation, scope invalidation, and lightweight hosted transport with no blessing-body or Storage calls. Synthetic fixture assertions do not establish a physical-device frame-rate or field-latency improvement.
- Focused Timeline UI checks cover the wide layout control, List-only filters, Threads keeping all lanes, circle reset, refresh persistence, response counts/photos, detail opening, normal/largest dark text with Reduce Motion, and landscape. `--manna-timeline-ui-test` seeds three local text responses by two people only in explicit Debug local UI mode.

- Independent streak regressions cover mixed 5/3 counts, random-only timely entry, evening-only general credit, same-day deduplication, exact separate deadlines, missing/scheduled prompts, overnight windows, next-random cutoff, membership, DST, and fresh displayed metadata after posting/reuse. `Scripts/test-independent-streaks.sh` verifies the four-column predecessor upgrade, safe grants, bounded-calendar equivalence to an unbounded reference, and sparse/dense history; `Scripts/test-shared-circle-settings.sh` also checks the five-column predecessor; its `--streak-first` mode proves the pending settings migration preserves an already deployed six-column successor. `independent_streak_deadlines_hosted.sql` is bounded, uses random fixtures, and rolls back; no dispatch/Storage API is invoked. Synthetic normal/largest-dark UI cases verify profile count/color, both Circle pills, zero visibility, popup counts, and 44-point targets.
- Media demand/saving regressions verify idle players make no voice download, Play downloads once and replay reuses it, saved voice playback bypasses the downloader, saved audio/video/photos/responses win before and after expiry, and archive refresh/relaunch reuses existing files despite changed remote URLs while downloading only new response media. Single and mixed-route voice segment tests verify compressed AAC/M4A output and retained duration.
- Playback regressions use local real CAF/AAC files and an injected download transport: 403/503 status privacy, silent URL cancellation, refreshed URLs/cache invalidation, stale success/failure fencing, unreadable bytes, and preserved M4A containers. Voice-assembly fixtures finalize writers and verify both source durations before checking combined duration. They do not reproduce the owner's physical-device failure or establish database pool saturation.
- Shared circle settings default off, retain legacy snapshots as leader-only, and authorize edits against fresh membership/permission state. Test off/on/off settings, invite rotation, photos, force notification, ordinary-member removal, outsider denial, leader-only permission/transfer, protected leader/self removal, and revoked permissions despite stale client metadata. `Scripts/test-shared-circle-settings.sh` runs disposable SQL/Storage checks and a concurrent revocation case; it does not deploy the pending migration.
- Streak explanations display the normal and independent consecutive timely-entry runs. Timely entry, late-entry breaks, gaps, daily/evening deduplication, and today's unfinished-day grace are covered. Focused UI checks verify the flame's anchored popup and attached-photo-only enlargement.
- Nudges require the sender's submission for the exact prompt, two current distinct members, and an unsubmitted recipient. Scheduled, no-late deadline, seven-hour evening deadline, circle-local midnight, next daily cutoff, same-prompt privacy, and one nudge per recipient/prompt are checked. Local mode never contacts APNs.

- Reuse preserves capture format, audio/photo/video/thumbnail and scripture; no responses are copied. Receiving-circle media respects the target privacy gate even for people outside the original circle.
- Invite hints survive store recreation/app updates, remain account/circle-isolated, and are validated by the server. Active members recover stored codes; legacy backfill never rotates, stale hints never restore a rotated code, removed members/outsiders cannot read codes.
- Timeline presentation omits unstarted/future prompts; underlying scheduled status never becomes open/missed just because a scheduled target elapsed. Early peer content stays gated. Welcome posts project to actual sent dates without changing prompt identity; List orders actual events and has no placeholder rows.
- Circle streaks cover distinct days, regular/evening deduplication, late counting, timely-entry recognition despite a late send, gaps, per-circle/member isolation, local calendars/DST, and welcome exclusion. Hosted metadata RPC tests reject outsiders/anonymous callers and do not expose blessing content.
- Timeline pages preserve complete days, membership markers, merged event identity, circle/account/time-zone scopes, and bounded zoom. Latest refreshes retain loaded older pages; old widget links fetch a single permitted detail when outside the loaded pages.
- Draft tests cover atomic media checkpoints, store recreation, account isolation, failed media-copy preservation, expiration, delayed checkpoints after sending, and independent working-media survival after saved-draft expiry. Resume rejects closed no-late windows even with an existing entry grant. Voice wake-lock leases restore normal sleep after the last recorder stops.

- Blessing text/transcript and edits accept 600/601/1,199/1,200 and reject 1,201; Unicode-scalar counters match PostgreSQL, and truncation preserves complete combined emoji/accents. All three local capture modes share this policy. Response limits remain 600.
- media-retention boundaries at 28/30 days, account-isolated archive save/reload/unsave, response timestamps, atomic partial-download failure, and media restored through local Timeline playback;
- Help catalog completeness and customer-facing explanations of saving, privacy, and deadline rules;

- deadline boundary: just before, exactly at, and after `ends_at`;
- an on-time entry grant permits completion after `ends_at` and after midnight while preserving the original prompt/day; without a grant, a no-late prompt rejects entry at the deadline;
- current-day gating versus historical visibility;
- duplicate submission rejection;
- deterministic timeline grouping and missed-state generation;
- server-precreated future prompts never render as missed Timeline rows;
- invite-code normalization;
- countdown formatting and prompt-state transitions.
- Universal invitation construction/parsing, unsafe-host rejection, and invitation persistence through bootstrap;
- circle-local prompt dates remain on their stored calendar day in western time zones;
- Live Activity APNs state remains backward compatible and encodes its exact three-minute terminal dismissal timestamp;
- notification copy preserves the locked-content gate, formats scripture references on a second line, uses “New blessing in [circle]” / “[circle]” titles, and selects right-side media in video-frame → attached-photo order with no avatar fallback;
- the communication-notification identity artwork fills the left image with the sender's profile photo, independently of logo availability; missing/invalid avatars fall back to the selected manna icon;
- cancelled row-level response loads are classified as cancellation and do not surface a user-facing error;
- circle creation preserves every selected setting and creates the current local-day prompt from the selected time zone, range, and response duration;
- invite-code regeneration requires the owner and immediately invalidates the previous code;
- repeat eligibility uses the target circle's window and the original submission time;
- repeat choices exclude expired, same-circle, and other-user blessings;
- ownership transfer requires the current owner and a current target member;
- member removal requires the current owner, rejects self-removal, and removes only the selected membership;
- historical details cannot author responses while current-day details can.
- widget selection covers active, current-day, prior-day, empty, and prompt-boundary refresh states.
- selected photos are normalized into stable local JPEG files instead of depending on temporary picker URLs;
- text and voice blessings accept an optional photo, while video blessings reject a separate photo attachment.
- restarting a local debug prompt resets the current user's submission and reopens a server-shaped response window without changing peer history.
- forcing a prompt requires the current circle owner and uses that circle's configured response length.
- Before today's start, welcome entry targets yesterday and ends at today's start. After today's start, join-day entry targets today and ends at circle-local midnight. Retained entry grants preserve the original date when completing later; tests include a 25-hour DST day.
- blessing edits accept the author before ten minutes, reject other users, and close at the exact ten-minute boundary.
- circle photo changes require the current owner and remain isolated to the selected circle.
- profile and circle photo crop output is always a square bounded JPEG, including zoom/offset rendering and invalid-viewport rejection; blessing photos retain their original aspect ratio.
- circle activity notification preferences default on and change only the selected membership.
- end-of-day time cannot precede the random range end, the join-day exception cannot open it early, and its visibility gate remains independent from the daily prompt.
- end-of-day entry closes at exactly seven hours or the next daily prompt; a timely entry grant still permits completion later, and notification deep links select the evening composer rather than the daily composer.

The transactional database regression suite can run against the linked migrated project without retaining fixtures:

```sh
supabase db query --linked --file supabase/tests/end_of_day_blessings.sql
```

The suite checks independent privacy after midnight, the two entry cutoffs, late daily sharing, entry grants, per-membership notification preferences, schedule validation, and anonymous RPC denial. It creates temporary test users and circles inside a transaction and rolls them back.

For blessing length validation, run `bash Scripts/test-blessing-character-limit.sh` with local PostgreSQL tools installed. It starts a disposable database, applies the real limit migration, and tests typed/voice/video submission and edits at the old/new boundaries, Unicode length, direct-table enforcement, RPC grants, and unchanged 600-character responses. Its entry predicate is a fixture, not full hosted membership/RLS coverage. Do not run `blessing_character_limit_schema.sql` against any existing database.

After deployment, `npx --no-install supabase db query --linked --file supabase/tests/blessing_character_limit_hosted.sql` checks the actual hosted create/submission/edit RPCs and guards using temporary transaction-scoped users/circles. Fixtures, posts, and notification queue events roll back; no dispatcher, cleanup worker, or Storage API runs. It tests RPC authorization rules but is not a complete authenticated-role RLS test.

## Integration tests

For isolated reuse/invite/nudge regressions run `bash Scripts/test-reuse-and-invites.sh`. It applies the real feature migrations and existing media-retention/length/outbox migrations against a disposable PostgreSQL fixture, loading the actual creation/join/rotation/visibility/entry functions. It verifies typed/voice/video media reuse, active-member code recovery and explicit rotation, the actual Storage SELECT policy, and nudge queue/dispatch authorization and timing. Submission timing is a minimal fixture, not full hosted entry-grant coverage. Never run the schema fixture or the Storage fixture against hosted Supabase. `reuse_blessing_media.sql`, `durable_circle_invites.sql`, and `circle_nudges.sql` are separate transaction/rollback RPC tests suitable for an already migrated linked project; they leave no users/circles/posts/notification events behind and never invoke Storage or a dispatcher.

The same disposable suite loads `202610130001_circle_streaks.sql` and its regression. After that migration is deployed, `npx --no-install supabase db query --linked --file supabase/tests/circle_streaks.sql` runs the actual metadata RPC under authenticated roles with temporary fixtures and rolls everything back. Deploy the streak migration before releasing the client which calls this RPC.

- create and join circle with two accounts;
- switch between multiple memberships and verify prompt/timeline isolation;
- leave as a member, leave as an owner with successors, and delete an owner-only circle;
- storage upload/finalize and abandoned-upload cleanup;
- RLS attempts across circles and before/after posting;
- realtime insert arrives only after visibility becomes legal;
- APNs dispatch retries remain idempotent.
- a peer blessing sends locked copy before the recipient posts and blessing content afterward; response alerts reach the blessing author and prior responders but never the new responder.
- one client receives realtime inserts after the other submits;
- scripture text is rendered in the viewer's translation while only the reference is stored;
- response RLS follows the parent blessing's visibility.

## UI and accessibility checks

- A typed draft survives closing/relaunching the app, resumes through the single primary Continue action on Today with its contents intact, and disappears after successful sending. Use one unique local test session across both launches.
- Blessing composer accepts 1,200 characters, clamps a 1,201-character input, displays the new counter, and sends successfully in local demo mode.
- Native automated accessibility audits check hit regions and descriptions in Today and Timeline List, with a repeat after scrolling. Rendered contrast remains a manual acceptance requirement: the small-phone native contrast audit still flags the Share button despite its numerically passing solid foreground/background pair (see the audit document). The audit test explicitly terminates any existing instance and supplies a Debug-only `--manna-local-ui-test` argument as an additional local-backend fence.
- Timeline defaults to a single-column List with VoiceOver or accessibility text sizes; its toolbar can switch back to Threads without increasing pinned-header spacing.
- Actual asset contrast tests cover both appearances and Increased Contrast, including action fills and selected verse cells. See `docs/ACCESSIBILITY_AUDIT.md` for the support matrix and physical common-task acceptance checklist.

- Today remains at a stable resting bottom position through timer ticks and repeated up/down scrolling; response drafts survive;
- guided circle setup validates the name, preserves Back navigation, explains each setting, and creates only after review;
- Help opens from the app menu and its topic menu switches directly between features;
- first Save blessing explains device-only storage; Save/Unsave updates the detail control and Timeline label;
- automatic saving is offered in setup and Settings; disabling shows all four keep choices, supports selection and Cancel, and keeps the toggle on until a choice is committed;
- automatic preference/account isolation, all/mine/none/selected filtering, conversion to manual, preserving pre-existing manual saves, cross-circle visibility locks, individual unsave exclusions, and atomic refresh failure;

- first-run onboarding can move About → Your Profile → Appearance → App Icon → Local Saving → Widget, edit name/photo, move backward without losing choices, and finish into the joined/no-circle app state;
- app-icon onboarding cards use the actual cream/midnight artwork in one column, and the widget guide remains readable at accessibility text sizes;
- circle creation exposes all owner settings before the final create action;
- circle creation exposes the optional photo picker, while Circle Settings confirms before discarding unsaved changes and saves from the top-right toolbar;
- an owner can regenerate an invite code only after acknowledging that the old code will stop working;
- small and large iPhone, iPad split view, portrait and landscape;
- light/dark appearance, Increased Contrast, Reduce Motion;
- Dynamic Type through accessibility sizes;
- VoiceOver order, labels, actions, and locked/missed announcements;
- keyboard avoidance and every touch target at least 44 points;
- camera/voice permission denial and recovery paths.
- timeline member header begins immediately below navigation, stays fixed on vertical scroll, permits avatars over the date-column area on horizontal scroll, and clips body cards below the horizontal divider and behind the full-width date strip.

## Device-only checks

- Voice recording prevents sleep in both blessing and response capture, then restores it on pause/stop/backgrounding. Checkpoint recovery must retain playable audio segments, photo/video, transcript, and scripture after forced termination or upload failure. Verify midnight cleanup cannot remove media from an already-authorized open composer.
- A nudge arrives only for an opted-in unsubmitted recipient, uses sender artwork with no content/media, opens the exact random/evening prompt, and does not start a Live Activity. Closed/completed/removed-member queue events are skipped; offline nudges are not stored for later APNs delivery.

- Save photo/video to Photos handles add-only permission, denied access, and playable exports;
- saved audio/video and response audio play after a 30-day hosted expiry; expired Unsave warns and removes only that account's archive;

- push-to-start, update, and explicit end Live Activity;
- no-late deadline and submission dismissals occur at terminal event + three minutes, while late-enabled activities stay visible until submission or replacement;
- an HTTPS invitation opened from Messages launches the installed app, preserves the code through sign-in/onboarding, and joins only after user confirmation;
- Dynamic Island compact/minimal/expanded layouts;
- lock-screen Live Activity circle name, prompt copy, `m:ss to respond` countdown, and immediate submitted state without changes to Dynamic Island;
- lock-screen privacy settings;
- full sender-profile-photo left artwork (logo fallback), circle-oriented title, photo/video-only right attachment, and locked/unlocked copy on a two-account physical-device circle; iOS's separate app-icon badge remains system-owned;
- one opted-in end-of-day reminder arrives without starting a Live Activity, opted-out members receive none, and the window closes after seven hours or the next daily prompt;
- background video upload interruption;
- speech transcription latency and audio-session interruption.
- voice capture produces a playable audio file after permission grant, interruption, stop, and relaunch;
- camera capture presents, records, returns a playable file, and recovers from denial or interruption.

## Diagnostic error and cached-loading regression coverage

Run `Scripts/test-backend-diagnostics.sh` for old/new ingestion compatibility, strict sanitized error fields, Speech/audio/upload categories, exact retries, account boundaries, retention/quotas, delayed event-vs-receipt timestamps, and the two-connection ingestion race. This uses disposable PostgreSQL only.

`DiagnosticFailureTests`, `SpeechDiagnosticTests`, `CircleMetadataStoreTests`, `IdentityPhotoCacheTests`, and `CachedCircleLoadingTests` cover typed backend connection-limit classification without raw data, callback propagation, priority/bounded queues and exact retries, upload outage deduplication, local expiration/account isolation, image limits/cancelled sign-out, gated startup/switching, stale account completion rejection, and concurrent refresh coalescing. Authentication-backed loading fixtures disable system notification registration and optional background work to isolate foreground loading deterministically. `CachedLoadingUITests` exercises navigation/loading/privacy at normal and largest dark text sizes using an explicit local-only Debug fixture.

## Offline saved archives and legacy voice playback

- Saved archives restore from cached account identity before any session refresh or repository bootstrap, even without circle metadata. Regressions cover unavailable sessions, a suspended server bootstrap, account isolation, explicit sign-out, and late results after sign-out. The ordinary Timeline automatically presents completed saves; local response counts/detail make no backend call. Tests cover circle switching, account isolation, sign-out fencing, locked same-day peers, and disabled edits/responses. Old manifests without prompt dates/time zones use a conservative 26-hour boundary for unpaired peer copies. Offline presentation never authorizes live content or mutations.
- A real CAF file renamed to `.data` reproduces the historical saved-recording failure with zero server calls. Playback now identifies the CAF header and stages local bytes as `.caf`; new saves preserve `.caf` for blessings and responses.
- `--manna-offline-saved-ui-test` is a Debug-only fixture with no valid network session and no circle metadata. It seeds a saved voice blessing and response with legacy `.data` filenames, then reuses the same archive across relaunch. The UI check opens the offline archive and plays both recordings at normal and largest dark text sizes. This fixture does not prove the owner's exact device failure or download transport status.
