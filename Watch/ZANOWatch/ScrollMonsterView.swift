// ScrollMonsterView.swift
// Watch/ZANOWatch
//
// The second page (session 13b): this week's Scroll Monster, as on the phone's Progress tab. The
// fight itself is computed on the phone (`ScrollMonster.current`) and arrives in
// `WatchStateSnapshot.scrollMonster`; the watch only draws it: the monster, its HP bar and the
// days left.

import SwiftUI

struct ScrollMonsterView: View {
    @Environment(WatchStateStore.self) private var store

    var body: some View {
        ScrollView {
            Group {
                if let monster = store.snapshot.scrollMonster {
                    MonsterCard(monster: monster)
                } else {
                    Text(Copy.watch.monsterNotSynced)
                        .font(WatchTheme.Typography.body)
                        .foregroundStyle(WatchTheme.Colors.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .padding(.vertical, WatchTheme.Spacing.sm)
        }
        .background(WatchTheme.Colors.background)
        .navigationTitle(Copy.watch.monsterTab)
    }
}

private struct MonsterCard: View {
    let monster: WatchScrollMonsterSnapshot

    /// 96pt = 4 px per sprite pixel on a 2x screen.
    private static let spriteSize: CGFloat = 96

    private var isDefeated: Bool { monster.resolvedState == .defeated }

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.xs) {
            Text(Copy.watch.monsterTitle)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(WatchTheme.Colors.muted)
            WatchPixelImage(
                image: WatchMonster.pixels(monster.resolvedState, variant: monster.variant).cgImage(),
                size: Self.spriteSize
            )
            Text(Copy.watch.monsterName)
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.text)
            WatchProgressBar(
                fraction: monster.hpFraction,
                color: WatchTheme.Buddy.monsterHP(fraction: monster.hpFraction),
                height: 8
            )
            MonsterNumbers(monster: monster)
            Text(isDefeated ? Copy.watch.monsterDefeated : Copy.watch.monsterHowTo)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(WatchTheme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.watch.monsterSpoken(hp: monster.hp, target: monster.target, days: monster.daysLeft))
    }
}

private struct MonsterNumbers: View {
    let monster: WatchScrollMonsterSnapshot

    var body: some View {
        HStack {
            Text(Copy.watch.monsterHP(monster.hp, of: monster.target))
            Spacer(minLength: WatchTheme.Spacing.xxs)
            Text(Copy.watch.monsterDaysLeft(monster.daysLeft))
        }
        .font(WatchTheme.Typography.captionEmphasized)
        .foregroundStyle(WatchTheme.Colors.text)
        .monospacedDigit()
    }
}

#Preview {
    NavigationStack {
        ScrollMonsterView()
    }
    .environment(WatchStateStore.shared)
}
