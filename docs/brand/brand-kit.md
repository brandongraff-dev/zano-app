# ZANO brand kit

**Status:** v2, 2026-09-24. The founder's own logo (swoosh-star mark + geometric wordmark) replaces
the v1 wordmark concept, and acid green is gone: the palette is taken from the logo (black, pearl,
brushed silver).
**Source of truth for:** the logo, app icon, colors, type and where the brand appears in the app.
Product decisions stay in `docs/spec.md`; this file never overrides it.

## Logo

Two parts, traced to vectors from the founder's master artwork:

- **The mark:** a four-point swoosh star with a teardrop counter. Brushed silver on black.
- **The wordmark:** thin geometric capitals, Λ-shaped A (no crossbar), rounded-rectangle O.
  Pearl white.

| File | Use |
|---|---|
| `zano-lockup.svg` / `zano-lockup-1200.png` | Mark above wordmark. Launch screen, splash, social. |
| `zano-mark.svg` | The mark in brushed silver (gradient). App icon, launch, big moments. |
| `zano-mark-white.svg` / `zano-mark-black.svg` | One-color mark (small sizes, light backgrounds, engraving). |
| `zano-wordmark.svg` | Wordmark, pearl `#F2F1ED`. Default in-app. |
| `zano-wordmark-white.svg` / `zano-wordmark-black.svg` | One-color wordmark. |
| `zano-app-icon.svg` / `zano-app-icon-1024.png` | App icon master (square; iOS applies the corner mask). |
| `zano-wordmark-1200.png` | Quick raster for docs, decks and social. |

In code: `ZanoWordmark(height:style:)` and `ZanoMark(height:style:)` in
`Core/Sources/Core/UI/Components/ZanoLogo.swift`, drawn from the same paths as the SVGs (unit space
100 high: mark 155.75 wide, wordmark 879.78 wide). `Theme.Colors.metallic` is the mark's gradient.

**Proportions:** wordmark 8.8 : 1, mark 1.56 : 1. In the lockup the wordmark's cap height is a fifth
of the mark's height, with a third of the mark's height between them.

**Clear space:** the wordmark's cap height on every side. Nothing else inside it.

**Minimum size:** wordmark 10 pt cap height (88 pt wide); mark 16 pt high. The wordmark's strokes are
thin: below 10 pt use the mark.

**Don't:**
- retype it in a font, or change letter spacing;
- recolor it in a hue (only pearl, silver, white or near-black);
- put the silver mark on a light or busy background (use the black one-color version);
- add effects beyond the mark's own brushed gradient (outlines, glows, drop shadows);
- stretch, rotate or crop it.

## App icon

The silver mark centred on near-black (`#050505` edges to `#1A1A1C` just above centre, a soft top
light), about 66% of the icon's width. `App/ZANO/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
is rendered from `zano-app-icon.svg`: re-render from the SVG, never edit the PNG.

## Color

Monochrome with muted metal accents. Light itself is the reward: the brightest thing on a screen is
what you've earned (spec §15, decision 2026-09-24).

| Token | Hex | Role |
|---|---|---|
| Ink | `#0A0A0B` | Background, text on light fills. |
| Surface | `#141416` | Cards. |
| Surface 2 | `#1C1C1F` | Nested cards, pressed states, hero top light. |
| Pearl | `#F2F1ED` | Primary text, the wordmark, primary buttons. |
| Platinum (accent) | `#E4E2DC` | Earned: completed rings, the unlock, badges. Never chrome. |
| Silver gradient | `#FAF9F6` → `#D6D4CF` → `#9E9C97` | The mark; earned hero moments. |
| Muted | `#8E8E93` | Secondary text. |
| Locked | `#DE5A52` | Locked status only. A muted red, not system red. |
| Warning | `#D9A55B` | Amber gold. |
| Goal colors | protein `#C8936A` bronze, focus `#8E96C8` slate, water `#86B4C4` glacier | Each goal's ring. Low chroma, so the screen stays calm. |

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
| App icon | Silver mark on black | `AppIcon.appiconset` |
| Launch screen | Lockup centred on ink | `project.yml` `UILaunchScreen`, `LaunchLogo` asset |
| Today header | Small wordmark | `TodayView.swift` |
| Onboarding hook (screen 1) | Wordmark above the unlock ring | `Screen1Hook.swift` |
| Paywall | Small wordmark above the headline | `PaywallView.swift` |
| Notification preview (onboarding) | The app icon (mark on black), drawn natively | `Screen12PermissionPriming.swift` |
| Share cards and posters | Wordmark footer instead of typed "ZANO" | `ShareCard.swift`, `SharePoster.swift` |
| Settings | Sign-off: wordmark, tagline, version | `SettingsView.swift` |

## Still to do

- Shield screen (`ZANOShieldConfig`) icon and widget branding: extensions need their own assets.
- Lock Card and NFC tag artwork from `zano-mark-black.svg` / `zano-wordmark-black.svg` (spec §25).
- The traced paths come from a raster; a vector master from the designer would tighten the curves.
- Trademark clearance (spec header: attorney search in Classes 9, 5, 32) before printing.
