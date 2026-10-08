import Testing
import Foundation
@testable import Core

@Suite("Manual workout minutes — summing, dedupe with Health and Strava, completion rule")
struct ManualWorkoutMinutesTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func health(startOffsetMin: Double, minutes: Double) -> WorkoutCandidate {
        let start = t0.addingTimeInterval(startOffsetMin * 60)
        return WorkoutCandidate(start: start, end: start.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60, source: .healthKit)
    }

    private func strava(startOffsetMin: Double, minutes: Double, id: String = "s1") -> WorkoutCandidate {
        let start = t0.addingTimeInterval(startOffsetMin * 60)
        return WorkoutCandidate(
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            activeSeconds: minutes * 60,
            source: .strava,
            externalID: id
        )
    }

    private func entry(_ minutes: Double, verified: Bool = true, kind: GoalEventKind = .log) -> GoalEvent {
        GoalEvent(
            ts: t0,
            kind: kind,
            source: .manual,
            verified: verified,
            meta: .object([
                "tier": .string("C"),
                ManualWorkoutMinutes.loggedMinutesMetaKey: .number(minutes),
            ])
        )
    }

    // MARK: Entries

    @Test func entriesAddUp() {
        let events = [entry(15), entry(20), entry(10)]
        #expect(ManualWorkoutMinutes.loggedMinutes(in: events) == 45)
    }

    @Test func onlyVerifiedLogEntriesCount() {
        let events = [
            entry(15),
            entry(30, verified: false),
            entry(30, kind: .verify),
            GoalEvent(ts: t0, kind: .log, value: 25, source: .nfc, verified: true),
            GoalEvent(ts: t0, kind: .complete, value: 40, source: .healthKit, verified: true),
        ]
        #expect(ManualWorkoutMinutes.loggedMinutes(in: events) == 15)
        #expect(ManualWorkoutMinutes.isEntry(events[0]))
        #expect(!ManualWorkoutMinutes.isEntry(events[3]))
    }

    @Test func entriesNeverAddToTheGoalsWorkoutCount() {
        // Workout goals store "3 workouts" as their target; an entry carries no `value`, so
        // `GoalDayProgress` doesn't count 15 minutes as 15 workouts.
        let progress = GoalDayProgress(targetValue: 3, unit: "workouts", events: [entry(15), entry(30)])
        #expect(!progress.isComplete)
        #expect(progress.loggedAmount == 0)
    }

    @Test func entriesDoNotMarkABinaryGoalDone() {
        let progress = GoalDayProgress(targetValue: nil, unit: nil, events: [entry(5)])
        #expect(!progress.isComplete)
    }

    @Test func completionFromTheTotalIsRecognized() {
        let completion = GoalEvent(
            ts: t0,
            kind: .complete,
            source: .manual,
            verified: true,
            meta: .object(["tier": .string("C"), ManualWorkoutMinutes.totalMetaKey: .number(35)])
        )
        #expect(ManualWorkoutMinutes.isCompletion(completion))
        #expect(ManualWorkoutMinutes.completionTotalMinutes(completion) == 35)
        #expect(GoalDayProgress.isVerifiedCompletion(completion))
        let gymHonorCheckIn = GoalEvent(ts: t0, kind: .complete, source: .manual, verified: true, meta: .object(["tier": .string("C")]))
        #expect(!ManualWorkoutMinutes.isCompletion(gymHonorCheckIn))
    }

    // MARK: Tracked minutes (Health + Strava)

    @Test func trackedMergesHealthAndStravaCopiesOnce() {
        // One 30-minute run in both Health and Strava, plus a separate 12-minute Strava ride.
        let tracked = ManualWorkoutMinutes.Tracked(
            health: [health(startOffsetMin: 0, minutes: 30)],
            strava: [strava(startOffsetMin: 1, minutes: 29), strava(startOffsetMin: 120, minutes: 12, id: "s2")]
        )
        #expect(tracked.longestMinutes == 30)
        #expect(tracked.totalMinutes == 42)
    }

    @Test func trackedWithNothingIsZero() {
        let tracked = ManualWorkoutMinutes.Tracked(health: [], strava: [])
        #expect(tracked == .zero)
    }

    // MARK: Progress and completion

    @Test func withoutManualMinutesProgressIsTheLongestWorkout() {
        let tracked = ManualWorkoutMinutes.Tracked(longestMinutes: 15, totalMinutes: 25)
        #expect(ManualWorkoutMinutes.progressMinutes(tracked: tracked, manualMinutes: 0) == 15)
        // The Tier A single-workout rule is unchanged: two short tracked workouts don't complete it.
        #expect(!ManualWorkoutMinutes.completesWithManual(tracked: tracked, manualMinutes: 0, requiredMinutes: 20))
    }

    @Test func manualMinutesAloneCompleteWithNoHealthOrStrava() {
        #expect(!ManualWorkoutMinutes.completesWithManual(tracked: .zero, manualMinutes: 15, requiredMinutes: 20))
        #expect(ManualWorkoutMinutes.completesWithManual(tracked: .zero, manualMinutes: 20, requiredMinutes: 20))
        #expect(ManualWorkoutMinutes.progressMinutes(tracked: .zero, manualMinutes: 35) == 35)
    }

    @Test func manualMinutesAddToEveryTrackedMinute() {
        let tracked = ManualWorkoutMinutes.Tracked(
            health: [health(startOffsetMin: 0, minutes: 12)],
            strava: [strava(startOffsetMin: 60, minutes: 8)]
        )
        #expect(ManualWorkoutMinutes.progressMinutes(tracked: tracked, manualMinutes: 10) == 30)
        #expect(ManualWorkoutMinutes.completesWithManual(tracked: tracked, manualMinutes: 10, requiredMinutes: 30))
        #expect(!ManualWorkoutMinutes.completesWithManual(tracked: tracked, manualMinutes: 9, requiredMinutes: 30))
    }

    @Test func aWorkoutInHealthAndStravaIsNotCountedTwiceInTheTotal() {
        let tracked = ManualWorkoutMinutes.Tracked(
            health: [health(startOffsetMin: 0, minutes: 15)],
            strava: [strava(startOffsetMin: 0, minutes: 15)]
        )
        // 15 tracked (once) + 10 by hand = 25, short of 30.
        #expect(ManualWorkoutMinutes.progressMinutes(tracked: tracked, manualMinutes: 10) == 25)
        #expect(!ManualWorkoutMinutes.completesWithManual(tracked: tracked, manualMinutes: 10, requiredMinutes: 30))
    }

    @Test func manualEntriesHaveNoDailyCap() {
        let events = (0..<6).map { _ in entry(15) }
        let manual = ManualWorkoutMinutes.loggedMinutes(in: events)
        #expect(manual == 90)
        #expect(ManualWorkoutMinutes.completesWithManual(tracked: .zero, manualMinutes: manual, requiredMinutes: 60))
    }

    // MARK: Picker

    @Test func suggestionIsWhatIsLeftRoundedUpToFive() {
        #expect(ManualWorkoutMinutes.suggestedMinutes(requiredMinutes: 35, progressMinutes: 0) == 35)
        #expect(ManualWorkoutMinutes.suggestedMinutes(requiredMinutes: 35, progressMinutes: 12) == 25)
        #expect(ManualWorkoutMinutes.suggestedMinutes(requiredMinutes: 20, progressMinutes: 18) == 5)
        #expect(ManualWorkoutMinutes.suggestedMinutes(requiredMinutes: 20, progressMinutes: 25) == 30)
    }

    @Test func pickedMinutesAreClamped() {
        #expect(ManualWorkoutMinutes.clamped(0) == 5)
        #expect(ManualWorkoutMinutes.clamped(45) == 45)
        #expect(ManualWorkoutMinutes.clamped(1_000) == 240)
    }

    // MARK: Required minutes

    @Test func requiredMinutesNeverDropBelowTheFloor() {
        // Workout goals store a weekly count ("3 workouts") as their target.
        #expect(HomeWorkoutVerifier.manualRequiredMinutes(for: .workoutHomeOutdoor, target: 3) == 20)
        #expect(HomeWorkoutVerifier.manualRequiredMinutes(for: .workoutHomeOutdoor, target: 45) == 45)
        #expect(HomeWorkoutVerifier.manualRequiredMinutes(for: .workoutGym, target: nil) == GymVerificationDefaults.requiredDwellMinutes)
        #expect(HomeWorkoutVerifier.manualRequiredMinutes(for: .workoutGym, target: 3) == 20)
    }
}
