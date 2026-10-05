// ScrollMonsterSection.swift
// App / ZANO / Features / Progress
//
// Progress > "This week's boss" (gamification, 2026-10-04): the weekly Scroll Monster with its HP bar,
// days left and loot, and under it the perfect-day run. The fight is computed locally
// (`ScrollMonster.current`): locked minutes hit it, completed goals land +20 crits. Loot is paid by
// Today (`ScrollMonster.claimLoot`), not here, so opening Progress never moves coins.

import SwiftUI
import Core

struct ScrollMonsterSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var week: ScrollMonster.Week?
    @State private var beaten = 0
    @State private var perfectStreak = 0
    @State private var perfectTotal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.buddy.monsterTitle)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
                .frame(minHeight: Theme.Metrics.minTapTarget)
            if let week {
                ScrollMonsterCard(week: week, beaten: beaten)
            }
            PerfectDayRow(streak: perfectStreak, total: perfectTotal)
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        if ScreenshotMode.screen != nil {
            let interval = ScrollMonster.week(containing: .now)
            week = ScrollMonster.Week(interval: interval, target: 600, damage: 340, daysLeft: 3, variant: 0)
            beaten = 4
            perfectStreak = 3
            perfectTotal = 11
            return
        }
        week = ScrollMonster.current(context: modelContext)
        beaten = ScrollMonster.beatenCount()
        perfectStreak = PerfectDay.streak()
        perfectTotal = PerfectDay.total()
    }
}

/// The monster, its HP bar (drains as you lock), days left and the loot line.
private struct ScrollMonsterCard: View {
    let week: ScrollMonster.Week
    let beaten: Int

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ScrollMonsterSprite(state: week.state, variant: week.variant, size: 96)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.buddy.monsterName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                hpBar
                HStack {
                    Text(Copy.buddy.monsterHP(week.hp, of: week.target))
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(Copy.buddy.monsterDaysLeft(week.daysLeft))
                }
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                Text(week.isDefeated ? Copy.buddy.monsterDefeated : Copy.buddy.monsterHowTo)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !week.isDefeated {
                    ZanoSticker(Copy.buddy.monsterLoot(ScrollMonster.lootCoins), systemImage: "bitcoinsign.circle.fill", color: Theme.Colors.warning, style: .tinted, size: .small)
                        .fixedSize()
                }
                if beaten > 0 {
                    Text(Copy.buddy.monsterBeatenCount(beaten))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium, tint: week.isDefeated ? Theme.Colors.ember : Theme.Colors.danger.opacity(0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.buddy.monsterSpoken(hp: week.hp, target: week.target, days: week.daysLeft))
    }

    private var hpBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.track)
                Capsule()
                    .fill(week.hpFraction > 0.5 ? Theme.Colors.danger : Theme.Colors.ember)
                    .frame(width: max(week.hp > 0 ? 8 : 0, proxy.size.width * week.hpFraction))
            }
        }
        .frame(height: 10)
    }
}

/// "Perfect days · 3 days in a row · 11 all time", with the buddy beaming.
private struct PerfectDayRow: View {
    let streak: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StoredBuddySprite(pose: streak > 0 ? .ecstatic : .idle, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.buddy.perfectTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(streak > 0 ? Copy.buddy.perfectRun(streak) : Copy.buddy.perfectHowTo)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if total > 0 {
                Text(Copy.buddy.perfectTotal(total))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }
}
