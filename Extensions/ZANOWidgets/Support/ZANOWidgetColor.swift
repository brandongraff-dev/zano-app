// ZANOWidgetColor.swift
// Extensions/ZANOWidgets/Support
//
// Hardcoded fallback color tokens, copied verbatim from docs/spec.md §15 Design System — the
// canonical values — for use ONLY inside Extensions/ZANOWidgets.
//
// Deliberately does NOT import or reference any Core/UI `Theme` type: per this session's task,
// Session 5's `Theme` may not exist yet on disk, and this extension has to keep compiling and
// rendering correctly regardless of when that design-system session lands. If/when
// `Core/Sources/Core/UI/Theme.swift` ships with equivalent tokens, this file should be deleted in
// favor of it — flagged in this task's knownIssues for the orchestrator.
//
// Widget chrome otherwise stays to system styles (system fonts, system materials via
// `.containerBackground`, SF Symbols) per this task's instructions — these are the only
// hardcoded colors in the extension, matching spec §15's "ONE accent only" rule.

import SwiftUI

enum ZANOWidgetColor {
    static let background = Color(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0B / 255.0)
    static let surface = Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x16 / 255.0)
    static let surface2 = Color(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1F / 255.0)
    static let textPrimary = Color(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0)
    static let textMuted = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0)

    /// The single accent color (spec §15: "ONE accent only") — earned/unlocked state.
    static let accent = Color(red: 0xB8 / 255.0, green: 0xFF / 255.0, blue: 0x3C / 255.0)
    static let danger = Color(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0)
    static let warning = Color(red: 0xFF / 255.0, green: 0xB0 / 255.0, blue: 0x20 / 255.0)

    // Ring colors (spec §15): workout = accent, protein = orange, focus = indigo, water = blue.
    static let ringWorkout = accent
    static let ringProtein = Color(red: 0xFF / 255.0, green: 0x7A / 255.0, blue: 0x00 / 255.0)
    static let ringFocus = Color(red: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0)
    static let ringWater = Color(red: 0x32 / 255.0, green: 0xAD / 255.0, blue: 0xE6 / 255.0)
}
