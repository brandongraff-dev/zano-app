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
    static let background = Color(red: 0x05 / 255.0, green: 0x05 / 255.0, blue: 0x06 / 255.0)
    static let surface = Color(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0)
    static let surface2 = Color(red: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x1C / 255.0)
    static let textPrimary = Color(red: 0xF2 / 255.0, green: 0xF1 / 255.0, blue: 0xED / 255.0)
    static let textMuted = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0)

    /// The single accent color, ZANO Blue `#3F7BFF` (mirrors `Theme.Colors.accent`). For text,
    /// strokes, bars and glyphs; never under a white label (white on it is 3.83:1).
    static let accent = Color(red: 0x3F / 255.0, green: 0x7B / 255.0, blue: 0xFF / 255.0)
    /// `#2A62E6` (mirrors `Theme.Colors.accentFill`): the fill of a filled blue button with a
    /// white label (5.27:1), e.g. the home widget's start-lock capsule.
    static let accentFill = Color(red: 0x2A / 255.0, green: 0x62 / 255.0, blue: 0xE6 / 255.0)
    static let danger = Color(red: 0xDE / 255.0, green: 0x5A / 255.0, blue: 0x52 / 255.0)
    static let warning = Color(red: 0xD9 / 255.0, green: 0xA5 / 255.0, blue: 0x5B / 255.0)

    // Ring colors: protein bronze, focus slate lavender, water glacier (mirrors `Theme.Colors.Ring`).
    // Workout still reuses the accent here; `Theme.Colors.Ring.workout` is now cool steel.
    static let ringWorkout = accent
    static let ringProtein = Color(red: 0xC8 / 255.0, green: 0x93 / 255.0, blue: 0x6A / 255.0)
    static let ringFocus = Color(red: 0x8E / 255.0, green: 0x96 / 255.0, blue: 0xC8 / 255.0)
    static let ringWater = Color(red: 0x86 / 255.0, green: 0xB4 / 255.0, blue: 0xC4 / 255.0)
}
