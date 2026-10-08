# Accessibility audit

Last updated: 2026-10-08

This records implementation and verification, not a declaration that every App Store label is supported. Do not select every label based on automated tests alone.

## Feature assessment

| Category | Implementation | Remaining acceptance |
| --- | --- | --- |
| VoiceOver | Named controls; author/date/type/content on cards; automatic single-column Timeline; adjustable crop and movement/reset actions; verse steppers | Traverse all common tasks on iPhone/iPad, including sign-in, permissions, media, and saved copies. User photos lack author-written descriptions. |
| Voice Control | Named controls and verse input labels; crop menu and verse steppers; single-column List | Complete tasks with spoken commands, including repeated play/send controls and dictation. |
| Larger Text | Semantic fonts, scaled verse cells, unconstrained countdown text, stacked circle-creation navigation, single-column Timeline | Complete every common task at 200%+; iPad and system capture/permissions remain unverified. |
| Dark Interface | Adaptive colors; separate orange foreground/action fills; system or explicit appearance | Verify physical capture/player/system sheets, widgets, and Live Activities. |
| Differentiate Without Color Alone | States have text/symbols; verse selection adds border/weight and selected trait; recording changes icon/label | Physical Differentiate Without Color acceptance. |
| Sufficient Contrast | Asset tests require 4.5:1 for text in light/dark and normal/high contrast; white action and selected-verse text have proper pairs; increased-contrast boundaries exceed 3:1 | Composed control states, media overlays, widgets, Live Activities, and Accessibility Inspector verification. |
| Reduced Motion | Onboarding/countdown check Reduce Motion; no ambient animations | Physical capture, playback, and system-navigation acceptance. |
| Captions | Editable/readable audio and video transcripts | **Not ready to claim:** no timed video captions/authoring or availability indicators. Audio transcripts alone do not establish support for the video flow. |
| Audio Descriptions | Native playback controls and text transcripts | **Not implemented:** no narrated visual-description authoring/tracks, availability indicators, or tested system preference behavior. Reading dialogue aloud is not an audio description. |

## Automated coverage

- Verification on 2026-10-08: **106 app/domain tests passed** on iPhone 17 / iOS 26.5; **15 local-demo UI tests passed** on an isolated 375-point iPhone SE simulator / iOS 26.5. The native hit-region/description audits and the largest-text dark List check passed. Screenshots confirm List dates no longer overlap content, and the compact frozen Threads header remains intact. The signed hosted Release device build passes; no phone install or TestFlight upload was performed.
- `AccessibilityContrastTests` resolves compiled assets in four trait combinations: Ink, Secondary Ink, Manna Ink, Iris, Dawn, Candle, and Missed on Canvas/Surface. Action text, selected verse text, and high-contrast boundaries are also checked.
- The native automated audit checks hit regions and sufficient descriptions in Today and accessible Timeline, before and after scrolling. Contrast is checked independently using compiled color assets. The small-phone native contrast audit still flags the rendered “Share a blessing” label after replacing the translucent system style with a solid orange button. The white/fill pair passes the numeric test; this does **not** establish that the native finding is a false positive. Rendered contrast acceptance remains open and the contrast audit is not reported as passing.
- UI coverage checks manual List selection, author/date/content labels, detail opening, and automatic List selection at the largest accessibility text category.
- Existing onboarding, largest-text dark/landscape, Help, saved-media, guided-circle, Today-scroll, and pinned Threads-header regressions remain in the local suite.
- Photo-output tests require a square bounded JPEG. Menu and VoiceOver crop actions use the same constrained state/output as pinch/drag.

## Common-task acceptance checklist

For **each supported device class**, check these with VoiceOver, Voice Control, accessibility text sizes, Increased Contrast, Differentiate Without Color, Reduce Motion, and both appearances:

1. Finish setup, move Back, sign in with Apple, and recover from denial/failure.
2. Create/review, join by code/link, switch circles, edit leader settings, and leave safely.
3. Enter daily/evening capture, type/record, recover from denied/interrupted capture, attach photos, and submit.
4. Tag using Start/End verse controls; read full passages; change translation/language.
5. Crop profile/circle photos with Adjust photo and VoiceOver actions; save/cancel.
6. Read both Timeline layouts and Today; understand locked/missed/late/saved states; open details.
7. Play/pause/seek audio, play/full-screen/close video, read transcripts, and send responses.
8. Edit, Save/Unsave, export to Photos, and manage automatic saving/expired-copy warnings.
9. Change profile/appearance/icon/notification preferences; use Help and its Topics menu.
10. Open notifications, widgets, and Live Activities; understand deadlines/submitted states without seeing the screen.

Hardware keyboard/Switch Control, landscape, iPad split view, loading/slow networks, and offline saved playback need their own checks. Record device, OS, date, flow, and result before making a support claim. No physical accessibility acceptance or App Store metadata changes were performed by this change.

## Apple criteria

Use Apple's [label overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels), [VoiceOver criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/), [Captions criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/captions-evaluation-criteria/), and [Audio Descriptions criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/audio-descriptions-evaluation-criteria/). Re-evaluate after customer-visible changes and update the customer Help topic with each change.
