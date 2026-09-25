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

        // MARK: - Premium UI pass 2026-09-24 (docs/design/premium-ui-plan.md)

        /// Hero while locked: `"2"` loud, `"goals to unlock"` quiet. Says what the number buys.
        public static func heroGoalsToUnlockLine(count: Int) -> String {
            count == 1 ? "1 goal to unlock" : "\(count) goals to unlock"
        }

        /// `"since 7:00 AM"` beside the locked eyebrow.
        public static func heroLockedSince(_ time: String) -> String { "since \(time)" }

        /// Section over the goals that gate the running lock.
        public static let sectionToUnlock = "To unlock"
        /// Section over active goals that don't gate the running lock.
        public static let sectionAlsoToday = "Also today"
        /// Section over every goal when nothing is locked.
        public static let sectionTodaysGoals = "Today's goals"

        /// A numeric goal's line under its title: `"72 of 150g"`. Water past a liter reads in liters
        /// (`"1.5 of 3 L"`): "1500 of 3000ml" truncated in a row.
        public static func goalProgressLine(current: Int, target: Int, unit: String) -> String {
            if target >= 1000, let currentL = liters(current, unit: unit), let targetL = liters(target, unit: unit) {
                return "\(currentL) of \(targetL) L"
            }
            return "\(current) of \(amount(target, unit: unit))"
        }

        /// What's left, beside the progress line: `"78g to go"`, `"1.5 L to go"`.
        public static func goalRemainingLine(remaining: Int, unit: String) -> String {
            if remaining >= 1000, let value = liters(remaining, unit: unit) {
                return "\(value) L to go"
            }
            return "\(amount(remaining, unit: unit)) to go"
        }

        /// `1500` ml -> `"1.5"`; `3000` -> `"3"`. Nil for any other unit.
        private static func liters(_ milliliters: Int, unit: String) -> String? {
            guard unit.lowercased() == "ml" else { return nil }
            let value = Double(milliliters) / 1000
            return value.formatted(.number.precision(.fractionLength(0...1)))
        }

        /// Under the hero number while locked: what the lock is waiting on, by name.
        /// `"Gym session + Protein"`, `"Gym session, Protein + 1 more"`.
        public static func heroRemainingGoals(_ titles: [String]) -> String? {
            switch titles.count {
            case 0: return nil
            case 1: return titles[0]
            case 2: return "\(titles[0]) + \(titles[1])"
            default: return "\(titles[0]), \(titles[1]) + \(titles.count - 2) more"
            }
        }

        /// Inline quick-log buttons (log straight from Today, no trip to Fuel).
        public static func quickAddAmount(_ value: Int, unit: String) -> String {
            "+\(amount(value, unit: unit))"
        }
        public static func quickAddAccessibility(_ value: Int, unit: String, goal: String) -> String {
            "Log \(amount(value, unit: unit)) of \(goal)"
        }

        public static let actionStart = "Start"
        /// Same words as `goToGymTitle`: one name for one action.
        public static let actionGo = "I'm at the gym"
        public static let statusRunning = "Running"
        public static func statusDwell(minutes: Int) -> String { "\(minutes) min" }
        /// A gym workout's row: it verifies on its own at the gym.
        public static let statusVerifiesAtGym = "Verifies at the gym"
        /// A gym workout with no saved gym: the row's action opens gym setup.
        public static let actionSetUpGym = "Set up your gym"
        /// Goals verified with no tap (HealthKit workouts, steps, sleep, the alarm).
        public static let statusVerifiesAutomatically = "Verifies automatically"
        /// One-tap log for goals marked done on your word (creatine, custom, reading…).
        public static let actionLog = "Log"
        /// VoiceOver label for a row's action capsule: `"Start, Focus"`, `"Log, Reading"`.
        public static func startActionSpoken(label: String, goal: String) -> String { "\(label), \(goal)" }
        /// Between a row's progress and what's left ("72 of 150g · 78g to go").
        public static let goalLineSeparator = "·"

        /// Confirmation before an honor-system log (the small friction spec'd for these goals).
        public static func logGoalConfirmTitle(goal: String) -> String { "Mark \(goal) done for today?" }
        public static let logGoalConfirmAction = "Mark done"
        public static let logGoalConfirmMessage = "This one runs on your word. Keep it honest."

        /// Undo toast after a quick-log: `"Logged 25g of Protein"`.
        public static func quickLogConfirmation(_ value: Int, unit: String, goal: String) -> String {
            "Logged \(amount(value, unit: unit)) of \(goal)"
        }
        public static let undoTitle = "Undo"
        public static let undoHint = "Removes that log"
        public static let undoDone = "Log removed"
        public static let undoFailed = "Couldn't undo that. Try again."

        /// Error lines (never a raw system error).
        public static let lockStartFailed = "Couldn't start the lock. Try again."
        public static let focusStartFailed = "Couldn't start focus. Try again."
        public static let statusDone = "Done"

        public static let logFailedTitle = "Couldn't log that. Try again."

        // MARK: - First-day state (empty-states pass 2026-09-24)
        //
        // The setup hero and the checklist under it, shown until the first lock has ever started.
        // Step titles are deliberately not `beginLockStandardTitle`: the UI tests find the bottom
        // bar's begin-lock button by that exact text, so a second match would make it ambiguous.

        /// Under the setup hero's headline.
        public static let heroSetupSubtitle = "Three steps and your first lock is live."

        public static let firstDayTitle = "Get set up"
        /// `"1 of 3 done"` beside the checklist title.
        public static func firstDayProgress(done: Int, total: Int) -> String { "\(done) of \(total) done" }

        public static let firstDayStepGoalsTitle = "Pick your goals"
        public static let firstDayStepGoalsDetail = "What you'll do to earn your apps back."
        public static let firstDayStepAppsTitle = "Choose apps to lock"
        public static let firstDayStepAppsDetail = "They stay shielded until your goals are done."
        public static let firstDayStepLockTitle = "Start your first lock"
        public static let firstDayStepLockDetail = "Lock in now, unlock by finishing today's goals."
        /// The last step before the steps above it are done.
        public static let firstDayStepLockWaiting = "Unlocks once the steps above are done."

        /// VoiceOver for a step: `"Step 2 of 3, Choose apps to lock, done"`.
        public static func firstDayStepAccessibility(index: Int, total: Int, title: String, isDone: Bool) -> String {
            "Step \(index) of \(total), \(title)" + (isDone ? ", done" : "")
        }

        // MARK: - Live rows + finish-setup card (buildout Wave 1D, 2026-09-25)

        /// A steps or home-workout row before Apple Health was ever connected: opens the primer.
        public static let actionConnectHealth = "Connect Apple Health"
        /// A gym row while a check-in is running: opens the check-in screen.
        public static let actionOpenCheckIn = "View"

        /// A steps row: `"4,200 of 10,000 steps"`.
        public static func stepsProgressLine(current: Int, target: Int) -> String {
            "\(current.formatted()) of \(target.formatted()) steps"
        }
        /// `"5,800 to go"`.
        public static func stepsRemainingLine(remaining: Int) -> String {
            "\(remaining.formatted()) to go"
        }
        /// A home/outdoor workout row: `"12 of 30 min"` (the longest single workout today).
        public static func workoutProgressLine(minutes: Int, target: Int) -> String {
            "\(minutes) of \(target) min"
        }
        /// Under the workout line: where the minutes come from.
        public static let workoutFromHealth = "from Apple Health"

        // Stretch (guided 5-minute timer, phone flat on the floor)
        public static let stretchTitle = "Stretch"
        public static let stretchInstruction = "Lay your phone flat on the floor and stretch until the timer ends."
        public static let stretchFlat = "Phone is flat"
        public static let stretchNotFlat = "Lay your phone flat"
        public static let stretchStop = "Stop"
        public static let stretchClose = "Done"
        public static let stretchDoneTitle = "Stretch counted"
        public static let stretchMissedTitle = "That one didn't count"
        public static let stretchMissedDetail = "The phone has to stay flat for most of the 5 minutes. Try again when you're ready."
        public static let stretchTryAgain = "Try again"
        public static let stretchStartFailed = "Couldn't start the timer. Try again."
        /// VoiceOver for the countdown: `"4 minutes 12 seconds left"`.
        public static func stretchRemainingSpoken(seconds: Int) -> String {
            let minutes = seconds / 60
            let rest = seconds % 60
            let minutePart = minutes == 1 ? "1 minute" : "\(minutes) minutes"
            let secondPart = rest == 1 ? "1 second" : "\(rest) seconds"
            return "\(minutePart) \(secondPart) left"
        }

        // Finish-setup card (after the first lock; items that make verification automatic)
        public static let setupCardTitle = "Finish setup"
        public static func setupCardProgress(done: Int, total: Int) -> String { "\(done) of \(total) done" }
        public static let setupCardDismiss = "Hide"
        public static let setupCardDismissSpoken = "Hide the finish setup checklist"
        public static let setupTagsTitle = "Set up NFC tags"
        public static let setupTagsDetail = "Tap a tag to log protein, water or a check-in."
        public static let setupGymTitle = "Save your gym"
        public static let setupGymDetail = "So gym workouts verify on their own."
        public static let setupHealthTitle = "Connect Apple Health"
        public static let setupHealthDetail = "Steps and workouts count automatically."
        public static let setupWidgetTitle = "Add the ZANO widget"
        public static let setupWidgetDetail = "Log protein and water from your Home Screen."

        // Widget how-to sheet
        public static let widgetHowToTitle = "Add the widget"
        public static let widgetHowToSteps = [
            "Touch and hold an empty spot on your Home Screen until the apps jiggle.",
            "Tap Edit, then Add Widget.",
            "Search for ZANO, pick a size, and tap Add Widget.",
        ]
        public static let widgetHowToDone = "Got it"
    }
}

// MARK: - Suggestion cards (buildout Wave 2F, 2026-09-25)
//
// One card at a time under Today's hero: Never Miss Twice, comeback, Plan B, travel, calendar light
// day, locked-out moment. Each is one headline, one line, one action and "Not today".

extension Copy.today {
    public static let suggestionDismiss = "Not today"
    public static func suggestionDismissSpoken(_ title: String) -> String { "Hide \(title) for today" }
    public static func startWithGoal(_ goal: String) -> String { "Start with \(goal)" }

    // Never Miss Twice
    public static let neverMissTwiceTitle = "Don't miss twice"
    public static func neverMissTwiceDetail(goal: String?) -> String {
        guard let goal else { return "Yesterday slipped. One goal today keeps your streak alive." }
        return "Yesterday slipped. \(goal) today keeps your streak alive."
    }
    public static func freezesLeft(_ count: Int) -> String {
        switch count {
        case 0: "No freezes left this week"
        case 1: "1 freeze left"
        default: "\(count) freezes left"
        }
    }

    // Comeback (3-day ramp)
    public static let comebackStartTitle = "Welcome back"
    public static let comebackStartDetail = "Three easy days to get rolling again. Lighter goals, no catching up."
    public static let comebackStartAction = "Start my comeback"
    public static func comebackDayTitle(day: Int, total: Int) -> String { "Comeback · day \(day) of \(total)" }
    public static let comebackDayDetail = "Goals are lighter for now. Just show up."
    public static let comebackDoneToday = "Today's done. See you tomorrow."
    public static let comebackStartFailed = "Couldn't start the comeback. Try again."

    // Plan B
    public static let planBTitle = "Rough day? Try Plan B"
    /// `"60g instead of 150g. Keeps your streak, for half the Earn minutes."`
    public static func planBDetail(reduced: Int, full: Int, unit: String) -> String {
        "\(amount(reduced, unit: unit)) instead of \(amount(full, unit: unit)). Keeps your streak, for half the Earn minutes."
    }
    /// A gym goal's Plan B is a shorter workout anywhere, read from Apple Health.
    public static func planBGymDetail(minutes: Int) -> String {
        "Any \(minutes)-min workout in Apple Health counts, a walk too. Half the Earn minutes."
    }
    public static let planBAction = "Switch to Plan B"
    public static func planBActiveTitle(goal: String) -> String { "Plan B: \(goal)" }
    public static let planBCountAction = "Count Plan B"
    public static func planBStartFocusAction(minutes: Int) -> String { "Start \(minutes)-min focus" }
    public static let planBVerifiesAutomatically = "Counts once Apple Health or the gym has it."
    public static let planBSwitchFailed = "Couldn't switch to Plan B. Try again."
    public static let planBCountFailed = "Couldn't count Plan B. Try again."

    // Travel
    public static let travelSuggestTitle = "Looks like you're traveling"
    public static let travelManualTitle = "Traveling?"
    public static let travelDetail = "Make the gym optional for the trip. Walks, steps and home workouts keep your day going."
    public static let travelSuggestAction = "Switch to travel mode"
    public static let travelManualAction = "I'm traveling"
    public static func travelActiveTitle(city: String?) -> String {
        guard let city, !city.isEmpty else { return "Travel mode is on" }
        return "Travel mode · \(city)"
    }
    public static let travelActiveDetail = "The gym is optional until you're back. New locks won't wait on it."
    public static let travelActiveAction = "I'm home"
    public static let travelFailed = "Couldn't change travel mode. Try again."

    // Calendar light day
    public static let calendarAskTitle = "Busy days, lighter goals"
    public static let calendarAskDetail = "Let ZANO see how packed your calendar is. On full days it suggests a lighter plan."
    public static let calendarAskAction = "Connect calendar"
    public static let calendarPackedTitle = "Packed calendar today"
    public static let calendarPackedDetail = "Want a lighter plan? Smaller targets keep your streak, for half the Earn minutes."
    public static let calendarPackedAction = "Go lighter today"
    public static let calendarFailed = "Couldn't read your calendar. Try again later."

    // Locked-out moment
    public static func lockedOutCardTitle(attempts: Int) -> String {
        "\(attempts) tries on blocked apps today"
    }
    public static let lockedOutCardDetail = "Share the moment. It keeps you honest."
    public static let lockedOutCardAction = "Share it"
    /// The "until I ..." phrase for the locked-out poster when one goal is left. `nil` when there's
    /// no natural phrase (the poster then says "right now").
    public static func lockedOutGoalPhrase(_ type: GoalType) -> String? {
        switch type {
        case .workoutGym: "hit the gym"
        case .workoutHomeOutdoor: "work out"
        case .focusSession: "finish my focus session"
        case .protein: "hit my protein"
        case .water: "drink my water"
        case .steps: "get my steps in"
        case .reading: "read"
        case .stretchMobility: "stretch"
        case .mealPrep: "meal prep"
        case .coldShowerSauna: "take my cold shower"
        case .creatine: "take my creatine"
        case .sleepOnTime, .sunriseAlarm, .custom: nil
        }
    }

    // Meal prep row
    public static let actionAddPhoto = "Add photo"
}
