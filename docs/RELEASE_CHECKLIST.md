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
- [x] Run the hosted dispatcher once per minute and verify consecutive HTTP 200 responses.
- [x] Recover a real interrupted dispatch and verify the prompt returns to `open`.
- [x] Diagnose the partial APNs result as provider-token rotation throttling and deploy a 45-minute server-only JWT cache.
- [ ] Verify a post-cooldown dispatch has no `TooManyProviderTokenUpdates`, observe alert/Live Activity presentation, and validate Production/TestFlight device tokens.
- [ ] Exercise a permanent APNs token error and verify invalid-token cleanup plus delivery observability.
- [ ] Implement and validate account export, account deletion, media cleanup, and retention controls.
- [x] Implement owner-confirmed member removal in the client, local repository, and server RPC.
- [ ] Deploy and validate member removal with two hosted accounts; implement and validate abuse reporting.
- [ ] Exercise offline, slow-network, upload interruption, expired signed URL, and service-failure recovery.

## Distribution

- [x] Create a generic iOS Release archive and inspect its code signature and entitlements.
- [ ] Export an App Store distribution archive and confirm production APNs, distribution provisioning, and `get-task-allow = false`.
- [ ] Upload to App Store Connect and resolve validation warnings.
- [ ] Run internal TestFlight, then the planned external cohort.
- [ ] Re-run the acceptance matrix on the candidate build.
- [ ] Complete App Store metadata, review credentials, privacy nutrition labels, and release notes.
