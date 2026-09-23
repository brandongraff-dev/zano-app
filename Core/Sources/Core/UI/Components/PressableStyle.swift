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

/// A `ButtonStyle` for tappable rows and cards: a slight press-in scale and dim on touch-down,
/// on `Theme.Motion.pressFeedback`. Under Reduce Motion the scale is dropped (the dim stays: "the
/// interface heard you" is information; the spring is not).
public struct PressableStyle: ButtonStyle {
    private let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter scale: Pressed scale. `0.98` (default) for full-width rows and cards — a 4%
    ///   shrink of a 361pt card is already 14pt; use `0.96` for compact controls and chips.
    public init(scale: CGFloat = 0.98) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
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
