# Release checklist

This checklist separates work that can be proven locally from work that needs production Apple or Supabase access.

## v0.2.2 (31) field-testing candidate

- [x] Deploy the private authenticated diagnostics collector and verify its account isolation, validation, quotas, retry idempotency, and cleanup.
- [x] Verify default-off consent persistence and the single draft-aware Continue action in the full 23-test simulator UI suite.
- [x] Complete final Debug/Release suites (206/202 tests) and inspect both rebuilt normal/largest-text screenshot checks.
- [x] Export and validate the hosted-configured v0.2.2 (31) distribution IPA at `build/TestFlight-0.2.2-31/manna circle.ipa`.
- [ ] Upload/process in App Store Connect and assign the intended TestFlight cohort.
- [ ] Match App Store Connect privacy answers to the account-linked performance/diagnostic collection before wider distribution.
- [ ] Run physical multi-account media, privacy, notification, and failure-reproduction acceptance using [the field-testing instructions](TESTFLIGHT_FIELD_TESTING.md).

## v0.2.2 (32) follow-up

- [x] Implement single smaller red/blue streak flames, photo enlargement/zoom, and fixed-horizontal Today.
- [x] Default new field-test account/device queues to on, preserving saved opt-outs and disclosing the setting.
- [x] Pass 215 Debug and 211 Release domain tests, including default-policy, early startup session-failure, streak, and Help regressions.
- [x] Complete final Release and nine distinct focused changed-flow UI cases/screenshots, with final accessibility-tree verification.
- [x] Export and validate a distinct hosted-configured v0.2.2 (32) IPA with the default-on flag at `build/TestFlight-0.2.2-32/manna circle.ipa`.
- [ ] Upload/process and assign build 32 to the intended TestFlight cohort; reproduce failures after collection is enabled.

## Locally verifiable

- [x] App and widget compile with blank Supabase configuration.
- [x] Deterministic local repository remains available to previews, tests, and simulator UI tests.
- [x] Unit and UI coverage exercises the primary Today and Timeline paths.
- [x] Privacy manifests are included in both app and widget targets and pass `plutil` validation.
- [x] Adaptive wordmark assets compile into the widget/Live Activity extension, and the full notification logo compiles into the notification service extension.
- [x] Draft App Store review notes identify permissions, review flow, and blockers.
- [x] Supply the final app icon and adaptive transparent manna wordmarks.
- [ ] Capture release-candidate screenshots.
- [ ] Finalize customer-facing privacy policy, support page, store description, age rating, and localization.

## Apple Developer and physical-device validation

- [ ] Enable and validate Sign in with Apple, Push Notifications, Live Activities, and App Groups for release identifiers and profiles.
- [ ] Verify push-to-start/update/end, Dynamic Island, lock screen, notification privacy, and background behavior.
- [ ] Register and sign `app.manna-circle.ios.notification-service`, deploy the mutable-content alert payload, and verify the expanded notification logo on a TestFlight device.
- [ ] Verify camera, microphone, speech recognition, audio playback, video playback, denial/recovery, and interruption handling.
- [ ] Complete VoiceOver, Increased Contrast, Reduce Motion, Dynamic Type, orientation, iPad, and small-phone checks.
- [ ] Verify widget snapshot sharing, refresh cadence, and every deep-link destination.

## Hosted Supabase validation

- [ ] Complete the two-account acceptance matrix for authentication, circles, RLS, realtime, Storage, RPCs, and gating.
- [x] Deploy all database migrations through `202610060010` and confirm local/remote history matches.
- [x] Run the hosted dispatcher once per minute and verify consecutive HTTP 200 responses.
- [x] Recover a real interrupted dispatch and verify the prompt returns to `open`.
- [x] Diagnose the partial APNs result as provider-token rotation throttling and deploy a 45-minute server-only JWT cache.
- [ ] Verify a post-cooldown dispatch has no `TooManyProviderTokenUpdates`, observe alert/Live Activity presentation, and validate Production/TestFlight device tokens.
- [x] Deploy `dispatch-prompts` version 8 with the mutable-content alert required by the notification-logo extension.
- [ ] Exercise a permanent APNs token error and verify invalid-token cleanup plus delivery observability.
- [ ] Implement and validate account export, account deletion, media cleanup, and retention controls.
- [x] Implement owner-confirmed member removal in the client, local repository, and server RPC.
- [ ] Deploy and validate member removal with two hosted accounts; implement and validate abuse reporting.
- [ ] Exercise offline, slow-network, upload interruption, expired signed URL, and service-failure recovery.

## Distribution

- [x] Create a generic iOS Release archive and inspect its code signature and entitlements.
- [x] Export an App Store distribution archive and confirm production APNs, distribution provisioning, `get-task-allow = false`, both signed extensions, and the bundled notification logo.
- [ ] Upload to App Store Connect and resolve validation warnings.
- [ ] Run internal TestFlight, then the planned external cohort.
- [ ] Re-run the acceptance matrix on the candidate build.
- [ ] Complete App Store metadata, review credentials, privacy nutrition labels, and release notes.
