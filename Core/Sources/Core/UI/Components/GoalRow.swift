// GoalRow.swift
// Core / UI / Components
//
// A single-goal list row, per docs/spec.md §15's core component list — used anywhere goals are
// listed rather than ringed (the Lock screen's "goals required to unlock" list, Progress's goal
// list, a lock-set editor). All text is caller-composed; see GoalRing.swift's header note on
// copy discipline, which applies here too.
//
// Design-quality pass (docs/design/{better-ui,better-layout,typography-color,composition-audit}):
//
//   * The whole card is the target. Padding and the card surface used to sit *outside* the `Button`,
//     so the hit area was the inner row only (a dead 12-16pt ring around it) and the press effect
//     scaled the label inside a static card (HIT-04). Both now live inside the button label, and
//     the press is `PressableStyle` — the private copy this file kept is gone.
//   * The leading slot is a fixed 44pt whether it holds a progress ring or a 32pt icon badge, so the
//     title's left edge no longer jumps 12pt between rows of one list (ALN-01, layout 4.6), and every
//     row is the same height (60pt) instead of 56 or 68.
//   * The trailing glyph is a choice, not a given. `GoalRowStatus` is a *state* (empty circle =
//     "not done"), which is wrong for rows that are actions ("tap to log 25g") or plans (paywall,
//     plan reveal). `trailing:` adds `.chevron`, `.add` and `.hidden` (layout 3.3, ICO-04, S-7).
//   * "In progress" is not a caution. It was `warning` (amber), which the palette reserves for
//     "needs attention soon"; it is now a half-filled circle in `textSecondary` (typography-color C9).
//   * The decisive text never clips. Title and detail were `lineLimit(1)`, so "Your usual chicken
//     bowl (48g)?" lost its grams first (layout 8.3). Both wrap to two lines.
//   * Numbers lead in a numeric detail ("72/150g": a bold "72", a quiet "/150g"); prose details
//     ("Verified at Equinox Downtown") stay plain caption text.
//   * A complete row is earned: a faint accent wash on the card, a check, and a struck-through,
//     receded title.

import SwiftUI

/// Where a goal stands for the row it's rendered in. Deliberately coarser than `GoalEventKind`
/// (`Core/Sources/Core/Models/GoalEvent.swift`) — this is a display-layer status the caller derives
/// from the day's events/plan, not a 1:1 mirror of the event log.
public enum GoalRowStatus: Equatable, Sendable {
    /// Not started yet today.
    case pending
    /// Logged/partially done but not yet verified complete.
    case inProgress
    /// Verified complete for today (`GoalEventKind.complete` fired).
    case complete
}

/// What sits at a `GoalRow`'s trailing edge.
public enum GoalRowTrailing: Equatable, Sendable {
    /// The goal's status glyph — empty circle, half circle or check, driven by `GoalRowStatus`.
    /// The default, and right for a row that *reports* progress (the Lock screen's required goals).
    case status
    /// A forward chevron: the row navigates somewhere.
    case chevron
    /// A plus: tapping the row logs or adds something (a gap-planner option, Quick Repeat). Use this
    /// instead of `.status` so an action does not read as an unchecked to-do.
    case add
    /// Nothing: an inert row (a plan preview on the paywall or plan reveal).
    case hidden
}

/// A row summarizing one goal: icon, title, optional detail, and completion status. Reuses
/// `GoalRing` for the leading indicator when `progress` is supplied, matching the ring visual
/// language used everywhere else in the design system.
public struct GoalRow: View {
    /// Fully-composed title, e.g. `"Leg day"`, `"Gallon a day"` (from `Goal.title`/`Copy`).
    private let title: String
    /// Fully-composed detail line, e.g. `"72/150g"`, `"Verified at Equinox Downtown"`. Optional.
    private let detail: String?
    private let icon: String
    private let color: Color
    private let status: GoalRowStatus
    /// Completion fraction for the leading ring, `0...1`. When `nil`, a plain icon badge is shown
    /// instead of a ring (e.g. for a goal with no partial-progress concept, like a single one-tap
    /// Tier C goal).
    private let progress: Double?
    private let trailing: GoalRowTrailing
    private let action: (() -> Void)?
    /// Optional caller-composed status word/phrase (e.g. "Complete", "In progress") appended to
    /// this row's combined VoiceOver announcement. `GoalRow` carries no `Copy` import of its own
    /// (see file header) — like every other string here, this is caller-composed, so pass
    /// `Copy.*` text from the call site rather than hardcoding a status word in this file. `nil`
    /// (the default) omits it, so the announcement is still title + detail only rather than
    /// falling back to a hardcoded English word. See `docs/design/ui-stress-test-findings.md` §2.2.
    private let statusAccessibilityLabel: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Caller-composed goal title.
    ///   - detail: Caller-composed detail line. Defaults to `nil`.
    ///   - icon: SF Symbol name for the goal (identifier, not copy).
    ///   - color: Row/ring tint — typically `Theme.Colors.Ring.color(for:)`. Defaults to
    ///     `Theme.Colors.accent`.
    ///   - status: Drives the trailing status glyph (and the row's earned treatment). Defaults to
    ///     `.pending`.
    ///   - progress: Optional completion fraction for a leading `GoalRing`. Defaults to `nil`.
    ///   - statusAccessibilityLabel: Optional caller-composed status word for VoiceOver (see
    ///     property doc above). Defaults to `nil`.
    ///   - trailing: What sits at the trailing edge. Defaults to `.status`.
    ///   - action: Optional tap handler (e.g. navigate to verify this goal). Defaults to `nil`.
    public init(
        title: String,
        detail: String? = nil,
        icon: String,
        color: Color = Theme.Colors.accent,
        status: GoalRowStatus = .pending,
        progress: Double? = nil,
        statusAccessibilityLabel: String? = nil,
        trailing: GoalRowTrailing = .status,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.color = color
        self.status = status
        self.progress = progress
        self.statusAccessibilityLabel = statusAccessibilityLabel
        self.trailing = trailing
        self.action = action
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
        // `trigger: status == .complete` fires on *any* change of that `Bool`, not only when it
        // becomes `true` — a row that flips back from `.complete` (a day rolling over on a
        // recurring goal, a logged event retracted/edited) would replay the same "you did it!"
        // haptic on the way back down. Gated to the forward transition only, matching
        // `TodayView.swift`'s already-correct identical-shape fix for `isLocked`. See
        // `docs/design/ui-stress-test-findings.md` §3.8.
        .sensoryFeedback(.success, trigger: status) { oldValue, newValue in
            oldValue != .complete && newValue == .complete
        }
    }

    /// The row inside its card. Padding and surface are part of the label so a tappable row presses
    /// (and is hit) as one card.
    private var card: some View {
        rowBody
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(
                radius: Theme.Radius.small,
                tint: status == .complete ? Theme.Colors.accent : nil
            )
    }

    private var rowBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            leadingIndicator

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(status == .complete ? Theme.Colors.textSecondary : Theme.Colors.text)
                    .strikethrough(status == .complete, pattern: .solid, color: Theme.Colors.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    detailView(detail)
                }
            }

            Spacer(minLength: 0)

            trailingIndicator
        }
        .frame(minHeight: Theme.Metrics.minTapTarget)
        .contentShape(Rectangle())
        // Without this, VoiceOver swipes through the leading ring/icon, title, detail, and status
        // glyph (whose SF Symbol name carries no semantic "complete/in progress/pending" meaning
        // on its own) as four disconnected stops. One explicit, ordered announcement replaces all
        // of that — see `docs/design/ui-stress-test-findings.md` §2.2.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel)
    }

    /// A numeric detail leads with its number; anything else is plain caption text.
    @ViewBuilder
    private func detailView(_ detail: String) -> some View {
        if NumeralText.hasNumeral(detail) {
            NumeralText(detail, size: .small, color: Theme.Colors.text, unitColor: Theme.Colors.muted)
        } else {
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Title, then detail (or the ring's own progress fraction when there's no separate detail
    /// text to carry it), then the optional caller-supplied status word — see
    /// `statusAccessibilityLabel`'s doc comment.
    private var combinedAccessibilityLabel: String {
        var parts = [title]
        if let detail {
            parts.append(detail)
        } else if let progress {
            let clamped = min(1, max(0, progress))
            parts.append("\(Int((clamped * 100).rounded()))%")
        }
        if let statusAccessibilityLabel {
            parts.append(statusAccessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }

    /// A fixed 44pt slot: the 44pt ring fills it, the 32pt badge sits centred in it. Either way the
    /// title starts at the same x.
    private var leadingIndicator: some View {
        ZStack {
            if let progress {
                GoalRing(progress: progress, color: color, size: .small, center: .icon(systemName: icon))
            } else {
                IconBadge(systemName: icon, tint: color, size: .small)
            }
        }
        .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch trailing {
        case .status:
            statusIndicator
        case .chevron:
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
        case .add:
            Image(systemName: "plus.circle.fill")
                .font(Theme.Typography.icon(.large))
                .foregroundStyle(Theme.Colors.textSecondary)
        case .hidden:
            EmptyView()
        }
    }

    /// One `Image` whose symbol and tint follow `status`, not three `Image`s in a `switch`: a
    /// `.symbolEffect(.replace)` content transition only runs when the *same* image view changes its
    /// symbol. Three branches of a `switch` are three different view identities, so the morph below
    /// could never fire and the glyph just popped.
    private var statusIndicator: some View {
        Image(systemName: statusSymbol)
            .font(Theme.Typography.icon(.large, weight: status == .pending ? .regular : .semibold))
            .foregroundStyle(statusTint)
            // SwiftUI doesn't interpolate between two different SF Symbol names on its own — without
            // this, the icon just replaces itself instantly at the exact spot the eye is drawn to
            // (docs/design/apple-design-review.md §4). No bounce: an icon swap is one object changing
            // state, not a spring (`Theme.Motion.iconSwap`).
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : Theme.Motion.iconSwap, value: status)
    }

    private var statusSymbol: String {
        switch status {
        case .complete: "checkmark.circle.fill"
        // Half-filled: "partway", in a neutral tone. Amber (`warning`) means "needs attention
        // soon" everywhere else in the app, which in-progress is not.
        case .inProgress: "circle.lefthalf.filled"
        case .pending: "circle"
        }
    }

    private var statusTint: Color {
        switch status {
        case .complete: Theme.Colors.accent
        case .inProgress: Theme.Colors.textSecondary
        case .pending: Theme.Colors.muted
        }
    }
}

#Preview("GoalRow") {
    VStack(spacing: Theme.Spacing.xs) {
        GoalRow(
            title: "Leg day",
            detail: "Verified at Equinox Downtown",
            icon: "dumbbell.fill",
            color: Theme.Colors.Ring.workout,
            status: .complete,
            progress: 1.0
        )
        GoalRow(
            title: "Protein",
            detail: "72/150g",
            icon: "fork.knife",
            color: Theme.Colors.Ring.protein,
            status: .inProgress,
            progress: 0.48,
            action: {}
        )
        GoalRow(
            title: "Cold shower",
            icon: "snowflake",
            color: Theme.Colors.Ring.coldShowerSauna,
            status: .pending
        )
        GoalRow(
            title: "Your usual chicken bowl (48g)?",
            icon: "fork.knife",
            color: Theme.Colors.Ring.protein,
            trailing: .add,
            action: {}
        )
        GoalRow(
            title: "Workout",
            detail: "Starts at 6:30 AM",
            icon: "figure.strengthtraining.traditional",
            trailing: .hidden
        )
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
