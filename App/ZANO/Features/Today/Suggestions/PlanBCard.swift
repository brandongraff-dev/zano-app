// PlanBCard.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 5.5 Plan B Days: "a smaller goal that still preserves the streak (20-min walk instead
// of gym; 25-min focus instead of 90). Half credit in Earn Mode." Two states:
//   - Offer: late in the day with a goal under half done. One tap switches it (`PlanB.accept`).
//   - Switched: progress toward the Plan B target. Once verified progress reaches it, "Count Plan B"
//     writes the `.planB` completion (`PlanB.recordCompletion`, then `GoalCompletionCoordinator`,
//     which pays half Earn minutes and unlocks if that was the last goal). Before that the button is
//     the goal's own next step (a quick log, a shorter focus session), or none for goals Health or
//     the gym verify.

import SwiftUI
import Core

struct PlanBCard: View {
    let state: PlanBState
    /// The button while switched but not yet met (`nil`: nothing to tap, it verifies on its own).
    let pendingActionTitle: String?
    let isBusy: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: "b.circle.fill",
            tint: Theme.Colors.Ring.color(for: state.goalType),
            title: state.isAccepted ? Copy.today.planBActiveTitle(goal: state.goalTitle) : Copy.today.planBTitle,
            detail: detail,
            actionTitle: actionTitle,
            isBusy: isBusy,
            onAction: onAction,
            onDismiss: onDismiss
        ) {
            if state.isAccepted {
                PlanBProgressBar(
                    fraction: state.reduced > 0 ? min(1, Double(state.current) / Double(state.reduced)) : 0,
                    color: Theme.Colors.Ring.color(for: state.goalType)
                )
            }
        }
    }

    private var detail: String {
        if state.isAccepted {
            let progress = Copy.today.goalProgressLine(current: state.current, target: state.reduced, unit: state.unit)
            guard !state.isMet, pendingActionTitle == nil else { return progress }
            return "\(progress) \(Copy.today.goalLineSeparator) \(Copy.today.planBVerifiesAutomatically)"
        }
        if state.goalType == .workoutGym {
            return Copy.today.planBGymDetail(minutes: state.reduced)
        }
        return Copy.today.planBDetail(reduced: state.reduced, full: state.full, unit: state.unit)
    }

    private var actionTitle: String? {
        guard state.isAccepted else { return Copy.today.planBAction }
        return state.isMet ? Copy.today.planBCountAction : pendingActionTitle
    }
}

private struct PlanBProgressBar: View {
    let fraction: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: fraction)
        .accessibilityHidden(true)
    }
}
