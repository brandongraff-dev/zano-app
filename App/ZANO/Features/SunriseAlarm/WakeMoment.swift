// WakeMoment.swift
// App / Features / SunriseAlarm
//
// docs/spec.md §5.10 point 4: a verified dismiss turns the alarm off. The ringing screen is a
// full-screen cover presented purely from `SunriseAlarmManager.isRinging` (`ContentView`), so the
// instant a dismiss succeeds the manager clears `isRinging` and the whole screen disappears — there
// was nowhere to show the "you're up" payoff. `WakeMoment` is the one extra bit of state that keeps
// the cover up for the length of that moment: `AlarmRingingView` calls `begin()` before it runs a
// dismiss, and `finish()` once the celebration has been on screen long enough to read (or
// `cancel()` if the dismiss failed). `ContentView` presents the cover while `isRinging ||
// isPlaying`.
//
// Only a dismiss run from `AlarmRingingView` plays the moment. A tag tapped from outside the app
// (`AppRouter`'s catch-up path) has no ringing screen to celebrate on.

import SwiftUI
import Observation
import Core

@MainActor
@Observable
final class WakeMoment {
    static let shared = WakeMoment()

    private(set) var isPlaying = false

    private init() {}

    func begin() { isPlaying = true }
    func finish() { isPlaying = false }
    func cancel() { isPlaying = false }
}

enum WakeMomentKind: Equatable {
    /// A dismiss that verified the morning goal.
    case verified
    /// The emergency exit: the alarm is off, the goal did not count.
    case escaped
}

/// The payoff laid over the ringing UI: a scrim, the Apple-style check (verified) or a sad sun
/// (escaped), a title and a one-line subtitle. Tapping anywhere (or VoiceOver's default action)
/// skips the wait. One VoiceOver element that reads the title and subtitle.
struct WakeMomentOverlay: View {
    let kind: WakeMomentKind
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textShown = false

    private var title: String {
        kind == .verified ? Copy.alarmRinging.wakeTitle : Copy.alarmRinging.escapedTitle
    }

    private var subtitle: String {
        kind == .verified ? Copy.alarmRinging.wakeSubtitle : Copy.alarmRinging.escapedSubtitle
    }

    var body: some View {
        ZStack {
            // Nearly opaque: the ringing screen underneath (headline, tag prompt) must not show
            // through behind the title and subtitle.
            Theme.Colors.background.opacity(0.97).ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                switch kind {
                case .verified:
                    VerifiedCheck()
                case .escaped:
                    SunCharacter(mood: .sad, animated: false)
                        .frame(width: 130, height: 130)
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.score(size: 40))
                        .foregroundStyle(Theme.Colors.text)
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                }
                .opacity(textShown ? 1 : 0)
                .offset(y: textShown || reduceMotion ? 0 : 10)
            }
            .padding(Theme.Spacing.lg)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSkip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(subtitle)")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.default, onSkip)
        .task {
            // Lands just after the check does (about 0.8s in).
            try? await Task.sleep(for: .milliseconds(reduceMotion || kind == .escaped ? 0 : 800))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { textShown = true }
        }
    }
}
