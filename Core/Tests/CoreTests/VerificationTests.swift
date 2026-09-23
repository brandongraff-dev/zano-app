// Core/Tests/CoreTests/VerificationTests.swift
//
// Tests the pure-logic pieces of Core/Sources/Core/Verification/{GymVerifier,GymAutoDetect,
// FocusSessionVerifier,MotionAntiCheat}.swift — the ones that don't require a live GPS/HealthKit/
// Motion signal to exercise. All four source files were read in full before writing this.
//
// Scope, and why it stops where it does (this task's brief: "pure-logic pieces that do not
// require a live GPS/HealthKit/Motion signal"):
//
//   - GymVerifier.swift: only `GymVerificationDefaults` (plain public constants) is pure.
//     `GymVerifier`'s own `isVerified`/`currentDwellMinutes`/`beginDwellTracking` all forward to
//     `GymDwellState`, a private `actor` that talks to a live `CLMonitor`, `CMMotionActivityManager`,
//     `HKHealthStore`, and fetches from `ModelContainer.appGroup` (a real App Group container this
//     test process has no entitlement for) — none of that is reachable here without a device.
//     `DwellSession`, the type that actually does the dwell-minutes-from-a-time-interval math, is
//     `private` to GymVerifier.swift, so it isn't visible even to `@testable import Core` from this
//     file. See `GymVerificationDefaultsTests` below.
//
//   - GymAutoDetect.swift: `clusterVisits(_:now:lookbackDays:)` is documented on the type itself as
//     "pure, synchronous, side-effect-free" over plain data — exactly what's under test in
//     `GymAutoDetectThresholdTests` below, including the two spec-sourced thresholds named in this
//     task (§9.4: min dwell 40 min, recurring ≥2×/14 days). `enrichWithHealthKitSignal` (live
//     HealthKit I/O) and the `fileprivate` `confidence(visitCount:averageDwellMinutes:)` formula
//     (not visible outside GymAutoDetect.swift) are out of scope for the same reason as GymVerifier.
//
//   - FocusSessionVerifier.swift: every method is `@MainActor` and touches ActivityKit
//     (`Activity<FocusActivityAttributes>.request`) and SwiftData (`ModelContainer.appGroup` by
//     default in its designated init). Nothing in this file is a free function over plain data —
//     even `elapsedActiveSeconds(asOf:)`'s pause-aware math lives on `RunningSession`, a `private`
//     nested struct of `FocusSessionVerifier` that this file can't reach. Excluded entirely per this
//     task's brief; there is no live-signal-free surface here to test.
//
//   - MotionAntiCheat.swift: `MotionAntiCheat`'s own `isLikelyAutomotive`/`recentActivities` both
//     call live CoreMotion (`CMMotionActivityManager`) and are excluded. `TapRateLimiter` — the
//     other type in this same file — is the pure piece this task names explicitly ("TapRateLimiter's
//     rate-limit math"): a plain `actor` over `Date`/`Int` arithmetic with zero framework I/O, so
//     it's tested exhaustively in `TapRateLimiterTests` below.

import Foundation
import CoreLocation
import Testing
@testable import Core

// MARK: - Shared deterministic fixtures

/// A fixed reference instant (2025-01-01T00:00:00Z) so every test below is deterministic —
/// clustering/rate-limit math is date-arithmetic-heavy, and neither `GymAutoDetect.clusterVisits`
/// nor `TapRateLimiter.evaluate` should ever be exercised against `Date()`/`.now` in a test.
private let fixedNow = Date(timeIntervalSince1970: 1_735_689_600)

/// UTC, not `.current` — a test that ran `TimeZone.current`-dependent day-boundary math would pass
/// or fail depending on the machine/CI runner's local time zone. `TapRateLimiter.evaluate`'s own
/// `calendar` parameter exists specifically so callers (including this file) can pin this down.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

// MARK: - GymVerificationDefaults (docs/spec.md §3, "Workout (gym)" row)

@Suite("GymVerificationDefaults")
struct GymVerificationDefaultsTests {
    @Test("default required dwell is 35 minutes, per spec §3's \"minimum dwell (default 35 min)\"")
    func requiredDwellMinutesMatchesSpec() {
        #expect(GymVerificationDefaults.requiredDwellMinutes == 35)
    }

    @Test("elevated-HR threshold is a physiologically sane BPM value")
    func elevatedHeartRateBPMIsSane() {
        // Not spec-sourced — GymVerifier.swift's own doc comment says as much ("Not sourced from
        // the spec verbatim ... a reasonable resting-exceeding threshold"). This isn't pinning an
        // exact product-decided number, just guarding against an accidental unit slip (e.g. a
        // future edit typing 10.0 or 1000.0 instead of a real BPM value).
        #expect(GymVerificationDefaults.elevatedHeartRateBPM > 60)
        #expect(GymVerificationDefaults.elevatedHeartRateBPM < 200)
    }
}

// MARK: - GymAutoDetect (docs/spec.md §9.4)

/// docs/spec.md §9.4 clustering runs over `CLVisit`, a system-populated Core Location value object
/// with no public parameterized initializer (Apple only vends real `CLVisit`s via
/// `CLLocationManagerDelegate.locationManager(_:didVisit:)`). This subclass is the standard
/// workaround: `CLVisit`'s designated `init()` is inherited, unmodified, from `NSObject` (Apple does
/// not mark it `unavailable`), and its four data properties are declared `open var … { get }` —
/// `open`, specifically, meaning overridable outside the defining module — which a subclass can
/// override with its own stored values.
///
/// **UNVERIFIED** (CLAUDE.md working rule 5 — no Mac/Xcode in this environment to check against the
/// live SDK): whether `CLVisit()` actually succeeds at runtime with usable (non-crashing) defaults
/// for the properties this subclass doesn't touch, and whether overriding these four get-only
/// properties compiles cleanly under Swift 6, could not be confirmed here. Flagged explicitly in
/// this task's `knownIssues`. If this doesn't compile/run on a real toolchain, every
/// `GymAutoDetectThresholdTests` test that builds a `MockVisit` (all but
/// `publishedConstantsMatchSpec`) is what needs fixing or removing first — the constants test alone
/// is unaffected and should keep passing regardless.
private final class MockVisit: CLVisit {
    private let mockArrivalDate: Date
    private let mockDepartureDate: Date
    private let mockCoordinate: CLLocationCoordinate2D
    private let mockHorizontalAccuracy: CLLocationAccuracy

    init(
        arrivalDate: Date,
        departureDate: Date,
        coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy = 15
    ) {
        self.mockArrivalDate = arrivalDate
        self.mockDepartureDate = departureDate
        self.mockCoordinate = coordinate
        self.mockHorizontalAccuracy = horizontalAccuracy
        super.init()
    }

    override var arrivalDate: Date { mockArrivalDate }
    override var departureDate: Date { mockDepartureDate }
    override var coordinate: CLLocationCoordinate2D { mockCoordinate }
    override var horizontalAccuracy: CLLocationAccuracy { mockHorizontalAccuracy }
}

@Suite("GymAutoDetect clustering")
struct GymAutoDetectThresholdTests {
    /// San Francisco-ish; the exact coordinate is arbitrary, only offsets relative to it matter.
    private let siteA = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    /// ~880 m east of `siteA` at this latitude (0.01° longitude × ~111,320 m/° × cos(37.77°)) —
    /// comfortably outside `GymAutoDetect.clusterRadiusMeters` (120 m), so visits here must form a
    /// separate cluster rather than merging with `siteA`.
    private let siteB = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4094)
    /// ~22 m north of `siteA` (0.0002° latitude × ~111,320 m/°) — well inside the 120 m cluster
    /// radius, standing in for ordinary GPS jitter between two real visits to the same gym.
    private let siteAJittered = CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4194)

    private func makeVisit(
        daysAgo: Int,
        dwellMinutes: Int,
        coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy = 15,
        now: Date = fixedNow
    ) -> MockVisit {
        let arrival = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: now)!
        let departure = arrival.addingTimeInterval(TimeInterval(dwellMinutes * 60))
        return MockVisit(arrivalDate: arrival, departureDate: departure, coordinate: coordinate, horizontalAccuracy: horizontalAccuracy)
    }

    @Test("published thresholds match spec §9.4 verbatim: min dwell 40 min, recurring ≥2×/14 days")
    func publishedConstantsMatchSpec() {
        #expect(GymAutoDetect.minimumDwellMinutes == 40)
        #expect(GymAutoDetect.minimumRecurringVisits == 2)
        #expect(GymAutoDetect.lookbackDays == 14)
    }

    @Test("two 40+ min visits to the same place, 14 days apart, cluster into one candidate")
    func recurringQualifyingVisitsFormOneCandidate() {
        let visits = [
            makeVisit(daysAgo: 10, dwellMinutes: 45, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 50, coordinate: siteA),
        ]
        let candidates = GymAutoDetect.shared.clusterVisits(visits, now: fixedNow)
        #expect(candidates.count == 1)
        #expect(candidates.first?.visitCount == 2)
        // (45 + 50) / 2 == 47, integer division per `VisitCluster.makeCandidate()`.
        #expect(candidates.first?.averageDwellMinutes == 47)
    }

    @Test("a dwell of exactly 40 minutes (the spec §9.4 boundary) qualifies")
    func exactlyMinimumDwellQualifies() {
        let visits = [
            makeVisit(daysAgo: 10, dwellMinutes: 40, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 40, coordinate: siteA),
        ]
        #expect(GymAutoDetect.shared.clusterVisits(visits, now: fixedNow).count == 1)
    }

    @Test("a dwell of 39 minutes (one under the spec §9.4 boundary) never qualifies, however often it recurs")
    func belowMinimumDwellNeverQualifies() {
        let visits = [
            makeVisit(daysAgo: 12, dwellMinutes: 39, coordinate: siteA),
            makeVisit(daysAgo: 8, dwellMinutes: 39, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 39, coordinate: siteA),
        ]
        #expect(GymAutoDetect.shared.clusterVisits(visits, now: fixedNow).isEmpty)
    }

    @Test("a single qualifying visit (only 1 occurrence) is not \"recurring\" and is excluded")
    func singleVisitIsNotRecurring() {
        let visits = [makeVisit(daysAgo: 5, dwellMinutes: 60, coordinate: siteA)]
        #expect(GymAutoDetect.shared.clusterVisits(visits, now: fixedNow).isEmpty)
    }

    @Test("a visit older than the 14-day lookback doesn't count toward recurrence")
    func visitsOutsideLookbackWindowAreExcluded() {
        let visits = [
            makeVisit(daysAgo: 20, dwellMinutes: 45, coordinate: siteA), // outside the 14-day window
            makeVisit(daysAgo: 3, dwellMinutes: 45, coordinate: siteA),  // the only visit inside it
        ]
        // Only one qualifying visit remains once the 20-day-old one is dropped by the lookback —
        // below `minimumRecurringVisits` (2), so the whole cluster is filtered out.
        #expect(GymAutoDetect.shared.clusterVisits(visits, now: fixedNow).isEmpty)
    }

    @Test("visits ~880 m apart form two separate clusters, not one")
    func distantVisitsFormSeparateClusters() {
        let visits = [
            makeVisit(daysAgo: 10, dwellMinutes: 45, coordinate: siteA),
            makeVisit(daysAgo: 8, dwellMinutes: 45, coordinate: siteB),
            makeVisit(daysAgo: 5, dwellMinutes: 45, coordinate: siteA),
            makeVisit(daysAgo: 2, dwellMinutes: 45, coordinate: siteB),
        ]
        let candidates = GymAutoDetect.shared.clusterVisits(visits, now: fixedNow)
        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.visitCount == 2 })
    }

    @Test("visits ~22 m apart (ordinary GPS jitter) merge into a single cluster")
    func nearbyJitteredVisitsMergeIntoOneCluster() {
        let visits = [
            makeVisit(daysAgo: 10, dwellMinutes: 45, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 45, coordinate: siteAJittered),
        ]
        let candidates = GymAutoDetect.shared.clusterVisits(visits, now: fixedNow)
        #expect(candidates.count == 1)
        #expect(candidates.first?.visitCount == 2)
    }

    @Test("an ongoing visit (departureDate == .distantFuture) measures dwell against `now`, not a fixed departure")
    func ongoingVisitMeasuresDwellAgainstNow() {
        let ongoingArrival = fixedNow.addingTimeInterval(-50 * 60) // 50 minutes before `now`
        let ongoingVisit = MockVisit(arrivalDate: ongoingArrival, departureDate: .distantFuture, coordinate: siteA)
        let priorVisit = makeVisit(daysAgo: 5, dwellMinutes: 45, coordinate: siteA)

        let candidates = GymAutoDetect.shared.clusterVisits([priorVisit, ongoingVisit], now: fixedNow)
        #expect(candidates.count == 1)
        #expect(candidates.first?.visitCount == 2)
    }

    @Test("a visit with an invalid (negative) horizontal accuracy is excluded as an invalid fix")
    func invalidHorizontalAccuracyIsExcluded() {
        let invalidVisit = makeVisit(daysAgo: 5, dwellMinutes: 45, coordinate: siteA, horizontalAccuracy: -1)
        let validVisit = makeVisit(daysAgo: 2, dwellMinutes: 45, coordinate: siteA)

        // Only one *valid* qualifying visit remains — below the recurring threshold.
        #expect(GymAutoDetect.shared.clusterVisits([invalidVisit, validVisit], now: fixedNow).isEmpty)
    }

    @Test("candidates are sorted by descending confidence: more/longer visits ranks first")
    func candidatesSortByDescendingConfidence() {
        let visits = [
            makeVisit(daysAgo: 12, dwellMinutes: 90, coordinate: siteA), // 4 long visits: high confidence
            makeVisit(daysAgo: 9, dwellMinutes: 90, coordinate: siteA),
            makeVisit(daysAgo: 6, dwellMinutes: 90, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 90, coordinate: siteA),
            makeVisit(daysAgo: 10, dwellMinutes: 40, coordinate: siteB), // 2 minimum-length visits: lower confidence
            makeVisit(daysAgo: 4, dwellMinutes: 40, coordinate: siteB),
        ]
        let candidates = GymAutoDetect.shared.clusterVisits(visits, now: fixedNow)
        #expect(candidates.count == 2)
        #expect(candidates.first?.visitCount == 4)
        #expect(candidates.last?.visitCount == 2)
        if let first = candidates.first, let last = candidates.last {
            #expect(first.confidence > last.confidence)
        }
    }

    @Test("a fresh GymCandidate defaults hasElevatedHeartRateSignal to false until enrichWithHealthKitSignal runs")
    func candidateDefaultsToNoHeartRateSignal() {
        let visits = [
            makeVisit(daysAgo: 10, dwellMinutes: 45, coordinate: siteA),
            makeVisit(daysAgo: 3, dwellMinutes: 45, coordinate: siteA),
        ]
        let candidates = GymAutoDetect.shared.clusterVisits(visits, now: fixedNow)
        #expect(candidates.first?.hasElevatedHeartRateSignal == false)
    }
}

// MARK: - TapRateLimiter (docs/spec.md §3 anti-cheat column: Protein/Water/Creatine; §9.8)

@Suite("TapRateLimiter")
struct TapRateLimiterTests {
    @Test("named presets match spec §3's anti-cheat column")
    func presetPoliciesMatchSpec() {
        // Water: "Tap rate limit (no 8 taps in a minute)", no daily cap.
        #expect(TapRateLimiter.Policy.water == TapRateLimiter.Policy(maxTapsPerMinute: 8, maxTapsPerDay: nil))
        // Creatine: "1 per day" is spec-exact.
        #expect(TapRateLimiter.Policy.creatine == TapRateLimiter.Policy(maxTapsPerMinute: 8, maxTapsPerDay: 1))
        // Protein: spec only says "daily cap on identical NFC taps" with no number — this file's
        // own doc comment says 6 is its assumption, not a spec-sourced value. Asserting the encoded
        // value here (not claiming it's spec-exact) so a silent future change to it is caught.
        #expect(TapRateLimiter.Policy.protein == TapRateLimiter.Policy(maxTapsPerMinute: 8, maxTapsPerDay: 6))
    }

    @Test("water: 8 taps within a minute are allowed, the 9th in that same window is rejected as too fast")
    func waterBurstLimitBoundary() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        for i in 0..<8 {
            let verdict = await limiter.evaluate(key: key, policy: .water, at: fixedNow.addingTimeInterval(Double(i)))
            #expect(verdict.isAllowed, "tap \(i + 1) of 8 should be allowed")
        }
        let ninth = await limiter.evaluate(key: key, policy: .water, at: fixedNow.addingTimeInterval(8))
        #expect(ninth == .reject(.tooFast))
    }

    @Test("water: taps that have aged out of the trailing 60s window don't count against the burst limit")
    func waterBurstWindowRolls() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        for i in 0..<8 {
            _ = await limiter.evaluate(key: key, policy: .water, at: fixedNow.addingTimeInterval(Double(i)))
        }
        // 61s after the *first* tap, all 8 have aged out of the trailing 60s window.
        let later = await limiter.evaluate(key: key, policy: .water, at: fixedNow.addingTimeInterval(61))
        #expect(later.isAllowed)
    }

    @Test("creatine: exactly 1 tap per day per spec §3; a second same-day tap is rejected, the next day resets")
    func creatineDailyCapOfOne() async {
        let limiter = TapRateLimiter()
        let key = UUID()

        let first = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow, calendar: utcCalendar)
        #expect(first == .allow(tapsRemainingToday: 0))

        let secondSameDay = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow.addingTimeInterval(120), calendar: utcCalendar)
        #expect(secondSameDay == .reject(.dailyCapReached))

        let nextDay = utcCalendar.date(byAdding: .day, value: 1, to: fixedNow)!
        let thirdNextDay = await limiter.evaluate(key: key, policy: .creatine, at: nextDay, calendar: utcCalendar)
        #expect(thirdNextDay == .allow(tapsRemainingToday: 0))
    }

    @Test("protein: 6/day cap (this file's own documented default) counts down correctly and then rejects")
    func proteinDailyCapCountsDown() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        var remaining: [Int?] = []
        // Spaced an hour apart so the per-minute burst limit never interferes — isolating this
        // test to the daily-cap axis only.
        for i in 0..<6 {
            let verdict = await limiter.evaluate(key: key, policy: .protein, at: fixedNow.addingTimeInterval(Double(i) * 3600), calendar: utcCalendar)
            if case .allow(let tapsRemainingToday) = verdict {
                remaining.append(tapsRemainingToday)
            } else {
                Issue.record("tap \(i + 1) of 6 should be allowed, got \(verdict)")
            }
        }
        #expect(remaining == [5, 4, 3, 2, 1, 0])

        let seventh = await limiter.evaluate(key: key, policy: .protein, at: fixedNow.addingTimeInterval(6 * 3600), calendar: utcCalendar)
        #expect(seventh == .reject(.dailyCapReached))
    }

    @Test("knownTapsToday (authoritative GoalEvent count) overrides this actor's own in-memory counter")
    func knownTapsTodayOverridesInternalCounter() async {
        let limiter = TapRateLimiter()
        let key = UUID()

        // This actor's own counter is still 0 (nothing evaluated yet), but the caller already
        // knows — from real GoalEvent rows, per the type's persistence-note doc comment — that
        // today's protein cap has already been met.
        let verdict = await limiter.evaluate(key: key, policy: .protein, knownTapsToday: 6, at: fixedNow, calendar: utcCalendar)
        #expect(verdict == .reject(.dailyCapReached))

        // knownTapsToday re-syncs the internal counter even on a rejection — a later call that
        // omits it should see the same authoritative count, not fall back to a stale/zero value.
        let later = await limiter.evaluate(key: key, policy: .protein, at: fixedNow.addingTimeInterval(3600), calendar: utcCalendar)
        #expect(later == .reject(.dailyCapReached))
    }

    @Test("a tap rejected for being too fast is never counted against the daily cap")
    func tooFastRejectionDoesNotConsumeDailyCap() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        let tightPolicy = TapRateLimiter.Policy(maxTapsPerMinute: 1, maxTapsPerDay: 5)

        let first = await limiter.evaluate(key: key, policy: tightPolicy, at: fixedNow, calendar: utcCalendar)
        #expect(first == .allow(tapsRemainingToday: 4))

        // Same second: burst-rejected before the daily counter is ever touched.
        let second = await limiter.evaluate(key: key, policy: tightPolicy, at: fixedNow.addingTimeInterval(1), calendar: utcCalendar)
        #expect(second == .reject(.tooFast))

        // Once the burst window has cleared, the daily count should read 1 used / 4 remaining —
        // not 2 used — proving the rejected tap above was never recorded.
        let third = await limiter.evaluate(key: key, policy: tightPolicy, at: fixedNow.addingTimeInterval(120), calendar: utcCalendar)
        #expect(third == .allow(tapsRemainingToday: 3))
    }

    @Test("tapsRemainingToday(for:) is a pure read — calling it never itself consumes the daily allowance")
    func tapsRemainingTodayDoesNotMutateState() async {
        let limiter = TapRateLimiter()
        let key = UUID()

        let before = await limiter.tapsRemainingToday(for: key, policy: .creatine, on: fixedNow, calendar: utcCalendar)
        #expect(before == 1)
        let beforeAgain = await limiter.tapsRemainingToday(for: key, policy: .creatine, on: fixedNow, calendar: utcCalendar)
        #expect(beforeAgain == 1)

        let tap = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow, calendar: utcCalendar)
        #expect(tap == .allow(tapsRemainingToday: 0))

        let after = await limiter.tapsRemainingToday(for: key, policy: .creatine, on: fixedNow, calendar: utcCalendar)
        #expect(after == 0)
    }

    @Test("reset(key:) clears both the rolling burst window and the daily counter")
    func resetClearsAllTrackedState() async {
        let limiter = TapRateLimiter()
        let key = UUID()

        let first = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow, calendar: utcCalendar)
        #expect(first == .allow(tapsRemainingToday: 0))
        let capped = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow.addingTimeInterval(60), calendar: utcCalendar)
        #expect(capped == .reject(.dailyCapReached))

        await limiter.reset(key: key)

        let afterReset = await limiter.evaluate(key: key, policy: .creatine, at: fixedNow.addingTimeInterval(120), calendar: utcCalendar)
        #expect(afterReset == .allow(tapsRemainingToday: 0))
    }

    @Test("two different keys (goals) are rate-limited completely independently")
    func perKeyIndependence() async {
        let limiter = TapRateLimiter()
        let keyA = UUID()
        let keyB = UUID()

        let a1 = await limiter.evaluate(key: keyA, policy: .creatine, at: fixedNow, calendar: utcCalendar)
        #expect(a1 == .allow(tapsRemainingToday: 0))
        // keyB's own creatine cap must be untouched by keyA's tap.
        let b1 = await limiter.evaluate(key: keyB, policy: .creatine, at: fixedNow, calendar: utcCalendar)
        #expect(b1 == .allow(tapsRemainingToday: 0))
    }

    @Test("a policy with no daily cap (nil, e.g. Water) never rejects for dailyCapReached, however many taps land")
    func noDailyCapNeverRejectsOnCount() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        // Spaced 61s apart so every tap also clears the burst window, isolating this test to the
        // daily-cap axis only.
        for i in 0..<20 {
            let verdict = await limiter.evaluate(key: key, policy: .water, at: fixedNow.addingTimeInterval(Double(i) * 61), calendar: utcCalendar)
            #expect(verdict == .allow(tapsRemainingToday: nil), "tap \(i + 1) with no daily cap should always allow")
        }
        let remaining = await limiter.tapsRemainingToday(for: key, policy: .water, on: fixedNow, calendar: utcCalendar)
        #expect(remaining == nil)
    }

    @Test("the daily cap resets at local calendar-day boundaries, not a rolling 24h window")
    func dailyCapResetsAtCalendarBoundaryNotRollingWindow() async {
        let limiter = TapRateLimiter()
        let key = UUID()
        let lateNightComponents = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 1, day: 1, hour: 23, minute: 59, second: 59
        )
        let lateNight = utcCalendar.date(from: lateNightComponents)!

        let first = await limiter.evaluate(key: key, policy: .creatine, at: lateNight, calendar: utcCalendar)
        #expect(first == .allow(tapsRemainingToday: 0))

        // Two seconds later, but past local midnight: a new calendar day, so the cap must have
        // reset even though far less than 24 rolling hours elapsed since the first tap.
        let justAfterMidnight = lateNight.addingTimeInterval(2)
        let second = await limiter.evaluate(key: key, policy: .creatine, at: justAfterMidnight, calendar: utcCalendar)
        #expect(second == .allow(tapsRemainingToday: 0))
    }

    @Test("Verdict.isAllowed reflects .allow/.reject correctly")
    func verdictIsAllowedComputedProperty() {
        #expect(TapRateLimiter.Verdict.allow(tapsRemainingToday: nil).isAllowed)
        #expect(TapRateLimiter.Verdict.allow(tapsRemainingToday: 3).isAllowed)
        #expect(!TapRateLimiter.Verdict.reject(.tooFast).isAllowed)
        #expect(!TapRateLimiter.Verdict.reject(.dailyCapReached).isAllowed)
    }
}
