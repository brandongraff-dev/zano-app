# 2026 iOS visual language: what shifted, and what it means for ZANO's tokens

**Status:** Research and recommendations only. No Swift, spec, or asset file was changed. The only
file this task wrote is this one.

**As of:** 2026-09-23. iOS 27 shipped on 2026-09-14 (MacRumors). iOS 26 shipped Sept 2025.

**Honesty about verification:** there is no Mac, Simulator, or device in this environment, so
nothing about ZANO was rendered. Every statement about how ZANO "looks" is a static read of the
Swift source plus arithmetic on the hex tokens. The research tools also return text, not images, so
"what top apps look like" is secondhand (section 3.6). Every statement about Apple's direction is tagged
with how well it is sourced (legend below). Where a claim could not be confirmed it is listed in
section 12 instead of being asserted.

**Evidence legend** (every non-obvious claim carries one):

| Tag | Meaning |
|---|---|
| [Apple] | Fetched this session from developer.apple.com (HIG pages, WWDC25/26 session pages, docs) or Apple's newsroom |
| [Press] | MacRumors / Engadget / Cult of Mac / Wikipedia: reliable on facts, thin on Apple's reasoning |
| [3P] | Third-party blog or analysis. Useful color, not authority |
| [Calc] | Computed in this session (sRGB to WCAG contrast, CIE Lab / OKLab, CIEDE2000, Machado 2009 color-vision-deficiency matrices). Reproducible with the scripts described in section 12 |
| [Read] | Static read of this repo's source |
| [Judgment] | My design opinion. Not verified, needs eyes on a device |

**Relationship to sibling docs in `docs/design/`:** `apple-design-review.md` covers motion,
gestures, and reduced motion; `ui-stress-test-findings.md` covers accessibility, empty/extreme
states, and RTL; `animation-*.md` cover the animation toolkit. This doc does not repeat them. It
covers what they do not: materials and depth, dark-surface construction, the single-accent system,
type, shape, and the non-app surfaces (widgets, shield, icon). Where it updates a sibling doc's
conclusion, it says so.

---

## 0. Verdict

1. **The direction in spec §15 is not obsolete. It is closer to Apple's 2026 advice than most
   apps.** WWDC26's "Communicate your brand identity on iOS" says: keep chrome standard, put brand
   expression in the content layer, spend color on meaning (hierarchy, interaction, status), and be
   sparse [Apple]. A near-black, single-accent, ring-centric app is exactly a content-layer brand.
2. **What did shift is the surface vocabulary around that content.** iOS 26 made chrome glass and
   controls capsule-shaped; iOS 27 (announced 2026-06-08, shipped 2026-09-14) tuned that glass with
   a darkened edge, brighter specular highlights, and better diffusion, plus a user slider from
   "ultra clear" to "fully tinted" [Apple newsroom via search snippet, Press]. ZANO's cards are
   flat fills with no edge treatment, so they now sit in an OS whose native language is
   rim-lit edges.
3. **Today's UI is flat by construction.** Across every `.swift` file in the repo there is exactly
   one SwiftUI `Material` (`TodayView.swift:110`; the shield extension's UIKit
   `.systemMaterialDark` blur is the only other), one gradient (`ShareCard.swift:80`), zero
   shadows, zero glows, zero glass [Read]. All depth comes from three fills that differ by 3.6 and
   4.0 L* [Calc].
   The spec's own style paragraph (§16) asks for "subtle inner glow on active elements" and "crisp
   1px hairline dividers"; the current tokens cannot deliver either (hairline resolves to
   1.06:1 against its own surface [Calc]).
4. **Two real legibility defects fall out of the arithmetic**, independent of taste: the
   hold-to-commit button's light label sits on a sweeping acid-green fill at 1.35:1 [Calc, Read]
   (section 11), and the ring/bar track is 1.08:1 against its card [Calc].
5. **Dynamic Type is still fully off.** Theme.swift still builds every font with a fixed
   `size:` [Read], and 68 more `.font(.system(size:` literals across 35 files bypass Theme
   entirely [Read]. Apple's typography and brand-identity guidance both name Dynamic Type as
   non-optional [Apple]. This was flagged in `ui-stress-test-findings.md` 1.2 and is unchanged.
6. **The single-accent rule is sound but leaks in the additive ring palette.** The eight chromatic
   "assumption" ring hues in `Theme.Colors.Ring` add a second green (`steps`) and a second yellow
   (`sunrise`) next to the accent and warning tokens, and 18 of the 66 pairs among the 12
   chromatic ring hues collapse (dE2000 < 12) under at least one of normal / protan / deutan /
   tritan vision [Calc]. Fix with a glyph-first rule plus a smaller hue set (section 4).
7. **Do not put glass on ZANO's cards.** Apple is explicit: glass belongs to the navigation layer
   floating above content; glass on the content layer competes with content and muddies hierarchy
   [Apple, WWDC25 219 and HIG Materials]. Use glass only for chrome, and let the system do it
   (section 2).
8. **One hand-rolled pre-iOS-26 idiom should be replaced:** `TodayView`'s
   `safeAreaInset` + `.background(.ultraThinMaterial)` bottom dock. On iOS 26+ the API for this is
   `safeAreaBar`, which brings the system scroll-edge effect with it [3P confirming Apple API;
   section 2.3].
9. **Controls should become capsules.** iOS 26 controls are capsule-shaped across sizes [Apple,
   WWDC25 356]. `PrimaryButton` and the other 12pt rounded-rect controls read as the previous era
   next to system chrome.
10. **Everything below is gated on deployment target 17.0.** `project.yml` and `Core/Package.swift`
    both pin iOS 17 [Read]. Every iOS 26 API named here (`glassEffect`, `safeAreaBar`,
    `scrollEdgeEffectStyle`, `ConcentricRectangle`) needs `if #available(iOS 26, *)` with the
    existing look as the fallback; `Color.mix` is iOS 18, so tokens below are precomputed hex, not
    runtime mixes.

---

## 1. What actually shifted (timeline)

| Date | Change | Source |
|---|---|---|
| 2025-06-09 | Liquid Glass + new design system announced. HIG Materials, Color, Layout updated | [Apple] |
| 2025-07 to 2025-10 | Later betas raised frost/opacity in bars and overlays after readability complaints; iOS 26.1 added a user "Clear / Tinted" toggle | [Press: Wikipedia, MacRumors] |
| 2025-09-09 | HIG Materials updated again | [Apple change log] |
| 2025-12-16 | HIG Color, Typography (emphasized weights added to Dynamic Type specs), Buttons, Widgets updated | [Apple change logs] |
| 2026-03-24 | HIG Sheets: button placement updated | [Apple change log] |
| 2026-06-08 | WWDC26. iOS 27 refinements announced; HIG Tab Bars updated; new sessions "Principles of great design" (250) and "Communicate your brand identity on iOS" (251) | [Apple] |
| 2026-09-14 | iOS 27 released | [Press: MacRumors] |

**What iOS 27 changed in the glass itself** [Apple newsroom via search snippet; Press: MacRumors,
Cult of Mac, Engadget]:

- Better diffusion of complex content behind glass, "more depth and separation."
- A darkened edge around glass elements and brighter specular highlights.
- A Settings slider, "ultra clear" to "fully tinted." Engadget describes the tinted end as more
  opaque and higher contrast, "the more opaque look from earlier versions" [Press].
- Sharper, more layered app icons (Icon Composer).
- Most refinements apply to existing apps on iOS 27 **without recompiling**, and adapt to Reduce
  Transparency and Increase Contrast [Press: MacRumors].
- `UIDesignRequiresCompatibility` (the iOS 26 opt-out) is reportedly ignored when building against
  the iOS 27 SDK [3P quoting Apple docs; not verified directly. Do not plan on the opt-out].

**Implications for ZANO** (each maps to a section below):

| Shift | What ZANO should do |
|---|---|
| Glass chrome is now the default and is user-tunable from clear to opaque | Use system bars/sheets/tab bar untouched; never paint a custom bar background; test both ends of the slider (2.4, 12) |
| OS edges are now rim-lit and darker-interior | Give ZANO's opaque cards an edge light so they belong to the same visual family without becoming glass (3.3) |
| Controls are capsules; containers are concentric | Move controls to `Capsule`; make nested radii follow `outer - inset` (6) |
| Apple: Dynamic Type and emphasized weights are baseline | Replace fixed `size:` fonts in Theme (5) |
| Widgets and icons now render in Default / Dark / Clear / Tinted | Mark accent groups in widgets; ship a layered icon (7) |
| Brand = content layer, color = meaning | Formalize an accent budget and a closed set of data hues (4) |

**What did not shift:** dark-first apps are fine; a single high-chroma accent on near-black is
fine; HIG still says avoid pure-black *inversions* and prefer semantic colors [Apple, Dark Mode].
Nothing in 2026 guidance argues for changing `background`, `surface`, `surface2`, `text`, or
`accent` hex values on trend grounds alone. The recommendations below add tokens and fix
specific defects; they do not rebrand.

---

## 2. Materials and depth: where glass goes, and where it must not

### 2.1 The rule Apple now states plainly

- Liquid Glass forms "a distinct functional layer for controls and navigation that floats above
  content" [Apple, HIG Materials]. "Don't use in content layer"; exceptions are transient controls
  such as sliders and toggles while active [Apple].
- Never stack glass on glass; put fills/vibrancy on top of glass, not more glass [Apple, WWDC25 219].
- "Regular" variant for anything with text; "clear" only over media-rich content with a dimming layer
  and bold content on top [Apple, WWDC25 219]. Never mix variants.
- Tint is for emphasis on primary actions only; "put color in the content layer instead" [Apple,
  WWDC25 219; HIG Color].
- Glass needs something behind it to work [3P: Donny Wals]. Over a flat `#0A0A0B` field there is
  almost nothing to refract, so glass chrome will read as a dark translucent pill with a specular
  rim, and its character will come from cards scrolling under it [Judgment]. That is a reason to
  keep content layered, not a reason to add glass.

### 2.2 Decision table for every ZANO surface

| ZANO surface | Layer | Treatment | Why |
|---|---|---|---|
| Screen background (`Colors.background`) | Content | Flat, optionally a very low-alpha accent radial behind the hero ring | Content layer; keep flat |
| Cards, rows, tiles (`surface`, `surface2`) | Content | Opaque fill + edge light + (section 3.3) | Glass here is explicitly discouraged |
| Ring center content, numerals | Content | Opaque | Legibility |
| Tab bar, navigation bar, toolbars | Navigation | System component only, `.tint(accent)`; no custom background | HIG Tab Bars: "Don't customize tab bar backgrounds" [Apple] |
| Sheets (any presented as a sheet: Gym Setup, NFC Setup, Paywall if so) | Navigation/modal | System sheet. Do not add `presentationBackground` overrides on partial detents (none exist today [Read]) | iOS 26 partial-height sheets are inset glass; a custom fill defeats it [Apple, WWDC25 323] |
| Bottom primary action dock on Today | Navigation-adjacent | `safeAreaBar` on iOS 26+, existing inset+material below (2.3) | Gets the system scroll-edge effect |
| `PrimaryButton.standard` | Content CTA | Stays an opaque acid-green **capsule**. Do not convert to `glassProminent` | Brand identity element; label contrast on tinted glass with a light accent is unverified (12) |
| `PrimaryButton.holdToCommit` | Content, safety-critical | Opaque, never glass | Progress-fill semantics and contrast must be deterministic |
| Shield (extension) | System-hosted | `ShieldConfiguration` only: blur style + `backgroundColor` (7.3) | No SwiftUI available |
| Share cards (`ShareCard`) | Exported image | Opaque only | `ImageRenderer` and glass/blur is a known risk; keep exports deterministic (12) |
| Unlock celebration | Full-screen | Dim scrim + accent particles | Not chrome |
| Widgets / Live Activities | System-rendered | See section 7 | System applies Clear/Tinted |

### 2.3 The one concrete material site: `TodayView.swift:105-111`

```swift
// Today [Read]
.safeAreaInset(edge: .bottom) {
    primaryButtonView
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
        .background(.ultraThinMaterial)      // full-width blur strip: the pre-iOS-26 idiom
}
```

This is a floating-chrome-over-scrolling-content site, which `apple-design-review.md` section 7
said the reviewed set did not contain (TodayView was out of that run's scope). HIG Layout says to
use scroll-edge effects and Liquid Glass instead of "solid or semi-opaque backgrounds" behind
floating controls [Apple, Layout]. The iOS 26 API for a custom bottom bar is
`safeAreaBar(edge:alignment:spacing:content:)`, which takes the signature of `safeAreaInset` and
adds the scroll view's edge effect [3P, confirming an Apple API]. Recommended shape (a small
`ViewBuilder` helper in Core/UI, so the availability branch lives in one place):

```swift
@ViewBuilder
func zanoBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
    if #available(iOS 26, *) {
        safeAreaBar(edge: .bottom) { bar() }                 // system scroll-edge treatment
    } else {
        safeAreaInset(edge: .bottom) { bar().background(.ultraThinMaterial) }   // today's look
    }
}
```

This supersedes the "propose a `Theme.Materials` token" note in `apple-design-review.md` 7: on
iOS 26+ the answer is an API, not a token. On 17-25 keep the current strip. `Theme.swift` needs no
material token for this.

### 2.4 What the system now does to ZANO for free, and what to check

Building with the Xcode 26+ SDK already gives standard components (`NavigationStack` bars, sheets,
`Toggle`, `Picker`, `Button` in system styles, any `TabView`) the glass treatment on iOS 26 and 27
devices regardless of the 17.0 deployment target [Apple, WWDC25 323]. Things that fight it:

- Any custom bar/sheet background color. In the repo, `presentationBackground`,
  `toolbarBackground`, `UITabBarAppearance`, and `UINavigationBarAppearance` do not appear at all
  [Read], which is good. `scrollContentBackground(.hidden)` and `listRowBackground(.clear)` on
  `Form`/`List` screens (Progress, Trophy, Cosmetics, Fuel, Settings) are the correct pattern for a
  custom dark canvas and are fine.
- `.tint(Theme.Colors.accent)` appears at only two leaf sites in the app (`PaywallView`,
  `Screen5PhoneTime`) and there is no root tint [Read]. The asset catalog's `AccentColor` is already
  `#B8FF3C` [Read], so system controls should pick up the accent once the app is built with that
  asset; confirm on a device (12). ZANOApp/ContentView are owned by another workflow this run, so
  this is a note for them (`ContentView` is still the Session 0 scaffold [Read]).
- Forced dark: 24 App files reference `.preferredColorScheme(.dark)`, each per screen [Read]. HIG's
  first Dark Mode practice is "avoid app-specific appearance settings" [Apple], so a dark-only app
  is a deliberate deviation. Make it airtight at the root plus `UIUserInterfaceStyle = Dark` in the
  generated Info.plist (`project.yml`, another workflow's file) so system alerts, keyboard, status
  bar, and the new glass chrome all resolve dark even before a screen's modifier runs [Judgment].
- Slider extremes: at "ultra clear" the tab bar over near-black content is a dark pill; at "fully
  tinted" it is close to opaque [Press]. Neither should look broken over ZANO's canvas; check both
  (12).

### 2.5 Do not

- No `glassEffect` on `LockStatusCard`, `GoalRow`, `RecapCard`, `PaywallCard`, or any tile.
- No custom bar backgrounds; no `Material` behind a title.
- No looping animation of blur radius or glow (HIG Reduce Motion: "avoid animating depth changes or
  blurs" [Apple, Accessibility]). Static glow on a completed ring is fine; pulsing glow is not.

---

## 3. Dark surfaces and real depth cues

### 3.1 Audit of the three-fill ladder [Calc]

| Token | Hex | CIE L* | Step |
|---|---|---|---|
| `background` | `#0A0A0B` | 2.76 | |
| `surface` | `#141416` | 6.39 | +3.63 |
| `surface2` | `#1C1C1F` | 10.38 | +4.00 |

For reference, Apple's iOS 13+ dark system stack (`#000000`, `#1C1C1E`, `#2C2C2E`, `#3A3A3C`) is L*
0 / 10.3 / 18.1 / 24.5, steps of about 10.3, 7.7, 6.4; Spotify's well-known
`#121212`/`#181818`/`#282828` is 5.5 / 8.3 / 16.1. (Both from memory of widely published values,
not re-fetched; Apple says its system color values were adjusted in iOS 26 but publishes them only
as images [Apple, Color], so treat the comparison as approximate.) ZANO's steps are the tightest of
the three, and only about a third of Apple's first step.

That is not automatically wrong. `#0A0A0B` avoids pure-black smearing and leaves headroom for an
"elevated" tone. But it means **fill alone cannot carry hierarchy**, and the current code relies on
fill alone.

### 3.2 Findings

| # | Finding | Evidence |
|---|---|---|
| D1 | `Colors.hairline` = `surface2` at 0.8 alpha resolves to `#1A1A1D`: **1.06:1** against `surface`. It is effectively invisible. Used in 8 files, including `PaywallCard`'s unselected plan border | [Calc, Read] |
| D2 | Ring and bar tracks are `surface2` on a `surface` card: **1.08:1**. An unfilled ring at 20% reads as a floating arc, not "20% of a ring" | [Calc, Read: `GoalRing`, `TimeBankBar`] |
| D3 | `accent.opacity(0.16)` icon-badge fills (e.g. `LockStatusCard`) composite to `#2E3A1C`: OKLCH chroma 0.051 vs the accent's 0.223, i.e. a drab olive that sits next to a fully saturated lime ring | [Calc, Read] |
| D4 | Depth-cue inventory for the whole repo: 1 SwiftUI `Material` (plus the shield's UIKit blur), 1 `LinearGradient`, 0 shadows, 0 glows, 0 glass. 43 hand-rolled `.background(Theme.Colors.surface…)` / `.fill(Theme.Colors.surface…)` fills in 25 files | [Read] |
| D5 | Sheets/modals reuse `background`. HIG's model is base vs *elevated* backgrounds so foreground layers advance [Apple, Dark Mode]. With a custom dark palette the system will not do that for ZANO, so a sheet on `#0A0A0B` over an app on `#0A0A0B` has no elevation cue | [Read, Apple] |
| D6 | Cards separate from the canvas by 1.07:1. Not a WCAG failure (text and chevrons identify the component), but it is the reason edge light matters | [Calc] |

### 3.3 Recommended construction (no palette change required)

**A. One edge-light token pair and one surface modifier.** Because D4 shows 43 sites hand-rolling
the same fill, this is the one abstraction worth having (CLAUDE.md's "three similar call sites beat
a premature protocol" is about speculative protocols; this is 43 real sites).

```swift
// Theme.swift: proposed, not applied
public enum Colors {
    // …existing tokens unchanged…

    /// Replaces surface2@0.8 (#1A1A1D, 1.06:1 on surface). white@0.08 -> #272729, 1.23:1.
    public static let hairline = Color.white.opacity(0.08)

    /// Empty ring/bar track. Was surface2 (1.08:1). white@0.10 -> #2C2C2D on surface, 1.32:1.
    public static let track = Color.white.opacity(0.10)

    /// Label/icon color for anything drawn ON an accent, danger, or warning fill.
    /// Never `text`: #F5F5F7 on accent is 1.11:1, `background` on accent is 16.40:1;
    /// on danger 3.13:1 vs 5.81:1.
    public static let onFill = background
}
```

```swift
// Core/UI: proposed. The 0.10 / 0.02 (and 0.22 / 0.10) belong in Theme as edge tokens; shown
// inline here for readability only.
public extension View {
    func zanoSurface(
        _ fill: Color = Theme.Colors.surface,
        radius: CGFloat = Theme.Radius.medium
    ) -> some View { modifier(ZanoSurface(fill: fill, radius: radius)) }
}

private struct ZanoSurface: ViewModifier {
    let fill: Color
    let radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(contrast == .increased ? 0.22 : 0.10),
                                 Color.white.opacity(contrast == .increased ? 0.10 : 0.02)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
    }
}
```

Why this shape [Judgment, corroborated by 3P]: a 1px top-lit gradient stroke is the standard way
dark design systems (Raycast's, and Vercel/Linear-style cards reverse-engineered by third parties:
roughly `rgba(255,255,255,0.06)` hairline borders plus a 1px top highlight) get depth where a
drop shadow cannot show on near-black [3P]. It is also the same visual idea iOS 27 just gave to
glass (darker interior, brighter rim) [Press], so opaque ZANO cards and system glass chrome read
as one family. Reading `colorSchemeContrast` gives Increase Contrast a stronger edge for free
(HIG: supply increased-contrast variants and test with it on [Apple, Dark Mode]).

A one-line alternative for the highlight is `fill.shadow(.inner(color: .white.opacity(0.07),
radius: 0, x: 0, y: 1))` (SwiftUI `ShapeStyle` inner shadow, iOS 16+). Whether a zero-radius inner
shadow renders as a crisp 1px line is unverified (12); prefer the stroke version.

**B. Derived accent tints, computed in a perceptual space, not `opacity`.** `Color.mix(with:by:in:)`
(`.perceptual`) is the right tool but is iOS 18 [3P: Donny Wals]; with a 17.0 target, precompute:

| Token (proposed) | Hex | OKLCH (L, C, h=128°) | Use | Replaces |
|---|---|---|---|---|
| `accentWash` | `#223403` | 0.30, 0.075 | Icon-badge fill, selected row, unlock chip | `accent.opacity(0.16)` = `#2E3A1C` (C 0.051) |
| `accentDim` | `#3B5800` | 0.42, 0.11 | Glow core, ring track beneath an active accent ring, hairline on a highlighted card | `accent.opacity(0.4)` borders |

Accent text on `accentWash` is 11.15:1 [Calc]. The point is not "make it brighter"; it is that
`opacity` tints of a saturated color on near-black lose chroma faster than they lose lightness, so
they read as a different, dirtier color instead of a dimmer version of the accent. [Judgment on how
it looks; the chroma numbers are Calc.] This is Linear's principle: derive the family from one
accent in a perceptual space (Linear generates its themes from base, accent, and contrast in LCH)
[3P: Linear].

**C. Static glow on earned states only.** The spec's "subtle inner glow on active elements" (§16)
has no token today. Two static pieces cover it: a 1px `accentDim` inner stroke on an active card or
ring, and, for *completed/earned* states only (a full ring, the Time Bank fill), an outer
`Theme.Colors.accent.opacity(0.35)` `.shadow(radius: 14)`. Both static, no animated radius (section
2.5). On OLED near-black a glow is visible at low brightness where a fill-only tier change is not
[Judgment].

**D. Elevation semantics.** Add `Theme.Colors.backgroundElevated` (start with the existing
`surface` hex, `#141416`) and use it as the fill for anything that presents over the app when a
system sheet material is *not* in play (full-screen covers such as `UnlockCelebrationView`,
`AlarmRingingView`, onboarding). It costs no new color and restores HIG's base-vs-elevated
distinction [Apple, Dark Mode] for D5.

### 3.4 Optional: retune the ladder (only if 3.3 is not enough on a device)

If, on an OLED panel at low brightness, cards still merge with the canvas after edge light and
tracks, widen the steps. Same faint cool tint, four tiers [Calc]:

| Tier | Hex | L* | `muted` `#8E8E93` contrast on it |
|---|---|---|---|
| background | `#0A0A0B` (unchanged) | 2.76 | 6.07:1 |
| surface | `#18181A` | 8.32 | 5.44:1 |
| surface2 | `#242427` | 14.31 | 4.75:1 |
| surface3 (pressed, selected) | `#313135` | 20.47 | 3.97:1 (fails AA) |

Widening costs muted-text contrast. If adopted, lift `muted` to `#A1A1A6` (6.61:1 on today's
`surface2`; higher on the old tiers) at the same time. Spec §15 marks these hex values "starting
point, tune after image-gen exploration," so this is within the spec's own remit, but
`Theme.swift`'s header treats them as spec-authoritative, so amend §15 first. **Recommendation:
do 3.3 first, ship, look at a device, and only then decide on 3.4.** [Judgment]

### 3.5 True black vs `#0A0A0B`

Apple's own dark base on iPhone is `#000000` and Google's guidance is `#121212` (both from memory,
not re-fetched). ZANO's `#0A0A0B` sits
between and both camps are defensible. Real cost of not being black: the Dynamic Island cutout is
pure black, so a `#0A0A0B` canvas shows a faint pill edge at the top of every screen, and Live
Activity backgrounds that paint `#0A0A0B` can show a seam against the island [Judgment; not
verified]. Not worth changing the token; worth making the *expanded Live Activity/Dynamic Island*
regions transparent or `#000` (section 7).

### 3.6 What the reference apps actually do (text sources only)

I could not look at screenshots: the fetch tools return page text, not images, so everything below
comes from published design-system text and third-party write-ups, not from seeing the apps.
Treat "how they look" as secondhand.

| Reference | What the sources say | Takeaway for ZANO |
|---|---|---|
| Apple system dark | Two background sets, base (recedes) and elevated (advances); dark palette is not a black inversion; prefer system backgrounds so the distinction is perceptible [Apple, Dark Mode] | Reproduce base-vs-elevated semantics in custom tokens (3.3.D) |
| Spotify | Widely published `#121212` base, `#181818`/`#282828` layers, one green accent [from memory] | Same shape as ZANO's system (near-black ladder + one accent); ZANO's steps are tighter |
| Raycast / Vercel-style cards | Near-black card fill, `rgba(255,255,255,0.06)` 1px border, 1px top inner highlight, large ambient shadow [3P reverse-engineering] | The edge-light recipe in 3.3.A |
| Linear | Near-monochrome dark chrome; color only for status and accent; elevation and themes generated from base/accent/contrast in LCH [3P: Linear's own post] | Derive tints perceptually (3.3.B); keep chrome neutral |
| WHOOP | Black backgrounds so colored data "pops"; green/yellow/red vocabulary repeated everywhere; hero score around 72pt-equivalent [3P] | Closed hue vocabulary (A2, A6); big numerals are a hierarchy tool, not decoration |
| Opal (the direct category peer) | Dark UI, playful 3D "gems" for milestones, gamified focus score; visual details not documented in what I could fetch [3P] | Confirms the category tolerates game-progress energy; do not copy the mascot/gem approach (section 9) |

---

## 4. The single-accent system

### 4.1 What current practice says

- **Apple, brand identity (WWDC26 251):** use color intentionally for hierarchy and grouping,
  indicating interaction (tint), and status/feedback; restraint "maximizes impact"; with Liquid
  Glass, move brand color into the content area so controls stay clean. Slack's example: tint used
  sparingly for primary actions, unread badges, new message, selected tab [Apple].
- **Apple, HIG Color:** apply color sparingly to glass; only the primary action gets a colored glass
  background; "avoid using the same color to mean different things"; "avoid relying solely on
  color" to differentiate objects or communicate essential information [Apple].
- **Apple, HIG Buttons:** limit prominent buttons to 1-2 per view [Apple].
- **Linear:** near-monochrome chrome, three theme inputs (base, accent, contrast), everything else
  derived in LCH [3P].
- **WHOOP:** "every hue carries meaning"; a three-color vocabulary repeated on every screen so it is
  learned once [3P: 925studios].

Synthesis [Judgment]: single-accent systems work when (1) the accent has exactly one meaning, (2)
neutrals are one tinted family, (3) accent tints are derived perceptually, (4) on-fill label color
is a contrast rule, not a per-screen choice, and (5) any additional hues form a small closed set
with a stated rule about where they may appear.

### 4.2 Audit of `Theme.Colors` against that [Calc]

| Check | Result | Verdict |
|---|---|---|
| `accent` on `background` / `surface` / `surface2` | 16.40 / 15.25 / 14.09 : 1 | Excellent |
| `text` on accent | **1.11 : 1** | Must never happen; use `background` (16.40:1) |
| `text` on `danger` fill | **3.13 : 1** (fails 4.5) | Use `background` on danger fills (5.81:1) |
| `danger` as text/icon on `surface` / `surface2` | 5.40 / 4.99 : 1 | Passes AA; borderline for small text on `surface2` |
| `muted` on `surface` / `surface2` | 5.64 / 5.21 : 1 | Passes 4.5; HIG recommends 7:1 for small custom text [Apple, Dark Mode]; no Increase Contrast variant exists |
| `focus` `#5E5CE6` on `surface` / `surface2` | **3.64 / 3.36 : 1** | Passes 3:1 as a graphic; fails 4.5:1 as text or small icon |
| Perceived lightness of the four spec rings (OKLCH L) | accent 0.92, protein 0.72, water 0.71, focus **0.56** | Focus reads visibly weaker than its siblings on OLED |
| Min pairwise dE2000 across the four spec rings, normal + 3 CVD simulations | 14.7 | Spec's four hues are safe as a set |

### 4.3 Where the additive ring palette breaks the "one accent" intent

`Theme.Colors.Ring` extends the spec's four hues with eight chromatic "assumption" hues (plus a
neutral `custom`) borrowed from Apple's system palette [Read]. Problems:

1. **Semantic collisions.** `steps` `#32D74B` is a second green next to the accent lime
   (dE2000 15.7 in normal vision; 10.7 protan); `sunrise` `#FFD60A` is a second yellow next to
   `warning` `#FFB020` and next to the accent (dE2000 3.1 against the accent under deuteranopia).
   HIG: "avoid using the same color to mean different things" [Apple]. If a green ring can mean
   "steps" and the acid-green accent means "earned," the accent's meaning is diluted.
2. **They cannot be kept distinct.** Of the 66 pairs among the 12 chromatic ring hues, 18 fall
   below dE2000 12 (my rough threshold for "reads as the same hue at ring-stroke width on dark") in
   at least one of normal / protan / deutan / tritan vision. In normal vision alone, `water` vs
   `cold` is 7.6 and `creatine` vs `danger` is 11.0. I also ran a greedy hue search on the OKLCH
   wheel (L 0.74-0.78, C 0.12-0.15) with the four spec hues fixed (focus lifted per A3) and added
   four more: the worst-case pair fell to 9.3 after the first extra hue and 6.2 after the fourth.
   That is a search, not a proof, but it points the same way as the audit: a 12-hue palette is not
   distinguishable by color alone under CVD, and this is a property of color perception, not a
   tuning problem. [Calc]
3. **The comment in `Theme.swift` calls them "Apple's own system palette hues," but Apple changed
   its system color values in iOS 26** (HIG Color change log, 2025-06-09) [Apple]. The "native
   look" premise is stale, and Apple states the values only as swatch images, so I cannot verify
   the new numbers.

### 4.4 Recommendations

| # | Change | Token / file | Notes |
|---|---|---|---|
| A1 | **Glyph-first rule.** Every ring, row, and chart must identify its goal by glyph or label, never by hue alone. Hue is redundant reinforcement | `GoalRing` (`center: .icon`), `RingClusterCell`, `GoalRow`, widgets | HIG "Differentiate Without Color" [Apple, Accessibility]. This is what makes A2 safe |
| A2 | **Map every goal type into the four spec hues plus neutral, and tell goals apart by glyph.** Suggested mapping: accent = workout, steps, stretch/mobility (the Move family); protein orange = protein, creatine, meal prep (Fuel); focus indigo = focus, reading, sleep-on-time, sunrise alarm (Mind/Rest); water blue = water, cold shower/sauna; `muted` = custom. Option 2 if a family feels too crowded: allow at most 3 supplemental hues chosen for CVD separation (the search in 4.3 suggests roughly 7 chromatic hues is the practical ceiling) | `Theme.Colors.Ring`, `Ring.color(for:)` | Removes the `steps`-green and `sunrise`-yellow collisions and gives the accent one meaning again. Trade-offs: two rings of one family shown side by side share a hue, which is exactly what A1 (glyph-first) covers; and it extends the accent to steps/stretch rings, so if that dilutes "earned," give those two a neutral (`text` at reduced opacity) ring instead. Needs a design decision, so it is a proposal, not a patch |
| A3 | Lift `focus` from `#5E5CE6` to `#6F71FC` (OKLCH L 0.62, same hue 278, chroma kept; in sRGB gamut) | `Ring.focus` | 4.77:1 on `surface`, 4.41:1 on `surface2`, evens ring weight. Amend §15 (spec lists `#5E5CE6`). Optional if `focus` is never used as text/icon |
| A4 | Codify on-fill labels: `Colors.onFill` (3.3.A) for accent, danger, warning fills | `PrimaryButton`, `PaywallCard` badge, share cards | Removes the class of bug in section 11.1 |
| A5 | Add `accentWash`/`accentDim` (3.3.B) | `Theme.Colors` | Replaces ad hoc `accent.opacity(...)` across `LockStatusCard`, `PrimaryButton`, `PaywallCard`, etc. |
| A6 | **Accent budget**, written into §15: per screen at most one accent-*filled* control, plus accent only for earned/unlock state and the workout ring. Data hues appear only as ring strokes or glyph tints inside their own goal's ring or row; never as button fills, backgrounds, or text | Spec §15, code review checklist | Matches Apple's "1-2 prominent buttons per view" and WHOOP's closed vocabulary |
| A7 | Root `.tint(Theme.Colors.accent)` (asset catalog `AccentColor` is already correct) | `ZANOApp.swift` (other workflow) | So system toggles, pickers, selected tab pick up the accent instead of blue |

---

## 5. Typography

### 5.1 What is verified in the current code [Read]

`Theme.Typography` is 8 members, all `.system(size: N, ...)` with a fixed `N`; they do not scale
with Dynamic Type. `numeral*` use `.rounded`. 23 call sites use the numerals across 20 files (including Watch); 68
literal `.font(.system(size:` sites across 35 files (app, widgets, watch) bypass Theme entirely.
So a Theme-only fix reaches the tokens, not the literals: the literals need a grep-and-migrate pass.

### 5.2 What Apple now says

- Dynamic Type is required on iOS; use text styles; test up to the accessibility sizes [Apple,
  Typography]. Support enlargement up to 200% [Apple, Accessibility]. Custom fonts must implement
  the same behaviors (`relativeTo:`) [Apple, Typography; 3P: Crosley].
- Dec 2025: emphasized weights added to the Dynamic Type spec (Large Title, Title 1-2 Bold;
  Title 3, Body, Headline Semibold) [Apple, Typography].
- iOS 26 style: bolder, left-aligned, tighter leading for hierarchy; left-align in critical moments
  such as alerts and onboarding [Apple, WWDC25 356].
- Tight leading for 1-2 line list rows, avoid tight for 3+ lines [Apple, Typography]. `Font.leading`.
- Avoid Ultralight/Thin/Light [Apple]. ZANO's lightest is Regular: fine.
- Width axis (`.compressed/.condensed/.standard/.expanded`, iOS 16+) is meant for display sizes, "rarely
  the right axis for body text" [3P: Sarunw, Crosley]. Rounded is for a friendly tone (Fitness rings,
  Watch) and "not a universal UI replacement" [3P: Crosley].
- Minimum iOS text size 11pt; ZANO's smallest is 13: fine [Apple].

### 5.3 Recommendations tied to `Theme.Typography`

| Token | Today | Proposed | Note |
|---|---|---|---|
| `title` | `.system(22, .bold)` | `.title2.weight(.bold)` | 22pt at default size; Apple's emphasized Title 2 is Bold |
| `headline` | `.system(17, .semibold)` | `.headline` | Identical at default |
| `body` | `.system(15, .regular)` | `.subheadline` | ZANO "body" is Apple's Subheadline (15). Apple's `.body` is 17. Do not rename silently: decide whether long-form text should be 17 |
| `caption` | `.system(13)` | `.footnote` | 13 at default |
| `captionEmphasized` | `.system(13, .semibold)` | `.footnote.weight(.semibold)` | |
| `numeralLarge/Medium/Small` | fixed 44/28/17, `.rounded`, `monospacedDigit` | `@ScaledMetric` via a modifier (below) | Static `Font` functions cannot hold `@ScaledMetric`; a `ViewModifier` can |
| (new) `eyebrow` | none | `.footnote.weight(.semibold)`, uppercase, `tracking(0.8)` | The all-caps small labels the mockups imply need positive tracking; SF Pro auto-tracks by size but not for caps runs [Judgment] |

```swift
// proposed: Core/UI. Cap ring/pill numerals so AX5 doesn't blow out a 148pt ring.
public struct ZanoNumeral: ViewModifier {
    public enum Scale { case large, medium, small }
    public let scale: Scale
    @ScaledMetric(relativeTo: .largeTitle) private var large: CGFloat = 44
    @ScaledMetric(relativeTo: .title)      private var medium: CGFloat = 28
    @ScaledMetric(relativeTo: .headline)   private var small: CGFloat = 17

    public func body(content: Content) -> some View {
        let size: CGFloat = switch scale { case .large: large; case .medium: medium; case .small: small }
        // large/medium: condensed default design (proposal); small: keep rounded for pill counts.
        let font: Font = scale == .small
            ? .system(size: size, weight: .bold, design: .rounded)
            : .system(size: size, weight: .bold).width(.condensed)
        content
            .font(font.monospacedDigit())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
```

**Numeral face: an opinion, needs an A/B on a device.** Spec §15 says "big numerals … e.g., a
condensed grotesque" and describes the feel as "ranked mode … not childish." `.rounded` bold is
the friendliest face Apple ships (Fitness/Timer) [3P: Crosley], which pulls toward "wellness," the
opposite of the brief [Judgment]. SF Pro Condensed at display size is a zero-cost, no-bundled-font
way to meet the spec's literal wording, it fits more characters in a ring center (the ring center
currently relies on `minimumScaleFactor(0.6)` to fit strings like `72/150g` [Read]), and it reads as
athletic rather than cozy. Recommended: `numeralLarge` and `numeralMedium` to condensed default
design; keep `numeralSmall` rounded for pill counts. Verify that `.width(.condensed)` combines
with `.monospacedDigit()` as expected (12).

The prior docs' `.contentTransition(.numericText(value:))` recommendation still applies on top of
this; nothing here conflicts.

---

## 6. Shape and concentricity

**What shifted.** iOS 26 controls are capsules at all sizes; capsules are used "a lot" because they
support concentricity and touch-friendly layouts; nested content should use a *concentric* radius
(parent radius minus padding); `buttonBorderShape(.capsule)` is now the default for bordered
buttons [Apple, WWDC25 356 and 323]. SwiftUI exposes `ConcentricRectangle` /
`.containerConcentric` corners on iOS 26 [Apple, WWDC25 323].

**ZANO today.** `Radius.small = 12` is documented as "small controls (pills, chips, buttons)" and
`PrimaryButton`, the hold-to-commit body, and its border all use it [Read]. A 12pt rounded rectangle
button next to a system capsule tab bar and capsule system buttons is the previous era's idiom.

**Good news: the radius and spacing tokens already compose concentrically** in three pairings, and
this should be written down and enforced instead of rediscovered:

| Outer | Inset | Inner = outer − inset | Token pair |
|---|---|---|---|
| `Radius.medium` 20 | `Spacing.xs` 8 | 12 | medium card holding a small tile |
| `Radius.large` 28 | `Spacing.xs` 8 | 20 | large surface holding a medium card |
| `Radius.large` 28 | `Spacing.md` 16 | 12 | large surface holding a small tile with generous inset |

Other combinations (e.g. 20 with a 12 inset = 8) have no token and will look slightly off. A
one-line helper makes this checkable:

```swift
extension Theme.Radius {
    /// Concentric inner radius: outer − inset (WWDC25 356). Prefer the three pairings above.
    static func inner(of outer: CGFloat, inset: CGFloat) -> CGFloat { max(0, outer - inset) }
}
```

**Recommendations.**

- **S1:** Controls (`PrimaryButton` both styles, `PaywallCard` badge, chips) become `Capsule()`;
  `Radius.small` stays for non-control tiles. This is a §15 amendment (spec lists Radius 12/20/28
  without saying what each is for). Consider a taller primary CTA (around 52pt) rather than the
  roughly 46pt that a 17pt `headline` line plus `Spacing.sm` vertical padding yields [Judgment].
- **S2:** Icon-badge circles (`LockStatusCard` 40pt, `GoalRow` 32pt, `GhostProgressBanner` 40pt)
  stay circles (a circle is the capsule case, radius = half the height). Only the size drift called
  out in `apple-design-review.md` 8.2 needs a token.
- **S3:** On iOS 26+, nested rounded rectangles that hug a display corner (full-bleed hero cards at
  the screen edge) can use `ConcentricRectangle`; behind `#available`, low priority.

---

## 7. Surfaces ZANO does not draw itself

These are outside `Core/UI` and mostly owned elsewhere this run; the recommendations are for
whoever owns them.

### 7.1 Widgets (`Extensions/ZANOWidgets`)

Home Screen widgets now render in four appearances: Light, Dark (full color) and Clear (Liquid
Glass), Tinted (desaturated + the user's tint) [Apple, HIG Widgets]. In Clear/Tinted the system
**drops the widget background** and splits the view into an accent group and a primary group
(`widgetAccentable`). ZANO's Home widget sets a fixed
`containerBackground(ZANOWidgetColor.background)`, and there is exactly one `widgetAccentable()` in
the repo (`ZANOLockScreenWidget.swift:182`) [Read]. In
Tinted mode, ZANO's hue-coded rings (accent/protein/focus/water) will flatten to one tint, so:

- Mark ring strokes and the lock badge `widgetAccentable()`; leave numerals in the primary group.
- Ensure ring identity survives desaturation: glyph + label + ring *position*, not hue (this is
  A1 again, and it is a direct product requirement here).
- Use `@Environment(\.widgetRenderingMode)` to drop the glow/edge treatment in accented modes.
- `ZANOWidgetColor.swift` (and `WatchTheme.swift`) duplicate `Theme.Colors` [Read]. Any token change
  in section 3/4 must be mirrored there until the duplication is removed (already flagged in
  `ui-stress-test-findings.md` 4.1).

### 7.2 Live Activities and Dynamic Island

Expanded Dynamic Island regions sit on the hardware's pure black. Paint them transparent or `#000`
so the island and content merge; a `#0A0A0B` fill can show a seam [Judgment, not verified].

### 7.3 Shield (`ZANOShieldConfig`)

`ShieldConfiguration` accepts only `backgroundBlurStyle` (`UIBlurEffect.Style`), `backgroundColor`
(`UIColor`), `icon` (`UIImage`), and `Label`s with `UIColor`s [Apple, ManagedSettingsUI]. It is not
SwiftUI, so the ring, edge-light, and glass treatments do not apply; the in-app `ShieldPreview` can
only approximate it. Today's extension sets `.systemMaterialDark`, no `backgroundColor`, no `icon`,
and re-declares the accent hex as a private `UIColor` [Read]. Cheap wins:

- Set `backgroundColor` to `#0A0A0B` at ~0.7 alpha so the blur is brand-tinted near-black rather than
  the system's default gray-dark [Judgment].
- Provide an `icon` (lock glyph) so the shield has a focal point beyond text.
- Single-source the accent through a `#if canImport(UIKit)` `Theme.UIColors` in Core (UIKit is
  permitted here because the API requires it, per CLAUDE.md).

### 7.4 App icon

WWDC26's design guide describes Icon Composer's multi-layer icon format with per-appearance
annotations and Liquid Glass layer properties [Apple, WWDC26 design guide]; the iOS 26 appearances
are Default, Dark, Clear, and Tinted. The project has a classic
`AppIcon.appiconset` [Read]. A flat legacy icon is likely to look unmigrated beside glass-layered
icons [Judgment; the system's fallback treatment for legacy icons is unverified]. For the Tinted
appearance the system desaturates: design the mark to survive on luminance, not hue (an acid-green
mark on near-black already does). Owner: the workflow that owns `Assets.xcassets`.

---

## 8. Motion (deliberately brief; see `apple-design-review.md`)

- HIG Reduce Motion now reads: reduce automatic/repetitive animation, "tighten animation springs
  (reduce bounce)," replace x/y/z transitions with fades, avoid animating depth changes or blurs
  [Apple, Accessibility]. The gating already in `Theme.Motion` and the components (`nil` or a short
  ease) is consistent with that.
- New constraint from this doc's recommendations: static glow/edge only. Do not add an animated
  blur radius to "breathe" the accent glow.
- `Theme.Motion` springs are still `spring(response:dampingFraction:)`. That API is not deprecated;
  a future cleanup could re-express them as `spring(duration:bounce:)` for legibility with no visual
  change. Low priority.
- Apple's own glass buttons scale, bounce, and shimmer on press (`interactive()`) [Apple, WWDC25
  323]. `PrimaryButton`'s 0.97 scale + spring already matches the *feel*; no change.

---

## 9. Considered and rejected

| Trend | Why not for ZANO |
|---|---|
| Glass cards / glassmorphism everywhere | Apple says not on the content layer; nothing behind ZANO's flat canvas to refract; costs legibility (NN/G's core critique of iOS 26 was translucent controls over busy content) [Apple, 3P: NN/G] |
| Multi-hue gradients / animated mesh backgrounds (`MeshGradient`, iOS 18+) | Fights "one accent"; continuous animated backgrounds are a Reduce Motion and battery cost; wrong tone ("confident, not childish") |
| Bento grids as a layout system | Fine as a grid, but not a visual language ZANO needs; adds nothing to the defects in sections 3, 4, and 11 |
| 3D collectible rewards (Opal's gems) [3P] | A category move, not a token move; conflicts with restraint |
| Neumorphism / soft double shadows | Shadows cannot show on near-black; edge light does the same job honestly |
| Switching to system semantic colors wholesale | HIG prefers them, and they carry base/elevated for free, but §15's palette *is* the brand; keep custom tokens and reproduce the two behaviors that matter (elevation semantics, increased-contrast variant) |

---

## 10. Prioritized recommendations

Effort: S (< 1h), M (half day), L (day+). "Device" = needs a real screen to accept.

| Pri | Change | Where | Source | Effort | Device? | §15 amendment? |
|---|---|---|---|---|---|---|
| P0 | Fix `holdToCommit` label-on-fill contrast (section 11.1) | `PrimaryButton.swift:99` | Calc | S | Yes (look) | No |
| P0 | `hairline` = white@0.08; add `track` = white@0.10; use `track` in `GoalRing` and `TimeBankBar` | `Theme.swift`, 2 components | Calc | S | Yes | Additive (new tokens; `hairline` is not in §15's table) |
| P0 | Add `onFill`; apply to every accent/danger/warning fill | `Theme.swift`, `PaywallCard` badge, any share card | Calc | S | No | No |
| P0 | `ZanoSurface` modifier (edge light) and migrate the 43 fills, starting with `LockStatusCard`, `GoalRow`, `RecapCard`, `PaywallCard` | Core/UI | Read, 3P | M | Yes | No |
| P1 | Dynamic Type: semantic styles in `Theme.Typography` + `ZanoNumeral` + migrate the 68 literals | `Theme.swift`, 35 files | Apple | L | Yes (AX sizes) | Yes (type line) |
| P1 | `accentWash` / `accentDim`; replace `accent.opacity(0.16/0.4)` | `Theme.swift`, `LockStatusCard`, `PrimaryButton`, `PaywallCard` | Calc | S | Yes | Additive |
| P1 | Controls to `Capsule()`; document the three concentric pairings; `Radius.inner` helper | `PrimaryButton`, `PaywallCard` | Apple | S | Yes | Yes (radius usage) |
| P1 | `zanoBottomBar` (`safeAreaBar` on 26+) in `TodayView` | `TodayView.swift:105-111` | 3P/Apple | S | Yes | No |
| P1 | Glyph-first rule; audit every ring/row for a glyph or label | `GoalRing`, `RingClusterCell`, widgets | Apple, Calc | M | No | Add rule |
| P1 | Increase Contrast variants: `muted` to `#A1A1A6`, stronger edge | `Theme.swift` (via `colorSchemeContrast` in modifiers) | Apple | M | Yes | No |
| P2 | Ring family collapse (A2) and `focus` lift (A3) | `Theme.Colors.Ring` | Calc | M | Yes | Yes |
| P2 | Numeral face A/B: rounded vs condensed default vs expanded | `numeralLarge/Medium` | Judgment | S | Yes | Yes |
| P2 | Widgets: `widgetAccentable`, rendering-mode branches; Dynamic Island transparency; Shield `backgroundColor`/`icon`; layered app icon | Extensions, Assets | Apple | M | Yes | No |
| P2 | Elevation semantics `backgroundElevated` for full-screen covers | `Theme.swift`, celebration/alarm/onboarding | Apple | S | Yes | Additive |
| P3 | Ladder retune (3.4) | `Theme.Colors` | Calc | S | Yes | Yes |

**Proposed §15 amendments, consolidated:** (1) add `hairline` definition, `track`, `onFill`,
`accentWash`, `accentDim`, `backgroundElevated`; (2) Radius: state which token is for controls
(capsule) vs surfaces; (3) Type: "SF Pro text styles with Dynamic Type; numerals via ScaledMetric,
face TBD after device A/B"; (4) Color: add the accent budget (A6) and the glyph-first rule (A1);
(5) `focus` lift and ring-family collapse if accepted. `docs/spec.md` was not edited by this task.

---

## 11. Incidental code findings (for whoever owns these files)

Found while tying the research to real call sites. None were fixed here.

**11.1 `PrimaryButton.holdToCommit` label goes illegible as the fill sweeps** [Read, Calc].
`PrimaryButton.swift:99` sets `.foregroundStyle(Theme.Colors.text)` (`#F5F5F7`) for the whole
label, while the background fill sweeps to `accent.opacity(0.9)` over `surface2` (`#A8E839`). Light
text on that fill is **1.35:1** (on the unfilled `surface2` it is 15.61:1). So as the user holds,
the label washes out exactly where the fill passes under it, on the app's most consequential
confirmation control. The `.standard` style is correct (`background` on accent, 16.40:1).
Fix pattern (standard for slide/hold controls): render the label twice, a light one on the track
and a dark (`onFill`) copy above it masked to the same `width * holdProgress`, so the color flips
exactly at the fill edge:

```swift
label.foregroundStyle(Theme.Colors.text)
    .overlay(alignment: .leading) {
        GeometryReader { proxy in
            label.foregroundStyle(Theme.Colors.onFill)
                .frame(width: proxy.size.width, alignment: .leading)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: proxy.size.width * holdProgress)
                }
        }
    }
```

The same "light text on a tinted progress fill" pattern is worth grepping in `AlarmRingingView`'s
escape hatch and `Screen14FirstWin`'s `EmergencyHoldControl` (both hand-roll the hold gesture per
`ui-stress-test-findings.md` 1.1).

**11.2 `PaywallCard.swift:109`** has `.animation(Theme.Motion.springStandard, value: isSelected)`
with no `accessibilityReduceMotion` gate; `PaywallCard`, `OnboardingQuestion`, `ShareCard`, and
`FounderSeriesCard` are the four Core UI components with no reduce-motion reference at all [Read].
Its unselected border uses `hairline` (invisible, D1).

**11.3 The type literal count** (68 sites/35 files) means that fixing Theme alone will leave most
of the app fixed-size; plan the migration as a mechanical grep pass after the token change.

---

## 12. What could not be verified, and the device checklist

**Not verifiable in this environment (state as assumptions, not facts):**

1. Whether the iOS 27 "Liquid Glass" slider affects third-party glass, or only system UI. Engadget
   does not say [Press]. Assume it can affect any glass ZANO uses; ZANO uses system chrome only.
2. Label legibility of `glassProminent` / `glassEffect(.regular.tint(accentLime))`. A light accent
   tint on glass with a white label is a known contrast risk; developer forums report inconsistent
   tint rendering [3P]. That is why section 2.2 keeps the CTA opaque.
3. `fill.shadow(.inner(... radius: 0 ...))` rendering as a crisp 1px highlight.
4. `.width(.condensed)` + `.monospacedDigit()` composing as expected in a ring center.
5. `ImageRenderer` fidelity for materials/blur (assumed unreliable, so share cards stay opaque).
6. Dynamic Island / Live Activity seam with `#0A0A0B` (3.5, 7.2).
7. Apple's iOS 26+ system color values (published as swatch images only).
8. Whether `ZANOApp` builds pick up `AccentColor` for system controls without an explicit root
   `.tint`.
9. Exact iOS 27 glass details beyond Apple's press language ("darkened edge," "brighter specular
   highlights"), which come from press summaries.
10. The `UIDesignRequiresCompatibility` iOS 27 behavior (third-party quotes of Apple's docs).

**Method for the [Calc] numbers**: sRGB to linear to WCAG 2 relative luminance and contrast; CIE
L*a*b* (D65) and CIEDE2000; OKLab/OKLCH (Ottosson); Machado et al. 2009 CVD matrices (severity 1.0)
applied in linear RGB. The scratch scripts that produced them live in this session's scratchpad, not
in the repo (this task was limited to writing this file); they are short enough to re-create from
this description if someone wants to re-run them or to add a `tools/` script later.

**When a Mac exists, render this matrix before accepting any token change:**

| Axis | Values |
|---|---|
| OS | iOS 26.x and iOS 27 |
| Liquid Glass slider (iOS 27) | ultra clear, default, fully tinted |
| Accessibility | Increase Contrast on, Reduce Transparency on, Reduce Motion on, Bold Text on |
| Text size | Default, AX3, AX5 |
| Color filter (Settings > Accessibility > Display & Text Size > Color Filters) | Red/Green (deuteranopia), Red/Green (protanopia), Blue/Yellow (tritanopia), Grayscale |
| Brightness | 100%, 30%, minimum (OLED near-black steps) |
| Widget appearance | Default, Dark, Clear, Tinted |
| Screens | Today (locked and earned), Lock, Fuel, Paywall, ShieldPreview, hold-to-commit mid-hold, Trophy |

Acceptance test for section 3: at 30% brightness, can you tell where a card ends and where a ring's
unfilled portion is, on Today, with no squinting? If yes with 3.3 alone, skip 3.4.

---

## 13. Sources

**Apple (primary)**

- WWDC26 "Communicate your brand identity on iOS" (251): https://developer.apple.com/videos/play/wwdc2026/251/
- WWDC26 "Principles of great design" (250): https://developer.apple.com/videos/play/wwdc2026/250/
- WWDC26 "What's new in SwiftUI" (269): https://developer.apple.com/videos/play/wwdc2026/269/
- WWDC26 Design guide: https://developer.apple.com/wwdc26/guides/design/
- Apple newsroom, June 2026 (iOS 27): https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/
- WWDC25 "Get to know the new design system" (356): https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC25 "Meet Liquid Glass" (219): https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 "Build a SwiftUI app with the new design" (323): https://developer.apple.com/videos/play/wwdc2025/323/
- HIG: Materials, Color, Dark Mode, Typography, Accessibility, Buttons, Widgets, Tab Bars, Sheets,
  Layout: https://developer.apple.com/design/human-interface-guidelines/
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- ShieldConfiguration: https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration

**Press**

- MacRumors, "How Liquid Glass Is Changing in iOS 27": https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/
- MacRumors, "Apple Releases iOS 27": https://www.macrumors.com/2026/09/14/apple-releases-ios-27/
- Engadget, iOS 27 Liquid Glass slider: https://www.engadget.com/2252856/how-to-adjust-liquid-glass-effect-ios-27/
- Cult of Mac, "5 biggest Liquid Glass changes in iOS 27": https://www.cultofmac.com/news/liquid-glass-changes-ios-27-macos-27
- Wikipedia, Liquid Glass (timeline): https://en.wikipedia.org/wiki/Liquid_Glass

**Third-party (lower authority; cited for color, not as authority)**

- NN/G, "Liquid Glass Is Cracked, and Usability Suffers in iOS 26": https://www.nngroup.com/articles/liquid-glass/
- Linear, "How we redesigned the Linear UI": https://linear.app/now/how-we-redesigned-the-linear-ui
- 925 Studios, WHOOP design breakdown: https://www.925studios.co/blog/whoop-design-breakdown
- Donny Wals, "Designing custom UI with Liquid Glass on iOS 26": https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/
- Donny Wals, "Mixing colors in SwiftUI and Xcode 16": https://www.donnywals.com/mixing-colors-in-swiftui-and-xcode-16/
- Codakuma / community notes on `safeAreaBar`: https://codakuma.com/floating-safe-area-bar/
- Blake Crosley, "SF Pro: variable axes, optical sizing, and the Dynamic Type contract": https://blakecrosley.com/blog/sf-pro-typography-system
- Sarunw, SF font width styles: https://sarunw.com/posts/sf-font-width-styles/
- Raycast design-system write-up (reverse-engineered, third party): https://oh-my-design.kr/design-systems/raycast
- Opal UI breakdown (screensdesign): https://screensdesign.com/showcase/opal-screen-time-control
- ecorpit, iOS 27 migration notes (source for the `UIDesignRequiresCompatibility` claim): https://ecorpit.com/ios-27-liquid-glass-xcode-27-migration-guide-2026/
