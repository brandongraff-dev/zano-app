// ZANOEarnMeterLiveActivity.swift
// Extensions/ZANOWidgets/LiveActivities
//
// Active lock (Earn Mode) Live Activity — docs/spec.md §5.11/§6: "Time Bank draining bar".
// Consumes `Core.EarnMeterActivityAttributes` exactly per this task's CONTRACTS. Like the Gym
// Dwell activity, this is entirely externally driven — `ContentState` is pushed by whichever
// engine owns the running lock (`LockEngineManager`/`TimeBankEngine`), this file only renders it.
//
// There's no fixed daily maximum for earned minutes in the data model (`TimeBank.earnedMin` is
// unbounded), so the draining bar is drawn against a visual ceiling (`meterCapMinutes`, matching
// `ZANOTimeBankBarView`'s Home widget default) rather than a literal percentage of "the max you
// could ever earn" — flagged in this task's knownIssues as a product-copy nicety, not a
// correctness issue (the exact remaining-minutes number is always shown as text too).
//
// The "View Today" affordance is a `Link` to a `zano://today` deep link — matching spec §14's
// `OpenTodayIntent` ("— | Deep link") in *effect*, without depending on that intent's exact
// AppIntent shape (not one of this task's 4 frozen CONTRACTS names) or on `LiveActivityIntent`
// conformance inside a Live Activity (see ZANOFocusLiveActivity.swift's header comment for the
// same reasoning).

import ActivityKit
import Core
import SwiftUI
import WidgetKit

struct ZANOEarnMeterLiveActivity: Widget {
    static let openTodayURL = URL(string: "zano://today")!
    private static let meterCapMinutes = 120

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarnMeterActivityAttributes.self) { context in
            ZANOEarnMeterLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ZANOWidgetColor.background)
                .activitySystemActionForegroundColor(ZANOWidgetColor.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.lockSetName, systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(WidgetCopy.minutesRemaining(context.state.earnedMinutesRemaining))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ZANOWidgetColor.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ZANOTimeBankBarView(
                            remainingMinutes: context.state.earnedMinutesRemaining,
                            capMinutes: Self.meterCapMinutes
                        )
                        HStack {
                            Text(WidgetCopy.earnMeterGoalsRemaining(context.state.goalsRemaining))
                            Spacer()
                            if let nextLockTime = context.state.nextLockTime {
                                Text(nextLockTime, style: .relative)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ZANOWidgetColor.accent)
            } compactTrailing: {
                Text("\(context.state.earnedMinutesRemaining)m")
                    .foregroundStyle(ZANOWidgetColor.accent)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ZANOWidgetColor.accent)
            }
        }
    }
}

private struct ZANOEarnMeterLockScreenView: View {
    let attributes: EarnMeterActivityAttributes
    let state: EarnMeterActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.lockSetName, systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                Spacer()
                Link(destination: ZANOEarnMeterLiveActivity.openTodayURL) {
                    Text(WidgetCopy.viewTodayLink)
                        .font(.caption.weight(.semibold))
                }
            }

            Text(WidgetCopy.minutesRemaining(state.earnedMinutesRemaining))
                .font(.title3.weight(.bold))
                .foregroundStyle(ZANOWidgetColor.accent)

            ZANOTimeBankBarView(remainingMinutes: state.earnedMinutesRemaining, capMinutes: 120)

            HStack {
                Text(WidgetCopy.earnMeterGoalsRemaining(state.goalsRemaining))
                Spacer()
                if let nextLockTime = state.nextLockTime {
                    Text(nextLockTime, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(ZANOWidgetColor.textMuted)
        }
        .padding()
    }
}
