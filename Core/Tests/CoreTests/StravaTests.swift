import Testing
import Foundation
@testable import Core

@Suite("Strava — activity mapping, Health dedupe, redirect, cache, wire format")
struct StravaTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func activity(
        id: String = "1",
        startOffsetMin: Double = 0,
        elapsedMin: Int = 40,
        movingMin: Int = 38,
        manual: Bool = false,
        maxHR: Double? = nil
    ) -> StravaActivity {
        StravaActivity(
            id: id,
            sportType: "Run",
            startDate: t0.addingTimeInterval(startOffsetMin * 60),
            elapsedSeconds: elapsedMin * 60,
            movingSeconds: movingMin * 60,
            manual: manual,
            hasHeartrate: maxHR != nil,
            maxHeartrate: maxHR
        )
    }

    private func health(startOffsetMin: Double, minutes: Double) -> WorkoutCandidate {
        let start = t0.addingTimeInterval(startOffsetMin * 60)
        return WorkoutCandidate(start: start, end: start.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60, source: .healthKit)
    }

    private func candidate(_ a: StravaActivity) -> WorkoutCandidate {
        guard case .counts(let c) = StravaWorkoutMapping.verdict(for: a) else {
            Issue.record("expected a counted activity")
            return health(startOffsetMin: 0, minutes: 0)
        }
        return c
    }

    // MARK: Mapping

    @Test func recordedActivityMapsToMovingTimeAndWallClockSpan() {
        let c = candidate(activity(id: "42", elapsedMin: 40, movingMin: 33))
        #expect(c.source == .strava)
        #expect(c.externalID == "42")
        #expect(c.start == t0)
        #expect(c.end == t0.addingTimeInterval(40 * 60))
        #expect(c.activeSeconds == 33 * 60)
        #expect(c.wholeMinutes == 33)
        #expect(c.heartRateCorroboration == nil)
    }

    @Test func handEnteredActivityIsNotCounted() {
        #expect(StravaWorkoutMapping.verdict(for: activity(manual: true)) == .notCounted(.enteredByHand))
        #expect(StravaWorkoutMapping.countedCandidates([activity(manual: true)]).isEmpty)
    }

    @Test func zeroMovingTimeIsNotCounted() {
        #expect(StravaWorkoutMapping.verdict(for: activity(movingMin: 0)) == .notCounted(.noDuration))
    }

    @Test func heartRateCorroborationUsesTheSameThresholdAsHealth() {
        let threshold = HomeWorkoutVerificationDefaults.elevatedHeartRateBPM
        #expect(candidate(activity(maxHR: threshold + 40)).heartRateCorroboration == true)
        #expect(candidate(activity(maxHR: threshold - 10)).heartRateCorroboration == false)
    }

    @Test func elapsedShorterThanMovingStillSpansTheMovingTime() {
        let c = candidate(activity(elapsedMin: 10, movingMin: 30))
        #expect(c.end == t0.addingTimeInterval(30 * 60))
    }

    // MARK: Dedupe

    @Test func sameRunInHealthAndStravaIsOneWorkout() {
        // Strava starts a minute later and ends a minute later: same run.
        let s = candidate(activity(startOffsetMin: 1, elapsedMin: 40))
        #expect(WorkoutDedupe.isSameWorkout(health(startOffsetMin: 0, minutes: 40), s))
    }

    @Test func backToBackWorkoutsAreTwoWorkouts() {
        let s = candidate(activity(startOffsetMin: 31, elapsedMin: 30, movingMin: 30))
        #expect(!WorkoutDedupe.isSameWorkout(health(startOffsetMin: 0, minutes: 30), s))
    }

    @Test func smallOverlapIsNotTheSameWorkout() {
        // 5 minutes of a 30-minute workout overlap (17%): a cool-down walk into a separate ride.
        let s = candidate(activity(startOffsetMin: 25, elapsedMin: 30, movingMin: 30))
        #expect(!WorkoutDedupe.isSameWorkout(health(startOffsetMin: 0, minutes: 30), s))
    }

    @Test func shortWorkoutInsideALongOneIsTheSameWorkout() {
        // A 20-minute Strava segment fully inside a 60-minute Health workout.
        let s = candidate(activity(startOffsetMin: 10, elapsedMin: 20, movingMin: 20))
        #expect(WorkoutDedupe.isSameWorkout(health(startOffsetMin: 0, minutes: 60), s))
    }

    @Test func zeroLengthSpansMatchOnStartTime() {
        let a = WorkoutCandidate(start: t0, end: t0, activeSeconds: 0, source: .healthKit)
        let near = WorkoutCandidate(start: t0.addingTimeInterval(60), end: t0.addingTimeInterval(60), activeSeconds: 0, source: .strava)
        let far = WorkoutCandidate(start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(600), activeSeconds: 0, source: .strava)
        #expect(WorkoutDedupe.isSameWorkout(a, near))
        #expect(!WorkoutDedupe.isSameWorkout(a, far))
    }

    @Test func mergeKeepsHealthAndDropsItsStravaCopy() {
        let h = health(startOffsetMin: 0, minutes: 40)
        let copy = candidate(activity(id: "copy", startOffsetMin: 1))
        let separate = candidate(activity(id: "evening", startOffsetMin: 600))
        let merged = WorkoutDedupe.merge(health: [h], strava: [copy, separate])
        #expect(merged.count == 2)
        #expect(merged.first == h)
        #expect(merged.last?.externalID == "evening")
    }

    @Test func mergeAlsoDropsDuplicateStravaEntries() {
        let a = candidate(activity(id: "a"))
        let b = candidate(activity(id: "b", startOffsetMin: 0.5))
        #expect(WorkoutDedupe.merge(health: [], strava: [a, b]).count == 1)
    }

    @Test func stravaQualifiesWhenHealthHasNothing() {
        let s = candidate(activity(movingMin: 25))
        #expect(WorkoutDedupe.qualifyingStravaWorkout(health: [], strava: [s], requiredMinutes: 20) == s)
    }

    @Test func stravaTooShortDoesNotQualify() {
        let s = candidate(activity(elapsedMin: 20, movingMin: 18))
        #expect(WorkoutDedupe.qualifyingStravaWorkout(health: [], strava: [s], requiredMinutes: 20) == nil)
    }

    @Test func stravaCopyOfAShortHealthWorkoutGetsNoSecondVote() {
        // Health recorded the run as 15 minutes; Strava's copy says 25. One workout, one vote: Health's.
        let h = health(startOffsetMin: 0, minutes: 15)
        let s = candidate(activity(startOffsetMin: 0, elapsedMin: 26, movingMin: 25))
        #expect(WorkoutDedupe.qualifyingStravaWorkout(health: [h], strava: [s], requiredMinutes: 20) == nil)
    }

    @Test func separateStravaWorkoutQualifiesNextToAShortHealthOne() {
        let h = health(startOffsetMin: 0, minutes: 10)
        let s = candidate(activity(startOffsetMin: 120, movingMin: 30))
        #expect(WorkoutDedupe.qualifyingStravaWorkout(health: [h], strava: [s], requiredMinutes: 20) == s)
    }

    @Test func handEnteredStravaWorkoutNeverQualifies() {
        let strava = StravaWorkoutMapping.countedCandidates([activity(movingMin: 60, manual: true)])
        #expect(WorkoutDedupe.qualifyingStravaWorkout(health: [], strava: strava, requiredMinutes: 20) == nil)
    }

    // MARK: Redirect

    @Test func parsesAnAuthorizedRedirect() {
        let url = URL(string: "zano://zano.app/strava?state=abc&code=xyz&scope=read,activity:read_all")!
        #expect(StravaCallback.parse(url) == .authorized(code: "xyz", state: "abc", scope: "read,activity:read_all"))
    }

    @Test func parsesADeniedRedirect() {
        let url = URL(string: "zano://zano.app/strava?state=abc&error=access_denied")!
        #expect(StravaCallback.parse(url) == .denied)
    }

    @Test func ignoresOtherURLs() {
        #expect(StravaCallback.parse(URL(string: "https://zano.app/strava?code=x&state=y")!) == nil)
        #expect(StravaCallback.parse(URL(string: "zano://zano.app/strava?code=x")!) == nil)
        #expect(StravaCallback.parse(URL(string: "zano://goals")!) == nil)
    }

    // MARK: Cache and sync timing

    @Test func cacheMergeKeepsNewestCopyAndDropsOldActivities() {
        let keepSince = t0.addingTimeInterval(-86_400)
        let old = activity(id: "old", startOffsetMin: -3 * 24 * 60)
        let first = activity(id: "1", movingMin: 20)
        let updated = activity(id: "1", movingMin: 35)
        let later = activity(id: "2", startOffsetMin: 60)
        let merged = StravaActivityStore.merge(existing: [old, first], fetched: [updated, later], keepSince: keepSince)
        #expect(merged.map(\.id) == ["2", "1"])
        #expect(merged.last?.movingSeconds == 35 * 60)
    }

    @Test func fetchIsThrottled() {
        let now = t0
        #expect(StravaActivitySync.isDue(lastFetch: nil, now: now, force: false))
        #expect(!StravaActivitySync.isDue(lastFetch: now.addingTimeInterval(-60), now: now, force: false))
        #expect(StravaActivitySync.isDue(lastFetch: now.addingTimeInterval(-StravaActivitySync.minimumInterval), now: now, force: false))
        #expect(StravaActivitySync.isDue(lastFetch: now.addingTimeInterval(-60), now: now, force: true))
        // A clock moved backwards never blocks fetching.
        #expect(StravaActivitySync.isDue(lastFetch: now.addingTimeInterval(3_600), now: now, force: false))
    }

    @Test func fetchWindowStartsAtTheBeginningOfYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13 UTC
        let start = StravaActivitySync.fetchStart(now: now, calendar: calendar)
        #expect(start == calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
    }

    // MARK: Wire format

    @Test func decodesTheFunctionsResponse() throws {
        let json = """
        {"activities":[{"id":"9876543210123","sportType":"Ride","startDate":"2026-10-07T06:01:00Z",
        "elapsedSeconds":2400,"movingSeconds":2280,"manual":false,"hasHeartrate":true,"maxHeartrate":162}]}
        """
        let decoded = try StravaJSON.decoder.decode(StravaActivitiesResponse.self, from: Data(json.utf8))
        #expect(decoded.activities.count == 1)
        let a = try #require(decoded.activities.first)
        #expect(a.id == "9876543210123")
        #expect(a.movingSeconds == 2280)
        #expect(a.maxHeartrate == 162)
        #expect(a.startDate == ISO8601DateFormatter().date(from: "2026-10-07T06:01:00Z"))
    }

    @Test func decodesNullHeartRate() throws {
        let json = """
        {"activities":[{"id":"1","sportType":"Walk","startDate":"2026-10-07T06:01:00.000Z",
        "elapsedSeconds":1500,"movingSeconds":1400,"manual":true,"hasHeartrate":false,"maxHeartrate":null}]}
        """
        let a = try #require(try StravaJSON.decoder.decode(StravaActivitiesResponse.self, from: Data(json.utf8)).activities.first)
        #expect(a.maxHeartrate == nil)
        #expect(a.manual)
    }

    @Test func mapsFunctionErrors() {
        func body(_ code: String) -> Data { Data("{\"error\":\"\(code)\"}".utf8) }
        #expect(StravaClient.error(status: 404, body: body("not_linked")) == .notLinked)
        #expect(StravaClient.error(status: 410, body: body("revoked")) == .notLinked)
        #expect(StravaClient.error(status: 429, body: body("rate_limited")) == .rateLimited)
        #expect(StravaClient.error(status: 401, body: Data()) == .notConfigured)
        #expect(StravaClient.error(status: 400, body: body("scope_missing")) == .scopeMissing)
        #expect(StravaClient.error(status: 502, body: body("strava_failed")) == .failed)
    }

    @Test func goalEventSourceHasStrava() {
        #expect(GoalEventSource(rawValue: "strava") == .strava)
    }
}
