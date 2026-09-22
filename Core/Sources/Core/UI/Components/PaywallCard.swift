// PaywallCard.swift
// Core / UI / Components
//
// The paywall plan card from docs/spec.md §15's core component list and the P5 mockup in §16:
// "annual plan card highlighted '$39.99/yr · 7 days free', monthly option smaller". Spec §15 names
// this component but defines no initializer for it — its shape is inferred from how
// `App/ZANO/Features/Onboarding/PaywallView.swift` (this repo's only caller) already uses it: a
// selectable row with a title, a fully-composed price line, an optional detail line, and an
// optional badge (e.g. "BEST VALUE") for the highlighted plan. All text is caller-composed (from
// `Core/Sources/Core/Copy`), matching every other `Core/UI/Components` file's "no hardcoded copy"
// convention (see e.g. `GoalRow.swift`'s header note) — `SubscriptionPackage`/pricing types never
// appear here; the caller resolves them to plain strings first.

import SwiftUI

/// A single selectable subscription plan row for the paywall (docs/spec.md §21, §7.13). Reuses the
/// same "row with leading selection glyph, trailing value" visual language as `GoalRow`/
/// `LockStatusCard` so the paywall reads as part of the same design system, not a one-off screen.
public struct PaywallCard: View {
    private let title: String
    private let priceLine: String
    private let detailLine: String?
    private let badgeLabel: String?
    private let isHighlighted: Bool
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: Caller-composed plan name, e.g. "Annual" / "Monthly".
    ///   - priceLine: Caller-composed, fully formatted price, e.g. "$39.99/yr".
    ///   - detailLine: Caller-composed secondary line, e.g. "$3.33/mo · 7 days free". Defaults to
    ///     `nil`.
    ///   - badgeLabel: Caller-composed badge text, e.g. "BEST VALUE". `nil` shows no badge.
    ///     Defaults to `nil`.
    ///   - isHighlighted: Whether this is the emphasized plan (spec §21/§16 P5: "annual
    ///     highlighted") — tints the border even when not the current selection. Defaults to
    ///     `false`.
    ///   - isSelected: Whether this plan is the user's current selection — drives the leading
    ///     glyph and a stronger border/fill. Defaults to `false`.
    ///   - action: Tap handler (select this plan).
    public init(
        title: String,
        priceLine: String,
        detailLine: String? = nil,
        badgeLabel: String? = nil,
        isHighlighted: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.priceLine = priceLine
        self.detailLine = detailLine
        self.badgeLabel = badgeLabel
        self.isHighlighted = isHighlighted
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.muted)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Text(title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        if let badgeLabel {
                            Text(badgeLabel)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.background)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accent, in: Capsule())
                        }
                    }
                    if let detailLine {
                        Text(detailLine)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }

                Spacer(minLength: 0)

                Text(priceLine)
                    .font(Theme.Typography.numeralSmall())
                    .foregroundStyle(Theme.Colors.text)
            }
            .padding(Theme.Spacing.md)
            .background(
                isSelected ? Theme.Colors.surface2 : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Theme.Colors.accent
                            : (isHighlighted ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.hairline),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.springStandard, value: isSelected)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.sm) {
        PaywallCard(
            title: "Annual",
            priceLine: "$39.99/yr",
            detailLine: "$3.33/mo · 7 days free",
            badgeLabel: "BEST VALUE",
            isHighlighted: true,
            isSelected: true,
            action: {}
        )
        PaywallCard(
            title: "Monthly",
            priceLine: "$6.99/mo",
            isSelected: false,
            action: {}
        )
    }
    .padding()
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
