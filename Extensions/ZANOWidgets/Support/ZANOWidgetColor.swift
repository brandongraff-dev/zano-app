// ZANOWidgetColor.swift
// Extensions/ZANOWidgets/Support
//
// The widgets' colour tokens. Originally a hand-copied mirror of the spec's first palette (the
// near-black canvas, muted bronze/lavender/glacier rings), kept separate because Core's `Theme` did
// not exist yet. It does now, and this extension already imports Core (`ZANOWidgetComponents` draws
// the star with `Theme.Colors.metallic`), so since pass 2 (2026-10-03, docs/design/
// visual-direction-v2.md "Pass 2: playful") every token here simply *points at* the v2 palette: the
// indigo-ink canvas, ZANO Blue, ember for the streak flame, and the saturated goal colours. One
// source of truth, so the Home Screen, StandBy and Live Activities match the app.
//
// All of these are `static let`s on non-actor enums holding `Color` (Sendable), so they are safe to
// read from widget timeline/rendering code, which is not main-actor isolated.
//
// StandBy and the accented/vibrant rendering modes strip or desaturate colour themselves
// (`.widgetAccentable()` marks what stays lit), so nothing here needs a StandBy variant.

import SwiftUI
import Core

enum ZANOWidgetColor {
    /// `#0B0E24` indigo ink (was near-black `#050506`).
    static let background = Theme.Colors.background
    static let backgroundDeep = Theme.Colors.backgroundDeep
    static let surface = Theme.Colors.surface
    static let surface2 = Theme.Colors.surface2
    static let textPrimary = Theme.Colors.text
    /// `#A6A4C8` (was a 45% system grey).
    static let textMuted = Theme.Colors.muted

    /// ZANO Blue `#3F7BFF`. For text, strokes, bars and glyphs; never under a white label.
    static let accent = Theme.Colors.accent
    /// `#2A62E6`: the fill under a white label (5.27:1), e.g. the start-lock capsule.
    static let accentFill = Theme.Colors.accentFill
    /// The second aurora light, for the widget backgrounds.
    static let violet = Theme.Colors.Aurora.violet
    /// The streak flame (ember is for streak and fire moments only).
    static let ember = Theme.Colors.ember
    static let danger = Theme.Colors.danger
    static let warning = Theme.Colors.warning

    // Goal colours (v2, saturated): workout volt, protein apricot, focus violet, water sky.
    static let ringWorkout = Theme.Colors.Ring.workout
    static let ringProtein = Theme.Colors.Ring.protein
    static let ringFocus = Theme.Colors.Ring.focus
    static let ringWater = Theme.Colors.Ring.water
}
