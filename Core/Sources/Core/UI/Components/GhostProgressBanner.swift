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
// bare numerals plus filled/outline person glyphs, never spelled-out words, the same "numeric
// data, not copy" precedent `StreakPill` documents at its own declaration. The only English word
// this file could possibly introduce is `title`, and that's an optional value the *caller*
// supplies (like `RecapCard.rankLabel`/`LockStatusCard.detailLine`), never a literal baked in here.

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
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .animation(Theme.Motion.springStandard, value: comparison)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(composedAccessibilityLabel)
    }

    private var content: some View {
        Group {
            if let action {
                Button(action: action) { rowBody }
                    .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                        .textCase(.uppercase)
                }
                Text(comparison.headline)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if comparison.hasGhostWeek {
                scoreboard
            }

            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .contentShape(Rectangle())
    }

    /// `"flag.checkered"` — a race/finish-line glyph for "race your past self" (spec §5.4's own
    /// framing). Assumption flagged in `knownIssues`: there's no Mac here to render-check this SF
    /// Symbol name exists on every targeted iOS version; a wrong name degrades to a blank glyph in
    /// `Image(systemName:)` rather than crashing, so the worst case is a missing icon, not a
    /// broken build/runtime.
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            Image(systemName: "flag.checkered")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
    }

    /// Bare numerals distinguished by a filled ("you") vs. outline ("ghost") person glyph — no
    /// spelled-out words, per this file's copy-discipline note above.
    private var scoreboard: some View {
        HStack(spacing: Theme.Spacing.sm) {
            scoreItem(icon: "person.fill", value: comparison.currentCompletedCount, tint: Theme.Colors.text)
            Rectangle()
                .fill(Theme.Colors.hairline)
                .frame(width: 1, height: 24)
            scoreItem(icon: "person", value: comparison.ghostCompletedCount, tint: Theme.Colors.muted)
        }
    }

    private func scoreItem(icon: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(tint)
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
