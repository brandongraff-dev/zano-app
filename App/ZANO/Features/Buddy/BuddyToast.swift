// BuddyToast.swift
// App / ZANO / Features / Buddy
//
// The reward beats on Today (gamification, 2026-10-04), shown one at a time above the action bar for
// a few seconds: new gear put on, a level reached, a perfect day, the weekly Scroll Monster beaten.
// Each shows the buddy (or the defeated monster) and one line. One VoiceOver element each.

import SwiftUI
import Core

enum BuddyToast: Equatable, Identifiable {
    case gear(BuddyGear)
    case levelUp(Int)
    case perfectDay(streak: Int)
    case monsterBeaten(coins: Int, variant: Int)

    var id: String {
        switch self {
        case .gear(let gear): "gear-\(gear.rawValue)"
        case .levelUp(let level): "level-\(level)"
        case .perfectDay(let streak): "perfect-\(streak)"
        case .monsterBeaten(let coins, let variant): "monster-\(coins)-\(variant)"
        }
    }
}

struct BuddyToastView: View {
    let toast: BuddyToast

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            art
            Text(message)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.md)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
        .zanoGlass(in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var art: some View {
        switch toast {
        case .gear(let gear):
            BuddySprite(buddy, pose: .ecstatic, size: 48, gear: gear)
        case .levelUp, .perfectDay:
            BuddySprite(buddy, pose: .ecstatic, size: 48)
        case .monsterBeaten(_, let variant):
            ScrollMonsterSprite(state: .defeated, variant: variant, size: 48)
        }
    }

    private var message: String {
        switch toast {
        case .gear(let gear): Copy.buddy.gearAdopted(buddy, gear: gear)
        case .levelUp(let level): Copy.buddy.levelUp(buddy, level: level)
        case .perfectDay(let streak): Copy.buddy.perfectDay(streak: streak)
        case .monsterBeaten(let coins, _): Copy.buddy.monsterBeaten(coins: coins)
        }
    }
}

/// The weekly boss, pixel-crisp. Decorative.
struct ScrollMonsterSprite: View {
    let state: ScrollMonster.State
    let variant: Int
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ScrollMonster.pixels(state, variant: variant).cgImage() {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Lv 5" and a thin XP bar under Today's buddy: the bar moves with every goal (+10 XP) and earned
/// unlock (+30). Tapping it is handled by the caller (opens Settings > Buddy).
struct BuddyLevelStrip: View {
    let progress: BuddyProgress
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(Copy.buddy.level(progress.level))
                .font(Theme.Typography.captionEmphasized.weight(.heavy))
                .foregroundStyle(Theme.BuddyColors.onSignature)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 2)
                .background(Capsule().fill(color))
                .fixedSize()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, proxy.size.width * progress.levelFraction))
                }
            }
            .frame(height: 6)
        }
        .animation(Theme.Motion.springStandard, value: progress.xp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.buddy.levelSpoken(progress.level))
        .accessibilityValue(progress.xpToNextLevel.map { Copy.buddy.toNextLevel($0, next: progress.level + 1) } ?? Copy.buddy.maxLevel)
    }
}
