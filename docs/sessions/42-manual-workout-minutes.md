# Session 42 — Log workout minutes by hand (no location required)

- **Branch:** worktree branch, based on `origin/claude/dazzling-hypatia-ed6q5d` at `d8a667e`
- **Spec sections:** §3 (both workout rows; Tier C "honesty + friction"), §9.4 (gym auto-detect stays optional), §9.8 (never accuse: entries by hand are labelled "logged by hand"), §14 (App Intents catalog), §24 (location: "Provide a manual check-in fallback")
- **Status:** Scaffolded — Unverified (awaiting a CI compile and `ManualWorkoutMinutesTests`)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder: "users can also add gym minutes by hand because people work out from home, so don't make it
required they go somewhere."

1. A "Log minutes" path for both workout goals (`workoutHomeOutdoor`, `workoutGym`): stepper + quick picks
   (15/20/30/45/60), starting at what's left of today's target, confirmed with a hold
   (`PrimaryButton(style: .holdToCommit)`), written through a new App Intent. Minutes add up across the day,
   no daily cap.
2. Nothing forces location: a workout goal is creatable and completable with no gym saved, location denied
   and Health not connected.
3. Today: the workout tile's action is "Log minutes"; "Connect Apple Health" / "Save your gym" move to the
   sheet's secondary link. Plan B reads manual minutes.
4. Siri: "Log a workout" App Shortcut.
5. Copy in Core; Core tests for summing and dedupe with Health and Strava.
6. Spec §3 workout rows (and §14) updated.

## Definition of done

- With no gym, location denied and no Health/Strava, a person can log 20+ minutes by hand and the workout goal
  completes for the day (lock unlocks if it was the last required goal).
- Minutes by hand add to deduped Health/Strava minutes; one workout in both Health and Strava counts once.
- Entries and a completion by hand are shown as "logged by hand" (Today tile, sheet list, gym screen).
- The gym's one-a-day honor check-in is unchanged.

## Log

### 2026-10-08 — Manual workout minutes: Core rule, write path, intent, Today, gym screen, goals copy, tests

- **Files touched:**
  - new `Core/Sources/Core/Verification/ManualWorkoutMinutes.swift` (pure rule + `ManualWorkoutLogResult`)
  - modified `Core/Sources/Core/Verification/HomeWorkoutVerifier.swift` (`logManualMinutes`, `trackedMinutesToday`,
    `manualRequiredMinutes(for:target:)`, manual-total branch in `checkToday`)
  - new `Core/Sources/Core/Intents/LogWorkoutMinutesIntent.swift`
  - modified `Core/Sources/Core/Intents/ZanoShortcuts.swift` ("Log a workout")
  - new `Core/Sources/Core/Copy/WorkoutMinutesCopy.swift` (`Copy.workoutMinutes`)
  - modified `Core/Sources/Core/Copy/GoalsCopy.swift`, `Core/Sources/Core/Copy/GymCopy.swift`
  - new `Core/Tests/CoreTests/ManualWorkoutMinutesTests.swift` (15 tests)
  - new `App/ZANO/Features/Today/LogWorkoutMinutesSheet.swift`
  - modified `App/ZANO/Features/Today/TodayView.swift`
  - modified `App/ZANO/Features/GymSetup/GymCheckInView.swift`
  - modified `App/ZANO/Features/Goals/Model/GoalCatalog.swift`
  - modified `docs/spec.md` (§3 workout rows, §14 intents table)
- **What changed:**
  - **Storage.** One entry = a verified `.log` `GoalEvent`, `source: .manual` (`.siri` from Siri), `value: nil`,
    `meta: {"tier": "C", "loggedMinutes": N}`. When the day's total reaches the goal's minutes, one verified
    `.complete` with `source: .manual`, `value: nil`,
    `meta: {"tier": "C", "manualMinutesTotal", "manualMinutes", "trackedMinutes", "requiredMinutes"}`. Same
    `source: .manual` + `tier: "C"` convention as `GymVerifier.recordManualCheckIn`; no new `GoalEventSource`
    case and no migration.
  - **Rule (`ManualWorkoutMinutes`).** Tracked workouts (Health + Strava) are merged with
    `WorkoutDedupe.merge` (session 40). With no minutes by hand nothing changes: one tracked workout must reach
    the target (Tier A). Once any minutes are logged by hand, the day's total counts: every deduped tracked
    minute + every minute by hand ≥ required minutes. Required minutes are
    `HomeWorkoutVerifier.manualRequiredMinutes(for:target:)`: home = `requiredMinutes(target:)` (never under 20);
    gym = `travelGymRequiredMinutes(target:)` (the gym's dwell minutes, default 35, never under 20).
  - **Write path.** `HomeWorkoutVerifier.logManualMinutes(goalID:minutes:source:)` (actor-isolated insert, then
    the total check, then `GoalCompletionCoordinator.goalEventRecorded`). `checkToday` (Health observer, Today's
    refresh loop) also completes from the total when minutes by hand exist, so a Health workout landing later
    can finish a day that was partly logged by hand.
  - **Intent.** `LogWorkoutMinutesIntent` (`LiveActivityIntent`, like `LogWaterIntent`): `minutes`, `source`,
    plus a non-parameter `goalID` Today/the gym screen pass; without it, the home workout goal, else the gym
    goal. Added to `ZanoShortcuts` ("Log a workout with ZANO").
  - **Sheet (`LogWorkoutMinutesSheet`).** Headline, Tier C badge "Logged by hand · counts", today's
    "N of M min today" + "K min to go", a −/+ stepper (one adjustable VoiceOver element) in 5-minute steps
    (5–240), quick picks 15/20/30/45/60, today's entries listed as "30 min · logged by hand" with times, an
    optional secondary link ("Connect Apple Health…" for home with Health not asked; "Save your gym…" for a gym
    goal with no gym), and a "Hold to log 30 min" hold-to-commit button that runs the intent.
  - **Today.** Home workout tile: action is always "Log minutes"; progress line shows minutes (manual-aware)
    even before Health is connected, second line "logged by hand" / "tracked + logged by hand" / "from Apple
    Health". Gym tile with no saved gym: "Log minutes" (was "Set up your gym"). A day completed from minutes
    shows "logged by hand" under Done. Plan B: progress includes manual minutes; the pending action for workouts
    is "Log minutes" and opens the sheet (was the Health primer).
  - **Gym screen.** "Worked out somewhere else? Log minutes" under the actions when no gym is saved and when
    away/left early. A day completed from minutes shows "Logged by hand · N minutes today" instead of "Checked
    in manually". `noGymMessage` adds "Working out at home? Log your minutes by hand."
  - **Goals.** `GoalCatalog.setupIsRequired` is now `false` for both workouts, so the goals editor no longer
    flags them "Needs setup" (it still offers "Set up gym" / "Connect Health"). Picker copy: gym
    "…Working out at home? Log your minutes by hand.", chip "Gym location, or log minutes"; home "…or log your
    minutes by hand.", chip "Apple Health, or log minutes". Picker's "Save your gym" next step says it's optional
    (it already had "Later").
  - **Onboarding** never forced gym setup or location (checked `Screen3MainGoal`, `Screen10PlanReveal`): no
    change needed.
- **Decisions made and why:**
  - **`value: nil` on entries.** Workout goals store a weekly count as `targetValue` ("3 workouts", see
    `GoalTargetRule`). `GoalDayProgress` sums `value` of verified `.log`/`.verify`/`.complete` events, so an
    entry with `value: 15` would read as 15 of 3 and the coordinator's rollup would complete the goal on 5
    minutes. Minutes live in `meta` instead; `.log` (not `.verify`) so a binary goal isn't marked done either.
  - **Single-workout rule kept for Tier A.** Without minutes by hand, two short Health workouts still don't add
    up (unchanged behaviour). Summation applies only once the person logs by hand, which is the case the
    founder asked for.
  - **Home tile is always "Log minutes"** (not only when Health isn't connected): a Health-connected person who
    trained without their watch needs the same way in. Health still completes it on its own.
  - **Gym honor check-in untouched** (one a day). Minutes have no cap; the hold is the friction.
  - **Widgets:** skipped. The Home widget and Control Center buttons fire with one tap; a workout entry should
    keep the hold-to-confirm and a minutes choice, which a widget button can't offer. Siri gets it instead.
- **Known issues / TODOs left behind:**
  - `ManualCheckInSheet`'s blocker reads "You've used today's manual check-in" when the gym goal was completed
    by minutes (both are `.complete` + `.manual`); the gym screen doesn't show that sheet once complete, so this
    is only reachable by racing it. Left as-is per "keep the gym honor check-in as-is".
  - Gym goals' `targetValue` is a weekly workout count, but `GymVerifier.requiredDwellMinutes` and Today's
    `gymRequiredMinutes` read it as dwell minutes (pre-existing). Manual minutes use the travel-mode rule
    (never under 20), so a "3 workouts" gym goal needs 20 minutes by hand.
  - No undo for an entry by hand yet (Today's undo toast is protein/water only).
  - Today reads tracked minutes for the gym tile only while travel mode is on (pre-existing refresh scope); the
    sheet reads them fresh on open, and the write path always counts them.
- **Unverified API details (flag for first compile):**
  - `LogWorkoutMinutesIntent.swift:53-74`: `@MainActor perform()` awaiting a `Sendable` final class's async
    method and holding a SwiftData `Goal` across the await (same shape as `LogCustomGoalIntent`).
  - `HomeWorkoutVerifier.swift:445-490` (`HomeWorkoutQueryState.logManualMinutes`): non-`Sendable` `Goal` kept across
    `await trackedMinutes(in:)` inside the actor (same as the existing `checkToday`).
  - `LogWorkoutMinutesSheet.swift:190`: `accessibilityAdjustableAction` switch with `@unknown default`;
    `Text(_:format: .dateTime.hour().minute())`; `ForEach` with a `let` inside the builder.
  - `GymCheckInView.swift:150`: `.sheet(isPresented:)` with a computed `Binding` and an `if let` body.
  - `ManualWorkoutMinutesTests` builds `GoalEvent`s without a container and uses the internal
    `GoalDayProgress(targetValue:unit:events:)` via `@testable` (same as existing tests).
- **Needs verification on:** CI (compile + `ManualWorkoutMinutesTests`); Simulator (sheet layout, hold,
  Today tile/progress lines, gym screen links); device (Health workout + entries by hand adding up; a lock
  ending when the total completes the last required goal; Siri "Log a workout").

## Blockers

- No Mac (CI is the compiler).

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (coordinator owns the board for this session)
- [x] No secrets committed
