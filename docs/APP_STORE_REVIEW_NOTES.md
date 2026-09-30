# App Store review notes

Status: draft for a future release candidate. Values marked **Release input required** must be completed before submission.

## App overview

Blessing Circle is a private-circle gratitude app. A circle receives one server-authored prompt at a randomized time within the circle owner's configured schedule. Members have the circle's configured response window to share one blessing as typed text, voice-transcribed text, or video. Historical posts remain visible, while the current prompt's peer posts unlock only after the reviewing user submits their own blessing.

The app also includes:

- optional Bible-reference tagging, rendered in each viewer's selected public-domain translation;
- text or voice responses on visible blessings;
- a Live Activity during an active response window;
- a Home Screen widget that shows an active prompt or rotates eligible blessings;
- private circle creation and invite-code joining.

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

The app does not track users for advertising. Privacy manifests are included for the app and widget. The planned collection, retention, export, and deletion behavior is documented in `PRIVACY_AND_RETENTION.md`.

**Release blockers:** in-app account deletion/export, durable media cleanup, abuse reporting, owner member-removal controls, and production validation of Row Level Security are not complete. These must not be represented as available in App Store metadata.

## App Store Connect inputs still required

- final app name, subtitle, description, keywords, category, age rating, support URL, marketing URL, and privacy-policy URL;
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
