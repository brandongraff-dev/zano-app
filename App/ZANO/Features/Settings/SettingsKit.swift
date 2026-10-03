// SettingsKit.swift
// App / Features / Settings
//
// Visual pass 2 (2026-10-03, founder: "more playful", Settings "calmer than the rest but on-theme").
// The few pieces Settings and its sub-screens (Nudges, Pause, Auto-Focus, Goals, and the LockSetup
// rules screens) share, so each screen stops hand-rolling its own eyebrow + caption + card:
//
//   * `SettingsSticker`       a colour sticker per row (rounded square, ink glyph), replacing the
//                             monochrome grey discs. Colours come from the goal palette; each
//                             section has its own family so a section reads as one thing.
//   * `SettingsSectionTitle`  a rounded section title (not a small grey eyebrow) with an optional
//                             (i) that holds the explanation that used to sit under the card.
//   * `SettingsPalette`       the per-section colours, in one place.
//
// Built only from Core tokens and components (`ZanoInfoButton`, `Theme`); Core/UI is untouched.

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

/// A colour sticker: a rounded square in `tint` with an ink glyph and a glossy rim. 32pt base,
/// scaling with Dynamic Type like `IconBadge` (capped at 1.4x). Disabled rows fade it to `muted`.
/// Decorative (the row's title carries the meaning).
struct SettingsSticker: View {
    let systemImage: String
    var tint: Color = Theme.Colors.muted
    var baseSize: CGFloat = Theme.Metrics.iconBadgeSmall

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let size = baseSize * min(scale, 1.4)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        let fill = isEnabled ? tint : Theme.Colors.surface2
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.Colors.background : Theme.Colors.muted)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: [fill, fill.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
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
