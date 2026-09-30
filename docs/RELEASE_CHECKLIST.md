# Release checklist

This checklist separates work that can be proven locally from work that needs production Apple or Supabase access.

## Locally verifiable

- [x] App and widget compile with blank Supabase configuration.
- [x] Deterministic local repository remains available to previews, tests, and simulator UI tests.
- [x] Unit and UI coverage exercises the primary Today and Timeline paths.
- [x] Privacy manifests are included in both app and widget targets and pass `plutil` validation.
- [x] Draft App Store review notes identify permissions, review flow, and blockers.
- [ ] Supply the final app icon and capture release-candidate screenshots.
- [ ] Finalize customer-facing privacy policy, support page, store description, age rating, and localization.

## Apple Developer and physical-device validation

- [ ] Enable and validate Sign in with Apple, Push Notifications, Live Activities, and App Groups for release identifiers and profiles.
- [ ] Verify push-to-start/update/end, Dynamic Island, lock screen, notification privacy, and background behavior.
- [ ] Verify camera, microphone, speech recognition, audio playback, video playback, denial/recovery, and interruption handling.
- [ ] Complete VoiceOver, Increased Contrast, Reduce Motion, Dynamic Type, orientation, iPad, and small-phone checks.
- [ ] Verify widget snapshot sharing, refresh cadence, and every deep-link destination.

## Hosted Supabase validation

- [ ] Complete the two-account acceptance matrix for authentication, circles, RLS, realtime, Storage, RPCs, and gating.
- [ ] Validate randomized scheduling, retry/idempotency, invalid-token cleanup, and observability.
- [ ] Implement and validate account export, account deletion, media cleanup, and retention controls.
- [ ] Implement and validate abuse reporting and owner member removal.
- [ ] Exercise offline, slow-network, upload interruption, expired signed URL, and service-failure recovery.

## Distribution

- [ ] Archive the signed Release configuration and inspect the privacy report and entitlements.
- [ ] Upload to App Store Connect and resolve validation warnings.
- [ ] Run internal TestFlight, then the planned external cohort.
- [ ] Re-run the acceptance matrix on the candidate build.
- [ ] Complete App Store metadata, review credentials, privacy nutrition labels, and release notes.
