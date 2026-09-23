// TodayCopy.swift
// Core / Copy
//
// `Copy.today` — every user-facing string `App/ZANO/Features/Today/TodayView.swift` calls, under
// the `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s header).
//
// Repo-wide Copy sweep (2026-09-22): `TodayView.swift` previously defined its own `private enum
// Copy` nested inside the view — real Swift (it compiles: a type's own nested declaration shadows
// the module-level `Core.Copy` inside that type's scope), but exactly the "flat standalone enum"
// CLAUDE.md and `Copy.swift`'s own header call out as the mistake to avoid, and exactly what that
// file's own header comment already flagged as "a known deviation... recommend a follow-up moves
// `Copy` below into `Core/Sources/Core/Copy/TodayCopy.swift`". `LockStatusView.swift` independently
// made the identical choice for its own screen (see `LockStatusCopy.swift`, this same sweep) — two
// agents assuming two different private shapes for the same "Copy lives in views for now" workaround
// is the exact bug class this sweep exists to catch, even though neither one actually failed to
// compile. Every string value below is copied verbatim from that file's removed private enum, so
// this is a pure move, not a rewrite.

import Foundation

extension Copy {
    public enum today {
        public static let screenTitle = "Today"

        public static func lockStatusLine(isLocked: Bool, goalsRemaining: Int) -> String {
            guard isLocked else { return "Unlocked" }
            return goalsRemaining == 1 ? "Locked · 1 goal left" : "Locked · \(goalsRemaining) goals left"
        }

        public static let ringTitleWorkout = "Workout"
        public static let ringTitleProtein = "Protein"
        public static let ringTitleFocus = "Focus"
        public static let ringNotSet = "Not set"

        public static let setupIncompleteTitle = "Finish setup to start locking"
        public static let beginLockTitle = "Hold to start today's lock"
        public static func startFocusTitle(minutes: Int) -> String { "Start \(minutes)-min focus session" }
        public static let focusRunningTitle = "Focus session running…"
        public static let goToGymTitle = "I'm at the gym"
        public static func verifyingAtGymTitle(minutes: Int) -> String { "Verifying at the gym… (\(minutes) min so far)" }
        public static let allDoneTitle = "All goals done — unlocking…"
        public static let openFuelTitle = "Log the rest on Fuel"
        public static let ghostModeTitle = "Ghost Mode"
        public static let unlockCelebrationFallbackGoalName = "Today's goals"
    }
}
