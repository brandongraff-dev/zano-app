// WatchTheme.swift
// Watch/ZANOWatch
//
// A target-local MIRROR of `Core/Sources/Core/UI/Theme.swift`'s tokens (colors, spacing,
// typography, motion) — every value below is copied by hand from that file, not imported from
// it. This is not the codebase's preferred pattern (CLAUDE.md: "Shared code only in
// Core/Sources/Core/<Module>") — it exists only because of a real, current constraint documented
// in three places already touched by this task:
//
//   - `Core/Package.swift`'s `platforms:` list declares only `.iOS(.v17)`. Swift Package Manager
//     refuses to resolve the `Core` product for a watchOS target at all until `.watchOS(...)` is
//     added there.
//   - Even if that were added, `Core`'s single unified target imports `FamilyControls`,
//     `ManagedSettings`, `DeviceActivity` (`LockEngine/LockEngineManager.swift`) and `ActivityKit`
//     (`Verification/FocusSessionVerifier.swift`, `LiveActivity/*`) — none of which exist on the
//     watchOS SDK. `Core` would need splitting into a watchOS-safe subset and an iOS-only
//     remainder before any watchOS target could link it, which is a package-wide restructuring
//     far outside this task's scope (`Watch/ZANOWatch/` only) and a real collision risk against
//     the several other concurrent workflows editing `Core/Sources/Core/*` this same run.
//   - `project.yml`'s `ZANOWatch` target block already documents this exact gap ("Does NOT depend
//     on `package: Core`... Watch/ZANOWatch's Swift files are plain SwiftUI with no Core types").
//
// So: every hex/size/curve below is hand-copied from `Theme.swift` as of this task and MUST be
// kept in sync by hand if `Theme.swift` changes, until `Core` gains real watchOS support — at
// which point this whole file should be deleted and every call site here switched to
// `import Core; Theme....` directly. Flagged in this task's knownIssues.
//
// Deliberately trimmed to only what the watch UI actually uses (CLAUDE.md: "Don't add
// abstractions... beyond what the current session's scope requires") — not a 1:1 copy of every
// token in `Theme.swift`.

import SwiftUI

public enum WatchTheme {

    // MARK: - Colors (mirrors `Theme.Colors`, spec §15's token table)

    public enum Colors {
        /// Mirrors `Theme.Colors.background` (`#0A0A0B`).
        public static let background = Color(watchThemeHex: 0x0A_0A_0B)
        /// Mirrors `Theme.Colors.surface` (`#141416`).
        public static let surface = Color(watchThemeHex: 0x14_14_16)
        /// Mirrors `Theme.Colors.surface2` (`#1C1C1F`).
        public static let surface2 = Color(watchThemeHex: 0x1C_1C_1F)
        /// Mirrors `Theme.Colors.text` (`#F5F5F7`).
        public static let text = Color(watchThemeHex: 0xF5_F5_F7)
        /// Mirrors `Theme.Colors.muted` (`#8E8E93`).
        public static let muted = Color(watchThemeHex: 0x8E_8E_93)
        /// Mirrors `Theme.Colors.accent` (`#B8FF3C`) — the one brand accent (earned/unlock).
        public static let accent = Color(watchThemeHex: 0xB8_FF_3C)
        /// Mirrors `Theme.Colors.danger` (`#FF453A`).
        public static let danger = Color(watchThemeHex: 0xFF_45_3A)
        /// Mirrors `Theme.Colors.warning` (`#FFB020`).
        public static let warning = Color(watchThemeHex: 0xFF_B0_20)

        /// Mirrors `Theme.Colors.Ring` — only the four ring colors the watch actually shows
        /// (`WatchRingKind`: workout/protein/focus/water). `Theme.Colors.Ring`'s other,
        /// spec-unassigned ring colors (steps, creatine, ...) are not mirrored — the watch has no
        /// ring for them.
        public enum Ring {
            /// Spec-exact: workout rings reuse the single brand accent.
            public static let workout = Colors.accent
            /// Spec-exact `#FF7A00`.
            public static let protein = Color(watchThemeHex: 0xFF_7A_00)
            /// Spec-exact `#5E5CE6`.
            public static let focus = Color(watchThemeHex: 0x5E_5C_E6)
            /// Spec-exact `#32ADE6`.
            public static let water = Color(watchThemeHex: 0x32_AD_E6)

            public static func color(for kind: WatchRingKind) -> Color {
                switch kind {
                case .workout: workout
                case .protein: protein
                case .focus: focus
                case .water: water
                }
            }
        }
    }

    // MARK: - Spacing (mirrors `Theme.Spacing`, spec §15: "4, 8, 12, 16, 24, 32")

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
    }

    // MARK: - Typography (mirrors `Theme.Typography`, trimmed to watch-appropriate sizes)
    //
    // watchOS screens run far smaller than the phone (spec §15's 44pt `numeralLarge` is oversized
    // for a 41mm/45mm face), so these are NOT copied 1:1 from `Theme.Typography`'s point sizes —
    // same font traits (rounded, monospaced-digit numerals; system default for body/caption) at
    // sizes tuned for the watch. Flagged as a deliberate, documented deviation, not drift.

    public enum Typography {
        /// The watch equivalent of `Theme.Typography.numeralMedium()` — a ring's center value.
        public static func numeralMedium() -> Font {
            .system(size: 20, weight: .bold, design: .rounded).monospacedDigit()
        }
        /// The watch equivalent of `Theme.Typography.numeralSmall()`.
        public static func numeralSmall() -> Font {
            .system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
        }
        public static let headline = Font.system(size: 15, weight: .semibold, design: .default)
        public static let body = Font.system(size: 13, weight: .regular, design: .default)
        public static let caption = Font.system(size: 11, weight: .regular, design: .default)
        public static let captionEmphasized = Font.system(size: 11, weight: .semibold, design: .default)
    }

    // MARK: - Motion (mirrors `Theme.Motion`)

    public enum Motion {
        /// Mirrors `Theme.Motion.ringFill` (spec §15: "ring fills ease-out 600ms").
        public static let ringFill: Animation = .easeOut(duration: 0.6)
        /// Mirrors `Theme.Motion.springStandard`.
        public static let springStandard: Animation = .spring(response: 0.35, dampingFraction: 0.82)
    }
}

// MARK: - Hex color helper

extension Color {
    /// Same packed-`0xRRGGBB` helper as `Theme.swift`'s `Color(zanoHex:)`, renamed so it can't be
    /// confused with (or collide with) that one if `Core` ever does become importable here.
    init(watchThemeHex value: UInt32) {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
