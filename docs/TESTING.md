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

## Debug notification and daily prompt controls

Debug builds add a **Developer testing** section at the bottom of User settings:

- **Send test notification** schedules a local, time-sensitive notification after five seconds. Background the app before it fires. Tapping it follows the same `blessingcircle://today/capture` route as the production APNs alert.
- **Start daily blessing test** restarts today's prompt when the app is using `LocalBlessingRepository`, clears only the current local user's submission for that prompt, opens the full capture flow, and starts a local Live Activity.
- With a hosted Supabase session, the daily control is preview-only: it exercises the Today timer and Live Activity but disables sharing. This preserves server-authoritative prompt timing and never writes test state to the hosted database.

Launch with `BLESSING_CIRCLE_FORCE_LOCAL=1` when a complete debug submission flow is needed. These controls are compiled out of Release builds.

Use an available simulator name from `xcrun simctl list devices available` if the example device is unavailable.

## Unit tests

- deadline boundary: just before, exactly at, and after `ends_at`;
- current-day gating versus historical visibility;
- duplicate submission rejection;
- deterministic timeline grouping and missed-state generation;
- invite-code normalization;
- countdown formatting and prompt-state transitions.
- repeat eligibility uses the target circle's window and the original submission time;
- repeat choices exclude expired, same-circle, and other-user blessings;
- ownership transfer requires the current owner and a current target member;
- member removal requires the current owner, rejects self-removal, and removes only the selected membership;
- historical details cannot author responses while current-day details can.
- widget selection covers active, current-day, prior-day, empty, and prompt-boundary refresh states.
- selected photos are normalized into stable local JPEG files instead of depending on temporary picker URLs;
- text and voice blessings accept an optional photo, while video blessings reject a separate photo attachment.
- restarting a local debug prompt resets the current user's submission and reopens a server-shaped response window without changing peer history.

## Integration tests

- create and join circle with two accounts;
- switch between multiple memberships and verify prompt/timeline isolation;
- leave as a member, leave as an owner with successors, and delete an owner-only circle;
- storage upload/finalize and abandoned-upload cleanup;
- RLS attempts across circles and before/after posting;
- realtime insert arrives only after visibility becomes legal;
- APNs dispatch retries remain idempotent.
- one client receives realtime inserts after the other submits;
- scripture text is rendered in the viewer's translation while only the reference is stored;
- response RLS follows the parent blessing's visibility.

## UI and accessibility checks

- small and large iPhone, iPad split view, portrait and landscape;
- light/dark appearance, Increased Contrast, Reduce Motion;
- Dynamic Type through accessibility sizes;
- VoiceOver order, labels, actions, and locked/missed announcements;
- keyboard avoidance and every touch target at least 44 points;
- camera/voice permission denial and recovery paths.

## Device-only checks

- push-to-start, update, and explicit end Live Activity;
- Dynamic Island compact/minimal/expanded layouts;
- lock-screen privacy settings;
- background video upload interruption;
- speech transcription latency and audio-session interruption.
- voice capture produces a playable audio file after permission grant, interruption, stop, and relaunch;
- camera capture presents, records, returns a playable file, and recovers from denial or interruption.
