// GoalActionList.swift
// App / ZANO / Features / Today
//
// Today's and Lock's goal list: one inset-grouped card, one row per goal, each row with the one
// action that moves that goal forward right there (docs/design/premium-ui-plan.md, UX pass).
//
// Why rows with actions instead of a ring row + one "Log the rest on Fuel" button: the old screen
// made the most common action of the day (logging protein or water) cost a tab switch, a scroll and
// a tap, and it showed only the goals gating the lock. Now every goal is visible with its progress
// in words ("72 of 150g · 78g to go"), and logging is one tap in place, with a haptic and the ring
// filling where you're already looking. Actions that start something (a focus session, gym dwell
// tracking) are blue capsules; quick-logs wear the goal's own color (content color, not chrome);
// a done goal gets the accent check, the one earned mark in the row. Glyphs on the blue fills use
// `onAccent`. At accessibility text sizes a row stacks (ring and words, then the action) so titles
// and progress get two lines instead of truncating beside a capsule.

import SwiftUI
import Core

struct GoalActionItem: Identifiable, Equatable {
    enum Trailing: Equatable {
        /// A one-tap log in the goal's color ("+25g").
        case quickAdd(label: String, accessibilityLabel: String)
        /// Starts something (a focus session, gym tracking, a one-tap log). Blue capsule.
        case start(label: String)
        /// Read-only state ("Running", "12 min", "Verifies automatically").
        case status(String, isLive: Bool)
        case done
        case none
    }

    let id: UUID
    let title: String
    let icon: String
    let color: Color
    let progress: Double
    /// "72 of 150g", "Not yet", "Done".
    let primaryLine: String
    /// "78g to go".
    var secondaryLine: String? = nil
    var isRequired: Bool = false
    let trailing: Trailing
}

struct GoalActionList: View {
    let items: [GoalActionItem]
    /// Disables every action while one is in flight.
    var isBusy: Bool = false
    let onAction: (GoalActionItem) -> Void

    @State private var tapTick = 0

    init(items: [GoalActionItem], isBusy: Bool = false, onAction: @escaping (GoalActionItem) -> Void) {
        self.items = items
        self.isBusy = isBusy
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Colors.hairline)
                        .frame(height: Theme.Metrics.edgeWidth)
                        // Inset to the text column, iOS inset-grouped style: the divider starts
                        // after the ring, so the rings read as one column.
                        .padding(.leading, Theme.Spacing.md + GoalActionRow.ringSize + Theme.Spacing.sm)
                }
                GoalActionRow(item: item, isBusy: isBusy) {
                    tapTick += 1
                    onAction(item)
                }
            }
        }
        .zanoCard()
        .sensoryFeedback(.impact(weight: .medium), trigger: tapTick)
    }
}

struct GoalActionRow: View {
    static let ringSize: CGFloat = 46

    let item: GoalActionItem
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(item: GoalActionItem, isBusy: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isBusy = isBusy
        self.action = action
    }

    private var isDone: Bool { item.trailing == .done }

    /// Stacked at accessibility sizes; side by side otherwise.
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var textLineLimit: Int { isStacked ? 2 : 1 }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ring
                        words
                        Spacer(minLength: 0)
                    }
                    if item.trailing != .none {
                        trailing
                    }
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    ring
                    words
                    Spacer(minLength: Theme.Spacing.xs)
                    trailing
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: 68)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: item)
    }

    private var ring: some View {
        GoalRing(
            progress: item.progress,
            color: item.color,
            size: .custom(Self.ringSize),
            center: .icon(systemName: isDone ? "checkmark" : item.icon)
        )
        .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(textLineLimit)
            HStack(spacing: Theme.Spacing.xxs) {
                Text(item.primaryLine)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isDone ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let secondary = item.secondaryLine {
                    Text(Copy.today.goalLineSeparator)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                    Text(secondary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .lineLimit(textLineLimit)
            .minimumScaleFactor(0.85)
        }
        .fixedSize(horizontal: false, vertical: isStacked)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.trailing {
        case .quickAdd(let label, let spoken):
            Button(action: action) {
                Text(label)
                    .font(.system(.subheadline, weight: .bold).width(.condensed))
                    .foregroundStyle(item.color)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.wash(item.color), in: Capsule())
                    .overlay(Capsule().strokeBorder(item.color.opacity(0.35), lineWidth: 1))
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .disabled(isBusy)
            .accessibilityLabel(spoken)

        case .start(let label):
            Button(action: action) {
                Text(label)
                    .font(.system(.subheadline, weight: .bold).width(.condensed))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.interactive, in: Capsule())
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .disabled(isBusy)
            .accessibilityLabel(Copy.today.startActionSpoken(label: label, goal: item.title))

        case .status(let text, let isLive):
            HStack(spacing: Theme.Spacing.xxs) {
                if isLive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(item.color)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                }
                Text(text)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isLive ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(textLineLimit)
            }
            .fixedSize(horizontal: !isStacked, vertical: true)

        case .done:
            Image(systemName: "checkmark")
                .font(Theme.Typography.icon(.small, weight: .heavy))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.accent, in: Circle())
                .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 8)
                .accessibilityHidden(true)

        case .none:
            EmptyView()
        }
    }
}
