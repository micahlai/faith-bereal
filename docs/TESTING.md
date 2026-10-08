# Testing strategy

## Commands

```sh
xcodegen generate
xcodebuild -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

xcodebuild -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Set `SUPABASE_URL='' SUPABASE_PUBLISHABLE_KEY=''` on simulator build/test commands to force the normal blank-configuration fallback. The UI test also launches with `BLESSING_CIRCLE_FORCE_LOCAL=1`, so it never authenticates with or reads from hosted Supabase.
UI tests set `BLESSING_CIRCLE_SKIP_ONBOARDING=1` so established-screen coverage remains deterministic; omit it to verify the About → Appearance → App Icon → Local Saving → Widget → Join/Create first-run flow. Saving tests supply a unique `BLESSING_CIRCLE_SAVING_TEST_SESSION` in local Debug mode, isolating their temporary archives and preferences from normal simulator data.

## TestFlight candidate

Use an integer build number greater than the latest App Store Connect build:

```sh
TESTFLIGHT_BUILD_NUMBER=2 Scripts/prepare-testflight.sh
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
- the communication-notification identity artwork follows the selected manna icon, including automatic light/dark resolution, and adds a small sender avatar inside the left image without replacing the logo;
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
- a member may submit before or after the response window on the local calendar day they join, but not on a later day unless ordinary late-sharing rules apply.
- blessing edits accept the author before ten minutes, reject other users, and close at the exact ten-minute boundary.
- circle photo changes require the current owner and remain isolated to the selected circle.
- profile and circle photo crop output is always a square bounded JPEG, including zoom/offset rendering and invalid-viewport rejection; blessing photos retain their original aspect ratio.
- circle activity notification preferences default on and change only the selected membership.
- end-of-day time cannot precede the random range end, the join-day exception cannot open it early, and its visibility gate remains independent from the daily prompt.
- end-of-day entry closes at exactly five hours or the next daily prompt; a timely entry grant still permits completion later, and notification deep links select the evening composer rather than the daily composer.

The transactional database regression suite can run against the linked migrated project without retaining fixtures:

```sh
supabase db query --linked --file supabase/tests/end_of_day_blessings.sql
```

The suite checks independent privacy after midnight, the two entry cutoffs, late daily sharing, entry grants, per-membership notification preferences, schedule validation, and anonymous RPC denial. It creates temporary test users and circles inside a transaction and rolls them back.

## Integration tests

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

- Today remains at a stable resting bottom position through timer ticks and repeated up/down scrolling; response drafts survive;
- guided circle setup validates the name, preserves Back navigation, explains each setting, and creates only after review;
- Help opens from the app menu and its topic menu switches directly between features;
- first Save blessing explains device-only storage; Save/Unsave updates the detail control and Timeline label;
- automatic saving is offered in setup and Settings; disabling shows all four keep choices, supports selection and Cancel, and keeps the toggle on until a choice is committed;
- automatic preference/account isolation, all/mine/none/selected filtering, conversion to manual, preserving pre-existing manual saves, cross-circle visibility locks, individual unsave exclusions, and atomic refresh failure;

- first-run onboarding can move About → Appearance → App Icon → Local Saving → Widget, move backward without losing choices, and finish into the joined/no-circle app state;
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

- Save photo/video to Photos handles add-only permission, denied access, and playable exports;
- saved audio/video and response audio play after a 30-day hosted expiry; expired Unsave warns and removes only that account's archive;

- push-to-start, update, and explicit end Live Activity;
- no-late deadline and submission dismissals occur at terminal event + three minutes, while late-enabled activities stay visible until submission or replacement;
- an HTTPS invitation opened from Messages launches the installed app, preserves the code through sign-in/onboarding, and joins only after user confirmation;
- Dynamic Island compact/minimal/expanded layouts;
- lock-screen Live Activity circle name, prompt copy, `m:ss to respond` countdown, and immediate submitted state without changes to Dynamic Island;
- lock-screen privacy settings;
- logo-plus-sender-avatar left artwork, circle-oriented title, photo/video-only right attachment, and locked/unlocked copy on a two-account physical-device circle; iOS's separate app-icon badge remains system-owned;
- one opted-in end-of-day reminder arrives without starting a Live Activity, opted-out members receive none, and the window closes after five hours or the next daily prompt;
- background video upload interruption;
- speech transcription latency and audio-session interruption.
- voice capture produces a playable audio file after permission grant, interruption, stop, and relaunch;
- camera capture presents, records, returns a playable file, and recovers from denial or interruption.
