// SettingsKit.swift
// App / Features / Settings
//
// Visual pass 2 (2026-10-03, founder: "more playful", Settings "calmer than the rest but on-theme").
// The few pieces Settings and its sub-screens (Nudges, Pause, Auto-Focus, Goals, and the LockSetup
// rules screens) share, so each screen stops hand-rolling its own eyebrow + caption + card:
//
//   * `SettingsSticker`       a colour sticker per row (Core's `ZanoSticker`), replacing the
//                             monochrome grey discs. Colours come from the goal palette; each
//                             section has its own family so a section reads as one thing.
//   * `SettingsSectionTitle`  a rounded section title (not a small grey eyebrow) with an optional
//                             (i) that holds the explanation that used to sit under the card.
//   * `SettingsPalette`       the per-section colours, in one place.
//
// Built only from Core tokens and components (`ZanoSticker`, `ZanoInfoButton`, `Theme`); Core/UI is
// untouched.

import SwiftUI
import Core

/// Per-section sticker and toggle colours (goal palette). Calm: one family per section.
enum SettingsPalette {
    static let goals = Theme.Colors.Ring.steps
    static let lockSets = Theme.Colors.Ring.focus
    static let gym = Theme.Colors.Ring.workout
    static let tags = Theme.Colors.Ring.water
    static let sunrise = Theme.Colors.Ring.sunriseAlarm
    static let sleep = Theme.Colors.Ring.sleepOnTime
    static let focus = Theme.Colors.Ring.focus
    static let calendar = Theme.Colors.Ring.mealPrep
    static let rewards = Theme.Colors.Ring.sunriseAlarm
    static let gear = Theme.Colors.Ring.creatine
    static let nudges = Theme.Colors.Ring.creatine
    static let systemNotifications = Theme.Colors.Ring.coldShowerSauna
    static let restore = Theme.Colors.accent
    static let help = Theme.Colors.Ring.water
    static let health = Theme.Colors.Ring.creatine
    static let legal = Theme.Colors.muted
    static let danger = Theme.Colors.danger
    /// Toggles in the lock-rules screens (schedule, earn mode) wear the lock colour.
    static let lockToggle = Theme.Colors.Ring.focus
}

/// A colour sticker for a row: Core's `ZanoSticker` (icon-only, filled), sized from a point size.
/// Disabled rows get the quiet tinted version in `muted`. Decorative (the row's title says it).
struct SettingsSticker: View {
    let systemImage: String
    var tint: Color = Theme.Colors.muted
    var baseSize: CGFloat = Theme.Metrics.iconBadgeSmall

    @Environment(\.isEnabled) private var isEnabled

    private var size: ZanoSticker.Size {
        if baseSize <= 28 { return .small }
        if baseSize <= 40 { return .regular }
        return .large
    }

    var body: some View {
        ZanoSticker(
            systemImage: systemImage,
            color: isEnabled ? tint : Theme.Colors.muted,
            style: isEnabled ? .filled : .tinted,
            size: size
        )
        .accessibilityHidden(true)
    }
}

/// A section's title in the rounded voice, with an optional (i) holding its explanation.
struct SettingsSectionTitle: View {
    let title: String
    var info: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            if let info {
                ZanoInfoButton(info, accessibilityLabel: Copy.settings.sectionInfoLabel(title))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(minHeight: Theme.Metrics.minTapTarget)
    }
}
