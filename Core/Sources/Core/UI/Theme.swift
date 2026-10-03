// Theme.swift
// Core / UI
//
// The single source of design tokens for every ZANO surface (app + extensions), per
// docs/spec.md §15 "Design System & UI Direction". Every component in `Core/Sources/Core/UI`
// and every app-only screen in `App/ZANO/Features` must build its visuals exclusively from
// `Theme` — no ad hoc hex literals or magic numbers outside this file (spec §15, CLAUDE.md
// "Conventions").
//
// Light mode (2026-10-03, founder: "A light mode for the app would be nice"). Every colour token
// resolves per colour scheme: the dark values are the visual-direction-v2 palette unchanged, the
// light values are its cool-soft-white twin (docs/design/visual-direction-v2.md §10). The pairs are
// `ZanoTone`s in `Theme.Tones`; `Theme.Colors` builds a dynamic `Color` from each (a `UIColor`
// dynamic provider, no asset catalog), so token names and call sites are unchanged and the whole
// app adapts. The app follows the system appearance unless Settings > Appearance overrides it
// (`ZanoAppearance`, applied once at the root). A few surfaces stay dark on purpose (alarm ringing,
// unlock celebration, share posters/moments, the shield); see §10 of that document.

// No user-facing copy lives here (CLAUDE.md: "User-facing copy lives in Core/Sources/Core/Copy").
// `Theme` only ever exposes colors, radii, spacing, type ramps, and motion curves.
//
// Design-quality pass (docs/design/{better-ui,typography-color,2026-ios-trends,composition-audit}
// findings, 2026-09-23). What changed here and why, in one place so nobody has to re-derive it:
//
//   * Separation. `surface` on `background` is 1.08:1 and the old `hairline` (surface2 @ 0.8) was
//     1.06:1 against its own card, so cards, dividers, tracks and unselected borders were
//     effectively invisible. `hairline`, `hairlineStrong` and `track` are now white overlays
//     (pure white, not `text` — a tinted near-white edge reads as dirt on near-black). Measured
//     (WCAG, over `surface`): hairline 1.40, hairlineStrong 1.86, track 1.61.
//   * Accent tints. `accent.opacity(0.16)` composites to a drab olive (#2E3A1C). `accentWash` and
//     `accentDim` are precomputed, on-hue tints instead (`Color.mix` is iOS 18; the deployment
//     target is 17).
//   * On-fill labels. `onFill` (near-black) is the label for anything drawn on a pearl, danger or
//     warning fill (18.0 / 5.5 / 9.2:1). White-on-blue buttons use `onAccent` on `accentFill`
//     (5.3:1), not on `accent` itself (white on `#3F7BFF` is only 3.8:1).
//   * Type. Text styles now map to system text styles, so they follow Dynamic Type and read
//     identically to the old fixed sizes at the default setting (22/17/15/13). `numeralSmall` and
//     `numeralMedium` now follow Dynamic Type too (2026-09-24); larger numerals stay
//     fixed-size `Font`s for source compatibility, gain a hero tier (72pt), and `NumeralText`
//     (Components/NumeralText.swift) is the Dynamic-Type-aware way to render them.
//   * Edge light. The card edge (`edgeTop`/`edgeBottom`, `edgeGradient(increasedContrast:)`) and the
//     accent-control rim (`specular`) live here as tokens, so the *edges* of `ZanoSurface` and
//     `PrimaryButton` carry no opacity literals of their own. Their hue wash (10% / 18% active), glow
//     (22%) and pressed-glow (35%) strengths are still local to those two files: they are one-off
//     recipe constants, not shared tokens.
//   * Everything new is additive: no token was renamed or removed, and every `Theme.*` reference in
//     App and Core resolves against this file (the widget and watch targets keep their own mirrored
//     token files, `ZANOWidgetColor` and `WatchTheme`, and are unaffected). Two *existing* tokens
//     changed value, both deliberately: `hairline` (a visible white overlay instead of `surface2` at
//     0.8), and the text styles `title`/`headline`/`body`/`caption`/`captionEmphasized` (fixed point
//     sizes -> Dynamic Type text styles: identical at the default text size, larger at bigger ones,
//     so a fixed-height container around them needs to tolerate growth).

// Visual direction v2 (2026-10-02, docs/design/visual-direction-v2.md) retuned the palette (indigo
// ink canvas, saturated ring colours, ember), added the glass tokens, the `hero` radius, the score
// face (`Typography.score`), rounded headings and the v2 motion tokens. That document supersedes the
// spec's token table; the notes above describe the previous pass.

import SwiftUI
import UIKit

/// ZANO's design system: colors, radii, spacing, typography, and motion — all sourced from
/// docs/spec.md §15. Everything here is a value type / static constant; `Theme` itself is never
/// instantiated.
public enum Theme {

    // MARK: - Colors

    /// Color tokens. Every token resolves per color scheme (light mode, 2026-10-03): the dark value
    /// is the visual-direction-v2 palette unchanged, the light value is its "cool soft white" twin
    /// (docs/design/visual-direction-v2.md §10). The pairs live in `Theme.Tones`; these are the
    /// `Color`s built from them, so a view that reads `Theme.Colors.text` follows the scheme with no
    /// code of its own. Static lets on a non-actor enum holding `Color` (Sendable): safe from widget
    /// and other nonisolated code.
    public enum Colors {
        /// Dark `#0B0E24` indigo ink / light `#F5F6FB` cool soft white with a faint lavender. Not
        /// black, not pure white: the glass needs a little colour behind it.
        public static let background = Tones.background.color
        /// The bottom of the canvas gradient, under the tab bar and pinned action bars.
        public static let backgroundDeep = Tones.backgroundDeep.color
        /// Opaque surface: the solid glass fallback under Reduce Transparency, sheets. White in light.
        public static let surface = Tones.surface.color
        /// Secondary surface (nested solid wells, tracks, pressed states).
        public static let surface2 = Tones.surface2.color
        /// Primary text. Dark: warm white with a breath of violet (19.0:1 on ink). Light: ink
        /// `#13142B` (16.7:1 on the light canvas).
        public static let text = Tones.text.color
        /// Metadata text, about 70% of `text` (dark 7.6:1 on ink; light `#5C5E7E`, 5.8:1).
        public static let muted = Tones.muted.color

        /// Ember. Streak and fire moments only: the streak flame, the warm aurora blob of an earned
        /// day, milestone bursts. Never a control colour. Light `#B34A06` (5.0:1, usable as text).
        public static let ember = Tones.ember.color

        /// The aurora's light sources (`ZanoAuroraBackground`). Decorative only: never text. In
        /// light mode they are softer, pastel-leaning hues; the aurora's low opacities turn them
        /// into faint tints of the white canvas.
        public enum Aurora {
            public static let blue = Tones.auroraBlue.color
            public static let violet = Tones.auroraViolet.color
            public static let ember = Tones.auroraEmber.color
        }
        /// ZANO Blue, the primary accent. Dark `#3F7BFF` (5.32:1 on ink). Light `#2A62E6` (the same
        /// blue one step deeper: 4.9:1 on the light canvas, so it still works as text). Primary
        /// buttons, selection, the tab bar's lit tab and earned moments. Never under a white label
        /// in dark mode: a *filled* blue control uses `accentFill`.
        public static let accent = Tones.accent.color

        /// `#2A62E6` — the fill of a filled blue control (`PrimaryButton`'s `.accent` tint and its
        /// hold-to-commit sweep). White on it is 5.27:1 in both schemes.
        public static let accentFill = Tones.accentFill.color

        /// The brushed-metal fill of the logo mark and of earned hero moments. Dark: pearl top-left
        /// to silver bottom-right. Light: a darker steel (the silver vanishes on a white canvas).
        public static var metallic: LinearGradient { LinearGradient(
            colors: [metalLight, metalMid, metalDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ) }
        private static let metalLight = Tones.metalLight.color
        private static let metalMid = Tones.metalMid.color
        private static let metalDark = Tones.metalDark.color

        // MARK: Interactive

        /// An alias of `accent`, kept because 40+ call sites use it: selection strokes, the lit
        /// tab, chosen options. Same rules as `accent`. New code may use either name.
        public static let interactive = accent
        /// The fill behind a selected control (a chosen option, an active segment).
        public static let interactiveWash = Tones.interactiveWash.color

        // MARK: Ambient light

        /// The cool light a locked screen sits in: quiet, a little cold. Paired with `accent` for
        /// the earned state so the backdrop itself tells you where you stand.
        public static let lockedAmbient = Tones.lockedAmbient.color
        /// Top stop of a hero surface's vertical gradient (bottom stop is `surface`).
        public static let surfaceHero = Tones.surfaceHero.color
        /// Danger: the emergency unlock and nothing else. Light `#C42F3F` (5.1:1).
        public static let danger = Tones.danger.color
        /// Warning state (warm amber). Light `#9A5F00` (4.9:1).
        public static let warning = Tones.warning.color

        // MARK: Derived neutrals

        /// A crisp 1px edge/divider tone. Dark: white at 12% (1.40:1 over `surface`; pure white,
        /// not `text`: a tinted edge reads as dirt on near-black). Light: ink at 10%.
        public static let hairline = Tones.hairline.color

        /// A stronger edge for pressed / selected-neutral / Increase Contrast states.
        public static let hairlineStrong = Tones.hairlineStrong.color

        /// The empty part of a bar, pager dot or unearned grid tile. Rings use
        /// `Ring.track(for:)` instead (their own hue), not this.
        public static let track = Tones.track.color

        // MARK: Card edge light

        /// The card edge: a 1px *top-lit* gradient in dark mode (drop shadows are invisible on
        /// near-black), a plain ink hairline that darkens slightly toward the bottom in light mode
        /// (where the soft drop shadow does the lifting).
        public static let edgeTop = Tones.edgeTop.color
        public static let edgeBottom = Tones.edgeBottom.color
        /// The same edge under Increase Contrast (`colorSchemeContrast == .increased`).
        public static let edgeTopIncreased = Tones.edgeTopIncreased.color
        public static let edgeBottomIncreased = Tones.edgeBottomIncreased.color

        /// The card edge as a stroke style. `increasedContrast` swaps in the stronger pair.
        public static func edgeGradient(increasedContrast: Bool = false) -> LinearGradient {
            LinearGradient(
                colors: increasedContrast ? [edgeTopIncreased, edgeBottomIncreased] : [edgeTop, edgeBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// The specular rim on an *accent-filled* control (the top edge of `PrimaryButton`): white at
        /// 30%, in both schemes (it sits on blue). Only ever on a filled control, never on a card.
        public static let specular = Color.white.opacity(0.30)

        /// The label/icon colour for anything drawn ON a `text`/`metallic`, `danger`, `warning` or
        /// goal-colour fill: `background`. Dark: near-black ink on bright fills. Light: the white
        /// canvas on the deeper light-mode fills (every light fill clears 4.5:1 against it).
        public static let onFill = background

        /// Glass: the frost on a content card. Dark: white 9% at the top to 4% at the bottom, read
        /// through to the aurora. Light: a white frosted panel (86% → 66%).
        public static let glassFill = Tones.glassFill.color
        public static let glassFillTop = Tones.glassFillTop.color
        public static let glassFillBottom = Tones.glassFillBottom.color
        /// The raised (hero) glass: a step brighter.
        public static let glassRaisedTop = Tones.glassRaisedTop.color
        public static let glassRaisedBottom = Tones.glassRaisedBottom.color
        /// The tint laid over real material on chrome glass (tab bar, capsules): ink in dark mode so
        /// the blur reads ink-frosted, white in light mode so it reads milk-frosted, not system grey.
        public static let glassChromeTint = Tones.glassChromeTint.color
        /// The soft shade along a glass surface's bottom edge (inner shadow).
        public static let glassInnerShade = Tones.glassInnerShade.color
        /// The soft drop shadow under a light-mode glass card (clear in dark mode, where a shadow
        /// on ink reads as nothing). Light mode only lifts cards with this, not with an edge glow.
        public static let glassShadow = Tones.glassShadow.color
        /// A recessed well inside glass (`zanoWell`).
        public static let wellFill = Tones.wellFill.color

        /// The glass's rim: dark, a 1px specular stroke lit from above (white 35% at the top edge,
        /// nearly gone at the sides, a faint return at the bottom); light, a white top highlight over
        /// an ink hairline.
        public static var glassEdge: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: glassEdgeStops[0], location: 0),
                    .init(color: glassEdgeStops[1], location: 0.45),
                    .init(color: glassEdgeStops[2], location: 0.75),
                    .init(color: glassEdgeStops[3], location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        private static let glassEdgeStops: [Color] = [
            Tones.glassEdge0.color, Tones.glassEdge1.color, Tones.glassEdge2.color, Tones.glassEdge3.color,
        ]

        /// `glassEdge` under Increase Contrast: every stop roughly doubled.
        public static var glassEdgeIncreased: LinearGradient {
            LinearGradient(colors: glassEdgeIncreasedStops, startPoint: .top, endPoint: .bottom)
        }
        private static let glassEdgeIncreasedStops: [Color] = [
            Tones.glassEdgeHi0.color, Tones.glassEdgeHi1.color, Tones.glassEdgeHi2.color,
        ]

        /// The uncharged metal of the living star (`ZanoLivingMark`, the widgets' charged star):
        /// translucent white in dark mode, translucent ink in light mode, so the empty star is a
        /// visible outline in both.
        public static let markGraphiteTop = Tones.markGraphiteTop.color
        public static let markGraphiteBottom = Tones.markGraphiteBottom.color
        /// The uncharged star's outline stroke.
        public static let markGraphiteEdge = Tones.markGraphiteEdge.color

        // MARK: Pass 2: playful (docs/design/visual-direction-v2.md "Pass 2: playful")

        /// The confetti box: the hues a win is allowed to throw. ZANO Blue plus the five loudest goal
        /// colours (volt, apricot, pink, sky, sun). Decorative only, never text.
        public static let confetti: [Color] = [
            accent, Ring.workout, Ring.protein, Ring.creatine, Ring.water, Ring.sunriseAlarm,
        ]

        /// The bright top half of a sticker's face (`ZanoSticker`): the "printed vinyl" highlight.
        /// Stickers are physical objects, so they look the same in both schemes.
        public static let stickerHighlight = Color.white.opacity(0.32)
        /// The shade along a sticker's bottom inside edge, so it reads as a thick, peel-able chip.
        public static let stickerShade = Color.black.opacity(0.18)
        /// The white die-cut border around a decorative (icon-only) sticker.
        public static let stickerRim = Color.white.opacity(0.85)

        /// The label on a blue fill: white, on `accentFill` (5.27:1).
        public static let onAccent = Color.white

        /// Drop-shadow tone for a lifted surface (`ZanoSurface`'s elevated shadow). Dark: black at
        /// 55%. Light: a soft indigo shade at 18%.
        public static let shadow = Tones.shadow.color

        /// The bright leading cap on a ring's progress arc (`GoalRing`): white at 85%.
        public static let ringCap = Color.white.opacity(0.85)

        /// A middle text tier for paragraph copy that should be quieter than `text` but easier to
        /// read than `muted`. Dark `#D2D0EA`; light `#3B3D5E` (9.7:1).
        public static let textSecondary = Tones.textSecondary.color

        /// Elevation semantics (HIG: base vs elevated). Same tone as `surface`; it exists so the
        /// *intent* is legible at the call site.
        public static let backgroundElevated = surface

        // MARK: Accent tints (precomputed, on-hue)

        /// The accent at surface strength: icon-badge discs, selected rows, the unlock chip.
        public static let accentWash = Tones.accentWash.color

        /// The accent's dim core: a highlighted-but-unselected border, the track beneath an active
        /// accent bar.
        public static let accentDim = Tones.accentDim.color

        /// The disc/wash fill for an icon badge or chip tinted `tint`. The accent gets its on-hue
        /// precomputed wash (`accentWash`); every other hue falls back to 18% of itself.
        public static func wash(_ tint: Color) -> Color {
            tint == accent ? accentWash : tint.opacity(0.18)
        }

        /// Per-goal ring colours. Dark: the saturated v2 hues. Light: deeper twins of the same hues,
        /// each at least 4.5:1 on the light canvas, so they work as text, as graphics, and as fills
        /// under an `onFill` label in both schemes.
        ///
        /// Rule of use (docs/design/2026-ios-trends.md §4): a hue only ever identifies a ring by
        /// reinforcement — every ring/row must also be identifiable by glyph or label, never by
        /// color alone. Do not use `Ring.focus` as text in dark mode (3.9:1 on `background`).
        ///
        /// Fewer hues per screen (docs/design/competitive-research.md 3.11.4): a screen may show its
        /// per-goal hues for three, at most four, rings. A dense view (five or more rings) switches
        /// to ONE scheme instead: complete = `accent`, incomplete = `textSecondary`.
        public enum Ring {
            /// Volt (dark `#C8F04A`, light `#4F7300`).
            public static let workout = Tones.ringWorkout.color
            /// Apricot (dark `#FF9548`, light `#B8520A`).
            public static let protein = Tones.ringProtein.color
            /// Violet (dark `#9B7BFF`, light `#6A48E0`).
            public static let focus = Tones.ringFocus.color
            /// Sky (dark `#3CC8FF`, light `#00749E`).
            public static let water = Tones.ringWater.color
            /// Steps ring: mint.
            public static let steps = Tones.ringSteps.color
            /// Creatine/supplement ring: pink.
            public static let creatine = Tones.ringCreatine.color
            /// Sunrise alarm / morning routine ring: sun.
            public static let sunriseAlarm = Tones.ringSunrise.color
            /// Sleep-on-time ring: periwinkle.
            public static let sleepOnTime = Tones.ringSleep.color
            /// Reading ring: tan.
            public static let reading = Tones.ringReading.color
            /// Weekly meal prep ring: teal.
            public static let mealPrep = Tones.ringMealPrep.color
            /// Stretch/mobility ring: orchid.
            public static let stretchMobility = Tones.ringStretch.color
            /// Cold shower / sauna ring: ice.
            public static let coldShowerSauna = Tones.ringCold.color
            /// User-defined custom goal ring — deliberately neutral (`muted`).
            public static let custom = Colors.muted

            /// The unfilled part of a ring: the ring's own hue at 20%, so a 0% ring still reads as
            /// *that goal's* ring (Apple Activity convention) instead of a neutral grey arc.
            public static func track(for color: Color) -> Color {
                color.opacity(0.20)
            }

            /// Resolves the ring color for a `GoalType` (`Core/Sources/Core/Models/Goal.swift`).
            public static func color(for goalType: GoalType) -> Color {
                switch goalType {
                case .workoutGym, .workoutHomeOutdoor: workout
                case .focusSession: focus
                case .protein: protein
                case .water: water
                case .steps: steps
                case .creatine: creatine
                case .sunriseAlarm: sunriseAlarm
                case .sleepOnTime: sleepOnTime
                case .reading: reading
                case .mealPrep: mealPrep
                case .stretchMobility: stretchMobility
                case .coldShowerSauna: coldShowerSauna
                case .custom: custom
                }
            }
        }
    }

    // MARK: - Tones (light/dark pairs)

    /// The light/dark pair behind every adaptive colour token. `Theme.Colors` is what views use;
    /// reach for a tone directly only where an API needs a `UIColor` or a fixed scheme (the shield's
    /// `ShieldConfiguration`, the navigation bar's title attributes).
    public enum Tones {
        private static let ink: UInt32 = 0x13_14_2B
        private static let white: UInt32 = 0xFF_FF_FF
        private static let black: UInt32 = 0x00_00_00

        public static let background = ZanoTone(light: 0xF5_F6_FB, dark: 0x0B_0E_24)
        public static let backgroundDeep = ZanoTone(light: 0xE8_EA_F4, dark: 0x06_08_1A)
        public static let surface = ZanoTone(light: 0xFF_FF_FF, dark: 0x16_1A_3A)
        public static let surface2 = ZanoTone(light: 0xEC_EE_F6, dark: 0x1F_24_50)
        public static let text = ZanoTone(light: ink, dark: 0xF4_F3_FF)
        public static let textSecondary = ZanoTone(light: 0x3B_3D_5E, dark: 0xD2_D0_EA)
        public static let muted = ZanoTone(light: 0x5C_5E_7E, dark: 0xA6_A4_C8)
        public static let ember = ZanoTone(light: 0xB3_4A_06, dark: 0xFF_8A_3D)

        public static let auroraBlue = ZanoTone(light: 0x5B_8C_FF, dark: 0x3F_7B_FF)
        public static let auroraViolet = ZanoTone(light: 0xA5_7B_FF, dark: 0x8F_5B_FF)
        public static let auroraEmber = ZanoTone(light: 0xFF_9A_55, dark: 0xFF_8A_3D)

        public static let accent = ZanoTone(light: 0x2A_62_E6, dark: 0x3F_7B_FF)
        public static let accentFill = ZanoTone(0x2A_62_E6)
        public static let interactiveWash = ZanoTone(light: 0x2A_62_E6, 0.12, dark: 0x3F_7B_FF, 0.16)
        public static let accentWash = ZanoTone(light: 0xDF_E7_FF, dark: 0x15_25_5E)
        public static let accentDim = ZanoTone(light: 0xA9_BF_F5, dark: 0x24_40_8C)

        public static let metalLight = ZanoTone(light: 0x8C_91_A6, dark: 0xFA_F9_F6)
        public static let metalMid = ZanoTone(light: 0x66_6B_80, dark: 0xD6_D4_CF)
        public static let metalDark = ZanoTone(light: 0x44_48_5C, dark: 0x9E_9C_97)

        public static let lockedAmbient = ZanoTone(light: 0xC3_C8_F2, dark: 0x2A_2F_7A)
        public static let surfaceHero = ZanoTone(light: 0xFF_FF_FF, dark: 0x1D_22_48)
        public static let danger = ZanoTone(light: 0xC4_2F_3F, dark: 0xF0_60_6E)
        public static let warning = ZanoTone(light: 0x9A_5F_00, dark: 0xF5_B5_4A)

        public static let hairline = ZanoTone(light: ink, 0.10, dark: white, 0.12)
        public static let hairlineStrong = ZanoTone(light: ink, 0.18, dark: white, 0.20)
        public static let track = ZanoTone(light: ink, 0.10, dark: white, 0.16)
        public static let edgeTop = ZanoTone(light: ink, 0.06, dark: white, 0.14)
        public static let edgeBottom = ZanoTone(light: ink, 0.12, dark: white, 0.06)
        public static let edgeTopIncreased = ZanoTone(light: ink, 0.22, dark: white, 0.30)
        public static let edgeBottomIncreased = ZanoTone(light: ink, 0.32, dark: white, 0.18)

        public static let glassFill = ZanoTone(light: white, 0.74, dark: white, 0.07)
        public static let glassFillTop = ZanoTone(light: white, 0.86, dark: white, 0.09)
        public static let glassFillBottom = ZanoTone(light: white, 0.66, dark: white, 0.04)
        public static let glassRaisedTop = ZanoTone(light: white, 0.96, dark: white, 0.13)
        public static let glassRaisedBottom = ZanoTone(light: white, 0.84, dark: white, 0.05)
        public static let glassChromeTint = ZanoTone(light: white, 0.45, dark: 0x0B_0E_24, 0.35)
        public static let glassInnerShade = ZanoTone(light: ink, 0.05, dark: black, 0.22)
        public static let glassShadow = ZanoTone(light: 0x2A_2D_5C, 0.10, dark: black, 0)
        public static let wellFill = ZanoTone(light: ink, 0.04, dark: white, 0.05)
        public static let glassEdge0 = ZanoTone(light: white, 1.0, dark: white, 0.35)
        public static let glassEdge1 = ZanoTone(light: ink, 0.07, dark: white, 0.06)
        public static let glassEdge2 = ZanoTone(light: ink, 0.07, dark: white, 0.04)
        public static let glassEdge3 = ZanoTone(light: ink, 0.12, dark: white, 0.12)
        public static let glassEdgeHi0 = ZanoTone(light: ink, 0.26, dark: white, 0.6)
        public static let glassEdgeHi1 = ZanoTone(light: ink, 0.30, dark: white, 0.22)
        public static let glassEdgeHi2 = ZanoTone(light: ink, 0.38, dark: white, 0.3)
        public static let markGraphiteTop = ZanoTone(light: ink, 0.16, dark: white, 0.11)
        public static let markGraphiteBottom = ZanoTone(light: ink, 0.08, dark: white, 0.035)
        public static let markGraphiteEdge = ZanoTone(light: ink, 0.30, dark: white, 0.16)
        public static let shadow = ZanoTone(light: 0x2A_2D_5C, 0.18, dark: black, 0.55)

        public static let ringWorkout = ZanoTone(light: 0x4F_73_00, dark: 0xC8_F0_4A)
        public static let ringProtein = ZanoTone(light: 0xB8_52_0A, dark: 0xFF_95_48)
        public static let ringFocus = ZanoTone(light: 0x6A_48_E0, dark: 0x9B_7B_FF)
        public static let ringWater = ZanoTone(light: 0x00_74_9E, dark: 0x3C_C8_FF)
        public static let ringSteps = ZanoTone(light: 0x0E_7A_43, dark: 0x4B_E3_8C)
        public static let ringCreatine = ZanoTone(light: 0xC2_2F_72, dark: 0xFF_6F_AE)
        public static let ringSunrise = ZanoTone(light: 0x94_66_00, dark: 0xFF_C9_4A)
        public static let ringSleep = ZanoTone(light: 0x46_52_D8, dark: 0x7C_8C_FF)
        public static let ringReading = ZanoTone(light: 0x9A_5A_22, dark: 0xE9_A8_6B)
        public static let ringMealPrep = ZanoTone(light: 0x00_77_6A, dark: 0x34_D6_BE)
        public static let ringStretch = ZanoTone(light: 0x9A_3F_D0, dark: 0xD1_7B_FF)
        public static let ringCold = ZanoTone(light: 0x0F_6E_8C, dark: 0x8F_E3_FF)
    }

    // MARK: - Radius

    /// Corner radii from spec §15: "Radius: 12 / 20 / 28".
    ///
    /// What each is *for* (docs/design/2026-ios-trends.md §6): controls (buttons, chips, pills) are
    /// `Capsule()` and need no token; `small` is for non-control tiles and nested wells; `medium`
    /// for standard cards; `large` for hero surfaces.
    ///
    /// The scale steps by 8, which equals `Spacing.xs`, so nested corners are concentric
    /// (`inner = outer − inset`) exactly when a nested surface sits `Spacing.xs` inside its parent:
    /// medium(20) holds small(12) at an 8pt inset; large(28) holds medium(20) at 8pt, or small(12)
    /// at 16pt. Any other pairing has no token — use `inner(of:inset:)`.
    public enum Radius {
        /// `16` — small tiles, nested wells and chips that are not full capsules.
        public static let small: CGFloat = 16
        /// `24` — standard cards and goal tiles.
        public static let medium: CGFloat = 24
        /// `32` — large surfaces (share cards, sheets, shield screens).
        public static let large: CGFloat = 32
        /// `36` — the one hero surface per screen (visual direction v2: radius follows hierarchy).
        public static let hero: CGFloat = 36

        /// The concentric inner radius for a surface sitting `inset` points inside a parent with
        /// corner radius `outer`: `max(outer − inset, 0)`. Prefer the three token pairings in the
        /// type-level note; reach for this only when content padding forces another inset.
        public static func inner(of outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, 0)
        }
    }

    // MARK: - Spacing

    /// Spacing scale from spec §15: "Spacing scale: 4, 8, 12, 16, 24, 32".
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        /// `48` — the breath above/below a screen's hero (visual direction v2).
        public static let xxl: CGFloat = 48
    }

    // MARK: - Metrics

    /// Fixed sizes that are not spacing: hit targets, badge diameters, stroke weights. Named so
    /// nobody re-derives 44 or 32 at a call site.
    public enum Metrics {
        /// HIG minimum hit target. Grow the *target*, not the visual (`View.minTapTarget()`).
        public static let minTapTarget: CGFloat = 44
        /// The one selection stroke width (selected plan, option, tile).
        public static let selectedStroke: CGFloat = 1.5
        /// Icon-badge diameters (`IconBadge`): one scale instead of the seven the app had drifted
        /// into (32/36/40/44/52/60/96).
        public static let iconBadgeSmall: CGFloat = 32
        public static let iconBadgeMedium: CGFloat = 44
        public static let iconBadgeLarge: CGFloat = 96
        /// Minimum height of a `PrimaryButton`. A 17pt headline line plus `Spacing.sm` above and
        /// below is ~46pt; 52pt reads as the confident capsule iOS 26 controls are, and is well
        /// over `minTapTarget`.
        public static let primaryButtonHeight: CGFloat = 52
        /// Width of a card edge / divider stroke.
        public static let edgeWidth: CGFloat = 1
        /// Sticker heights (`ZanoSticker`): compact chips and the chunky default.
        public static let stickerSmall: CGFloat = 26
        public static let stickerRegular: CGFloat = 34
        public static let stickerLarge: CGFloat = 48
        /// The minimum height of a goal tile (`GoalTile`), so a row of two reads as a game board.
        public static let goalTileMinHeight: CGFloat = 156
        /// Height of a horizontal progress bar (`TimeBankBar`). 10pt read as a hairline next to a
        /// 28pt numeral; 12pt has presence without becoming a slab.
        public static let progressBarHeight: CGFloat = 12
        /// A ring's stroke as a fraction of its diameter (9/88 and 14/148 in the fixed presets).
        public static let ringStrokeRatio: CGFloat = 0.095
        /// The floating tab bar: capsule height and each item's minimum hit target.
        public static let tabBarHeight: CGFloat = 64
        public static let tabBarItem: CGFloat = 52
    }

    // MARK: - Typography

    /// Type ramp from spec §15: "Type: SF Pro ...; big numerals for grams/minutes/streak". SF Pro
    /// is the system font, so these are all system fonts (no bundled font asset needed).
    ///
    /// Two families:
    ///
    ///  * **Text styles** (`display` … `unit`) are built from system text styles, so they follow
    ///    the user's Dynamic Type setting. At the default size they are identical to the sizes
    ///    this file previously hard-coded (title 22, headline 17, body 15, caption 13). Note
    ///    `body` is Apple's *Subheadline* (15pt), not Apple's `.body` (17pt): ZANO's "body" has
    ///    always been the 15pt tier, and renaming it would silently resize every screen.
    ///  * **Numerals** are condensed, bold, `monospacedDigit()` fonts so big stat numbers don't
    ///    jiggle in width as they tick. `numeralSmall`/`numeralMedium` are built on text styles
    ///    (Headline / Title 1) and follow Dynamic Type; `numeralLarge`/`numeralHero` and
    ///    `numeral(size:)` are fixed sizes (a `Font` cannot hold `@ScaledMetric`), so a big stat
    ///    that should scale renders through `NumeralText` instead of `.font(numeral…())`.
    ///
    /// A `Font` cannot carry tracking or leading either, which is why no screen ever had any.
    /// `View.zanoText(_:)` applies a style's font *and* its tracking/leading.
    public enum Typography {

        // MARK: Numerals

        /// Display numerals (72pt, heavy): the one number a screen exists to show — the Today
        /// state, the Time Bank reward, the wake-up counters, the alarm clock, a streak
        /// milestone. Aim for a hero-to-supporting ratio of at least 3:1 (competitor dashboards
        /// sit near 72pt against ~13pt captions; this app's largest text used to be 22pt).
        /// Numerals are SF Pro at a narrow width (premium-ui-plan.md: the Nike reference — big,
        /// athletic, condensed numbers over quiet UI). Native widths, so no bundled font. Hero
        /// numerals go to `.compressed`; everything smaller stays `.condensed` so it holds up at
        /// 17pt.
        public static func numeralHero() -> Font {
            score(size: 88)
        }

        /// The score face (visual direction v2): SF Pro Expanded, black. Big, wide, arcade-scoreboard
        /// numerals for the one number a screen exists to show. ~35% wider than the compressed face
        /// `numeral(size:)` uses, so give it room (`NumeralText` shrinks to fit; a bare `Text` needs
        /// `.minimumScaleFactor`).
        public static func score(size: CGFloat, weight: Font.Weight = .black) -> Font {
            .system(size: size, weight: weight).width(.expanded).monospacedDigit()
        }
        /// Large numerals (e.g. a Live Activity countdown, a `.large` ring's center value,
        /// secondary big stats).
        public static func numeralLarge() -> Font {
            numeral(size: 48, weight: .heavy)
        }
        /// Medium numerals (e.g. `GoalRing` center value, `TimeBankBar`'s remaining-minutes label).
        /// Built on the Title 1 text style (28pt at the default size), so it follows Dynamic Type.
        public static func numeralMedium() -> Font {
            .system(.title, design: .rounded, weight: .bold).monospacedDigit()
        }
        /// Small numerals (e.g. `StreakPill`'s count, compact stat chips). Built on the Headline
        /// text style (17pt at the default size), so it follows Dynamic Type.
        public static func numeralSmall() -> Font {
            .system(.headline, design: .rounded, weight: .bold).monospacedDigit()
        }
        /// A numeral at an arbitrary point size, for layouts where the size is a function of a
        /// container (a ring's center scales with the ring's diameter). Same face as the named
        /// numerals. Prefer the named tiers wherever the size is not container-driven. 60pt and up
        /// switch to the compressed width the hero uses.
        public static func numeral(size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight).width(size >= 60 ? .compressed : .condensed).monospacedDigit()
        }

        // MARK: Text styles (Dynamic Type)

        /// Hero headlines (onboarding hook, plan reveal, celebration): Large Title, rounded bold.
        /// 34pt at the default size. Replaces the ad hoc 34/30 rounded sizes.
        /// Condensed heavy, like the numerals: headlines are short and should hit like a number.
        /// v2: SF Pro Rounded bold — the app's friendly voice (it was condensed heavy).
        public static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        /// Full-screen focal messages (the shield headline) and custom screen titles: Title 1,
        /// condensed heavy. 28pt at the default size — between `display` and `title`.
        public static let titleLarge = Font.system(.title, design: .rounded, weight: .bold)
        /// Screen/section titles. Title 2, bold: 22pt at the default size.
        public static let title = Font.system(.title2, design: .rounded, weight: .bold)
        /// Card headlines (e.g. `LockStatusCard`'s status line, `ShieldPreview`'s headline).
        /// Headline: 17pt semibold at the default size.
        public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        /// v2: a control/status label — Subheadline, rounded semibold (15pt). Capsules, chips, tab
        /// labels, quick-add buttons.
        public static let label = Font.system(.subheadline, design: .rounded, weight: .semibold)
        /// Default body text. Subheadline: 15pt at the default size (see the type-level note on
        /// why this is not Apple's 17pt `.body`).
        public static let body = Font.system(.subheadline, design: .default, weight: .regular)
        /// Secondary / caption text (subtitles, timestamps, fine print). Footnote: 13pt.
        public static let caption = Font.system(.footnote, design: .default, weight: .regular)
        /// Emphasized caption (e.g. a pill label). Footnote semibold: 13pt.
        public static let captionEmphasized = Font.system(.footnote, design: .default, weight: .semibold)
        /// The unit beside a numeral ("g", "min", "/150g"): Subheadline, rounded semibold, so it
        /// shares the numeral's face at a fraction of its weight on the page.
        public static let unit = Font.system(.subheadline, design: .rounded, weight: .semibold)

        // MARK: Icons

        /// The four glyph sizes the app actually needs (it had drifted into 17 ad hoc point
        /// sizes). Built from text styles so an icon beside text tracks that text's size.
        public enum IconSize: Sendable {
            /// Caption2, 11pt — inline with a caption label.
            case xsmall
            /// Footnote, 13pt — trailing chevrons, small status glyphs.
            case small
            /// Body, 17pt — the icon in a 44pt badge or beside a headline.
            case medium
            /// Title 3, 20pt — status indicators, selection glyphs.
            case large
        }

        /// An SF Symbol font for `size`. Weight defaults to semibold (the app's house weight for
        /// glyphs beside semibold/bold text).
        public static func icon(_ size: IconSize, weight: Font.Weight = .semibold) -> Font {
            switch size {
            case .xsmall: .system(.caption2, weight: weight)
            case .small: .system(.footnote, weight: weight)
            case .medium: .system(.body, weight: weight)
            case .large: .system(.title3, weight: weight)
            }
        }

        // MARK: Styles that need more than a Font

        /// A named text style for `View.zanoText(_:)`. Styles that are just a font (`title`,
        /// `headline`, `caption`, …) are here too so a screen has one way to say "this is a
        /// title" instead of two.
        public enum Style: Sendable {
            case display, titleLarge, title, headline, body
            /// Multi-line copy: `body` with 3pt of extra leading (SF's default is tight for 3+
            /// lines).
            case paragraph
            case caption, captionEmphasized
            /// The small label above a headline: caption-emphasized, sentence case. It used to be
            /// tracked all caps, which frontend-design flags as the commonest tell of generated UI
            /// (premium-ui-plan.md §5); hierarchy now comes from size and weight.
            case eyebrow
            case unit
        }
    }

    // MARK: - Motion

    /// Motion curves from spec §15: "Motion: spring animations; ring fills ease-out 600ms; unlock
    /// celebration ≤ 1.2s; haptics on every verified event."
    public enum Motion {
        /// Spec-exact: "ring fills ease-out 600ms". Drives `GoalRing`'s trim animation and
        /// `TimeBankBar`'s fill animation.
        public static let ringFill: Animation = .easeOut(duration: 0.6)

        /// Spec-exact ceiling: "unlock celebration ≤ 1.2s". Callers building an unlock-burst
        /// animation (e.g. the Today screen's celebration overlay) should keep the total sequence
        /// at or under this duration.
        public static let unlockCelebrationMaxDuration: TimeInterval = 1.2

        /// Standard UI spring for state changes (selection, row status flips, sheet content
        /// swaps) — spec §15's general "Motion: spring animations" direction, tuned for a
        /// confident-but-not-bouncy feel.
        public static let springStandard: Animation = .spring(response: 0.35, dampingFraction: 0.82)

        /// A snappier, more energetic spring for celebratory/positive feedback (unlock bursts,
        /// streak milestones, badge reveals) — still within `unlockCelebrationMaxDuration`.
        public static let springCelebration: Animation = .spring(response: 0.45, dampingFraction: 0.68)

        /// For 1:1 gesture-tracked motion the user's finger is actively driving (a hold-to-commit
        /// fill, a future drag-to-dismiss sheet) — critically damped, no overshoot, snappier settle
        /// than `springStandard` since a released gesture should feel like it "catches" immediately
        /// rather than continue conversing. Apple's own shipped value for directly-manipulated
        /// repositioning (WWDC18 "Designing Fluid Interfaces"): damping 1.0, response 0.4. Distinct
        /// from `springStandard` (0.82 damping, for passive state flips the user didn't directly
        /// touch) and from `springCelebration` (0.68 damping, deliberate overshoot for celebratory
        /// beats) — pick by *what caused the change*, not by feel alone.
        public static let springGesture: Animation = .spring(response: 0.4, dampingFraction: 1.0)

        /// Duration of `PrimaryButton`'s `.holdToCommit` press-and-hold gesture, per this task's
        /// brief ("hold-to-commit variant: 2-second press + haptics").
        public static let holdToCommitDuration: TimeInterval = 2.0

        /// Touch-down feedback (button/row/card press). HIG's press-feedback budget is 100–160ms
        /// and `springStandard` (response 0.35) settles slower than that, so presses get their own
        /// curve. Promoted from a file-private helper in `PrimaryButton` now that `PressableStyle`
        /// and every tappable card share it.
        public static let pressFeedback: Animation = .spring(response: 0.16, dampingFraction: 0.75)

        /// Same-family SF Symbol / glyph swaps (lock ↔ unlock, circle ↔ check): no bounce. Icon
        /// swaps should read as one object changing state, not a spring.
        public static let iconSwap: Animation = .spring(duration: 0.3, bounce: 0)

        // MARK: v2 (visual direction v2, 2026-10-02)

        /// A goal completing, the star's charge burst: a quick, bouncy pop. Use it for *earned*
        /// beats only; it overshoots on purpose.
        /// Pass 2: springier (0.34 / 0.46, was 0.28 / 0.52): a bigger, rounder overshoot.
        public static let springPop: Animation = .spring(response: 0.34, dampingFraction: 0.46)

        /// The tab bar's selection pill sliding between tabs. Pass 2: squishier (more overshoot).
        public static let tabPill: Animation = .spring(response: 0.4, dampingFraction: 0.68)

        // MARK: Pass 2: playful (2026-10-03)

        /// The bounce back after a press (`PressableStyle` on release): a fast spring with visible
        /// overshoot, so every tile feels like a squishy button. Press-*in* stays `pressFeedback`.
        public static let springSquish: Animation = .spring(response: 0.3, dampingFraction: 0.45)

        /// Numbers rolling to a new value (`RollingNumber`, `NumeralText`'s `.numericText` roll).
        public static let numberRoll: Animation = .spring(response: 0.45, dampingFraction: 0.72)

        /// The mascot's jump on a goal completion, crouch to landing, in seconds.
        public static let mascotJumpDuration: TimeInterval = 0.9

        /// The mascot's little spin when poked, in seconds.
        public static let mascotSpinDuration: TimeInterval = 0.7

        /// One squash-and-stretch hop of a perky mascot, in seconds.
        public static let mascotHopPeriod: TimeInterval = 1.6

        /// How often a charged mascot does its wiggle, in seconds (it wiggles for the first 0.6s).
        public static let mascotWigglePeriod: TimeInterval = 3.2

        /// One full up-and-down of the star's idle bob, in seconds.
        public static let idleBobPeriod: TimeInterval = 3.4

        /// The aurora's redraw interval (12 fps: its blobs move a fraction of a point per frame).
        public static let auroraFrameInterval: TimeInterval = 1.0 / 12

        /// Convenience for call sites gating a spring behind
        /// `@Environment(\.accessibilityReduceMotion)` — covers the common case of animating a
        /// state flip with `springStandard` when motion is allowed, and snapping instantly when it
        /// isn't. `nil` (not a zero-duration animation) is deliberate: it fully disables implicit
        /// animation for that value change rather than still running the animation machinery for no
        /// visible benefit. Call sites that need a different base curve (`.ringFill`,
        /// `.springCelebration`, `.springGesture`) write their own `reduceMotion ? nil : ...`
        /// ternary directly instead of this helper — this only covers the `springStandard` majority
        /// case so it doesn't collapse four different curves into one name.
        public static func standard(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : springStandard
        }

        /// The press-feedback curve, with Reduce Motion swapped for a flat 100ms ease (the
        /// opacity/scale change is real information — "the interface heard you" — but the
        /// spring's settle is not needed).
        public static func press(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.1) : pressFeedback
        }
    }
}

// MARK: - Text style modifier

/// Applies a `Theme.Typography.Style`: its font, plus the tracking/leading/case a `Font` cannot
/// carry. Color is deliberately left to the caller.
public struct ZanoTextStyle: ViewModifier {
    private let style: Theme.Typography.Style

    public init(_ style: Theme.Typography.Style) {
        self.style = style
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        switch style {
        case .display:
            content.font(Theme.Typography.display).tracking(-0.2)
        case .titleLarge:
            content.font(Theme.Typography.titleLarge)
        case .title:
            content.font(Theme.Typography.title)
        case .headline:
            content.font(Theme.Typography.headline)
        case .body:
            content.font(Theme.Typography.body)
        case .paragraph:
            content.font(Theme.Typography.body).lineSpacing(3)
        case .caption:
            content.font(Theme.Typography.caption)
        case .captionEmphasized:
            content.font(Theme.Typography.captionEmphasized)
        case .eyebrow:
            content.font(Theme.Typography.captionEmphasized)
        case .unit:
            content.font(Theme.Typography.unit)
        }
    }
}

extension View {
    /// Applies `style`'s font, tracking, leading and case (see `Theme.Typography.Style`). Set the
    /// color separately with `foregroundStyle`.
    public func zanoText(_ style: Theme.Typography.Style) -> some View {
        modifier(ZanoTextStyle(style))
    }
}

// MARK: - Buddy colours

extension Theme {
    /// Each buddy's three world colours (`Buddy.color` and friends). Same in light and dark: they
    /// are the characters' own colours, like the sticker hues.
    public enum BuddyColors {
        public struct Trio: Sendable {
            public let signature: Color
            public let second: Color
            public let third: Color
            init(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
                signature = Color(zanoHex: a)
                second = Color(zanoHex: b)
                third = Color(zanoHex: c)
            }
        }

        public static func colors(for buddy: Buddy) -> Trio {
            switch buddy {
            case .stash: Trio(0x2BB5A0, 0x3B3F5C, 0x3F7BFF)
            case .zib: Trio(0x3F7BFF, 0x9CCBFF, 0xFFD447)
            case .lox: Trio(0xFF8A3D, 0x5B3B8C, 0xFFF1DC)
            case .pip: Trio(0x8F5BFF, 0xFF9FC8, 0xFFC94A)
            case .moko: Trio(0x2FB86B, 0xFFF6DE, 0xFF9FB2)
            case .brick: Trio(0xE5484D, 0x2B2D42, 0xFFD447)
            case .tank: Trio(0xC8F04A, 0x5C6378, 0xFF8A3D)
            case .volt: Trio(0x1FA2FF, 0xFFD447, 0x0B2E59)
            case .howl: Trio(0x5B7BFF, 0x2A3466, 0xFFC94A)
            }
        }
    }
}

// MARK: - Hex color helper

extension Color {
    /// Builds a `Color` from a packed `0xRRGGBB` literal, the format every token in this file is
    /// written in. Named `zanoHex` (not a bare `hex:`) so it doesn't collide with any general-
    /// purpose `Color(hex:)` helper another module might add later; this initializer exists only
    /// to keep `Theme`'s token declarations exactly as legible as the spec's own `#RRGGBB` table.
    init(zanoHex value: UInt32) {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

// MARK: - Adaptive tone

/// One colour token as a light/dark pair (hex + opacity for each scheme). Value type, Sendable:
/// safe to build `Color`s from in widget and other nonisolated code.
public struct ZanoTone: Sendable, Hashable {
    public let light: UInt32
    public let lightOpacity: Double
    public let dark: UInt32
    public let darkOpacity: Double

    public init(light: UInt32, _ lightOpacity: Double = 1, dark: UInt32, _ darkOpacity: Double = 1) {
        self.light = light
        self.lightOpacity = lightOpacity
        self.dark = dark
        self.darkOpacity = darkOpacity
    }

    /// The same colour in both schemes.
    public init(_ both: UInt32, _ opacity: Double = 1) {
        self.init(light: both, opacity, dark: both, opacity)
    }

    /// The tone resolved for one scheme, as a fixed (non-dynamic) `UIColor`.
    public func uiColor(for scheme: ColorScheme) -> UIColor {
        scheme == .light ? Self.make(light, lightOpacity) : Self.make(dark, darkOpacity)
    }

    /// A dynamic `UIColor` that follows the trait collection it is resolved in. An unspecified
    /// style resolves dark (the app's original, and still default-in-doubt, look).
    public var dynamicUIColor: UIColor {
        let tone = self
        return UIColor { traits in
            tone.uiColor(for: traits.userInterfaceStyle == .light ? .light : .dark)
        }
    }

    /// The adaptive SwiftUI colour: resolves against the view's `colorScheme`.
    public var color: Color { Color(uiColor: dynamicUIColor) }

    /// The tone pinned to one scheme.
    public func color(for scheme: ColorScheme) -> Color { Color(uiColor: uiColor(for: scheme)) }

    private static func make(_ value: UInt32, _ opacity: Double) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: CGFloat(opacity)
        )
    }
}
