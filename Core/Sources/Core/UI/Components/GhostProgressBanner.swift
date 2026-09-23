// GhostProgressBanner.swift
// Core / UI / Components
//
// Renders `GhostMode.GhostComparison` (Core/Sources/Core/Retention/GhostMode.swift), per
// docs/spec.md §5.4 ★ Ghost Mode: "Race your past self. The app shows a 'ghost' of your best
// week: 'Ghost You had already trained twice by Tuesday.' Zero social pressure, pure
// self-competition."
//
// Deliberately self-contained: the only required parameter is a `GhostMode.GhostComparison`
// value, produced by calling `await GhostMode.shared.ghostComparison(for: .now)`. That's enough
// to drop this straight into a screen later (Today, Progress, wherever) without this task also
// having to edit that screen's file — this task specifically does not touch
// `App/ZANO/Features/Today` to wire it in; see this task's `knownIssues` for that exact
// integration point.
//
// Copy discipline (CLAUDE.md: "no hardcoded user-facing strings in views"): the one piece of
// prose this view renders, `comparison.headline`, is composed by `GhostMode`, not here — see that
// file's header comment for why it (not `Core/Sources/Core/Copy`) owns that composition in this
// task's scope. Everything else this view draws — the you-vs-ghost scoreboard — is rendered as
// bare numerals plus a full-strength vs. faded runner glyph, never spelled-out words, the same
// "numeric data, not copy" precedent `StreakPill` documents at its own declaration. The only
// English word this file could possibly introduce is `title`, and that's an optional value the
// *caller* supplies (like `RecapCard.rankLabel`/`LockStatusCard.detailLine`), never a literal baked
// in here.
//
// Design-quality pass (docs/design/{better-ui,composition-audit}-findings):
//
//   * The whole card is the target and presses as one (padding and surface moved inside the
//     `Button`, `PressableStyle` replaces the private copy of the same style this file carried).
//   * The scoreboard says what it is: the *same* runner glyph at full strength for you and faded for
//     the ghost, instead of a filled vs outline person that read as "logged in / logged out"
//     (ICO-08). It is what the feature is — racing a past self.
//   * The badge is an `IconBadge` (on-hue wash, 44pt), the eyebrow is the shared eyebrow style, and
//     the scores are `NumeralText` (scales with Dynamic Type, odometer roll).

import SwiftUI

/// A Theme-consistent banner comparing today's progress against the user's "ghost" — their best
/// historical week, at the same day-of-week point (docs/spec.md §5.4).
public struct GhostProgressBanner: View {
    private let comparison: GhostMode.GhostComparison
    /// Optional caller-composed eyebrow/section label (e.g. `"Ghost Mode"`). `nil` omits the row
    /// entirely — see this file's header comment on why this view has no copy of its own to fall
    /// back to.
    private let title: String?
    /// Optional tap handler (e.g. navigate to a future Ghost Mode detail/history screen). `nil`
    /// leaves the banner non-interactive, matching `LockStatusCard`/`GoalRow`'s own convention.
    private let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - comparison: The comparison to render, from `GhostMode.shared.ghostComparison(for:)`.
    ///   - title: Optional caller-composed eyebrow label. Defaults to `nil`.
    ///   - action: Optional tap handler. Defaults to `nil` (non-interactive).
    public init(
        comparison: GhostMode.GhostComparison,
        title: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.comparison = comparison
        self.title = title
        self.action = action
    }

    /// Tint reflects standing vs. the ghost: `accent` (the design system's one earned/positive
    /// color, spec §15 "ONE accent only") when ahead, `muted` when tied or when there's no ghost
    /// week yet, `warning` — never `danger` — when behind. Spec §8 rule 9 ("no shame") is about
    /// missed goals, not this feature specifically, but the same spirit applies: trailing your own
    /// ghost is a nudge to react to, not a failure state, so this never reaches for the red/danger
    /// token.
    private var tint: Color {
        guard comparison.hasGhostWeek else { return Theme.Colors.muted }
        if comparison.isAheadOfGhost { return Theme.Colors.accent }
        if comparison.isTiedWithGhost { return Theme.Colors.muted }
        return Theme.Colors.warning
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(PressableStyle())
            } else {
                card
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: comparison)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(composedAccessibilityLabel)
        .accessibilityAddTraits(action != nil ? .isButton : [])
    }

    private var card: some View {
        rowBody
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // `flag.checkered` — a race/finish-line glyph for "race your past self" (spec §5.4's
            // own framing). A wrong name degrades to a blank glyph in `Image(systemName:)` rather
            // than crashing, so the worst case is a missing icon, not a broken build/runtime.
            IconBadge(systemName: "flag.checkered", tint: tint, size: .medium)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if let title {
                    Text(title)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                }
                Text(comparison.headline)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if comparison.hasGhostWeek {
                scoreboard
            }

            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(minHeight: Theme.Metrics.iconBadgeMedium)
            }
        }
        .contentShape(Rectangle())
    }

    /// Bare numerals distinguished by a full-strength ("you") vs. faded ("ghost") runner — no
    /// spelled-out words, per this file's copy-discipline note above.
    private var scoreboard: some View {
        HStack(spacing: Theme.Spacing.sm) {
            scoreItem(value: comparison.currentCompletedCount, tint: Theme.Colors.text, glyphOpacity: 1)
            Rectangle()
                .fill(Theme.Colors.hairline)
                .frame(width: Theme.Metrics.edgeWidth, height: Theme.Spacing.lg)
            scoreItem(value: comparison.ghostCompletedCount, tint: Theme.Colors.muted, glyphOpacity: 0.45)
        }
    }

    private func scoreItem(value: Int, tint: Color, glyphOpacity: Double) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "figure.run")
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(tint)
                .opacity(glyphOpacity)
            // A plain `Text("\(value)")` swap pops instantly on its own; `NumeralText`'s
            // `.numericText` is a built-in "odometer" roll that rides the same
            // `.animation(value: comparison)` applied above (docs/design/apple-design-review.md §4).
            NumeralText("\(value)", size: .small, color: tint)
        }
    }

    /// One spoken label combining the optional eyebrow with the full comparison sentence, rather
    /// than separately labeling the scoreboard's bare numerals (which have no accessible words of
    /// their own to attach) — same "collapse to one label" reasoning `StreakPill`/`GoalRing`
    /// document at their own declarations.
    private var composedAccessibilityLabel: Text {
        if let title {
            return Text("\(title). \(comparison.headline)")
        }
        return Text(comparison.headline)
    }
}
