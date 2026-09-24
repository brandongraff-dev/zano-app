// SelectableCard.swift
// Core / UI / Components
//
// Single-choice option cards. The app had five selection idioms and three copy-pasted rows:
// onboarding Q1/Q5/Q6 (`Screen3MainGoal`, `Screen7FallOff`, `Screen8CoachVoice` — the same code
// three times), the paywall's radio glyph, Settings' coach-voice rows, the sunrise alarm's variant
// rows, and a `Toggle` misused as a radio on the lock-set list. All text-only, none with a press
// state, and the unselected border was `hairline` — invisible (docs/design/better-layout-findings.md
// 4.2, better-ui-findings.md MOT-02, composition-audit.md S-6). Edges and affordances should be
// learned once.
//
// Selected = a lifted `surface2` fill + 1.5pt white border (drawn *inside*, so selecting never shifts layout) +
// filled check. Unselected = surface + visible hairline + empty radio. The optional leading glyph
// makes an option scannable before it is read (onboarding's "what's your main goal" was five
// identical text rows).

import SwiftUI

/// A tappable single-choice card: optional leading icon, title, optional subtitle, and a trailing
/// radio/check. All text is caller-composed.
public struct SelectableCard: View {
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let isSelected: Bool
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Caller-composed option title.
    ///   - subtitle: Caller-composed supporting line (e.g. a coach voice's sample). Defaults to `nil`.
    ///   - icon: SF Symbol name for a leading `IconBadge`. Defaults to `nil` (no leader).
    ///   - isSelected: Whether this option is the current choice.
    ///   - action: Tap handler (select this option).
    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    IconBadge(
                        systemName: icon,
                        tint: Theme.Colors.text,
                        size: .small
                    )
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.muted)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    // Selection is announced by the `.isSelected` trait below, not by the glyph's
                    // symbol name ("checkmark circle fill").
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .background(
                isSelected ? Theme.Colors.surface2 : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.interactive : Theme.Colors.hairline,
                        lineWidth: isSelected ? 1.5 : Theme.Metrics.edgeWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The name the layout audit used for the same component.
public typealias SelectableRow = SelectableCard

#Preview("SelectableCard") {
    VStack(spacing: Theme.Spacing.sm) {
        SelectableCard(title: "Get to the gym", subtitle: "Build a workout habit", icon: "dumbbell.fill", isSelected: true, action: {})
        SelectableCard(title: "Eat enough protein", icon: "fork.knife", isSelected: false, action: {})
        SelectableCard(title: "Plain option", isSelected: false, action: {})
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
