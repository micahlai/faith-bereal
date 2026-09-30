# Accessibility audit

Last updated: 2026-09-30

## Locally verified

- SwiftUI semantic controls and Dynamic Type are used throughout primary flows.
- The local UI suite launches Today and verifies the Timeline member header remains available after vertical scrolling.
- A second UI test launches in dark mode at the largest accessibility text category and verifies Today’s primary content and share action remain reachable.
- Light-mode text contrast against Canvas is 15.09:1 for Ink, 5.84:1 for Secondary Ink, 5.72:1 for Iris, 5.48:1 for Dawn, and 5.09:1 for Candle. Dark primary and secondary text exceed 10:1.
- Missed and late states include labels and symbols; they do not rely on color alone.
- Primary controls use native buttons with at least 44-point hit regions. Verse cells were raised to 44 points.
- Bible verse range selection has Start and End steppers in addition to drag and tap interaction.
- Capture mode and response mode controls adapt at accessibility Dynamic Type sizes.
- The countdown animation respects Reduce Motion.

## Still requires device or manual validation

- Full VoiceOver traversal and rotor order on every sheet and media player.
- Increased Contrast and Differentiate Without Color on physical devices.
- Camera, microphone, speech-recognition, Dynamic Island, Live Activity, and lock-screen behavior.
- iPad split view and hardware-keyboard focus traversal.

The release-readiness accessibility item remains open until these checks pass on supported physical devices.
