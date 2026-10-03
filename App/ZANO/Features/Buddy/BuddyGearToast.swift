// BuddyGearToast.swift
// App / ZANO / Features / Buddy
//
// The reward beat for buddy growth (2026-10-03): when an item of gear unlocks, the buddy puts it on
// (`BuddyProgress.adoptNewGear`) and Today shows this for a few seconds above its action bar:
// the buddy wearing it, and "Stash put on the shades! 7-day streak." One VoiceOver element.

import SwiftUI
import Core

struct BuddyGearToast: View {
    let gear: BuddyGear

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            BuddySprite(buddy, pose: .ecstatic, size: 48, gear: gear)
            Text(Copy.buddy.gearAdopted(buddy, gear: gear))
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
}
