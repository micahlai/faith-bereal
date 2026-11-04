# App Store review notes

Status: draft for a future release candidate. Values marked **Release input required** must be completed before submission.

Combined source target: **0.6.0 (51)**, pending final build-number availability and a new signed archive. The earlier signed **0.5.3 (50)** is historical. Use the newest dated audit in [the release checklist](RELEASE_CHECKLIST.md); older audit rows are historical. Account deletion, report/block controls, privacy onboarding and the recording-retention implementation now exist. Public submission still needs the physical-device acceptance and release inputs below. Confirm the App Store Connect version/build selection and build-number availability before upload.

## Encryption export-compliance answer

The reviewed iOS client uses Apple's HTTPS networking, CryptoKit SHA-256 for sign-in/cache identities, and operating-system file protection. The pinned Supabase SDK's SHA-256 dependency uses CryptoKit on iOS. No custom encryption protocol or separate bundled iOS encryption implementation was found. `ITSAppUsesNonExemptEncryption` is therefore set to `false` in the generated app, and distribution-export validation requires it.

For this implementation, answer **No** to non-exempt encryption. If the form instead lists proprietary algorithms or standard algorithms implemented outside Apple's operating system, select **None of the algorithms mentioned above**. This does not mean traffic is unencrypted or that circle content is end-to-end encrypted; the service handles content for authorized members. Future cryptography/dependency changes require reassessment. [Apple's exemption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

## App overview

manna circle - daily blessings is a private-circle gratitude app. A circle receives one server-authored prompt at a randomized time within the circle owner's configured schedule. Members have the circle's configured response window to share one blessing as typed text, voice-transcribed text, or video. Historical posts remain visible, while the current prompt's peer posts unlock only after the reviewing user submits their own blessing.

The app also includes:

- optional Bible-reference tagging, rendered in each viewer's selected public-domain translation;
- text or voice responses on visible blessings;
- a Live Activity during an active response window;
- a Home Screen widget that shows an active prompt or rotates eligible blessings;
- private circle creation and invite-code joining.

## Bible content rights for the 0.6.0 target

The Bible worktree narrows the catalog to 12 reviewed public-domain versions, carries provider credits and rejects aliased responses. Public-domain text is still third-party content: the owner approved Content Rights Yes, saved and verified in Chrome, supported by the [version evidence and review explanation](BIBLE_CONTENT_RIGHTS.md). The production migration and matching public website disclosure remain separate rollout work. Only Content Rights was updated; no submission or build upload was performed.

## Review path

The checked-in build has a deterministic local repository for simulator development and automated tests. Production review must use a configured Supabase project and Sign in with Apple.

**Release input required:** provide an App Review test account or a review-safe authentication path, a prepared circle with at least two members, and exact credentials/instructions in App Store Connect. Do not submit the local demo as proof of production service behavior.

Suggested review sequence:

1. Sign in with Apple and select the prepared circle.
2. Open Today. If its prompt is active, submit a typed blessing; otherwise use the review instructions for the prepared prompt.
3. Confirm that the current-day feed unlocks after submission.
4. Open Timeline and select a blessing to inspect its text/transcript, media preview, scripture, and responses.
5. Open the circle switcher and user settings to inspect appearance, Bible version, and widget refresh preferences.
6. On the prepared owner account, open circle settings to inspect the schedule, time zone, response window, late-post, repeat-window, rename, and ownership-transfer controls.
7. Add the Home Screen widget and start an active prompt to inspect its deep link.

## Permission explanations

- Notifications announce the circle's daily prompt and update its Live Activity.
- Camera and microphone access are requested only when the user chooses video capture.
- Speech recognition and microphone access are requested only when the user chooses voice transcription or a voice response.
- Photos and videos selected or captured for a blessing are stored privately for authorized circle members.

Permission denial leaves typed blessings available. Physical-device denial/recovery and interruption paths must be verified before release.

## Live Activities and widget

The Live Activity shows the circle name, prompt state, and remaining response time. Remote push-to-start, update, and end require the production APNs configuration and must be verified on physical devices.

The widget deep-links to Today during an active share window. Otherwise it rotates blessings already visible to the user and deep-links to the selected blessing. It displays only App Group snapshot data written after authenticated app access.

## Privacy and safety

The app does not track users for advertising. Privacy manifests are included for the app, widget and notification service. Account-linked collection, optional diagnostics, saved copies and deletion are documented in [the launch compliance record](LAUNCH_COMPLIANCE.md) and [privacy inventory](PRIVACY_AND_RETENTION.md). The public privacy policy and support contact are live; previously published App Store privacy answers still need comparison to the submitted candidate.

Reporting, mutual blocking, limited server text filtering and an operator inbox are implemented. Photos/audio/video publish immediately under circle authorization, without automated visual/audio screening or mandatory developer approval. Assess these safeguards against App Review guideline 1.2 before submission; do not claim comprehensive media filtering. Test report/block and moderation visibility with installed accounts.

In-app account deletion has a durable two-provider cleanup/completion path and synthetic hosted acceptance. Actual Sign in with Apple reauthentication/token revocation still needs a disposable physical-account test. A user data export remains a project commitment; it is not presented here as a universal App Store requirement.

Recording cleanup is implemented but deliberately disabled until the updated build is actually available plus the approved 72-hour grace. Record that availability and the scheduled activation before public release; an exported IPA is not availability. Photos/text remain with history. Automatic saving requires an open, connected app with enough device storage and does not guarantee every recording is copied. See [MEDIA_RETENTION.md](MEDIA_RETENTION.md).

## App Store Connect inputs still required

- App Store name availability for “manna circle - daily blessings,” plus the final subtitle, description, keywords, category, age rating, support URL, marketing URL, and privacy-policy URL;
- 1024×1024 production app icon without transparency;
- required iPhone and iPad screenshots from the signed release candidate;
- privacy nutrition-label answers reconciled with the final backend and third-party SDK behavior;
- review contact, review credentials/instructions, and notes for the randomized prompt;
- export-compliance answers and content-rights confirmation;
- final version/build numbers and TestFlight release notes.

## Release evidence to attach

- passing clean build, unit tests, and UI tests for the release commit;
- two-account hosted acceptance results;
- physical-device Sign in with Apple, camera, speech, notification, Live Activity, and widget results;
- accessibility audit results on supported devices;
- account deletion/export, media cleanup, reporting, and member-removal results;
- screenshots of the final metadata and privacy-label configuration.
