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
//
// Design-quality pass (docs/design/{composition-audit #5,better-ui,typography-color,better-layout}):
//
//   * Annual and monthly were the same object: 71pt cards differing by a 40%-opacity stroke and a
//     pill, the price — the thing being sold — a 17pt caption-sized numeral. `isHighlighted` now
//     sets the *hero* layout (spec P5: "annual highlighted, monthly smaller"): a large-radius card,
//     an accent wash, roomier padding and the price at 28pt; the other plan stays a compact row with
//     a 17pt price. The price is a `NumeralText` ("$39.99" loud, "/yr" quiet).
//   * Selection is unmistakable and costs no layout: a 2pt accent stroke drawn *inside* the card on
//     an on-hue accent wash, with the radio filling to a check. The unselected border is a real edge
//     now (it was `hairline` at 1.06:1, i.e. none); a highlighted-but-unselected plan keeps a dim
//     accent stroke so it still reads as the recommended one.
//   * The badge's label is `onFill` on the accent fill (16.4:1), set as tracked caps via the shared
//     eyebrow tracking; it wraps beneath the title when a long localized title leaves no room.
//   * The card presses (`PressableStyle`) — `.buttonStyle(.plain)` swallowed the press on the app's
//     revenue screen — is announced as selected to VoiceOver, and its animation is gated on
//     Reduce Motion (it was one of four Core UI components with no gate at all).

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Caller-composed plan name, e.g. "Annual" / "Monthly".
    ///   - priceLine: Caller-composed, fully formatted price, e.g. "$39.99/yr".
    ///   - detailLine: Caller-composed secondary line, e.g. "$3.33/mo · 7 days free". Defaults to
    ///     `nil`.
    ///   - badgeLabel: Caller-composed badge text, e.g. "BEST VALUE". `nil` shows no badge.
    ///     Defaults to `nil`.
    ///   - isHighlighted: Whether this is the emphasized plan (spec §21/§16 P5: "annual
    ///     highlighted") — gives it the larger *hero* layout and keeps an accent edge even when it
    ///     is not the current selection. Defaults to `false`.
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

    private var radius: CGFloat {
        isHighlighted ? Theme.Radius.large : Theme.Radius.medium
    }

    private var padding: CGFloat {
        isHighlighted ? Theme.Spacing.lg : Theme.Spacing.md
    }

    private var priceSize: NumeralText.Size {
        isHighlighted ? .medium : .small
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.muted)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    // Selection is announced by the `.isSelected` trait below, not by the glyph's
                    // symbol name ("checkmark circle fill").
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    // Title and badge share a row while they fit; a long localized title pushes the
                    // badge beneath it instead of squeezing or truncating either.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.xs) {
                            titleText
                            badge
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            titleText
                            badge
                        }
                    }
                    if let detailLine {
                        Text(detailLine)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(isHighlighted ? Theme.Colors.textSecondary : Theme.Colors.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Theme.Spacing.xs)

                NumeralText(priceLine, size: priceSize)
                    .fixedSize()
            }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .background(
                isSelected ? Theme.Colors.accentWash : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                if isSelected {
                    // Selected: a 2pt accent stroke, drawn inside so selecting never shifts layout.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.Colors.accent, lineWidth: 2)
                } else if isHighlighted {
                    // The recommended plan keeps a dim accent edge even when not chosen.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.Colors.accentDim, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.Colors.edgeGradient(), lineWidth: Theme.Metrics.edgeWidth)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleText: some View {
        Text(title)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var badge: some View {
        if let badgeLabel {
            Text(badgeLabel)
                .font(Theme.Typography.captionEmphasized)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.onFill)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.accent, in: Capsule())
        }
    }
}

#Preview("PaywallCard") {
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
        PaywallCard(
            title: "Annual",
            priceLine: "$39.99/yr",
            detailLine: "$3.33/mo · 7 days free",
            badgeLabel: "BEST VALUE",
            isHighlighted: true,
            isSelected: false,
            action: {}
        )
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
