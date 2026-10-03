// PressableStyle.swift
// Core / UI / Components
//
// Touch-down feedback for anything tappable that is not a `PrimaryButton`. `.buttonStyle(.plain)`
// suppresses SwiftUI's default press state almost entirely — a direct miss against HIG's
// "Response" principle (react on touch-down, not on release) — and the app had drifted into two
// private copies of the same fix (`GoalRow.RowPressStyle`, `GhostProgressBanner.RowPressStyle`)
// plus at least ten tappable cards with no press state at all (Today's lock card, the paywall plan
// cards, every onboarding option row). Two copies plus ten misses clears CLAUDE.md's "three
// similar call sites" bar for a shared piece (docs/design/better-ui-findings.md MOT-02).
//
// Put the padding and the background *inside* the `Button` label so the whole card is the hit
// target and the whole card presses — applying them outside leaves a dead ring around the row and
// scales only the label inside a static card (HIT-04).

import SwiftUI

/// A `ButtonStyle` for tappable rows and cards: a squish on touch-down and a springy bounce back on
/// release.
///
/// Pass 2 (playful, 2026-10-03): the press is a *squish*, not a shrink. The view gets a little wider
/// than it gets taller (x shrinks a quarter less than `scale`, y a quarter more), dims slightly, and
/// on release springs back on `Theme.Motion.springSquish`, overshooting past 1 like a rubber button.
/// Press-in stays on the fast `pressFeedback` curve (HIG's 100–160ms response budget). Under Reduce
/// Motion the scale is dropped and the release is a flat ease (the dim stays: "the interface heard
/// you" is information; the bounce is not).
public struct PressableStyle: ButtonStyle {
    private let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter scale: Pressed scale. `0.98` (default) for full-width rows and cards — a 4%
    ///   shrink of a 361pt card is already 14pt; use `0.96` for tiles, `0.92` for compact chips.
    public init(scale: CGFloat = 0.98) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        let give = 1 - scale
        return configuration.label
            .scaleEffect(
                x: pressed ? scale + give * 0.25 : 1,
                y: pressed ? scale - give * 0.25 : 1
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(curve(isPressed: configuration.isPressed), value: configuration.isPressed)
    }

    private func curve(isPressed: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.1) }
        return isPressed ? Theme.Motion.pressFeedback : Theme.Motion.springSquish
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// `PressableStyle()` — full-width row/card press.
    public static var pressable: PressableStyle { PressableStyle() }

    /// `PressableStyle(scale:)` — e.g. `.pressable(scale: 0.96)` for chips and compact controls.
    public static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

extension View {
    /// Grows the view's *hit target* to at least 44×44pt (`Theme.Metrics.minTapTarget`) without
    /// changing how it looks. The pattern `ShieldPreview`'s Emergency link already used: keep the
    /// small glyph or low-emphasis text the design wants, grow only the target. For glyph-only
    /// close/back/delete controls, which were 11–32pt.
    ///
    /// Apply to the *label* of the button (inside it), not to the button.
    public func minTapTarget() -> some View {
        frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
    }
}
