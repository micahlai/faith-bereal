# Design system

## Direction: quiet stained glass

The memorable element is a circular ten-minute “light window”: layered arcs of dawn blue, violet, and candle gold move only as time changes. Everything around it stays calm, tactile, and native. The faith-adjacent premise is expressed through light, gathering, and reflection—not religious symbols, gamification, or faux parchment.

The generic dark-dashboard recommendation generated during design discovery was rejected: it would make a private gratitude ritual feel like a utility console. Blessing Circle supports both system appearances and uses Apple materials sparingly.

## Tokens

| Role | Light | Dark | Use |
|---|---:|---:|---|
| Canvas | `#F7F5FA` | `#111018` | Main background |
| Surface | `#FFFFFF` | `#1C1A25` | Raised content |
| Ink | `#211E2B` | `#F8F5FF` | Primary text |
| Secondary ink | `#625D70` | `#C8C1D5` | Supporting text |
| Iris | `#6256A5` | `#AFA3F5` | Primary action / active thread |
| Dawn | `#4F86A8` | `#78B8D7` | Informational state |
| Candle | `#B9772E` | `#F0B867` | Countdown / warmth |
| Missed | `#8B5963` | `#E09AA8` | Missed state, always paired with icon/text |
| Divider | `#DED9E6` | `#3A3545` | Lines and boundaries |

App code exposes semantic roles, not literal color names in feature views.

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

