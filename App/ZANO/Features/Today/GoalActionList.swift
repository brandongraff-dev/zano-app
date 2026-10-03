// GoalActionList.swift
// App / ZANO / Features / Today
//
// Today's and Lock's goal list. v2 (docs/design/visual-direction-v2.md §4): each goal is its own
// glass tile washed in the goal's colour, two per row (an odd last tile spans the row as a wide
// tile; one per row at accessibility text sizes), with the one action that moves that goal forward
// full width at the bottom. A tile that completes pops and gets a solid rim in its colour (pass 3). The
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
///
/// Pass 2 (playful, docs/design/visual-direction-v2.md "Pass 2: playful"): the tile is the goal's
/// colour (`zanoGoalTile`: flat-tinted glass with a flat fill that rises with the day's progress;
/// pass 3 removed the juice gradient), the goal's glyph is a chunky sticker, the progress line rolls, and a tile with an action is
/// itself the button: the whole tile squishes on touch (`PressableStyle`), the sticker bounces on every
/// log, and completing it pops the tile and flips the sticker to a filled check (pass 3: the win's
/// one burst is the hero star's, not the tile's). Read-only tiles (Lock) are compact and not buttons.
struct GoalTile: View {
    let item: GoalActionItem
    let isWide: Bool
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumps when the goal flips to done: the burst, the pop and the sticker bounce.
    @State private var doneTick = 0
    /// Bumps when progress grows (a log landed): the sticker bounces.
    @State private var progressTick = 0

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

    /// Read-only tiles (Lock's, a status, nothing to do) don't need the board height.
    private var minHeight: CGFloat? {
        guard !isWide else { return nil }
        switch item.trailing {
        case .quickAdd, .start, .status: return Theme.Metrics.goalTileMinHeight
        case .done, .none: return nil
        }
    }

    var body: some View {
        if hasAction {
            Button(action: action) {
                face
            }
            .buttonStyle(.pressable(scale: 0.95))
            .disabled(isBusy)
            .accessibilityLabel(actionSpoken)
            .accessibilityValue(spokenWords)
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenWordsWithStatus)
        }
    }

    // MARK: Surface

    private var face: some View {
        // Captured as a plain value: the keyframe content closure is `@Sendable`.
        let popScale: Double = reduceMotion ? 1 : 1.06
        return Group {
            if isWide {
                wideLayout
            } else {
                tileLayout
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .zanoGoalTile(color: item.color, progress: item.progress, isDone: isDone)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .keyframeAnimator(initialValue: 1.0, trigger: doneTick) { tile, scale in
            tile.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(popScale, duration: 0.16, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: item)
        .onChange(of: isDone) { wasDone, nowDone in
            if !wasDone && nowDone { doneTick += 1 }
        }
        .onChange(of: item.progress) { old, new in
            if new > old { progressTick += 1 }
        }
    }

    // MARK: Layouts

    private var tileLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                sticker
                Spacer(minLength: Theme.Spacing.xs)
                if isDone { doneSparkle }
            }
            words(showsSecondary: false)
            Spacer(minLength: 0)
            affordance(fullWidth: true)
        }
    }

    private var wideLayout: some View {
        HStack(spacing: Theme.Spacing.md) {
            sticker
            words(showsSecondary: true)
            Spacer(minLength: Theme.Spacing.xs)
            if isDone {
                doneSparkle
            } else {
                affordance(fullWidth: false)
            }
        }
    }

    // MARK: Pieces

    /// The goal's glyph as a chunky sticker; a filled check once done. Tilted a little while open
    /// (decoration: it carries no words), straight once done.
    private var sticker: some View {
        ZanoSticker(
            systemImage: isDone ? "checkmark" : item.icon,
            color: item.color,
            style: isDone ? .filled : .tinted,
            size: .large,
            tilt: isDone ? 0 : -6,
            bounceTrigger: progressTick + doneTick
        )
        // Pass 3 (restraint): no burst here; the hero star's burst is the one burst per win.
        .accessibilityHidden(true)
    }

    /// A small sparkle sticker in the corner of a done tile.
    private var doneSparkle: some View {
        ZanoSticker(systemImage: "sparkles", color: item.color, size: .small, tilt: 12, bounceTrigger: doneTick)
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
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(isDone ? Theme.Colors.text : Theme.Colors.textSecondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
            if showsSecondary, let secondary = item.secondaryLine {
                Text(secondary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
        .accessibilityHidden(true)
    }

    /// Title, progress and (always, even when not shown) the "to go" line.
    private var spokenWords: String {
        [item.title, item.primaryLine, item.secondaryLine].compactMap { $0 }.joined(separator: ", ")
    }

    private var spokenWordsWithStatus: String {
        if case .status(let text, _) = item.trailing { return [spokenWords, text].joined(separator: ", ") }
        return spokenWords
    }

    /// What the tile-as-button does, for VoiceOver ("Add 25 grams of protein", "Start Focus").
    private var actionSpoken: String {
        switch item.trailing {
        case .quickAdd(_, let spoken): spoken
        case .start(let label): Copy.today.startActionSpoken(label: label, goal: item.title)
        case .status, .done, .none: item.title
        }
    }

    /// The tile's action, drawn as a chunky capsule (the whole tile is the button): a quick-log in the
    /// goal's own colour with an ink label, a start in ZANO Blue with a white label.
    @ViewBuilder
    private func affordance(fullWidth: Bool) -> some View {
        switch item.trailing {
        case .quickAdd(let label, _):
            chunkyCapsule(label, systemImage: "plus", fill: item.color, labelColor: Theme.Colors.onFill, fullWidth: fullWidth)
        case .start(let label):
            // `accentFill`, not `accent`: the white label needs the deeper blue for AA.
            chunkyCapsule(label, systemImage: "play.fill", fill: Theme.Colors.accentFill, labelColor: Theme.Colors.onAccent, fullWidth: fullWidth)
        case .status(let text, let isLive):
            HStack(spacing: Theme.Spacing.xxs + 2) {
                if isLive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(item.color)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isLive ? Theme.Colors.text : Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done, .none:
            EmptyView()
        }
    }

    private func chunkyCapsule(_ label: String, systemImage: String, fill: Color, labelColor: Color, fullWidth: Bool) -> some View {
        let shape = Capsule(style: .continuous)
        // The label already says "+25g"; the glyph only leads labels that don't start with a sign.
        let showsGlyph = !(label.hasPrefix("+") || label.hasPrefix("-"))
        return HStack(spacing: Theme.Spacing.xxs + 1) {
            if showsGlyph {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.xsmall, weight: .heavy))
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(Theme.Typography.label.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Theme.Metrics.minTapTarget)
        .background {
            // Pass 3 (restraint): a solid fill, no sheen, no coloured glow.
            shape.fill(fill)
        }
        .opacity(isBusy ? 0.6 : 1)
    }
}
