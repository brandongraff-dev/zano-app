// RingCluster.swift
// Core / UI / Components
//
// Lays out several `GoalRing`s together, per docs/spec.md §15's core component list and the P1
// mockup in §16 ("three progress rings labeled Workout, Protein (72/150g), Focus (25/50 min)").
// All text is caller-composed (see GoalRing.swift's header note on copy discipline).
//
// Design-quality pass (docs/design/{competitive-research,better-layout-findings,composition-audit}.md):
//
//   * The row FITS. Today rendered three `.large` rings (148pt each) in a horizontal scroller:
//     3×148 + 2×24 + 8 = 500pt inside a 361pt column, so on every iPhone the third ring (Focus)
//     was off-screen behind a hidden-indicator scroll — the product's face, clipped. `.row` is now
//     equal columns, with each ring shrinking to `min(size, column width)` (about 112pt for three
//     rings on a 393pt phone), and only scrolls for five or more items, where a scroller is the
//     honest answer.
//   * The number is in the ring. The value ("72" over "/150g") sits in the ring's center, the
//     goal's glyph moves to the label row beside its title, and no 13pt muted caption is left
//     carrying the most important number on the screen. Values that are not "value/target unit"
//     ("Done", "Not set") stay a caption below and keep the glyph in the ring, exactly as before.
//   * An unconfigured goal is an invitation, not a bug: `isPlaceholder` draws a dashed outline
//     with a plus.
//   * Rings are always identified by glyph or label as well as hue — never by color alone.

import SwiftUI

/// One ring's worth of display data for a `RingCluster`. A plain value type (not tied to `Goal`
/// or any SwiftData model) so this component stays usable anywhere a screen wants to show a set
/// of rings — Today's goal rings, a Recap's weekly goal-completion rings, a widget preview, etc.
public struct RingClusterItem: Identifiable, Equatable, Sendable {
    /// Cell identity. **Pass a stable id** (the goal's own id) for any cluster that re-renders: the
    /// default is a fresh `UUID()` per init, so every re-render makes each cell a brand-new view —
    /// its ring never animates from the old value, and `.onChange` completion pulses never fire.
    public let id: UUID
    /// Fully-composed label shown under the ring (e.g. `"Workout"`, `"Protein"`).
    public let title: String
    /// Completion fraction, `0...1` (unclamped values are clamped by the underlying `GoalRing`).
    public let progress: Double
    /// Ring tint — typically `Theme.Colors.Ring.color(for:)`.
    public let color: Color
    /// Fully-composed value string (e.g. `"72/150g"`, `"25/50 min"`). When it has the form
    /// "value/target unit" the cluster shows the value as the ring's center numeral with the
    /// "/target unit" beneath it (see `GoalRingCenter.text`); any other string ("Done", "Not
    /// set") is shown as a caption under the title. Optional — omit for a bare ring + title.
    public let valueText: String?
    /// SF Symbol identifying the goal. Shown in the ring's center when there is no numeric value
    /// to put there, otherwise in the label row beside `title`. When `nil`, no glyph is shown.
    public let centerIcon: String?
    /// Explicit center value (overrides parsing `valueText`), e.g. `"72"`.
    public let centerValue: String?
    /// Explicit small line under the center value, e.g. `"/150g"`. Only used with `centerValue`.
    public let centerUnit: String?
    /// `true` draws the unconfigured state: a dashed outline and a plus instead of a track and a
    /// value. Pass for a goal that has not been set up yet (`valueText` is then a caption such as
    /// "Not set").
    public let isPlaceholder: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        progress: Double,
        color: Color,
        valueText: String? = nil,
        centerIcon: String? = nil,
        centerValue: String? = nil,
        centerUnit: String? = nil,
        isPlaceholder: Bool = false
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.color = color
        self.valueText = valueText
        self.centerIcon = centerIcon
        self.centerValue = centerValue
        self.centerUnit = centerUnit
        self.isPlaceholder = isPlaceholder
    }
}

/// A row (or wrapping grid) of labeled `GoalRing`s. This is *not* a single concentric multi-ring
/// (Apple Activity–style); spec §16's P1 mockup shows the day's goals as separate side-by-side
/// rings, each with its own label and value, so that's the layout modeled here.
public struct RingCluster: View {

    /// How items are arranged.
    public enum Layout: Sendable {
        /// One row of equal columns that fits its container — rings shrink to `min(ringSize,
        /// column width)` rather than overflow. Best for 2–4 items, the common case on Today and
        /// Fuel. With five or more items it becomes a horizontal scroller at the preset size.
        case row
        /// An adaptive grid that wraps to multiple rows. Best for longer lists (e.g. a Progress
        /// screen showing every active goal, or a Recap's full weekly set).
        case grid
    }

    /// The most items `.row` will fit as equal columns before falling back to a scroller.
    private static let maxEqualColumns = 4

    private let items: [RingClusterItem]
    private let ringSize: GoalRing.Size
    private let layout: Layout
    /// Opt-in entrance stagger, default `false`. Deliberately off by default: the Frequency Gate
    /// cuts two ways for this component — `RingCluster` renders tens of times/day on Today/Fuel
    /// (a concurrent wave's screens, not touched here), where a stagger would be the wrong call,
    /// but occasional/weekly callers in this file's own safe set (`RecapCard`) are exactly the
    /// tier this skill's Gate says delight is earned. Keeping the default `false` means those
    /// high-frequency screens are unaffected unless they explicitly opt in
    /// (docs/design/animation-opportunities.md row 5).
    private let staggerAppearance: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - items: The rings to display, in order.
    ///   - ringSize: Size preset applied to every ring in the cluster — the *maximum* diameter for
    ///     an equal-column `.row`, which shrinks rings to fit. Defaults to `.medium`.
    ///   - layout: `.row` or `.grid`. Defaults to `.row`.
    ///   - staggerAppearance: When `true`, each cell fades/scales in with a small per-index
    ///     delay on first appearance (capped at ~5 items / 200ms total). Defaults to `false` —
    ///     see this property's doc comment above for why high-frequency callers should leave it
    ///     off.
    public init(
        items: [RingClusterItem],
        ringSize: GoalRing.Size = .medium,
        layout: Layout = .row,
        staggerAppearance: Bool = false
    ) {
        self.items = items
        self.ringSize = ringSize
        self.layout = layout
        self.staggerAppearance = staggerAppearance
    }

    public var body: some View {
        Group {
            switch layout {
            case .row:
                if items.count <= Self.maxEqualColumns {
                    equalColumns
                } else {
                    scrollingRow
                }
            case .grid:
                LazyVGrid(
                    // `.top`: a title that wraps to two lines must not push its ring below its
                    // neighbours' (grid cells default to centre alignment, so rings in one row would
                    // sit at different heights).
                    columns: [GridItem(.adaptive(minimum: ringSize.diameter + Theme.Spacing.xl), spacing: Theme.Spacing.lg, alignment: .top)],
                    spacing: Theme.Spacing.lg
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        cell(item, index: index, fitsColumn: false)
                    }
                }
            }
        }
        // If a caller mutates `items` in place (add/remove a ring) without itself wrapping that
        // in `withAnimation`, this keeps insert/remove from teleporting — each cell's own
        // `.transition` above supplies the actual visual (docs/design/apple-design-review.md §6.2).
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: items)
    }

    /// Equal columns; each cell's ring takes `min(ringSize, column width)`.
    private var equalColumns: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                cell(item, index: index, fitsColumn: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Five or more rings: a horizontal scroller at the preset size. A scroller is the honest
    /// answer here (they cannot all fit), and — unlike before — it is no longer used for the
    /// two-to-four case where it silently hid a ring.
    private var scrollingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item, index: index, fitsColumn: false)
                }
            }
            .padding(.horizontal, Theme.Spacing.xxs)
        }
    }

    private func cell(_ item: RingClusterItem, index: Int, fitsColumn: Bool) -> some View {
        RingClusterCell(
            item: item,
            size: ringSize,
            fitsColumn: fitsColumn,
            staggerAppearance: staggerAppearance,
            index: index
        )
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }
}

/// A `GoalRing` that takes `min(maxDiameter, width it is given)` and stays square. `RingCluster`'s
/// equal-column `.row` uses it so rings shrink to fit instead of overflowing.
private struct FittedGoalRing: View {
    let item: RingClusterItem
    let center: GoalRingCenter
    let maxDiameter: CGFloat

    var body: some View {
        GeometryReader { proxy in
            GoalRing(
                progress: item.progress,
                color: item.color,
                size: .custom(min(proxy.size.width, maxDiameter)),
                center: center
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxDiameter)
    }
}

/// A single labeled ring cell shared by both `RingCluster` layouts.
private struct RingClusterCell: View {
    let item: RingClusterItem
    let size: GoalRing.Size
    /// `true` in an equal-column row (the ring adapts to the column); `false` where the cell has a
    /// fixed width (scroller, grid) and the ring is exactly `size`.
    let fitsColumn: Bool
    let staggerAppearance: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The value/unit to show in the ring, when there is one: explicit `centerValue`, otherwise
    /// "value/target unit" parsed out of `valueText`.
    private var centerParts: (value: String, unit: String?)? {
        if item.isPlaceholder { return nil }
        if let value = item.centerValue { return (value, item.centerUnit) }
        if let valueText = item.valueText, let parts = ProgressTextSplit.split(valueText) {
            return (parts.value, parts.unit)
        }
        return nil
    }

    /// Ring center content. A value wins; otherwise the placeholder plus, otherwise the goal's
    /// glyph (the pre-redesign behavior for "Done" / "Not set" style values).
    private var ringCenter: GoalRingCenter {
        if item.isPlaceholder { return .add }
        if let parts = centerParts { return .value(parts.value, unit: parts.unit) }
        if let icon = item.centerIcon { return .icon(systemName: icon) }
        return .none
    }

    /// The glyph sits in the label row when the ring center is busy with a value or a plus.
    private var glyphInLabel: String? {
        switch ringCenter {
        case .value, .add: item.centerIcon
        case .icon, .text, .none: nil
        }
    }

    /// A caption under the title only when the value is *not* already in the ring.
    private var captionText: String? {
        centerParts == nil ? item.valueText : nil
    }

    private var glyphTint: Color {
        item.isPlaceholder ? Theme.Colors.muted : item.color
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ring

            VStack(spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    if let glyph = glyphInLabel {
                        Image(systemName: glyph)
                            .font(Theme.Typography.icon(.xsmall))
                            .foregroundStyle(glyphTint)
                    }
                    Text(item.title)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                        // A 44pt ring's cell is only ~64pt wide: one line cut a user-titled goal
                        // ("Gallon a day") to about eight characters. Small rings get two lines.
                        .lineLimit(size.diameter <= 60 ? 2 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                }
                if let captionText {
                    Text(captionText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(width: fitsColumn ? nil : max(size.diameter, 64))
        // Without this, VoiceOver swipes through the ring, title, and value as disconnected stops.
        // One announcement: the goal's name, then its value ("72/150g", or the percentage when the
        // caller supplied no value text). The ring's own center text is not read twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.valueText ?? "\(Int((min(1, max(0, item.progress)) * 100).rounded()))%")
        .opacity(staggerAppearance && !appeared ? 0 : 1)
        .scaleEffect(staggerAppearance && !reduceMotion && !appeared ? 0.85 : 1)
        .onAppear {
            guard staggerAppearance, !appeared else { return }
            if reduceMotion {
                // Reduced motion: a plain fade, no per-item delay, no scale.
                withAnimation(.easeOut(duration: 0.15)) { appeared = true }
            } else {
                // Cap the stagger window at ~5 items / 200ms total so a long list doesn't drag
                // the reveal out (docs/design/animation-opportunities.md row 5).
                let cappedIndex = min(index, 5)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(cappedIndex) * 0.04)) {
                    appeared = true
                }
            }
        }
    }

    @ViewBuilder
    private var ring: some View {
        if fitsColumn {
            FittedGoalRing(item: item, center: ringCenter, maxDiameter: size.diameter)
        } else {
            GoalRing(progress: item.progress, color: item.color, size: size, center: ringCenter)
        }
    }
}

#Preview("RingCluster") {
    VStack(spacing: Theme.Spacing.xl) {
        RingCluster(
            items: [
                RingClusterItem(title: "Workout", progress: 1.0, color: Theme.Colors.Ring.workout, valueText: "Done", centerIcon: "dumbbell.fill"),
                RingClusterItem(title: "Protein", progress: 0.48, color: Theme.Colors.Ring.protein, valueText: "72/150g", centerIcon: "fork.knife"),
                RingClusterItem(title: "Focus", progress: 0.5, color: Theme.Colors.Ring.focus, valueText: "25/50 min", centerIcon: "timer")
            ],
            ringSize: .large,
            layout: .row
        )
        RingCluster(
            items: [
                RingClusterItem(title: "Protein", progress: 0.48, color: Theme.Colors.Ring.protein, valueText: "72/150g", centerIcon: "fork.knife"),
                RingClusterItem(title: "Water", progress: 0.42, color: Theme.Colors.Ring.water, valueText: "1250/3000ml", centerIcon: "drop.fill")
            ],
            ringSize: .large,
            layout: .row
        )
        RingCluster(
            items: [
                RingClusterItem(title: "Workout", progress: 0, color: Theme.Colors.muted, valueText: "Not set", centerIcon: "dumbbell.fill", isPlaceholder: true),
                RingClusterItem(title: "Protein", progress: 0.2, color: Theme.Colors.Ring.protein, valueText: "30/150g", centerIcon: "fork.knife"),
                RingClusterItem(title: "Focus", progress: 0.9, color: Theme.Colors.Ring.focus, valueText: "45/50 min", centerIcon: "timer")
            ],
            ringSize: .large,
            layout: .row
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
