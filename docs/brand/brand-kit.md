# ZANO brand kit

**Status:** v1, 2026-09-24. Logo direction D (wordmark) chosen by the founder from four concepts.
**Source of truth for:** the logo, app icon, colors, type and where the brand appears in the app.
Product decisions stay in `docs/spec.md`; this file never overrides it.

## Logo

The logo is the **ZANO wordmark**: custom compressed letters (not a font) on a 282 × 100 unit
grid, stroke weight 20. The **O is the earned ring**: the same stadium ring the app fills when you
complete goals, in the one brand accent. White letters, green O.

| File | Use |
|---|---|
| `zano-wordmark.svg` | Default. White letters, green O, on dark. |
| `zano-wordmark-white.svg` | One color, all white (photos, tinted backgrounds). |
| `zano-wordmark-black.svg` | One color, near-black (light backgrounds, print, engraving). |
| `zano-mark.svg` | The symbol: the O ring alone, for spaces too small for the wordmark. |
| `zano-app-icon.svg` / `zano-app-icon-1024.png` | App icon master (square; iOS applies the corner mask). |
| `zano-wordmark-1200.png` | Quick raster for docs, decks and social. |

In code: `ZanoWordmark(height:style:)` and `ZanoMark(height:color:)` in
`Core/Sources/Core/UI/Components/ZanoLogo.swift`, drawn from the same coordinates as the SVGs.

**Grid:** Z 0–62, A 72–136, N 146–208, O 218–282. Cap height 100. Letter gap 10.

**Clear space:** half the cap height on every side. Nothing else inside it.

**Minimum size:** 16 pt cap height on screen (45 pt wide), 12 mm wide in print or engraving.
Below that, use the mark.

**Don't:**
- retype it in a font, or change letter spacing;
- recolor the letters green, or the O any color but the accent (except the one-color versions);
- put the two-color version on a light or busy background;
- add effects (outlines, gradients, drop shadows);
- stretch, rotate or crop it;
- lock it up with other words in the same line.

## App icon

The wordmark centred on `#0A0A0B`, about 81% of the icon's width, with a faint accent glow behind the
O. `App/ZANO/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is rendered from
`zano-app-icon.svg`: re-render from the SVG, never edit the PNG.

## Color

One accent, used only for earned states (spec §15, decision 2026-09-24).

| Token | Hex | Role |
|---|---|---|
| Acid (accent) | `#B8FF3C` | Earned: the O, completed goals, the unlock. Never chrome. |
| Ink | `#0A0A0B` | Background, text on accent. |
| Surface | `#141416` | Cards. |
| Surface 2 | `#1C1C1F` | Nested cards, pressed states. |
| Paper | `#F5F5F7` | Primary text, the wordmark letters, primary buttons. |
| Muted | `#8E8E93` | Secondary text. |
| Locked | `#FF453A` | Locked status only. |
| Goal colors | protein `#FF7A00`, focus `#5E5CE6`, water `#32ADE6` | Content color for each goal's ring. |

## Type

- **Display and numbers:** SF Pro at compressed and condensed widths, heavy. Big, athletic, few words.
- **Text:** SF Pro, sentence case. No tracked all-caps labels.
- **Web and print** (where SF isn't licensed): Barlow Condensed ExtraBold for display, Public Sans
  for text.

## Voice

Taglines: **"Earn it."** and **"Tap in."** Direct, short, second person, never guilt. The coach
voices (Hype, Tough Love, Chill, Data) change the tone, not the rules. Spec §5.13 has samples.

## Where the logo appears in the app

| Place | What | File |
|---|---|---|
| Launch screen | Wordmark centred on ink | `project.yml` `UILaunchScreen`, `LaunchLogo` asset |
| Onboarding hook (screen 1) | Wordmark above the unlock ring | `Screen1Hook.swift` |
| Paywall | Small wordmark above the headline | `PaywallView.swift` |
| Notification preview (onboarding) | The real app icon, drawn natively | `Screen12PermissionPriming.swift` |
| Share cards and posters | Wordmark footer instead of typed "ZANO" | `ShareCard.swift`, `SharePoster.swift` |
| Settings | Sign-off: wordmark, tagline, version | `SettingsView.swift` |

Not on everyday screens (Today, Lock, Fuel, Progress): the user already knows which app they're in,
and the logo there would compete with the content.

## Still to do

- Shield screen (`ZANOShieldConfig`) icon and widget branding: extensions need their own assets.
- Lock Card and NFC tag artwork from `zano-wordmark-black.svg` (spec §25).
- Trademark clearance (spec header: attorney search in Classes 9, 5, 32) before printing.
