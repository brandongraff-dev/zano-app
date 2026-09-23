// WatchCopy.swift
// Watch/ZANOWatch
//
// User-facing copy for the whole watch app, under the same `Copy.<area>` umbrella pattern every
// other feature area uses (`Core/Sources/Core/Copy/Copy.swift`'s doc comment, CLAUDE.md:
// "User-facing copy in Core/Sources/Core/Copy under the Copy.<area> umbrella pattern - never a
// flat standalone enum"). This is declared LOCALLY, inside the `Watch/ZANOWatch/` target, rather
// than as a real `Core/Sources/Core/Copy/WatchCopy.swift` adding `Copy.watch` to the real `Copy`
// namespace — because it would be unreachable there. `Core/Package.swift` only declares
// `.iOS(.v17)`, so nothing in `Core/Sources/Core/Copy` (or anywhere else in `Core`) can be
// imported by this target today, no matter which subfolder it lives in — see `WatchTheme.swift`'s
// header comment for the full explanation, which applies identically here.
//
// This file reproduces the exact shape a real `Copy.watch` would have (`enum Copy {}` + an
// `extension Copy { public enum watch { ... } }`, matching `CommonCopy.swift`'s pattern exactly)
// so that the day `Core` gains real watchOS support, every call site in this target that writes
// `Copy.watch.xyz` keeps compiling unchanged after this file is deleted and a real
// `Core/Sources/Core/Copy/WatchCopy.swift` takes its place. Flagged in this task's knownIssues.

/// Root namespace, matching `Core/Sources/Core/Copy/Copy.swift`'s own `public enum Copy {}`.
/// Never instantiated.
enum Copy {}

extension Copy {
    enum watch {

        // MARK: - Tab titles

        static let todayTab = "Today"
        static let actionsTab = "Actions"
        static let gymTab = "Gym"

        // MARK: - Today / rings

        static let todayTitle = "Today"
        static let noConnectionBanner = "iPhone not reachable — showing last known state."
        static let neverSyncedBanner = "Open ZANO on your iPhone once to sync your goals here."
        static let streakLabel = "Streak"

        static func ringTitle(for kind: WatchRingKind) -> String {
            switch kind {
            case .workout: "Workout"
            case .protein: "Protein"
            case .focus: "Focus"
            case .water: "Water"
            }
        }

        // MARK: - Start actions

        static let startLockTitle = "Start Lock"
        static let startLockSubtitle = "Shield distracting apps until today's goals are verified."
        static let startFocusTitle = "Start Focus"
        static let focusPresetMinutesFormat = "%d min"
        static let sendingToPhone = "Sending to iPhone…"
        static let lockRequestedConfirmation = "Lock requested"
        static let focusRequestedConfirmation = "Focus session requested"
        static let requestFailedTitle = "Couldn't reach iPhone"
        static let requestFailedMessage = "Your iPhone needs to be nearby and unlocked. This will keep trying in the background."
        static let emergencyUnlockTitle = "Emergency Unlock"
        static let emergencyUnlockConfirm = "Hold to confirm"

        static let activeLockStatusFormat = "Locked · %d goal(s) left"
        static let noActiveLock = "Nothing locked right now"

        // MARK: - Focus session (mirrors FocusActivityAttributes.ContentState on the phone)

        static let focusRunningTitle = "Focus running"
        static let focusPausedTitle = "Focus paused"
        static let endFocusButton = "End Session"

        // MARK: - Gym dwell (mirrors GymDwellActivityAttributes.ContentState on the phone)

        static let gymTitle = "Gym"
        static let noGymSession = "Not at the gym"
        static let dwellingFormat = "At the gym · %d min"
        static let verifiedAtFormat = "Verified at %d min"
        static let dwellVerified = "Verified ✓"

        // MARK: - Wrist-based workout (HealthKit HR collection — see WatchWorkoutSessionController)

        static let startWristWorkoutTitle = "Track with HR"
        static let startWristWorkoutSubtitle = "Wearing the watch during your workout makes gym verification more reliable."
        static let endWristWorkoutTitle = "End Workout"
        static let workoutRunningFormat = "Tracking · %d bpm"
        static let workoutRunningNoHR = "Tracking · waiting for HR…"
        static let workoutEndedConfirmation = "Workout saved"

        // MARK: - Connectivity

        static let connectivityUnsupported = "This Apple Watch can't connect to an iPhone."
        static let connectivityActivating = "Connecting to iPhone…"
    }
}
