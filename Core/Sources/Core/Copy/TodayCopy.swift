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
        /// The value shown on a ring with no goal behind it: a forward prompt, not a dead "Not
        /// set" (docs/spec.md §8 rule 2). Generic on purpose — the same string serves the Workout,
        /// Protein and Focus rings.
        public static let ringNotSet = "Add a goal"

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

        // MARK: - Design pass 2026-09-23 (moved here from `TodayView.swift`'s `extension Copy.today`)
        //
        // `TodayView` was redesigned around one hero number and briefly carried these in an
        // `extension Copy.today` at the bottom of the view file (App target), because this file was
        // outside that task's edit list. They are user-facing copy, so they live here (CLAUDE.md:
        // `Core/Sources/Core/Copy`); the values and call-site shapes are unchanged. Call sites are
        // still `Copy.today.<key>`.

        public static let heroSetupEyebrow = "Setup"
        public static let heroUnlockingEyebrow = "Unlocking"

        /// `"Locked"`, or `"Locked · Distractions"` when the lock set has a name.
        public static func heroLockedEyebrow(lockSetName: String?) -> String {
            guard let name = lockSetName, !name.isEmpty else { return "Locked" }
            return "Locked · \(name)"
        }

        /// The hero line while locked: the number leads, the words trail ("2 goals left").
        public static func heroGoalsLeftLine(count: Int) -> String {
            count == 1 ? "1 goal left" : "\(count) goals left"
        }

        /// The hero line while unlocked: `"3/4 done"`. `NumeralText` makes the "3" the hero and sets
        /// "/4 done" quietly beside it, so the count that changes is the loud one.
        public static func heroFractionDone(done: Int, total: Int) -> String { "\(done)/\(total) done" }

        /// VoiceOver version of `heroFractionDone` ("3 of 4 done"; a screen reader reads "3/4" as a
        /// fraction or a date).
        public static func heroFractionDoneSpoken(done: Int, total: Int) -> String { "\(done) of \(total) done" }

        public static func heroTimeBankChip(minutes: Int) -> String { "\(minutes) min banked" }

        /// Begin-lock is a plain tap now (the 2-second hold is reserved for commitment and emergency
        /// exits), so the hold variant's `beginLockTitle` above is no longer used by `TodayView`. The
        /// UI tests find the begin-lock button by this exact text: do not reword it without updating
        /// `ZANOUILabel.Today.startLock` in `ZANOUITests/ZANOUIScenarioSupport.swift`.
        public static let beginLockStandardTitle = "Start today's lock"

        /// The bottom action while setup is incomplete, once the tab shell supplies `onFinishSetup`.
        public static let finishSetupTitle = "Finish setup"

        /// `72` + `g` -> `"72g"`; `50` + `min` -> `"50 min"`. Short unit symbols hug the number.
        public static func amount(_ value: Int, unit: String) -> String {
            unit.count <= 2 ? "\(value)\(unit)" : "\(value) \(unit)"
        }

        /// A ring value in the "value/target unit" shape `RingCluster` splits into a big center
        /// numeral over a small tail: `"72/150g"`, `"25/50 min"`.
        public static func progressValue(current: Int, target: Int, unit: String) -> String {
            "\(current)/\(amount(target, unit: unit))"
        }

        public static let ringDone = "Done"
        public static let ringNotYet = "Not yet"

        public static func moreGoalsLink(count: Int) -> String {
            count == 1 ? "+1 more goal" : "+\(count) more goals"
        }
    }
}
