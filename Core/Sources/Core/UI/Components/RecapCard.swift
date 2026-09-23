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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the insight box's reveal-after-rings beat below. Weekly-frequency surface (spec
    /// §9.6's Sunday recap), so a one-shot sequenced reveal is exactly the tier
    /// `find-animation-opportunities`' Gate calls delight-eligible — not something a tens-of-
    /// times/day screen should do (docs/design/animation-opportunities.md row 9).
    @State private var hasAppeared = false

    public init(
        weekLabel: String,
        rankLabel: String? = nil,
        insightText: String? = nil,
        ringItems: [RingClusterItem],
        completionLabel: String? = nil,
        timeReclaimedLabel: String? = nil,
        bestDayLabel: String? = nil,
        streak: Int? = nil
    ) {
        self.weekLabel = weekLabel
        self.rankLabel = rankLabel
        self.insightText = insightText
        self.ringItems = ringItems
        self.completionLabel = completionLabel
        self.timeReclaimedLabel = timeReclaimedLabel
        self.bestDayLabel = bestDayLabel
        self.streak = streak
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            if !ringItems.isEmpty {
                // Occasional-frequency context (weekly), exactly where the Gate says the
                // stagger `RingCluster` otherwise defaults off is earned
                // (docs/design/animation-opportunities.md row 9).
                RingCluster(items: ringItems, ringSize: .small, layout: .row, staggerAppearance: true)
            }

            if completionLabel != nil || timeReclaimedLabel != nil || bestDayLabel != nil {
                statLines
            }

            if let insightText {
                // The coach's insight — the actual payoff of the whole weekly recap — fades/rises
                // in just after the rings settle rather than appearing simultaneously with them.
                // Reduced motion skips the delay chain entirely: show everything at once, no
                // stagger.
                Text(insightText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .opacity(reduceMotion || hasAppeared ? 1 : 0)
                    .offset(y: reduceMotion || hasAppeared ? 0 : 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.3), value: hasAppeared)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .onAppear { hasAppeared = true }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
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
        }
    }

    private var statLines: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if let completionLabel {
                statLine(icon: "checkmark.seal.fill", text: completionLabel)
            }
            if let timeReclaimedLabel {
                statLine(icon: "hourglass", text: timeReclaimedLabel)
            }
            if let bestDayLabel {
                statLine(icon: "star.fill", text: bestDayLabel)
            }
        }
    }

    private func statLine(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 18)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.text)
        }
    }
}
