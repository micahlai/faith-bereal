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

## Owner force-notification control

The current circle owner has an **Owner testing** section in Circle settings:

- **Force blessing notification** immediately opens or restarts today's server-authored response window after confirmation.
- In hosted mode, the authenticated request is owner-authorized by the database and the Edge Function sends real APNs alerts and Live Activity start requests to every active registered device in that circle.
- In local demo mode, the same control restarts today's in-memory prompt, clears only the current local user's submission for that prompt, and starts a local Live Activity without contacting APNs.

Launch with `BLESSING_CIRCLE_FORCE_LOCAL=1` for the complete simulator flow. Real multi-account delivery requires a deployed `dispatch-prompts` function with APNs secrets and physical devices registered in the same hosted circle.

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
- forcing a prompt requires the current circle owner and uses that circle's configured response length.

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
