// GoalRow.swift
// Core / UI / Components
//
// A single-goal list row, per docs/spec.md §15's core component list — used anywhere goals are
// listed rather than ringed (the Lock screen's "goals required to unlock" list, Progress's goal
// list, a lock-set editor). All text is caller-composed; see GoalRing.swift's header note on
// copy discipline, which applies here too.

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
    /// Completion fraction for the leading ring, `0...1`. When `nil`, a plain icon circle is
    /// shown instead of a ring (e.g. for a goal with no partial-progress concept, like a single
    /// one-tap Tier C goal).
    private let progress: Double?
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
    ///   - status: Drives the trailing indicator. Defaults to `.pending`.
    ///   - progress: Optional completion fraction for a leading `GoalRing`. Defaults to `nil`.
    ///   - statusAccessibilityLabel: Optional caller-composed status word for VoiceOver (see
    ///     property doc above). Defaults to `nil`.
    ///   - action: Optional tap handler (e.g. navigate to verify this goal). Defaults to `nil`.
    public init(
        title: String,
        detail: String? = nil,
        icon: String,
        color: Color = Theme.Colors.accent,
        status: GoalRowStatus = .pending,
        progress: Double? = nil,
        statusAccessibilityLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.color = color
        self.status = status
        self.progress = progress
        self.statusAccessibilityLabel = statusAccessibilityLabel
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { rowBody }
                    .buttonStyle(RowPressStyle())
            } else {
                rowBody
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .sensoryFeedback(.success, trigger: status == .complete)
    }

    private var rowBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            leadingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .strikethrough(status == .complete, pattern: .solid, color: Theme.Colors.muted)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            statusIndicator
        }
        .contentShape(Rectangle())
        // Without this, VoiceOver swipes through the leading ring/icon, title, detail, and status
        // glyph (whose SF Symbol name carries no semantic "complete/in progress/pending" meaning
        // on its own) as four disconnected stops. One explicit, ordered announcement replaces all
        // of that — see `docs/design/ui-stress-test-findings.md` §2.2.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel)
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

    @ViewBuilder
    private var leadingIndicator: some View {
        if let progress {
            GoalRing(progress: progress, color: color, size: .small, center: .icon(systemName: icon))
        } else {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Group {
            switch status {
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            case .inProgress:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warning)
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        // SwiftUI doesn't interpolate between two different SF Symbol names on its own — without
        // this, the icon just replaces itself instantly at the exact spot the eye is drawn to
        // (docs/design/apple-design-review.md §4).
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: status)
    }
}

/// Gives `GoalRow`'s tappable variant visible touch-down feedback — `.buttonStyle(.plain)` alone
/// suppresses SwiftUI's default press state almost entirely, a direct miss against HIG's
/// "Response" principle (react on pointer-down, not on release). Duplicated (not shared) in
/// `GhostProgressBanner.swift`, the only other row-style tappable component in this wave's safe
/// set — with just two call sites, CLAUDE.md's "three similar call sites beat a premature
/// protocol" argues against carving out a new shared file for this alone
/// (docs/design/apple-design-review.md §6.3).
private struct RowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
