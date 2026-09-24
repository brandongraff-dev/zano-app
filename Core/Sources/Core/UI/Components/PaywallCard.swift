// PaywallCard.swift
// Core / UI / Components
//
// The paywall plan card from docs/spec.md §15's core component list and the P5 mockup in §16:
// "annual plan card highlighted '$39.99/yr · 7 days free', monthly option smaller". Spec §15 names
// this component but defines no initializer for it — its shape is inferred from how
// `App/ZANO/Features/Onboarding/PaywallView.swift` (this repo's only caller) already uses it: a
// selectable row with a title, a fully-composed price line, an optional detail line, and an
// optional badge (e.g. "Best value") for the highlighted plan. All text is caller-composed (from
// `Core/Sources/Core/Copy`), matching every other `Core/UI/Components` file's "no hardcoded copy"
// convention (see e.g. `GoalRow.swift`'s header note) — `SubscriptionPackage`/pricing types never
// appear here; the caller resolves them to plain strings first.
//
// Design-quality pass (docs/design/{composition-audit #5,better-ui,typography-color,better-layout}):
//
//   * Annual and monthly were the same object: 71pt cards differing by a 40%-opacity stroke and a
//     pill, the price — the thing being sold — a 17pt caption-sized numeral. `isHighlighted` now
//     sets the *hero* layout (spec P5: "annual highlighted, monthly smaller"): a large-radius card,
//     roomier padding and the price at 28pt; the other plan stays a compact row with a 17pt price.
//     The price is a `NumeralText` ("$39.99" loud, "/yr" quiet).
//   * Selection costs no layout: the stroke is drawn *inside* the card. The unselected border is a
//     real edge (it was `hairline` at 1.06:1, i.e. none). The badge wraps beneath the title when a
//     long localized title leaves no room.
//   * The card presses (`PressableStyle`) — `.buttonStyle(.plain)` swallowed the press on the app's
//     revenue screen — is announced as selected to VoiceOver, and its animation is gated on
//     Reduce Motion (it was one of four Core UI components with no gate at all).
//
// Premium pass (2026-09-24, "light is earned"; spec §15 as amended): buying is not an earned state,
// so nothing on this card is acid green any more. Selection is the app-wide white selection (a 2pt
// `interactive` edge, the radio filling to a white check, a lifted fill); the badge is a white pill
// with dark text in sentence case; the highlighted plan's trial ("7 days free") gets its own quiet
// pill so the offer is readable at a glance; an unselected highlighted plan keeps a stronger
// neutral edge so it still reads as the recommended one. `PaywallView` now uses this component
// instead of a private copy of it.

import SwiftUI

/// A single selectable subscription plan row for the paywall (docs/spec.md §21, §7.12). Reuses the
/// same "row with leading selection glyph, trailing value" visual language as `GoalRow`/
/// `LockStatusCard` so the paywall reads as part of the same design system, not a one-off screen.
public struct PaywallCard: View {
    private let title: String
    private let priceLine: String
    private let detailLine: String?
    private let badgeLabel: String?
    private let trialLabel: String?
    private let isHighlighted: Bool
    private let isSelected: Bool
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Caller-composed plan name, e.g. "Annual" / "Monthly".
    ///   - priceLine: Caller-composed, fully formatted price, e.g. "$39.99/yr".
    ///   - detailLine: Caller-composed secondary line, e.g. "$3.33/mo". Defaults to `nil`.
    ///   - badgeLabel: Caller-composed badge text, e.g. "Best value". `nil` shows no badge.
    ///     Defaults to `nil`.
    ///   - trialLabel: Caller-composed trial pill, e.g. "7 days free". Shown on the highlighted
    ///     layout only; a compact card folds its trial into `detailLine`. Defaults to `nil`.
    ///   - isHighlighted: Whether this is the emphasized plan (spec §21/§16 P5: "annual
    ///     highlighted") — gives it the larger *hero* layout and keeps a stronger edge even when it
    ///     is not the current selection. Defaults to `false`.
    ///   - isSelected: Whether this plan is the user's current selection — drives the leading
    ///     glyph and a stronger border/fill. Defaults to `false`.
    ///   - action: Tap handler (select this plan).
    public init(
        title: String,
        priceLine: String,
        detailLine: String? = nil,
        badgeLabel: String? = nil,
        trialLabel: String? = nil,
        isHighlighted: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.priceLine = priceLine
        self.detailLine = detailLine
        self.badgeLabel = badgeLabel
        self.trialLabel = trialLabel
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

    private var fill: Color {
        guard isSelected else { return Theme.Colors.surface }
        return isHighlighted ? Theme.Colors.surfaceHero : Theme.Colors.surface2
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: isHighlighted ? .top : .center, spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.muted)
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
                    if isHighlighted, let trialLabel {
                        trialPill(trialLabel)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }

                Spacer(minLength: Theme.Spacing.xs)

                NumeralText(priceLine, size: priceSize)
                    .fixedSize()
            }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .background(fill, in: shape)
            .overlay {
                if isSelected {
                    // Selected: a 2pt white stroke, drawn inside so selecting never shifts layout.
                    shape.strokeBorder(Theme.Colors.interactive, lineWidth: 2)
                } else if isHighlighted {
                    // The recommended plan keeps a stronger neutral edge even when not chosen.
                    shape.strokeBorder(Theme.Colors.hairlineStrong, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(Theme.Colors.edgeGradient(), lineWidth: Theme.Metrics.edgeWidth)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(Theme.Colors.onFill)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xxs / 2)
                .background(Theme.Colors.interactive, in: Capsule())
        }
    }

    private func trialPill(_ label: String) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "gift.fill")
                .font(Theme.Typography.icon(.xsmall))
                .accessibilityHidden(true)
            Text(label)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.interactiveWash, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
    }
}

#Preview("PaywallCard") {
    VStack(spacing: Theme.Spacing.sm) {
        PaywallCard(
            title: "Annual",
            priceLine: "$39.99/yr",
            detailLine: "$3.33/mo",
            badgeLabel: "Best value",
            trialLabel: "7 days free",
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
            detailLine: "$3.33/mo",
            badgeLabel: "Best value",
            trialLabel: "7 days free",
            isHighlighted: true,
            isSelected: false,
            action: {}
        )
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
