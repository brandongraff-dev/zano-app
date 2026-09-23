// RingCluster.swift
// Core / UI / Components
//
// Lays out several `GoalRing`s together, per docs/spec.md §15's core component list and the P1
// mockup in §16 ("three progress rings labeled Workout, Protein (72/150g), Focus (25/50 min)").
// All text is caller-composed (see GoalRing.swift's header note on copy discipline).

import SwiftUI

/// One ring's worth of display data for a `RingCluster`. A plain value type (not tied to `Goal`
/// or any SwiftData model) so this component stays usable anywhere a screen wants to show a set
/// of rings — Today's goal rings, a Recap's weekly goal-completion rings, a widget preview, etc.
public struct RingClusterItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Fully-composed label shown under the ring (e.g. `"Workout"`, `"Protein"`).
    public let title: String
    /// Completion fraction, `0...1` (unclamped values are clamped by the underlying `GoalRing`).
    public let progress: Double
    /// Ring tint — typically `Theme.Colors.Ring.color(for:)`.
    public let color: Color
    /// Fully-composed value string shown under the title (e.g. `"72/150g"`, `"25/50 min"`).
    /// Optional — omit for a bare ring + title.
    public let valueText: String?
    /// SF Symbol shown in the ring's center. When `nil`, the ring center is empty (useful when
    /// `valueText` is long and better shown below the ring instead of inside it).
    public let centerIcon: String?

    public init(
        id: UUID = UUID(),
        title: String,
        progress: Double,
        color: Color,
        valueText: String? = nil,
        centerIcon: String? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.color = color
        self.valueText = valueText
        self.centerIcon = centerIcon
    }
}

/// A row (or wrapping grid) of labeled `GoalRing`s. This is *not* a single concentric multi-ring
/// (Apple Activity–style); spec §16's P1 mockup shows the day's goals as separate side-by-side
/// rings, each with its own label and value, so that's the layout modeled here.
public struct RingCluster: View {

    /// How items are arranged.
    public enum Layout: Sendable {
        /// A single horizontal row (scrolls if it overflows). Best for 2–4 items — the common
        /// case on Today.
        case row
        /// An adaptive grid that wraps to multiple rows. Best for longer lists (e.g. a Progress
        /// screen showing every active goal, or a Recap's full weekly set).
        case grid
    }

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
    ///   - ringSize: Size preset applied to every ring in the cluster. Defaults to `.medium`.
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            RingClusterCell(item: item, size: ringSize, staggerAppearance: staggerAppearance, index: index)
                                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxs)
                }
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: ringSize.diameter + Theme.Spacing.xl), spacing: Theme.Spacing.lg)],
                    spacing: Theme.Spacing.lg
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        RingClusterCell(item: item, size: ringSize, staggerAppearance: staggerAppearance, index: index)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
            }
        }
        // If a caller mutates `items` in place (add/remove a ring) without itself wrapping that
        // in `withAnimation`, this keeps insert/remove from teleporting — each cell's own
        // `.transition` above supplies the actual visual (docs/design/apple-design-review.md §6.2).
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: items)
    }
}

/// A single labeled ring cell shared by both `RingCluster` layouts.
private struct RingClusterCell: View {
    let item: RingClusterItem
    let size: GoalRing.Size
    let staggerAppearance: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Written as an explicit if/return rather than `item.centerIcon.map { .icon(...) } ?? .none`
    /// to avoid any ambiguity between `Optional.none` and `GoalRingCenter.none` at the call site.
    private var centerContent: GoalRingCenter {
        if let icon = item.centerIcon {
            return .icon(systemName: icon)
        }
        return .none
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GoalRing(
                progress: item.progress,
                color: item.color,
                size: size,
                center: centerContent
            )
            Text(item.title)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            if let valueText = item.valueText {
                Text(valueText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: max(size.diameter, 64))
        // Without this, VoiceOver swipes through the ring, title, and value as three disconnected
        // stops ("72%," "Workout," "72/150g") — combining them reads as one coherent announcement
        // instead. See `docs/design/ui-stress-test-findings.md` §2.2.
        .accessibilityElement(children: .combine)
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
}
