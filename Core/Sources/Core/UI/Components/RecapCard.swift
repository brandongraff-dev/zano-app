// RecapCard.swift
// Core / UI / Components
//
// The in-app card for a Weekly Report Card, per docs/spec.md §15's core component list, §5.14/
// §9.6 (the Sunday Weekly Recap Writer job), and `Models/Recap.swift` (`Recap`, `RecapStats`).
// This renders the card *inside* the app (Progress screen, a "this week" summary); the 9:16
// shareable export is a distinct, purpose-built component — `ShareCard` — since a shareable image
// has different layout/branding needs than an in-app card embedded in a scroll view.
//
// Takes `RecapStats` (the model's own plain jsonb-backed struct) plus caller-composed strings —
// it does not take the `Recap` `@Model` class itself, so it stays previewable/testable without a
// live `ModelContext` and has no SwiftData dependency of its own.
//
// Design-quality pass (docs/design/{competitive-research,better-layout,better-ui,composition-audit}):
//
//   * The stats are numbers, not sentences. "4/6 goals" and "6h 40m reclaimed" were 13pt caption
//     lines with a decorative accent glyph each; they are now two big-numeral cells (`NumeralText`
//     at 44pt, the unit word as a caption beneath) — the three-numbers-and-nothing-else recap the
//     competitive research found on WHOOP and Opal (spec P7: "chunky bold numerals"). "Best day"
//     stays a quiet line; no fourth stat.
//   * The rings fit and read. Four or fewer rings are `.medium` and share the card's width in equal
//     columns (they used to be 44pt rings in a scroller, cut off past the fourth, titles clipped to
//     eight characters). Five or more wrap in a grid, and — because thirteen ring hues on one dense
//     card is a rainbow, not information — switch to one scheme: complete = the accent, incomplete =
//     `textSecondary` (competitive-research 3.11.4).
//   * Concentric corners. The insight well used to be an r12 well at a 16pt inset in an r20 card
//     (concentric would be 4 — a loose corner, better-ui RAD-01). It now sits 8pt from the card
//     edge, where `Radius.small` inside `Radius.medium` is exact.
//   * Depth: the card is a `zanoCard`. Decorative accent glyphs are gone (accent means earned).
//   * An optional share affordance (`onShare`), because the recap is the product's shareable moment
//     (spec §5.14) and had no entry point on the card that shows it.

import SwiftUI

/// A card summarizing one week's `RecapStats`. See the file header for why this takes plain data
/// rather than the `Recap` SwiftData model directly.
public struct RecapCard: View {
    /// Fully-composed header, e.g. `"Week 6"`.
    private let weekLabel: String
    /// Fully-composed rank/season context, e.g. `"Rank Gold"`. Optional — `Recap.stats.
    /// rankMovement` is `nil` until Seasons ships (spec §5.9).
    private let rankLabel: String?
    /// The Weekly Recap Writer's line (`Recap.text`, spec §9.6: "≤60-word line: one specific win,
    /// one specific suggestion, no shame"). Optional — `nil` before Sunday's job has run.
    private let insightText: String?
    /// Per-goal completion rings for the week. Built by the caller from `RecapStats.
    /// goalCompletionRings` (keyed by goal id) joined against the user's actual `Goal` titles/
    /// colors — this card only knows how to lay rings out, not how to resolve an id to a title.
    private let ringItems: [RingClusterItem]
    /// Caller-composed, e.g. `"4/6 goals"` (from `RecapStats.goalsCompleted`/`goalsPlanned`).
    private let completionLabel: String?
    /// Caller-composed, e.g. `"6h 40m reclaimed"` (from `RecapStats.timeReclaimedMinutes`).
    private let timeReclaimedLabel: String?
    /// Caller-composed, e.g. `"Best day: Thursday"` (from `RecapStats.bestDay`).
    private let bestDayLabel: String?
    /// Raw streak count (`RecapStats.streak`) — numeric data, so this card renders it directly via
    /// `StreakPill` without needing a caller-composed string.
    private let streak: Int?
    /// Caller-composed VoiceOver label for the share button (e.g. `Copy.share.shareButtonTitle`).
    /// The button only appears when this and `onShare` are both non-`nil`.
    private let shareLabel: String?
    private let onShare: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the insight box's reveal-after-rings beat below. Weekly-frequency surface (spec
    /// §9.6's Sunday recap), so a one-shot sequenced reveal is exactly the tier
    /// `find-animation-opportunities`' Gate calls delight-eligible — not something a tens-of-
    /// times/day screen should do (docs/design/animation-opportunities.md row 9).
    @State private var hasAppeared = false

    /// More rings than this and the card switches to a wrapping grid in the single accent scheme.
    private static let denseThreshold = 4

    public init(
        weekLabel: String,
        rankLabel: String? = nil,
        insightText: String? = nil,
        ringItems: [RingClusterItem],
        completionLabel: String? = nil,
        timeReclaimedLabel: String? = nil,
        bestDayLabel: String? = nil,
        streak: Int? = nil,
        shareLabel: String? = nil,
        onShare: (() -> Void)? = nil
    ) {
        self.weekLabel = weekLabel
        self.rankLabel = rankLabel
        self.insightText = insightText
        self.ringItems = ringItems
        self.completionLabel = completionLabel
        self.timeReclaimedLabel = timeReclaimedLabel
        self.bestDayLabel = bestDayLabel
        self.streak = streak
        self.shareLabel = shareLabel
        self.onShare = onShare
    }

    private var isDense: Bool {
        ringItems.count > Self.denseThreshold
    }

    /// The rings as displayed: the caller's per-goal hues for a handful of rings, one scheme for a
    /// dense set (complete = accent, incomplete = `textSecondary`).
    private var displayedRings: [RingClusterItem] {
        guard isDense else { return ringItems }
        return ringItems.map { item in
            RingClusterItem(
                id: item.id,
                title: item.title,
                progress: item.progress,
                color: item.progress >= 1 ? Theme.Colors.accent : Theme.Colors.textSecondary,
                valueText: item.valueText,
                centerIcon: item.centerIcon,
                centerValue: item.centerValue,
                centerUnit: item.centerUnit,
                isPlaceholder: item.isPlaceholder
            )
        }
    }

    private var hasStats: Bool {
        completionLabel != nil || timeReclaimedLabel != nil || bestDayLabel != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header

                if !ringItems.isEmpty {
                    // Occasional-frequency context (weekly), exactly where the Gate says the
                    // stagger `RingCluster` otherwise defaults off is earned
                    // (docs/design/animation-opportunities.md row 9).
                    RingCluster(
                        items: displayedRings,
                        ringSize: isDense ? .small : .medium,
                        layout: isDense ? .grid : .row,
                        staggerAppearance: true
                    )
                }

                if hasStats {
                    stats
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, insightText == nil ? Theme.Spacing.md : Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let insightText {
                insightWell(insightText)
                    // 8pt (`Spacing.xs`) from the card edge: `Radius.small` in `Radius.medium` is
                    // exactly concentric there.
                    .padding([.horizontal, .bottom], Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
        .onAppear { hasAppeared = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(weekLabel)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                if let rankLabel {
                    Text(rankLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }

            Spacer(minLength: 0)

            if let streak {
                StreakPill(count: streak)
            }

            if let shareLabel, let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(Theme.Typography.icon(.medium))
                        .foregroundStyle(Theme.Colors.text)
                        .minTapTarget()
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(shareLabel)
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if completionLabel != nil || timeReclaimedLabel != nil {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    if let completionLabel {
                        statCell(completionLabel)
                    }
                    if let timeReclaimedLabel {
                        statCell(timeReclaimedLabel)
                    }
                }
            }

            if let bestDayLabel {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "star.fill")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                    Text(bestDayLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    /// A big-numeral stat with its unit word beneath ("6h 40m" over "reclaimed"). A label with no
    /// numeric lead (a localized spelled-out number, say) degrades to a plain headline instead of
    /// showing the same words twice.
    @ViewBuilder
    private func statCell(_ label: String) -> some View {
        if NumeralText.hasNumeral(label) {
            let rest = NumeralText.remainder(of: label)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                NumeralText(label, size: .large, remainder: .hidden)
                if !rest.isEmpty {
                    Text(rest)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One announcement of the original string ("6h 40m reclaimed"), not "6h 40m" then
            // "reclaimed" as two stops.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        } else {
            Text(label)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Insight

    private func insightWell(_ text: String) -> some View {
        // The coach's insight — the actual payoff of the whole weekly recap — fades/rises in just
        // after the rings settle rather than appearing simultaneously with them. Reduced motion
        // skips the delay chain entirely: show everything at once, no stagger.
        Text(text)
            .zanoText(.paragraph)
            .foregroundStyle(Theme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoWell()
            .opacity(reduceMotion || hasAppeared ? 1 : 0)
            .offset(y: reduceMotion || hasAppeared ? 0 : 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.3), value: hasAppeared)
    }
}

#Preview("RecapCard") {
    ScrollView {
        VStack(spacing: Theme.Spacing.lg) {
            RecapCard(
                weekLabel: "Week 6",
                rankLabel: "Rank Gold",
                insightText: "You showed up for every morning lift. Try stacking protein right after — you're closest on lift days.",
                ringItems: [
                    RingClusterItem(title: "Workout", progress: 1.0, color: Theme.Colors.Ring.workout),
                    RingClusterItem(title: "Protein", progress: 0.7, color: Theme.Colors.Ring.protein),
                    RingClusterItem(title: "Focus", progress: 0.5, color: Theme.Colors.Ring.focus)
                ],
                completionLabel: "4/6 goals",
                timeReclaimedLabel: "6h 40m reclaimed",
                bestDayLabel: "Best day: Thursday",
                streak: 14,
                shareLabel: "Share",
                onShare: {}
            )
            RecapCard(
                weekLabel: "Week 7",
                ringItems: [
                    RingClusterItem(title: "Workout", progress: 1.0, color: Theme.Colors.Ring.workout),
                    RingClusterItem(title: "Protein", progress: 0.7, color: Theme.Colors.Ring.protein),
                    RingClusterItem(title: "Focus", progress: 0.5, color: Theme.Colors.Ring.focus),
                    RingClusterItem(title: "Water", progress: 1.0, color: Theme.Colors.Ring.water),
                    RingClusterItem(title: "Gallon a day", progress: 0.3, color: Theme.Colors.Ring.water),
                    RingClusterItem(title: "Reading", progress: 0.0, color: Theme.Colors.Ring.reading)
                ],
                completionLabel: "2/6 goals",
                timeReclaimedLabel: "1h 5m reclaimed"
            )
        }
        .padding(Theme.Spacing.md)
    }
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
