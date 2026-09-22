// ZANOFocusLiveActivity.swift
// Extensions/ZANOWidgets/LiveActivities
//
// Focus session Live Activity — docs/spec.md §6/§5.12: "countdown, pause, end". Consumes
// `Core.FocusActivityAttributes` exactly per this task's CONTRACTS (owned by another session;
// referenced here, not redefined).
//
// Countdown uses `Text(timerInterval:countsDown:)` (ActivityKit's standard live-ticking timer
// text, WWDC22 "Deliver a great Live Activities experience") instead of manually formatting
// `secondsRemaining` every frame: the system ticks it every second on-device with zero extra
// content-state pushes from the app. When `isPaused` is true this switches to a static formatted
// duration instead, since an auto-ticking timer would visually keep counting down while the
// session is actually frozen.
//
// The "End" action is a `Link` to a `zano://focus/end` deep link, not `Button(intent:
// EndFocusIntent())`: Live Activity buttons require their intent to conform to `LiveActivityIntent`
// (a marker protocol on top of `AppIntent`), and `EndFocusIntent`'s conformance isn't part of this
// task's frozen CONTRACTS — a `Link` deep link works regardless of how that intent ends up
// declared, at the cost of opening the app instead of running in the background. `zano://tag/
// <uuid>`-style URLs are already this codebase's established NFC deep-link convention (spec §6),
// so `zano://focus/end` follows the same pattern. Flagged in this task's knownIssues as a
// candidate to upgrade to `Button(intent:)` once `EndFocusIntent`'s real conformance is known.
// "Pause" has no button here at all: spec §14's App Intents catalog has no Pause/Resume Focus
// intent, so this Live Activity only *displays* `isPaused`; see this task's knownIssues.

import ActivityKit
import Core
import SwiftUI
import WidgetKit

struct ZANOFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            ZANOFocusLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ZANOWidgetColor.background)
                .activitySystemActionForegroundColor(ZANOWidgetColor.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.goalTitle, systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ZANOFocusCountdownText(state: context.state)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ZANOWidgetColor.ringFocus)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if context.state.isPaused {
                            Text(WidgetCopy.focusPausedLabel)
                                .font(.caption2)
                                .foregroundStyle(ZANOWidgetColor.warning)
                        }
                        Link(destination: Self.endFocusURL) {
                            Text(WidgetCopy.focusEndButton)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(ZANOWidgetColor.ringFocus)
            } compactTrailing: {
                ZANOFocusCountdownText(state: context.state)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZANOWidgetColor.ringFocus)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(ZANOWidgetColor.ringFocus)
            }
        }
    }

    static let endFocusURL = URL(string: "zano://focus/end")!
}

private struct ZANOFocusLockScreenView: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.goalTitle, systemImage: "timer")
                    .font(.headline)
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                Spacer()
                if state.isPaused {
                    Text(WidgetCopy.focusPausedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ZANOWidgetColor.warning)
                }
            }

            ZANOFocusCountdownText(state: state)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(ZANOWidgetColor.ringFocus)

            ProgressView(value: Self.progressFraction(attributes: attributes, state: state))
                .tint(ZANOWidgetColor.ringFocus)

            Link(destination: ZANOFocusLiveActivity.endFocusURL) {
                Text(WidgetCopy.focusEndButton)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }

    private static func progressFraction(
        attributes: FocusActivityAttributes,
        state: FocusActivityAttributes.ContentState
    ) -> Double {
        let totalSeconds = Double(attributes.plannedMinutes * 60)
        guard totalSeconds > 0 else { return 0 }
        let remaining = Double(max(state.secondsRemaining, 0))
        return min(max((totalSeconds - remaining) / totalSeconds, 0), 1)
    }
}

/// Auto-ticking (or, while paused, static) countdown text shared by the Lock Screen banner and
/// every Dynamic Island region.
private struct ZANOFocusCountdownText: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Self.formatted(state.secondsRemaining))
                .monospacedDigit()
        } else {
            Text(
                timerInterval: Date.now...Date.now.addingTimeInterval(TimeInterval(max(state.secondsRemaining, 0))),
                countsDown: true,
                showsHours: false
            )
            .monospacedDigit()
        }
    }

    private static func formatted(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
