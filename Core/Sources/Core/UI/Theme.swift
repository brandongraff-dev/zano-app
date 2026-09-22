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

        /// A hairline divider tone — not in spec §15's table verbatim, but every mockup in §16
        /// calls for "crisp 1px hairline dividers"; derived from `surface2` at low opacity rather
        /// than inventing a new hex token.
        public static let hairline = surface2.opacity(0.8)

        /// Per-goal ring colors (spec §15: "Ring colors: workout = accent, protein = `#FF7A00`,
        /// focus = `#5E5CE6`, water = `#32ADE6`"). Spec only names those four; the remaining
        /// `GoalType` cases (steps, creatine, sunrise alarm, sleep, reading, meal prep, stretch,
        /// cold shower/sauna, custom) have no assigned hex in §15. `Ring.color(for:)` below
        /// extends the palette additively using Apple's own system palette hues so every goal type
        /// gets a stable, distinguishable ring color — flagged as an assumption in this task's
        /// decisions; revisit with design before shipping if §15 is amended with exact values.
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
    public enum Radius {
        /// `12` — small controls (pills, chips, buttons).
        public static let small: CGFloat = 12
        /// `20` — standard cards.
        public static let medium: CGFloat = 20
        /// `28` — large/hero surfaces (share cards, sheets, shield screens).
        public static let large: CGFloat = 28
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

    // MARK: - Typography

    /// Type ramp from spec §15: "Type: SF Pro ...; big numerals for grams/minutes/streak". SF Pro
    /// is the system font, so these are all `.system` fonts (no bundled font asset needed); the
    /// `numeral` styles add `.monospacedDigit()` so big stat numbers don't jiggle in width as they
    /// animate/tick (e.g. a live focus-session countdown, `TimeBankBar`'s minute label).
    public enum Typography {
        /// Large hero numerals (e.g. a Live Activity countdown, the Today ring's center number).
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
        /// Screen/section titles.
        public static let title = Font.system(size: 22, weight: .bold, design: .default)
        /// Card headlines (e.g. `LockStatusCard`'s status line, `ShieldPreview`'s headline).
        public static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        /// Default body text.
        public static let body = Font.system(size: 15, weight: .regular, design: .default)
        /// Secondary / caption text (subtitles, timestamps, fine print).
        public static let caption = Font.system(size: 13, weight: .regular, design: .default)
        /// Emphasized caption (e.g. a pill label).
        public static let captionEmphasized = Font.system(size: 13, weight: .semibold, design: .default)
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

        /// Duration of `PrimaryButton`'s `.holdToCommit` press-and-hold gesture, per this task's
        /// brief ("hold-to-commit variant: 2-second press + haptics").
        public static let holdToCommitDuration: TimeInterval = 2.0
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
