// PreviewCatalog.swift
// Core / UI
//
// A single scrollable screen exercising every component from docs/spec.md §15's core component
// list that this task owns, so the whole design system can be eyeballed in both light and dark
// system appearances at once (see `#Preview` blocks at the bottom).
//
// This is a development-only tool, not a shipped screen — nothing here is reachable from the app
// target. The sample strings below are fixture/placeholder data for visually exercising each
// component, not production copy, so they don't fall under CLAUDE.md's "no hardcoded UI strings"
// rule the way real screens (App/ZANO/Features) do; every component itself still takes 100% of
// its real display text as caller-supplied parameters (see each component's own file header) —
// this catalog is simply acting as one such caller, with made-up sample values.

import SwiftUI

/// Renders every `Core/Sources/Core/UI/Components` view this task owns against representative
/// sample data, grouped into labeled sections.
public struct PreviewCatalog: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                themeTokensSection
                goalRingSection
                ringClusterSection
                lockStatusCardSection
                streakPillSection
                timeBankBarSection
                primaryButtonSection
                goalRowSection
                shieldPreviewSection
                recapCardSection
                shareCardSection
                ghostProgressBannerSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Theme tokens

    private var themeTokensSection: some View {
        section("Theme — colors") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                swatch("background", Theme.Colors.background)
                swatch("surface", Theme.Colors.surface)
                swatch("surface2", Theme.Colors.surface2)
                swatch("accent", Theme.Colors.accent)
                swatch("danger", Theme.Colors.danger)
                swatch("warning", Theme.Colors.warning)
                swatch("workout", Theme.Colors.Ring.workout)
                swatch("protein", Theme.Colors.Ring.protein)
                swatch("focus", Theme.Colors.Ring.focus)
                swatch("water", Theme.Colors.Ring.water)
                swatch("steps", Theme.Colors.Ring.steps)
                swatch("creatine", Theme.Colors.Ring.creatine)
            }
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(color)
                .frame(height: 44)
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    // MARK: - GoalRing

    private var goalRingSection: some View {
        section("GoalRing") {
            HStack(spacing: Theme.Spacing.lg) {
                GoalRing(progress: 0.72, color: Theme.Colors.Ring.protein, size: .small, center: .icon(systemName: "fork.knife"))
                GoalRing(progress: 0.5, color: Theme.Colors.Ring.focus, size: .medium, center: .text("25/50"))
                GoalRing(progress: 1.0, color: Theme.Colors.Ring.workout, size: .large, center: .icon(systemName: "dumbbell.fill"))
            }
        }
    }

    // MARK: - RingCluster

    private var ringClusterSection: some View {
        section("RingCluster") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                RingCluster(items: sampleRingItems, ringSize: .medium, layout: .row)
                RingCluster(items: sampleRingItems + sampleRingItems, ringSize: .small, layout: .grid)
            }
        }
    }

    private var sampleRingItems: [RingClusterItem] {
        [
            RingClusterItem(title: "Workout", progress: 1.0, color: Theme.Colors.Ring.workout, valueText: "Done", centerIcon: "dumbbell.fill"),
            RingClusterItem(title: "Protein", progress: 0.48, color: Theme.Colors.Ring.protein, valueText: "72/150g", centerIcon: "fork.knife"),
            RingClusterItem(title: "Focus", progress: 0.5, color: Theme.Colors.Ring.focus, valueText: "25/50 min", centerIcon: "timer")
        ]
    }

    // MARK: - LockStatusCard

    private var lockStatusCardSection: some View {
        section("LockStatusCard") {
            VStack(spacing: Theme.Spacing.sm) {
                LockStatusCard(
                    isLocked: true,
                    statusLine: "Locked · TikTok, Instagram, YouTube",
                    detailLine: "1 goal left",
                    action: {}
                )
                LockStatusCard(
                    isLocked: false,
                    statusLine: "Unlocked",
                    detailLine: "Earned · 2h 10m unlocked"
                )
            }
        }
    }

    // MARK: - StreakPill

    private var streakPillSection: some View {
        section("StreakPill") {
            HStack(spacing: Theme.Spacing.md) {
                StreakPill(count: 14)
                StreakPill(count: 3, isFrozen: true)
            }
        }
    }

    // MARK: - TimeBankBar

    private var timeBankBarSection: some View {
        section("TimeBankBar") {
            VStack(spacing: Theme.Spacing.md) {
                TimeBankBar(remainingMinutes: 130, totalMinutes: 180, label: "2h 10m unlocked")
                TimeBankBar(remainingMinutes: 0, totalMinutes: 60, label: "Time Bank empty")
            }
        }
    }

    // MARK: - PrimaryButton

    private var primaryButtonSection: some View {
        section("PrimaryButton") {
            VStack(spacing: Theme.Spacing.md) {
                PrimaryButton(title: "Go to gym · 6 min away", systemImage: "figure.walk", action: {})
                PrimaryButton(title: "Unavailable", isEnabled: false, action: {})
                PrimaryButton(title: "Hold to commit", style: .holdToCommit, action: {})
            }
        }
    }

    // MARK: - GoalRow

    private var goalRowSection: some View {
        section("GoalRow") {
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
                    title: "Gallon a day",
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
            }
        }
    }

    // MARK: - ShieldPreview

    private var shieldPreviewSection: some View {
        section("ShieldPreview") {
            ShieldPreview(
                glyph: ShieldPreviewGlyph(systemImage: "play.tv.fill", caption: "TikTok"),
                headline: "TikTok unlocks after your workout",
                subline: "1 goal left · Streak 14",
                primaryActionTitle: "Show my goals",
                primaryAction: {},
                emergencyActionTitle: "Emergency",
                emergencyAction: {}
            )
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
    }

    // MARK: - RecapCard

    private var recapCardSection: some View {
        section("RecapCard") {
            RecapCard(
                weekLabel: "Week 6",
                rankLabel: "Rank Gold",
                insightText: "You showed up for every morning lift. Try stacking protein right after — you're closest on lift days.",
                ringItems: sampleRingItems,
                completionLabel: "4/6 goals",
                timeReclaimedLabel: "6h 40m reclaimed",
                bestDayLabel: "Best day: Thursday",
                streak: 14
            )
        }
    }

    // MARK: - ShareCard

    private var shareCardSection: some View {
        section("ShareCard") {
            ShareCard(content: sampleShareCardContent)
                .frame(width: 220, height: 220 * 16 / 9)
        }
    }

    private var sampleShareCardContent: ShareCardContent {
        ShareCardContent(
            title: "Week 6 · Rank Gold",
            dayRings: [
                ShareCardDayRing(label: "Mon", progress: 1.0),
                ShareCardDayRing(label: "Tue", progress: 1.0),
                ShareCardDayRing(label: "Wed", progress: 0.6),
                ShareCardDayRing(label: "Thu", progress: 1.0),
                ShareCardDayRing(label: "Fri", progress: 0.3),
                ShareCardDayRing(label: "Sat", progress: 0.0),
                ShareCardDayRing(label: "Sun", progress: 0.8)
            ],
            statLine: "4 workouts · 1,020g protein · 6h 40m time reclaimed",
            highlightLine: "Best day: Thursday",
            footerLabel: "ZANO"
        )
    }

    // MARK: - GhostProgressBanner

    /// Added per `docs/design/ui-stress-test-findings.md` §4.2: this catalog covered 10 of the 11
    /// named components in this safe set's Core UI list, missing `GhostProgressBanner` (added to
    /// the design system after the rest of the catalog existed). Includes a `hasGhostWeek: false`
    /// sample — the empty-state branch, which changes both the tint and hides the scoreboard.
    private var ghostProgressBannerSection: some View {
        section("GhostProgressBanner") {
            VStack(spacing: Theme.Spacing.md) {
                GhostProgressBanner(comparison: sampleGhostComparisonAhead, title: "Ghost Mode", action: {})
                GhostProgressBanner(comparison: sampleGhostComparisonNoGhostWeek, title: "Ghost Mode")
            }
        }
    }

    /// `GhostMode.GhostComparison` has no public initializer (see that type's own file) — only an
    /// internal, module-wide memberwise one, which this file can use because `PreviewCatalog.swift`
    /// compiles into the same `Core` module as `GhostMode.swift`, not because this catalog is
    /// re-declaring or widening that type's access.
    private var sampleGhostComparisonAhead: GhostMode.GhostComparison {
        GhostMode.GhostComparison(
            date: .now,
            weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now,
            dayOfWeekOffset: 2,
            dayLabel: "Tuesday",
            hasGhostWeek: true,
            ghostWeekStart: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: .now),
            ghostCompletedCount: 2,
            currentCompletedCount: 3,
            headline: "Ghost You had completed 2 goals by Tuesday. You're at 3 — ahead."
        )
    }

    private var sampleGhostComparisonNoGhostWeek: GhostMode.GhostComparison {
        GhostMode.GhostComparison(
            date: .now,
            weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now,
            dayOfWeekOffset: 2,
            dayLabel: "Tuesday",
            hasGhostWeek: false,
            ghostWeekStart: nil,
            ghostCompletedCount: 0,
            currentCompletedCount: 1,
            headline: "Keep going — your first Ghost week is still being written."
        )
    }

    // MARK: - Section helper

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
            content()
        }
    }
}

#Preview("PreviewCatalog — Light") {
    PreviewCatalog()
        .preferredColorScheme(.light)
}

#Preview("PreviewCatalog — Dark") {
    PreviewCatalog()
        .preferredColorScheme(.dark)
}
