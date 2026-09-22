// StreakPill.swift
// Core / UI / Components
//
// The streak indicator from docs/spec.md §15's core component list and the P1 mockup in §16
// ("streak pill '14 🔥'"). Renders an SF Symbol flame instead of the literal emoji so it inherits
// system dynamic type, tinting, and dark-mode rendering correctly. `count` is numeric data (not
// copy), so it's safe to render directly per CLAUDE.md's no-hardcoded-copy rule; any surrounding
// sentence ("14-day streak") is the caller's job via `Core/Sources/Core/Copy`.

import SwiftUI

/// A compact capsule showing the user's current streak length, per docs/spec.md §8 (Retention
/// Psychology Rules) — "streaks have forgiveness"; see `isFrozen` below for how that's reflected.
public struct StreakPill: View {
    private let count: Int
    /// True while a streak freeze (`StreakEngine.useFreeze`) is covering today instead of an
    /// earned unlock — swaps the flame for a snowflake and cools the tint so the pill visibly
    /// communicates "protected", not "broken" (spec §8 rule 3: "should feel protective, not
    /// fragile").
    private let isFrozen: Bool
    /// Optional VoiceOver label override. When `nil`, falls back to just the numeral (data, not a
    /// composed sentence) so this component never hardcodes accessibility copy; callers that want
    /// a full spoken phrase (e.g. "14 day streak") should supply it from `Copy`.
    private let accessibilityLabelOverride: String?

    public init(count: Int, isFrozen: Bool = false, accessibilityLabelOverride: String? = nil) {
        self.count = count
        self.isFrozen = isFrozen
        self.accessibilityLabelOverride = accessibilityLabelOverride
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: isFrozen ? "snowflake" : "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFrozen ? Theme.Colors.Ring.water : Theme.Colors.accent)
                .symbolEffect(.bounce, value: count)

            Text("\(count)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelOverride ?? "\(count)")
        .animation(Theme.Motion.springStandard, value: isFrozen)
    }
}
