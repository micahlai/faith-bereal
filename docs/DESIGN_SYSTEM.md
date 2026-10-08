# Design system

## Direction: warm manna

The visual system is drawn from `logo/logo1.png`: warm cream, charcoal ink, and a grounded orange mark. Dark orange is the primary interactive accent. Purple remains a deliberate supporting accent for scripture and reflective content, while the circular ten-minute “light window” blends the warm and supporting colors as time changes. Everything stays calm, tactile, and native.

The generic dark-dashboard recommendation generated during design discovery was rejected: it would make a private gratitude ritual feel like a utility console. manna circle supports both system appearances and uses Apple materials sparingly.

## Tokens

| Role | Light | Dark | Use |
|---|---:|---:|---|
| Canvas | `#F9F3E4` | `#1D1A17` | Main background; light value matches the logo field |
| Surface | `#FFFCF3` | `#29231E` | Raised content |
| Ink | `#2D2B2B` | `#FCF6E8` | Primary text; derived from the logo wordmark |
| Secondary ink | `#665F56` | `#D3C6B3` | Supporting text |
| Manna ink | `#975A24` | `#E4AD70` | Primary text, tint, focus, and active thread |
| Manna action fill | `#975A24` | `#A85F20` | Filled actions with white text |
| Iris | `#6256A5` | `#AFA3F5` | Scripture and reflective secondary accent |
| Dawn | `#31698E` | `#78B8D7` | Informational state |
| Candle | `#92531E` | `#E4AD70` | Countdown / warmth; related to the logo’s `#BA8347` dot |
| Missed | `#8B5963` | `#E09AA8` | Missed state, always paired with icon/text |
| Divider | `#DED4C2` | `#4A4036` | Lines and boundaries |

App code exposes semantic roles, not literal color names in feature views. Filled orange actions maintain at least 4.5:1 contrast with white text in both appearances; dark-mode orange text uses a lighter separate token. Primary buttons use a solid fill rather than iOS's translucent prominent-button treatment, which can weaken rendered contrast. Selected scripture cells use Surface text on Iris, not white on the light-purple dark-mode tint. Purple is not used as the primary CTA color. Contrast tests resolve actual asset colors in light/dark and normal/increased contrast.

## Typography

- UI, navigation, controls, times: San Francisco via SwiftUI semantic styles.
- Blessing content and reflective prompts: New York via `.serif`, preserving Dynamic Type.
- Headings are sentence case. No tracked all-caps labels.
- Text never shrinks below a semantic footnote and no fixed line heights are used.

## Layout

- 4-point base grid; common spacing is 8, 12, 16, 24, and 32 points.
- Phone horizontal gutter is 20 points; regular-width content is capped near 680 points.
- Every control has a minimum 44-point hit region.
- Cards use 18–24 point radii according to hierarchy; timeline events are not all wrapped in identical cards.
- Safe areas and the software keyboard must never cover primary actions.

## Primary screens

```text
Today                 Capture               Timeline
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ Circle name   │     │ 08:42 left    │     │  Sep 29       │
│               │     │               │     │ Ava  Ben  Mia │
│   countdown   │ --> │ mode selector │ --> │  ●    ○    ●  │
│  light window │     │ editor/camera │     │  │    │    │  │
│               │     │               │     │  ●    ●    ◌  │
│ Share blessing│     │ Send blessing │     │  │    │    │  │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Interaction

- Motion communicates countdown changes, submission success, or timeline insertion. No ambient looping animation.
- Haptics confirm mode selection and successful submission.
- Reduced Motion replaces arc transitions with immediate state updates.
- VoiceOver reads member, date, submission status, capture mode, and content as one coherent timeline element.
- Current-day locked content explains exactly how to unlock it.
