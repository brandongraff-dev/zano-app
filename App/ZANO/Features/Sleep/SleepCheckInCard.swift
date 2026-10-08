// SleepCheckInCard.swift
// App / ZANO / Features / Sleep
//
// "How rested do you feel?" on Today each morning (session 18; docs/spec.md §5.25). Five faces, the
// user's own buddy from drained to ecstatic, one tap. Draws nothing unless the check-in is turned on,
// it is morning, and last night has no answer yet. Skip puts it away for the day.

import SwiftUI
import Core

struct SleepCheckInCard: View {
    @State private var isVisible = false
    @State private var thanked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let poses: [BuddyPose] = [.drained, .sad, .meh, .happy, .ecstatic]

    var body: some View {
        Group {
            if thanked {
                Text(Copy.sleep.checkInThanks)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .zanoCard()
            } else if isVisible {
                card
            }
        }
        .task {
            await SleepManager.shared.recordLastNight()
            isVisible = SleepManager.shared.needsCheckIn()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.sleep.checkInTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(Self.poses.enumerated()), id: \.offset) { index, pose in
                    Button { answer(index + 1) } label: {
                        VStack(spacing: Theme.Spacing.xxs) {
                            StoredBuddySprite(pose: pose, size: 48)
                            Text(Copy.sleep.ratingLabel(index + 1))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pressable(scale: 0.92))
                    .accessibilityLabel(Copy.sleep.ratingLabel(index + 1))
                }
            }
            Button(Copy.sleep.skipButton) {
                SleepManager.shared.skipCheckIn()
                withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) { isVisible = false }
            }
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.muted)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func answer(_ rating: Int) {
        Task {
            await SleepManager.shared.submitRating(rating)
            withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
                isVisible = false
                thanked = true
            }
        }
    }
}
