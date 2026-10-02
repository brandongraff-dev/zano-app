// GoalActionList.swift
// App / ZANO / Features / Today
//
// Today's and Lock's goal list. v2 (docs/design/visual-direction-v2.md §4): each goal is its own
// glass tile washed in the goal's colour, two per row (an odd last tile spans the row as a wide
// tile; one per row at accessibility text sizes), with the one action that moves that goal forward
// full width at the bottom. A tile that completes pops (ring burst) and glows in its colour. The
// "78g to go" second line is spoken, not shown, on tiles (fewer words); wide tiles still show it.
//
// Before v2: one inset-grouped card, one row per goal (docs/design/premium-ui-plan.md, UX pass).
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(items: [GoalActionItem], isBusy: Bool = false, onAction: @escaping (GoalActionItem) -> Void) {
        self.items = items
        self.isBusy = isBusy
        self.onAction = onAction
    }

    /// Items in rows of two; a row of one is a wide tile. One per row at accessibility sizes.
    private var rows: [[GoalActionItem]] {
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    ForEach(row) { item in
                        GoalTile(item: item, isWide: row.count == 1, isBusy: isBusy) {
                            tapTick += 1
                            onAction(item)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: tapTick)
    }
}

/// One goal as a glass tile. `isWide`: the horizontal layout for a row of one.
struct GoalTile: View {
    static let ringSize: CGFloat = 46

    let item: GoalActionItem
    let isWide: Bool
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumps when the goal flips to done: the ring's burst and the tile's pop.
    @State private var doneTick = 0

    init(item: GoalActionItem, isWide: Bool, isBusy: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isWide = isWide
        self.isBusy = isBusy
        self.action = action
    }

    private var isDone: Bool { item.trailing == .done }
    private var hasAction: Bool {
        switch item.trailing {
        case .quickAdd, .start: true
        default: false
        }
    }

    var body: some View {
        // Captured as a plain value: the keyframe content closure is `@Sendable`.
        let popScale: Double = reduceMotion ? 1 : 1.04
        return Group {
            if isWide {
                wideLayout
            } else {
                tileLayout
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zanoCard(
            radius: Theme.Radius.medium,
            tint: reduceTransparency ? nil : item.color,
            active: isDone && !reduceTransparency
        )
        .keyframeAnimator(initialValue: 1.0, trigger: doneTick) { tile, scale in
            tile.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(popScale, duration: 0.16, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: item)
        .onChange(of: isDone) { wasDone, nowDone in
            if !wasDone && nowDone { doneTick += 1 }
        }
    }

    // MARK: Layouts

    private var tileLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                ring
                Spacer(minLength: Theme.Spacing.xs)
                if isDone { doneBadge }
            }
            words(showsSecondary: false)
            Spacer(minLength: 0)
            if hasAction || !isDone {
                trailing(fullWidth: true)
            }
        }
    }

    private var wideLayout: some View {
        HStack(spacing: Theme.Spacing.md) {
            ring
            words(showsSecondary: true)
            Spacer(minLength: Theme.Spacing.xs)
            if isDone {
                doneBadge
            } else {
                trailing(fullWidth: false)
            }
        }
    }

    // MARK: Pieces

    private var ring: some View {
        GoalRing(
            progress: item.progress,
            color: item.color,
            size: .custom(Self.ringSize),
            center: .icon(systemName: isDone ? "checkmark" : item.icon)
        )
        .zanoChargeBurst(trigger: doneTick, color: item.color)
        .accessibilityHidden(true)
    }

    private func words(showsSecondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.primaryLine)
                .font(Theme.Typography.label)
                .foregroundStyle(isDone ? item.color : Theme.Colors.textSecondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.85)
            if showsSecondary, let secondary = item.secondaryLine {
                Text(secondary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenWords)
    }

    /// Title, progress and (always, even when not shown) the "to go" line.
    private var spokenWords: String {
        [item.title, item.primaryLine, item.secondaryLine].compactMap { $0 }.joined(separator: ", ")
    }

    private var doneBadge: some View {
        Image(systemName: "checkmark")
            .font(Theme.Typography.icon(.small, weight: .heavy))
            .foregroundStyle(Theme.Colors.onFill)
            .frame(width: 28, height: 28)
            .background(item.color, in: Circle())
            .shadow(color: item.color.opacity(0.55), radius: 8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func trailing(fullWidth: Bool) -> some View {
        switch item.trailing {
        case .quickAdd(let label, let spoken):
            Button(action: action) {
                Text(label)
                    .font(Theme.Typography.label.weight(.bold))
                    .foregroundStyle(item.color)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
                    .background(Theme.Colors.wash(item.color), in: Capsule())
                    .overlay(Capsule().strokeBorder(item.color.opacity(0.45), lineWidth: 1))
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .disabled(isBusy)
            .accessibilityLabel(spoken)

        case .start(let label):
            Button(action: action) {
                Text(label)
                    .font(Theme.Typography.label.weight(.bold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
                    // `accentFill`, not `accent`: the white label needs the deeper blue for AA.
                    .background(Theme.Colors.accentFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Colors.glassEdge, lineWidth: 1))
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .disabled(isBusy)
            .accessibilityLabel(Copy.today.startActionSpoken(label: label, goal: item.title))

        case .status(let text, let isLive):
            HStack(spacing: Theme.Spacing.xxs + 2) {
                if isLive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(item.color)
                        .shadow(color: item.color.opacity(0.7), radius: 4)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isLive ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .done, .none:
            EmptyView()
        }
    }
}
