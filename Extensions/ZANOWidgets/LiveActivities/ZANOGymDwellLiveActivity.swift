// ZANOGymDwellLiveActivity.swift
// Extensions/ZANOWidgets/LiveActivities
//
// Gym dwell Live Activity — docs/spec.md §6: "At the gym · 22 min · verified at 35". Consumes
// `Core.GymDwellActivityAttributes` exactly per this task's CONTRACTS. Purely informational (no
// buttons in spec's description), driven entirely by whatever `ContentState` the Verification
// module pushes via `Activity.update(...)` — this file only renders it, it never polls
// `GymVerifier` itself (that engine tracks dwell time on the app/location-monitoring side, not
// from inside a widget-extension timeline).

import ActivityKit
import Core
import SwiftUI
import WidgetKit

struct ZANOGymDwellLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymDwellActivityAttributes.self) { context in
            ZANOGymDwellLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ZANOWidgetColor.background)
                .activitySystemActionForegroundColor(ZANOWidgetColor.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.gymName, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GymDwellClock(state: context.state)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ZANOWidgetColor.ringWorkout)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(
                            value: Double(context.state.elapsedMinutes),
                            total: Double(max(context.state.verifiedAtMinutes, 1))
                        )
                        .tint(ZANOWidgetColor.ringWorkout)
                        Text(WidgetCopy.gymDwellStatus(
                            elapsedMinutes: context.state.elapsedMinutes,
                            verifiedAtMinutes: context.state.verifiedAtMinutes
                        ))
                        .font(.caption2)
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(ZANOWidgetColor.ringWorkout)
            } compactTrailing: {
                // A long gym visit can run past 2 digits, and this compact region is only
                // comfortably wide enough for ~3 characters. See
                // `docs/design/ui-stress-test-findings.md` §3.7.
                GymDwellClock(state: context.state)
                    .foregroundStyle(ZANOWidgetColor.ringWorkout)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.state.isVerified ? "checkmark.seal.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(context.state.isVerified ? ZANOWidgetColor.accent : ZANOWidgetColor.ringWorkout)
            }
        }
    }
}

private struct ZANOGymDwellLockScreenView: View {
    let attributes: GymDwellActivityAttributes
    let state: GymDwellActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.gymName, systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                Spacer()
                if state.isVerified {
                    Label(WidgetCopy.gymVerifiedLabel, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ZANOWidgetColor.accent)
                }
            }

            Text(WidgetCopy.gymDwellStatus(
                elapsedMinutes: state.elapsedMinutes,
                verifiedAtMinutes: state.verifiedAtMinutes
            ))
            .font(.subheadline)
            .foregroundStyle(ZANOWidgetColor.textMuted)

            ProgressView(
                value: Double(state.elapsedMinutes),
                total: Double(max(state.verifiedAtMinutes, 1))
            )
            .tint(ZANOWidgetColor.ringWorkout)
        }
        .padding()
    }
}


/// The dwell minutes. When the arrival time is known it's a live system timer, so it keeps
/// counting on the Lock Screen while the app is suspended and can't push new minute counts.
private struct GymDwellClock: View {
    let state: GymDwellActivityAttributes.ContentState

    var body: some View {
        if let enteredAt = state.enteredAt {
            Text(enteredAt, style: .timer)
                .monospacedDigit()
        } else {
            Text("\(state.elapsedMinutes)m")
        }
    }
}
