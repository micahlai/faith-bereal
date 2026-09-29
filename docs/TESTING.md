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

Use an available simulator name from `xcrun simctl list devices available` if the example device is unavailable.

## Unit tests

- deadline boundary: just before, exactly at, and after `ends_at`;
- current-day gating versus historical visibility;
- duplicate submission rejection;
- deterministic timeline grouping and missed-state generation;
- invite-code normalization;
- countdown formatting and prompt-state transitions.

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
