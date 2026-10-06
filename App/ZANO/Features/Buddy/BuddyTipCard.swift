// BuddyTipCard.swift
// App / ZANO / Features / Buddy
//
// The first-week buddy intro on Today (2026-10-04): your buddy, a speech bubble with today's tip
// (`BuddyIntro`, one a day for seven days), and "Got it". Draws nothing once today's tip is dismissed
// or the week is over. Screenshot runs show the first tip.

import SwiftUI
import Core

struct BuddyTipCard: View {
    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tip: Int?

    var body: some View {
        Group {
            if let tip {
                card(tip)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            tip = ScreenshotMode.screen != nil ? 0 : BuddyIntro.tipForToday()
        }
    }

    private func card(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            StoredBuddySprite(pose: .happy, size: 48)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.buddy.introDay(index + 1, of: BuddyIntro.tipCount))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(buddy.color)
                Text(Copy.buddy.introTip(index, buddy: buddy))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.buddy.introGotIt) { dismiss(index) }
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .buttonStyle(.pressable(scale: 0.96))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(radius: Theme.Radius.medium)
        .accessibilityElement(children: .contain)
    }

    private func dismiss(_ index: Int) {
        BuddyIntro.dismiss(index)
        withAnimation(Theme.Motion.standard(reduceMotion: reduceMotion)) { tip = nil }
    }
}
