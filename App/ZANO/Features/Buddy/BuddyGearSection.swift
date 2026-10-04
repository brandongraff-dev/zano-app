// BuddyGearSection.swift
// App / ZANO / Features / Buddy
//
// Buddy growth on the Buddy screen (Settings > Buddy, 2026-10-03): the buddy's level (from
// lifetime earned unlocks) with a bar to the next one, and its gear: four items earned by playing
// (first earned unlock, 7/14/30-day best streak), never bought. Unlocked items are tapped to wear
// (tap again to take off); locked ones show what unlocks them. What's worn is stored in the App
// Group (`BuddyGear.storageKey`), so every buddy in the app, the widgets and the shield wear it.

import SwiftUI
import Core

struct BuddyGearSection: View {
    let buddy: Buddy

    @AppStorage(BuddyGear.storageKey, store: SharedDefaults.store) private var worn: BuddyGear = .bare
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = BuddyProgress(earnedUnlocks: 0, bestStreak: 0)

    private static let spriteSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            levelRow
            gearHeader
            gearGrid
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .onAppear(perform: refresh)
        .sensoryFeedback(.selection, trigger: worn)
        .onChange(of: worn) { _, _ in WidgetRefresh.reloadAll() }
    }

    private func refresh() {
        progress = ScreenshotMode.screen != nil ? .preview : BuddyProgress.load(from: modelContext)
    }

    // MARK: Level

    private var levelRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(Copy.buddy.level(progress.level))
                    .font(Theme.Typography.headline.weight(.heavy))
                    .foregroundStyle(Theme.BuddyColors.onSignature)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Capsule().fill(buddy.color))
                    .accessibilityLabel(Copy.buddy.levelSpoken(progress.level))
                Text(levelCaption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            levelBar
        }
        .accessibilityElement(children: .combine)
    }

    private var levelCaption: String {
        guard let remaining = progress.unlocksToNextLevel else { return Copy.buddy.maxLevel }
        return Copy.buddy.toNextLevel(remaining, next: progress.level + 1)
    }

    private var levelBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.track)
                Capsule()
                    .fill(buddy.color)
                    .frame(width: max(8, proxy.size.width * progress.levelFraction))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: Gear

    private var gearHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(Copy.buddy.gearTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.buddy.gearSubtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var gearGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 4)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(BuddyGear.wearable) { item in
                BuddyGearTile(
                    buddy: buddy,
                    gear: item,
                    isUnlocked: item.isUnlocked(by: progress),
                    isWorn: worn == item,
                    spriteSize: Self.spriteSize
                ) {
                    toggle(item)
                }
            }
        }
    }

    private func toggle(_ item: BuddyGear) {
        guard item.isUnlocked(by: progress) else { return }
        withAnimation(Theme.Motion.standard(reduceMotion: reduceMotion)) {
            worn = worn == item ? .bare : item
        }
    }
}

/// One gear item: the buddy wearing it, its name, and "Wearing" / "Tap to wear" / what unlocks it.
private struct BuddyGearTile: View {
    let buddy: Buddy
    let gear: BuddyGear
    let isUnlocked: Bool
    let isWorn: Bool
    let spriteSize: CGFloat
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                sprite
                Text(Copy.buddy.gearName(gear))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(status)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isWorn ? buddy.color : Theme.Colors.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .top)
            .background { shape.fill(isWorn ? buddy.color.opacity(0.18) : Theme.Colors.glassFill) }
            .overlay { shape.strokeBorder(isWorn ? buddy.color : Theme.Colors.hairline, lineWidth: isWorn ? 2 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.94))
        .disabled(!isUnlocked)
        .accessibilityLabel(Copy.buddy.gearTileLabel(gear, unlocked: isUnlocked, wearing: isWorn))
        .accessibilityAddTraits(isWorn ? .isSelected : [])
    }

    private var sprite: some View {
        BuddySprite(buddy, pose: isUnlocked ? .happy : .idle, size: spriteSize, gear: gear)
            .opacity(isUnlocked ? 1 : 0.35)
            .overlay(alignment: .bottomTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
    }

    private var status: String {
        guard isUnlocked else { return Copy.buddy.gearRequirement(gear) }
        return isWorn ? Copy.buddy.gearWearing : Copy.buddy.gearTapToWear
    }
}
