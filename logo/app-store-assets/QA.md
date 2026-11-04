# App Store artwork QA

Created for App Store Connect’s Header and Search Results placements.

**Current recommended header:** `app-store-header-3840x1646-safe.png`. The original header is retained for reference; Search Results is unchanged.

The safe header follows inspection of the actual iPhone product-page preview in Chrome. Its composition is scaled to 86% around the canvas center, with native text re-rendering and proportional placement of the original logo. Critical content lies between **x=576 and x=3249**, giving the phone preview additional breathing room. Palette, exact wording, hierarchy, and canvas dimensions remain the same. `app-store-header-safe-simulated-crop.png` is a local crop simulation removing 322 pixels from each side; it is review evidence, not a screenshot or an upload asset.

| Upload | Dimensions | Color | Size | SHA-256 |
| --- | --- | --- | --- | --- |
| `app-store-header-3840x1646-safe.png` | 3840 × 1646 | Opaque RGB, embedded sRGB | 132,170 bytes | `0648cfc27fe23c5f91d667002ea5574e48c68b0e5a0b05fac01d98b347719b6f` |
| `app-store-header-3840x1646.png` | 3840 × 1646 | Opaque RGB, embedded sRGB | 158,624 bytes | `2368bc67f6950135e177f3911df896a2bc3d39aa2510967e25cf2b9349c0605c` |
| `app-store-search-results-3840x2560.png` | 3840 × 2560 | Opaque RGB, embedded sRGB | 176,614 bytes | `909845b3759f10bce15da39db4b82c6f5967295a4128dc63bef58bce804a6042` |

Both contain the exact wording **BeReal for counting blessings from God**, with line breaks after “for” and “blessings”. The original dark `logo1_transparent.png` is composited without repainting, recoloring, or reshaping. Only its transparent exterior was cropped for placement; it was uniformly resized with Lanczos resampling. Logo originals remain unchanged.

Website references: `src/app/globals.css`, `src/app/page.tsx`, and `src/app/layout.tsx` in the separate manna circle website project. Canvas **#F9F3E4**, headline **#2D2B2B**, emphasis **#975A24**, circles **#DED4C2 / #E9DFCE**. Typography is Source Serif 4, weight 500, optical size 32. Font source: [Google Fonts Source Serif 4](https://github.com/google/fonts/tree/main/ofl/sourceserif4), licensed under the SIL Open Font License; the font itself is not redistributed in this deliverable.

Full-size, 1200-pixel previews, and 384-pixel thumbnails were visually inspected. Text and logo remain readable at thumbnail size. No text clipping, accidental overlaps, or transparent pixels. Header’s text bounds end at x=3460 on a 3840-pixel canvas; search text stays between x=938 and x=2903. Small decorative rings are intentionally subtle. Both PNGs were reopened and verified successfully.

Files ending `-preview.png` and `-thumbnail.png` support review; upload the safe header and the unchanged dimension-named Search Results original. No application behavior, metadata, dashboard settings, or original logo assets were changed by this design task.

Safe-header follow-up: 1200-pixel preview, 384-pixel thumbnail, and simulated crop were visually inspected. The new PNG was reopened and integrity-verified. Original header and Search Results SHA-256 hashes were rechecked and are unchanged.
