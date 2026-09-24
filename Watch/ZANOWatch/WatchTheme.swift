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
        /// Mirrors `Theme.Colors.background` (`#050506`).
        public static let background = Color(watchThemeHex: 0x05_05_06)
        /// Mirrors `Theme.Colors.surface` (`#111113`).
        public static let surface = Color(watchThemeHex: 0x11_11_13)
        /// Mirrors `Theme.Colors.surface2` (`#19191C`).
        public static let surface2 = Color(watchThemeHex: 0x19_19_1C)
        /// Mirrors `Theme.Colors.text` (`#F2F1ED`, pearl).
        public static let text = Color(watchThemeHex: 0xF2_F1_ED)
        /// Mirrors `Theme.Colors.muted` (`#8E8E93`).
        public static let muted = Color(watchThemeHex: 0x8E_8E_93)
        /// Mirrors `Theme.Colors.accent` (`#3F7BFF`, ZANO Blue) — the one brand accent. For text,
        /// strokes and rings; never under a white label (white on it is 3.83:1).
        public static let accent = Color(watchThemeHex: 0x3F_7B_FF)
        /// Mirrors `Theme.Colors.accentFill` (`#2A62E6`) — the fill of a filled blue button (e.g.
        /// a `.borderedProminent` tint), so its white label clears AA (5.27:1).
        public static let accentFill = Color(watchThemeHex: 0x2A_62_E6)
        /// Mirrors `Theme.Colors.danger` (`#DE5A52`).
        public static let danger = Color(watchThemeHex: 0xDE_5A_52)
        /// Mirrors `Theme.Colors.warning` (`#D9A55B`).
        public static let warning = Color(watchThemeHex: 0xD9_A5_5B)

        /// Mirrors `Theme.Colors.Ring` — only the four ring colors the watch actually shows
        /// (`WatchRingKind`: workout/protein/focus/water). `Theme.Colors.Ring`'s other,
        /// spec-unassigned ring colors (steps, creatine, ...) are not mirrored — the watch has no
        /// ring for them.
        public enum Ring {
            /// Workout ring. NOTE: `Theme.Colors.Ring.workout` is now cool steel `#A3B1C6` (blue
            /// means act / earned only); the watch still uses the accent here — sync when the
            /// watch rings get their design pass.
            public static let workout = Colors.accent
            /// Mirrors `Theme.Colors.Ring.protein` (`#C8936A`, bronze).
            public static let protein = Color(watchThemeHex: 0xC8_93_6A)
            /// Mirrors `Theme.Colors.Ring.focus` (`#8E96C8`, slate lavender).
            public static let focus = Color(watchThemeHex: 0x8E_96_C8)
            /// Mirrors `Theme.Colors.Ring.water` (`#86B4C4`, glacier).
            public static let water = Color(watchThemeHex: 0x86_B4_C4)

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
