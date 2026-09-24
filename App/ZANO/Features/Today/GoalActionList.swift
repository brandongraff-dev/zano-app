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
// tracking) are white capsules; quick-logs wear the goal's own color (content color, not chrome);
// a done goal gets the accent check, the one earned mark in the row.

import SwiftUI
import Core

struct GoalActionItem: Identifiable, Equatable {
    enum Trailing: Equatable {
        /// A one-tap log in the goal's color ("+25g").
        case quickAdd(label: String, accessibilityLabel: String)
        /// Starts something (a focus session, gym tracking). White capsule.
        case start(label: String)
        /// Read-only state ("Running", "12 min", "Auto at gym").
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

    init(item: GoalActionItem, isBusy: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isBusy = isBusy
        self.action = action
    }

    private var isDone: Bool { item.trailing == .done }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            GoalRing(
                progress: item.progress,
                color: item.color,
                size: .custom(Self.ringSize),
                center: .icon(systemName: isDone ? "checkmark" : item.icon)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(item.primaryLine)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(isDone ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    if let secondary = item.secondaryLine {
                        Text("·")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                        Text(secondary)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: Theme.Spacing.xs)

            trailing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: 68)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: item)
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
                    .foregroundStyle(Theme.Colors.onFill)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.interactive, in: Capsule())
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .disabled(isBusy)
            .accessibilityLabel("\(label) \(item.title)")

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
                    .lineLimit(1)
            }
            .fixedSize()

        case .done:
            Image(systemName: "checkmark")
                .font(Theme.Typography.icon(.small, weight: .heavy))
                .foregroundStyle(Theme.Colors.onFill)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.accent, in: Circle())
                .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 8)
                .accessibilityHidden(true)

        case .none:
            EmptyView()
        }
    }
}
