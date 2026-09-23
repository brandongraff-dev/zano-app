// Theme.swift
// Core / UI
//
// The single source of design tokens for every ZANO surface (app + extensions), per
// docs/spec.md §15 "Design System & UI Direction". Every component in `Core/Sources/Core/UI`
// and every app-only screen in `App/ZANO/Features` must build its visuals exclusively from
// `Theme` — no ad hoc hex literals or magic numbers outside this file (spec §15, CLAUDE.md
// "Conventions").
//
// This is intentionally a single, fixed dark palette, not a light/dark adaptive theme: spec §15
// opens with "Feel: dark, confident, game-progress energy" and never defines a light variant —
// ZANO's product surfaces are dark-mode-first by design (like the mockups in §16). Screens should
// still force `.preferredColorScheme(.dark)` where appropriate at the App/Features layer; that's
// outside this file's scope. `PreviewCatalog.swift` renders these fixed tokens under both
// `.preferredColorScheme(.light)` and `.dark` previews to confirm nothing regresses if the OS
// chrome (status bar, system alerts) flips appearance — not because the tokens themselves change.
//
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
//   * On-fill labels. `text` on an accent fill is 1.11:1. `onFill` is the one label color for
//     anything drawn on an accent/danger/warning fill (16.4 / 5.8 / 10.8:1).
//   * Type. Text styles now map to system text styles, so they follow Dynamic Type and read
//     identically to the old fixed sizes at the default setting (22/17/15/13). Numerals stay
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

import SwiftUI

/// ZANO's design system: colors, radii, spacing, typography, and motion — all sourced from
/// docs/spec.md §15. Everything here is a value type / static constant; `Theme` itself is never
/// instantiated.
public enum Theme {

    // MARK: - Colors

    /// Color tokens from docs/spec.md §15's "Tokens" table, reproduced exactly (hex values are
    /// spec-authoritative; do not retune here without updating §15 first).
    public enum Colors {
        /// `#0A0A0B` — app background.
        public static let background = Color(zanoHex: 0x0A0A0B)
        /// `#141416` — card / primary surface.
        public static let surface = Color(zanoHex: 0x14_14_16)
        /// `#1C1C1F` — secondary surface (nested cards, tracks, pressed states).
        public static let surface2 = Color(zanoHex: 0x1C_1C_1F)
        /// `#F5F5F7` — primary text.
        public static let text = Color(zanoHex: 0xF5_F5_F7)
        /// `#8E8E93` — secondary / muted text.
        public static let muted = Color(zanoHex: 0x8E_8E_93)
        /// `#B8FF3C` — the ONE brand accent (earned/unlock). Reserve for primary CTAs, the
        /// workout ring, and unlock/earned states — spec §15: "ONE accent only".
        public static let accent = Color(zanoHex: 0xB8_FF_3C)
        /// `#FF453A` — danger / locked state.
        public static let danger = Color(zanoHex: 0xFF_45_3A)
        /// `#FFB020` — warning state.
        public static let warning = Color(zanoHex: 0xFF_B0_20)

        // MARK: Derived neutrals (not in spec §15's table; derived, not new hues)

        /// A crisp 1px edge/divider tone — spec §16 calls for "crisp 1px hairline dividers".
        /// White at 12% (1.40:1 over `surface`, 1.33:1 over `background`). The previous value,
        /// `surface2` at 0.8, was 1.06:1 against its own card and drew nothing. Pure white, not
        /// `text`: a tinted edge reads as dirt on near-black.
        public static let hairline = Color.white.opacity(0.12)

        /// A stronger edge for pressed / selected-neutral / Increase Contrast states. White at
        /// 20% (1.86:1 over `surface`).
        public static let hairlineStrong = Color.white.opacity(0.20)

        /// The empty part of a bar, pager dot or unearned grid tile. White at 16% (1.53:1 over
        /// `background`, 1.61:1 over `surface`). Was `surface2` (1.16 / 1.08:1) — the "empty"
        /// half of a progress visual is the informational half and it vanished. Rings use
        /// `Ring.track(for:)` instead (their own hue), not this.
        public static let track = Color.white.opacity(0.16)

        // MARK: Card edge light

        /// The card edge is a 1px *top-lit* gradient (light falling from above), not a box outline:
        /// drop shadows are invisible on near-black, and a lit rim is what dark design systems (and
        /// iOS's own glass chrome) use for depth. Top and bottom stops, pure white.
        public static let edgeTop = Color.white.opacity(0.14)
        public static let edgeBottom = Color.white.opacity(0.06)
        /// The same edge under Increase Contrast (`colorSchemeContrast == .increased`): doubled.
        public static let edgeTopIncreased = Color.white.opacity(0.30)
        public static let edgeBottomIncreased = Color.white.opacity(0.18)

        /// The top-lit card edge as a stroke style. `increasedContrast` swaps in the stronger pair.
        public static func edgeGradient(increasedContrast: Bool = false) -> LinearGradient {
            LinearGradient(
                colors: increasedContrast ? [edgeTopIncreased, edgeBottomIncreased] : [edgeTop, edgeBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// The specular rim on an *accent-filled* control (the top edge of `PrimaryButton`): white at
        /// 30%, fading to nothing. Only ever on a filled control, never on a card.
        public static let specular = Color.white.opacity(0.30)

        /// The label/icon color for anything drawn ON an `accent`, `danger` or `warning` fill.
        /// Never `text`: `#F5F5F7` on accent is 1.11:1 (unreadable) and 3.13:1 on danger, while
        /// `background` is 16.4:1 on accent, 5.8:1 on danger and 10.8:1 on warning.
        public static let onFill = background

        /// `#C7C7CC` — a middle text tier for paragraph copy that should be quieter than `text`
        /// (18.2:1) but easier to read than `muted` (6.1:1): 11.8:1 on `background`, 10.9:1 on
        /// `surface`. Use for multi-line supporting copy; keep `muted` for metadata.
        public static let textSecondary = Color(zanoHex: 0xC7_C7_CC)

        /// Elevation semantics (HIG dark mode: base vs elevated). The fill for anything that
        /// presents over the app when the system's own sheet material is not in play (full-screen
        /// covers, celebration/alarm/onboarding backdrops). Same hex as `surface`, so it costs no
        /// new color; it exists so the *intent* is legible at the call site.
        public static let backgroundElevated = surface

        // MARK: Accent tints (precomputed, on-hue)

        /// `#223403` — the accent at dark-surface strength: icon-badge discs, selected rows, the
        /// unlock chip. `accent.opacity(0.16)` composites to `#2E3A1C`, whose chroma is about a
        /// quarter of the accent's, so it reads as a different, dirtier color instead of a dimmer
        /// version of the accent. Accent on this wash is 11.2:1, `text` 12.4:1.
        public static let accentWash = Color(zanoHex: 0x22_34_03)

        /// `#3B5800` — the accent's dim core: a highlighted-but-unselected border, the track
        /// beneath an active accent bar. Accent on this is 6.7:1; it is 2.26:1 against `surface`.
        public static let accentDim = Color(zanoHex: 0x3B_58_00)

        /// The disc/wash fill for an icon badge or chip tinted `tint`. The accent gets its
        /// on-hue precomputed wash (`accentWash`); every other hue falls back to 18% of itself,
        /// which is the same recipe the app used before but no longer applied to the accent
        /// (where it went olive).
        public static func wash(_ tint: Color) -> Color {
            tint == accent ? accentWash : tint.opacity(0.18)
        }

        /// Per-goal ring colors (spec §15: "Ring colors: workout = accent, protein = `#FF7A00`,
        /// focus = `#5E5CE6`, water = `#32ADE6`"). Spec only names those four; the remaining
        /// `GoalType` cases (steps, creatine, sunrise alarm, sleep, reading, meal prep, stretch,
        /// cold shower/sauna, custom) have no assigned hex in §15. `Ring.color(for:)` below
        /// extends the palette additively using Apple's own system palette hues so every goal type
        /// gets a stable, distinguishable ring color — flagged as an assumption in this task's
        /// decisions; revisit with design before shipping if §15 is amended with exact values.
        ///
        /// Rule of use (docs/design/2026-ios-trends.md §4): a hue only ever identifies a ring by
        /// reinforcement — every ring/row must also be identifiable by glyph or label, never by
        /// color alone (`GoalRing`/`RingCluster` always carry a glyph or label). Do not use
        /// `Ring.focus` as text: 3.9:1 on `background`, below the 4.5:1 text threshold.
        ///
        /// Fewer hues per screen (docs/design/competitive-research.md 3.11.4): a screen may show its
        /// per-goal hues for three, at most four, rings. A dense view (five or more rings — the
        /// weekly recap, a full progress grid) switches to ONE scheme instead: complete = `accent`,
        /// incomplete = `textSecondary`. `RecapCard` does this itself. The additive hues below also
        /// collide with each other and with the accent/warning tokens under color-vision
        /// deficiency (`steps` vs `accent`, `sunriseAlarm` vs `warning`, `water` vs `coldShowerSauna`),
        /// which is one more reason a hue must never be the only thing identifying a ring.
        public enum Ring {
            /// Spec-exact: workout rings reuse the single brand accent.
            public static let workout = Colors.accent
            /// Spec-exact `#FF7A00`.
            public static let protein = Color(zanoHex: 0xFF_7A_00)
            /// Spec-exact `#5E5CE6`.
            public static let focus = Color(zanoHex: 0x5E_5C_E6)
            /// Spec-exact `#32ADE6`.
            public static let water = Color(zanoHex: 0x32_AD_E6)

            // Additive extensions (assumption — not in spec §15's table; see the doc comment
            // above). Chosen from Apple's system color palette so they read as "native" and stay
            // visually distinct from the four spec-exact hues above.
            /// Assumption: steps ring.
            public static let steps = Color(zanoHex: 0x32_D7_4B)
            /// Assumption: creatine/supplement ring.
            public static let creatine = Color(zanoHex: 0xFF_37_5F)
            /// Assumption: sunrise alarm / morning routine ring.
            public static let sunriseAlarm = Color(zanoHex: 0xFF_D6_0A)
            /// Assumption: sleep-on-time ring.
            public static let sleepOnTime = Color(zanoHex: 0x0A_84_FF)
            /// Assumption: reading ring.
            public static let reading = Color(zanoHex: 0xAC_8E_68)
            /// Assumption: weekly meal prep ring.
            public static let mealPrep = Color(zanoHex: 0x66_D4_CF)
            /// Assumption: stretch/mobility ring.
            public static let stretchMobility = Color(zanoHex: 0xBF_5A_F2)
            /// Assumption: cold shower / sauna ring.
            public static let coldShowerSauna = Color(zanoHex: 0x5A_C8_FA)
            /// Assumption: user-defined custom goal ring — deliberately neutral (`muted`) since
            /// there is no inherent category color for a goal the user invents themselves.
            public static let custom = Colors.muted

            /// The unfilled part of a ring: the ring's own hue at 30%, so a 0% ring still reads as
            /// *that goal's* ring (Apple Activity convention) instead of a neutral grey arc. Over
            /// `background` this is 1.33:1 (focus) to 2.33:1 (workout); the old `surface2` track
            /// was 1.16:1 on Today and effectively vanished on a new day.
            public static func track(for color: Color) -> Color {
                color.opacity(0.30)
            }

            /// Resolves the ring color for a `GoalType` (`Core/Sources/Core/Models/Goal.swift`).
            /// Prefer this over hand-picking a color so every screen stays consistent, and so the
            /// four spec-exact assignments above are the only place that can drift from §15.
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
        /// `12` — small tiles, nested wells and chips that are not full capsules.
        public static let small: CGFloat = 12
        /// `20` — standard cards.
        public static let medium: CGFloat = 20
        /// `28` — large/hero surfaces (share cards, sheets, shield screens).
        public static let large: CGFloat = 28

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
    }

    // MARK: - Metrics

    /// Fixed sizes that are not spacing: hit targets, badge diameters, stroke weights. Named so
    /// nobody re-derives 44 or 32 at a call site.
    public enum Metrics {
        /// HIG minimum hit target. Grow the *target*, not the visual (`View.minTapTarget()`).
        public static let minTapTarget: CGFloat = 44
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
        /// Height of a horizontal progress bar (`TimeBankBar`). 10pt read as a hairline next to a
        /// 28pt numeral; 12pt has presence without becoming a slab.
        public static let progressBarHeight: CGFloat = 12
        /// A ring's stroke as a fraction of its diameter (9/88 and 14/148 in the fixed presets).
        public static let ringStrokeRatio: CGFloat = 0.095
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
    ///  * **Numerals** are fixed-size, rounded, bold, `monospacedDigit()` fonts so big stat numbers
    ///    don't jiggle in width as they tick. They stay `static func Font`s for source
    ///    compatibility; a `Font` value cannot hold `@ScaledMetric`, so anything that should scale
    ///    with Dynamic Type (a hero stat, the streak, a time bank) should render through
    ///    `NumeralText` instead of `.font(numeral…())`.
    ///
    /// A `Font` cannot carry tracking or leading either, which is why no screen ever had any.
    /// `View.zanoText(_:)` applies a style's font *and* its tracking/leading.
    public enum Typography {

        // MARK: Numerals

        /// Display numerals (72pt, heavy): the one number a screen exists to show — the Today
        /// state, the Time Bank reward, the wake-up counters, the alarm clock, a streak
        /// milestone. Aim for a hero-to-supporting ratio of at least 3:1 (competitor dashboards
        /// sit near 72pt against ~13pt captions; this app's largest text used to be 22pt).
        public static func numeralHero() -> Font {
            .system(size: 72, weight: .heavy, design: .rounded).monospacedDigit()
        }
        /// Large numerals (e.g. a Live Activity countdown, a `.large` ring's center value,
        /// secondary big stats).
        public static func numeralLarge() -> Font {
            .system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
        }
        /// Medium numerals (e.g. `GoalRing` center value, `TimeBankBar`'s remaining-minutes label).
        public static func numeralMedium() -> Font {
            .system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
        }
        /// Small numerals (e.g. `StreakPill`'s count, compact stat chips).
        public static func numeralSmall() -> Font {
            .system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// A numeral at an arbitrary point size, for layouts where the size is a function of a
        /// container (a ring's center scales with the ring's diameter). Same face as the named
        /// numerals. Prefer the named tiers wherever the size is not container-driven.
        public static func numeral(size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }

        // MARK: Text styles (Dynamic Type)

        /// Hero headlines (onboarding hook, plan reveal, celebration): Large Title, rounded bold.
        /// 34pt at the default size. Replaces the ad hoc 34/30 rounded sizes.
        public static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        /// Full-screen focal messages (the shield headline): Title 1, bold. 28pt at the default
        /// size — between `display` and `title`.
        public static let titleLarge = Font.system(.title, design: .default, weight: .bold)
        /// Screen/section titles. Title 2, bold: 22pt at the default size.
        public static let title = Font.system(.title2, design: .default, weight: .bold)
        /// Card headlines (e.g. `LockStatusCard`'s status line, `ShieldPreview`'s headline).
        /// Headline: 17pt semibold at the default size.
        public static let headline = Font.system(.headline, design: .default, weight: .semibold)
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
            /// The small all-caps label above a headline: caption-emphasized, uppercased, with
            /// +0.8pt tracking (SF auto-tracks by size but not for caps runs).
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
            content.font(Theme.Typography.display).tracking(-0.4)
        case .titleLarge:
            content.font(Theme.Typography.titleLarge).tracking(-0.2)
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
            content.font(Theme.Typography.captionEmphasized).textCase(.uppercase).tracking(0.8)
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
