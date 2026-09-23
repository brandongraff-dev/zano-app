// GymDwellView.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: "workout detection is more reliable with HR; haptic 'verified' tap when the
// gym dwell threshold is hit." Two independent things live on this one screen:
//
//   1. A read-only mirror of the phone's `GymVerifier` dwell state (`WatchStateSnapshot.gymDwell`,
//      field-for-field the same as `GymDwellActivityAttributes.ContentState` — see
//      `WatchStateModels.swift`). The watch cannot run `GymVerifier` itself (no `import Core`); it
//      only displays what the phone last reported and reacts to `isVerified` flipping true
//      (`WatchStateStore.apply(_:)` fires the haptic, not this view — this view just renders the
//      state, so the haptic fires even if this screen isn't the one currently on screen).
//   2. A real, independently-functioning "Track with HR" button
//      (`WatchWorkoutSessionController`) that starts an on-watch `HKWorkoutSession` — genuinely
//      improves the phone-side `GymVerifier`'s HR corroboration by giving HealthKit real samples
//      to sync, per that controller's header comment. This half works with zero WatchConnectivity
//      involvement at all.

import Foundation
import SwiftUI

struct GymDwellView: View {
    @Environment(WatchStateStore.self) private var store
    @State private var workout = WatchWorkoutSessionController.shared

    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.md) {
                dwellCard
                workoutCard
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .padding(.vertical, WatchTheme.Spacing.sm)
        }
        .background(WatchTheme.Colors.background)
        .navigationTitle(Copy.watch.gymTitle)
    }

    @ViewBuilder
    private var dwellCard: some View {
        if let dwell = store.snapshot.gymDwell {
            VStack(spacing: WatchTheme.Spacing.xs) {
                WatchGoalRing(
                    progress: dwell.verifiedAtMinutes > 0 ? Double(dwell.elapsedMinutes) / Double(dwell.verifiedAtMinutes) : 0,
                    color: dwell.isVerified ? WatchTheme.Colors.accent : WatchTheme.Colors.Ring.workout,
                    size: .large,
                    center: .text("\(dwell.elapsedMinutes)m")
                )
                Text(dwell.gymName)
                    .font(WatchTheme.Typography.headline)
                    .foregroundStyle(WatchTheme.Colors.text)
                if dwell.isVerified {
                    Text(Copy.watch.dwellVerified)
                        .font(WatchTheme.Typography.captionEmphasized)
                        .foregroundStyle(WatchTheme.Colors.accent)
                } else {
                    Text(String(format: Copy.watch.verifiedAtFormat, dwell.verifiedAtMinutes))
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(WatchTheme.Colors.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(WatchTheme.Spacing.sm)
            .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
        } else {
            Text(Copy.watch.noGymSession)
                .font(WatchTheme.Typography.body)
                .foregroundStyle(WatchTheme.Colors.muted)
                .frame(maxWidth: .infinity)
                .padding(WatchTheme.Spacing.sm)
                .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
        }
    }

    private var workoutCard: some View {
        VStack(spacing: WatchTheme.Spacing.xs) {
            switch workout.state {
            case .idle, .ended, .failed:
                Text(Copy.watch.startWristWorkoutSubtitle)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(WatchTheme.Colors.muted)
                    .multilineTextAlignment(.center)
                if case .failed(let message) = workout.state {
                    Text(message)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(WatchTheme.Colors.warning)
                }
                Button(Copy.watch.startWristWorkoutTitle) {
                    workout.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.Colors.Ring.workout)

            case .requestingAuthorization:
                ProgressView()
                Text(Copy.watch.startWristWorkoutTitle)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(WatchTheme.Colors.muted)

            case .running:
                if let bpm = workout.latestHeartRateBPM {
                    Text(String(format: Copy.watch.workoutRunningFormat, Int(bpm.rounded())))
                        .font(WatchTheme.Typography.numeralMedium())
                        .foregroundStyle(WatchTheme.Colors.danger)
                } else {
                    Text(Copy.watch.workoutRunningNoHR)
                        .font(WatchTheme.Typography.body)
                        .foregroundStyle(WatchTheme.Colors.muted)
                }
                Button(Copy.watch.endWristWorkoutTitle) {
                    workout.end()
                }
                .buttonStyle(.bordered)
                .tint(WatchTheme.Colors.danger)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
    }
}

#Preview {
    NavigationStack {
        GymDwellView()
    }
    .environment(WatchStateStore.shared)
}
