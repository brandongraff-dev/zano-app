// MotionAntiCheat.swift
// Core / Verification
//
// Two small, framework-decoupled anti-cheat primitives shared by every Tier A/B goal verifier
// (docs/spec.md §3 "Goal Catalog & Verification" — the "Anti-cheat" column — and §9.8 "Anti-Cheat
// Signals"). Both types live in this one file because this session owns exactly this file
// (`Core/Sources/Core/Verification/MotionAntiCheat.swift`) and neither type is large enough to
// justify asking for a second file:
//
//   - `MotionAntiCheat`   — a `CMMotionActivityManager` wrapper answering "is the user likely in a
//                           moving vehicle right now?" for gym-arrival / dwell verification
//                           (spec §3 "Workout (gym)" row: "can't be in car (Core Motion
//                           automotive)"; §9.4 Gym Auto-Detection: "Core Motion not automotive").
//   - `TapRateLimiter`    — a generic, reusable rate limiter for any tap-based goal (spec §3
//                           "Protein"/"Water"/"Creatine" rows: NFC-tap or widget-button taps).
//                           Enforces both a rolling per-minute burst limit ("no 8 taps in a
//                           minute") and an optional daily cap ("1 per day").
//
// docs/spec.md §9.8 is explicit about tone: "Never accuse — just don't count, and show 'not
// counted: too quick' transparently." Per CLAUDE.md, user-facing copy lives only in
// `Core/Sources/Core/Copy`, so neither type below renders or hardcodes that (or any) string —
// they return typed verdicts/reasons; whichever Copy/Intents-layer code turns a rejection into
// shield/toast text owns the exact wording.
//
// Both types fail *open* (never block, never throw, never accuse) whenever a signal is
// unavailable — permission denied, hardware absent, query error. That matches CLAUDE.md's "any
// lock/shield feature must always keep an emergency-unlock path. Never trap the user." and §9.8's
// "never accuse": a missed cheat is an acceptable cost here; a falsely blocked legitimate unlock
// is not.
//
// Call sites for other Verification-layer / Intents-layer code (per this session's own contract,
// since neither type appears in the shared SYSTEM CONTRACTS block):
//
//   let isDriving = await MotionAntiCheat.shared.isLikelyAutomotive()
//
//   let verdict = await TapRateLimiter.shared.evaluate(
//       key: goal.id,
//       policy: .water,                       // or .creatine / .protein / a custom Policy
//       knownTapsToday: todaysVerifiedTapCount // count of today's GoalEvents for this goal, if
//                                              // the caller already has SwiftData access;
//                                              // omit to fall back to this actor's own
//                                              // in-memory count (see TapRateLimiter doc below)
//   )
//   switch verdict {
//   case .allow: // proceed to record the GoalEvent
//   case .reject(let reason): // don't record it; hand `reason` to the Copy layer for messaging
//   }

import CoreMotion
import Foundation

// MARK: - MotionAntiCheat

/// Wraps `CMMotionActivityManager` to answer one question other verifiers need for anti-cheat
/// (docs/spec.md §3, §9.4, §9.8): is the user's device currently showing signs of being in a
/// moving vehicle, as opposed to actually walking into/being at a gym?
///
/// `CMMotionActivityManager` predates Swift 6 and is not marked `Sendable` by the SDK, even
/// though Apple documents `queryActivityStarting(from:to:to:withHandler:)` and
/// `startActivityUpdates(to:withHandler:)` as safe to invoke from any thread/queue — the handler
/// simply runs on whichever `OperationQueue` you pass in. That's the same "documented-safe,
/// SDK-not-yet-Sendable-annotated" situation `Store/SharedDefaults.swift` already calls out for
/// `UserDefaults`; this file mirrors that same `nonisolated(unsafe)` pattern rather than
/// inventing a new one.
public final class MotionAntiCheat: Sendable {

    public static let shared = MotionAntiCheat()

    /// Created once here and never reassigned afterward; see the type-level doc comment for why
    /// `nonisolated(unsafe)` is appropriate for this SDK type.
    nonisolated(unsafe) private let manager = CMMotionActivityManager()

    /// Serial (`maxConcurrentOperationCount = 1`) so concurrent `recentActivities` callers can't
    /// have their completion closures race each other; CoreMotion itself does the actual work off
    /// this queue and only delivers results on it.
    nonisolated(unsafe) private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.zano.core.motionAntiCheat"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// Backs `isDeviceFlat` — see that method's doc comment and `AccelerometerFlatnessState`
    /// (bottom of this file) for why the device-flat check gets its own actor-isolated state
    /// instead of sharing `manager`/`queue` above (those back `CMMotionActivityManager`, a
    /// different, stateless-per-query CoreMotion class).
    private let flatnessState = AccelerometerFlatnessState()

    private init() {}

    /// `false` on devices without the motion coprocessor Core Motion activity classification
    /// needs (per Apple's documentation, notably some iPads). Check before relying on any other
    /// method here returning a meaningful (as opposed to always-`false`) answer.
    public var isActivityAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    /// Current Core Motion authorization state. `CMMotionActivityManager` has no explicit
    /// "request authorization" call — unlike `CLLocationManager`, the system permission prompt is
    /// triggered automatically the first time `queryActivityStarting`/`startActivityUpdates` is
    /// actually invoked while the status is `.notDetermined`. Exposed so a caller that wants to
    /// gate its own UI (e.g. explain *why* it's about to prompt) can check first without
    /// side-effecting anything.
    public var authorizationStatus: CMAuthorizationStatus {
        CMMotionActivityManager.authorizationStatus()
    }

    /// A `Sendable` snapshot of a `CMMotionActivity` sample. `CMMotionActivity` itself is an
    /// `NSObject` subclass the SDK doesn't mark `Sendable`, so results are copied into this value
    /// type inside the query's completion handler before ever crossing back out to a caller —
    /// avoiding handing a non-`Sendable` reference type across the `async` boundary.
    public struct MotionActivitySample: Sendable, Equatable {
        public let date: Date
        public let automotive: Bool
        public let stationary: Bool
        public let walking: Bool
        public let running: Bool
        public let cycling: Bool
        /// `true` when `CMMotionActivity.confidence == .low` — Apple's own guidance is to treat
        /// low-confidence samples as too unreliable to act on.
        public let isLowConfidence: Bool

        init(_ activity: CMMotionActivity) {
            date = activity.startDate
            automotive = activity.automotive
            stationary = activity.stationary
            walking = activity.walking
            running = activity.running
            cycling = activity.cycling
            isLowConfidence = activity.confidence == .low
        }
    }

    /// Raw activity history for the trailing `lookback` seconds (default 3 minutes), oldest
    /// first — matching the order `CMMotionActivityManager` itself returns. Most callers should
    /// just use `isLikelyAutomotive(lookback:)`; this is exposed for verifiers (e.g. `GymVerifier`,
    /// owned elsewhere) that want more than a yes/no answer, such as a confidence trend across the
    /// dwell window.
    ///
    /// Returns `[]` when activity data is unavailable, authorization was denied/restricted, or the
    /// query fails — never throws (see the type-level doc comment on failing open).
    public func recentActivities(lookback: TimeInterval = 180) async -> [MotionActivitySample] {
        guard isActivityAvailable else { return [] }
        let status = authorizationStatus
        guard status == .authorized || status == .notDetermined else { return [] }

        let end = Date()
        let start = end.addingTimeInterval(-lookback)
        return await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: start, to: end, to: queue) { activities, _ in
                // Errors (including "permission just got denied mid-query") are swallowed by
                // design — an empty result reads as "no automotive signal found", which is the
                // fail-open behavior this whole file commits to.
                let samples = (activities ?? []).map(MotionActivitySample.init)
                continuation.resume(returning: samples)
            }
        }
    }

    /// Best-effort "is the user likely in a moving vehicle right now?" check (docs/spec.md §3
    /// "Workout (gym)" anti-cheat column; §9.4 Gym Auto-Detection: "Core Motion not automotive").
    ///
    /// Looks at the most recent non-low-confidence sample within `lookback` seconds (default 3
    /// minutes) and returns whether it was classified `automotive`. Returns `false` — i.e. "not
    /// flagged as automotive" — whenever the signal simply isn't available (no coprocessor,
    /// permission denied/restricted, no samples in the window, or every sample in the window is
    /// low-confidence). That's a deliberate fail-open default: per §9.8 ("never accuse") and
    /// CLAUDE.md ("never trap the user"), a missing signal must never block a real unlock.
    ///
    /// - Parameter lookback: How far back to look for the most recent usable sample. Defaults to
    ///   180 seconds, wide enough to cover the last-mile walk from a car into a gym without
    ///   reaching back into an unrelated earlier drive.
    public func isLikelyAutomotive(lookback: TimeInterval = 180) async -> Bool {
        let samples = await recentActivities(lookback: lookback)
        guard let latest = samples.reversed().first(where: { !$0.isLowConfidence }) else {
            return false
        }
        return latest.automotive
    }

    /// Best-effort "is the device currently lying flat (screen up or screen down) on a surface?"
    /// check, for the Stretch/mobility goal's device-flat anti-cheat signal (docs/spec.md §3
    /// "Stretch / mobility" row: "guided 5-min timer with device flat on floor (accelerometer
    /// check)"; anti-cheat column: "Device orientation"). `StretchVerifier`
    /// (`Core/Sources/Core/Verification/StretchVerifier.swift`) is this method's only call site as
    /// of this writing — added onto this existing type rather than forking a second motion-utility
    /// file, per that session's own task instructions.
    ///
    /// Uses raw accelerometer data (`CMMotionManager`), not `CMMotionActivityManager` (the class
    /// `MotionAntiCheat` otherwise wraps): Apple's motion-activity classifier has no
    /// "flat"/orientation signal, only coarse walking/running/automotive/cycling/stationary
    /// buckets, so a literal device-orientation check needs the separate, lower-level
    /// accelerometer API. Both live on this one type because they answer the same *kind* of
    /// question ("what is CoreMotion telling us about the device's current physical state, for
    /// anti-cheat purposes?") even though they're backed by different CoreMotion classes — see
    /// `AccelerometerFlatnessState` at the bottom of this file for the actual `CMMotionManager`
    /// state, kept separate from `manager`/`queue` above because it needs actor-isolated
    /// start/stop serialization those don't.
    ///
    /// Computes the tilt angle between the device's measured acceleration vector and its
    /// screen-normal (z) axis — `0°` is perfectly flat, `90°` is on-edge vertical — and returns
    /// whether that's within `toleranceDegrees`. Deliberately agnostic to screen-up vs.
    /// screen-down (a stretch mat is on the floor; either face is a legitimate "set the phone
    /// down" orientation) and to the accelerometer's face-up-vs-face-down sign convention, since
    /// the calculation only uses `abs(z)`.
    ///
    /// - Parameter toleranceDegrees: How far from perfectly flat still counts as "flat". `25` is
    ///   this file's own assumption (uneven floors/rugs, not a perfectly level surface) — spec §3
    ///   says only "device flat on floor", no exact tolerance. Flagged in knownIssues for a
    ///   product-feel pass once a device is available to test on.
    /// - Returns: `true` — fail-open, per this whole file's convention (see header comment) —
    ///   when the accelerometer is unavailable, a read is already in flight (see
    ///   `AccelerometerFlatnessState`), or no sample arrived in time. `false` only on an actual,
    ///   successfully-measured tilt beyond tolerance.
    public func isDeviceFlat(toleranceDegrees: Double = 25) async -> Bool {
        await flatnessState.isDeviceFlat(toleranceDegrees: toleranceDegrees)
    }
}

// MARK: - AccelerometerFlatnessState

/// Owns the one `CMMotionManager` instance backing `MotionAntiCheat.isDeviceFlat` and serializes
/// access to it. An `actor` (same rationale as `TapRateLimiter` below: the idiomatic Swift 6 way
/// to serialize concurrent mutable access without hand-rolled locking) because
/// `CMMotionManager.startAccelerometerUpdates()`/`stopAccelerometerUpdates()` is a single-handler,
/// stateful start/stop pair — two overlapping start/stop cycles racing each other (e.g. two
/// `StretchVerifier` tick-loop samples firing close together, or two concurrent callers) would
/// corrupt each other's reading, not just harmlessly duplicate work the way two concurrent
/// `CMMotionActivityManager` queries would.
///
/// Apple recommends keeping a single `CMMotionManager` per app rather than creating one per call
/// site; this type is that single instance for the device-flat check specifically (`GymVerifier`
/// separately owns its own `CMMotionActivityManager`-only anti-cheat state and never touches raw
/// accelerometer data, so there's no second instance to consolidate with here).
private actor AccelerometerFlatnessState {
    private let motionManager = CMMotionManager()

    /// Guards against actor reentrancy across the `Task.sleep` below: a second `isDeviceFlat` call
    /// arriving while one is already mid-sample fails open (returns `true`) rather than racing the
    /// first call's start/stop pair. Set before the only `await` in `isDeviceFlat`, so a reentrant
    /// call during that suspension reliably observes it.
    private var isSampling = false

    func isDeviceFlat(toleranceDegrees: Double) async -> Bool {
        guard motionManager.isAccelerometerAvailable else { return true }
        guard !isSampling else { return true }

        isSampling = true
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates()
        defer {
            motionManager.stopAccelerometerUpdates()
            isSampling = false
        }

        // Pull-based read (no handler closure): `startAccelerometerUpdates()` begins populating
        // `accelerometerData` asynchronously; give the sensor a brief moment to deliver its first
        // sample before reading it once. This sidesteps the handler-based API's "closure fires
        // repeatedly, must guard against resuming a checked continuation twice" hazard entirely.
        try? await Task.sleep(for: .milliseconds(250))

        guard let acceleration = motionManager.accelerometerData?.acceleration else { return true }
        return Self.tiltFromFlatDegrees(acceleration) <= toleranceDegrees
    }

    /// Angle (degrees) between the measured acceleration vector and the device's z axis
    /// (perpendicular to the screen). `0` = perfectly flat face-up or face-down; `90` = on edge.
    /// Uses `abs(z)` so it doesn't matter which face is up, or which sign convention this SDK
    /// version uses for that axis.
    private static func tiltFromFlatDegrees(_ acceleration: CMAcceleration) -> Double {
        let horizontalMagnitude = (acceleration.x * acceleration.x + acceleration.y * acceleration.y).squareRoot()
        let radians = atan2(horizontalMagnitude, abs(acceleration.z))
        return radians * 180 / .pi
    }
}

// MARK: - TapRateLimiter

/// Generic, reusable rate limiter for any tap-based goal verification — docs/spec.md §3: Protein
/// ("Daily cap on identical NFC taps"), Water ("Tap rate limit (no 8 taps in a minute)"),
/// Creatine ("1 per day"); §9.8: "Rate limits on taps ... Never accuse — just don't count."
///
/// Not tied to NFC specifically, or to any one goal type — call it from an NFC tap handler, a
/// widget button `AppIntent`, or anywhere else a raw "the user just tapped to log this goal"
/// event originates, keyed by whatever `UUID` identifies that goal/source to the caller (in
/// practice, `Goal.id`).
///
/// An `actor` rather than a plain class: this type's whole job is serializing concurrent mutable
/// access to per-key tap history (an NFC tap and a widget-button tap for the same goal can
/// plausibly race each other), and Swift's actor isolation is the idiomatic Swift 6 way to make
/// that safe without hand-rolled locking.
///
/// **Persistence note:** this actor's own daily counters are in-memory and process-local — they
/// reset whenever the app process is relaunched, which iOS does often. That's fine for the
/// rolling per-minute burst check (a 60-second window rarely spans a process restart), but a
/// *durable* daily cap should ultimately be backed by counting today's `GoalEvent` rows for that
/// goal (the actual source of truth, per `Core/Sources/Core/Models/GoalEvent.swift`). Callers that
/// have SwiftData access should pass that authoritative count via `knownTapsToday`; callers that
/// don't (e.g. a lightweight NFC delegate callback before any SwiftData write) can omit it and
/// get a reasonable, if restart-resettable, best effort from this actor's own counter.
public actor TapRateLimiter {

    public static let shared = TapRateLimiter()

    /// The two knobs docs/spec.md §3's anti-cheat column uses per goal type, bundled so a caller
    /// can pass one value instead of two.
    public struct Policy: Sendable, Equatable {
        /// Max accepted taps within any trailing 60-second window. Spec §3's Water row is the
        /// literal source for the default: "no 8 taps in a minute".
        public var maxTapsPerMinute: Int
        /// Max accepted taps per local calendar day, or `nil` for no daily cap.
        public var maxTapsPerDay: Int?

        public init(maxTapsPerMinute: Int = 8, maxTapsPerDay: Int? = nil) {
            self.maxTapsPerMinute = maxTapsPerMinute
            self.maxTapsPerDay = maxTapsPerDay
        }

        /// docs/spec.md §3 "Water" row. No daily cap — legitimate hydration happens many times a
        /// day; only the burst limit applies.
        public static let water = Policy(maxTapsPerMinute: 8, maxTapsPerDay: nil)

        /// docs/spec.md §3 "Creatine / supplement" row: "1 per day" is spec-exact.
        public static let creatine = Policy(maxTapsPerMinute: 8, maxTapsPerDay: 1)

        /// docs/spec.md §3 "Protein" row says "Daily cap on identical NFC taps" but does not pin
        /// an exact number the way Creatine's row does. `6` below is this file's own assumption —
        /// generous enough for several real shaker/tub taps across a day, low enough to catch
        /// someone tapping the same shaker forty times — not a value sourced from spec.md. Flagged
        /// in this task's knownIssues; tune with real usage data or an explicit product decision
        /// rather than treating it as settled.
        public static let protein = Policy(maxTapsPerMinute: 8, maxTapsPerDay: 6)
    }

    /// Why a tap was rejected. Intentionally not a `String` — per CLAUDE.md, user-facing copy
    /// (including spec §9.8's exact "not counted: too quick" wording) lives only in
    /// `Core/Sources/Core/Copy`; whichever layer owns that mapping translates this case into text.
    public enum RejectionReason: Sendable, Equatable {
        /// More than `Policy.maxTapsPerMinute` taps landed in the trailing 60-second window.
        case tooFast
        /// `Policy.maxTapsPerDay` (or the caller-supplied `knownTapsToday`) has already been met
        /// or exceeded for today.
        case dailyCapReached
    }

    public enum Verdict: Sendable, Equatable {
        /// The tap may be recorded. `tapsRemainingToday` is `nil` when the policy has no daily
        /// cap, otherwise how many more taps are allowed today *after* this one.
        case allow(tapsRemainingToday: Int?)
        case reject(RejectionReason)

        public var isAllowed: Bool {
            switch self {
            case .allow: return true
            case .reject: return false
            }
        }
    }

    private struct DailyCount {
        var day: Date
        var count: Int
    }

    /// Per-key rolling tap timestamps, pruned to the trailing 60 seconds on every `evaluate`.
    private var recentTaps: [UUID: [Date]] = [:]
    /// Per-key in-memory daily counter fallback — see the type-level doc comment's persistence
    /// note for why this is a fallback rather than the source of truth.
    private var dailyCounts: [UUID: DailyCount] = [:]

    public init() {}

    /// Evaluates (and, if allowed, records) one tap for `key` against `policy`.
    ///
    /// - Parameters:
    ///   - key: Identifies the goal/source this tap belongs to — in practice `Goal.id`. Different
    ///     keys are tracked completely independently, so one `TapRateLimiter` instance can safely
    ///     back every tap-based goal at once.
    ///   - policy: Which limits to apply. Defaults to `Policy()` (8/minute, no daily cap); prefer
    ///     one of the named presets (`.water`, `.creatine`, `.protein`) or a custom `Policy` for a
    ///     goal with its own configured cap.
    ///   - knownTapsToday: The caller's own authoritative count of taps already accepted today for
    ///     this `key` (e.g. from today's verified `GoalEvent` rows), if it has one. When supplied,
    ///     it replaces this actor's in-memory counter for the daily-cap check (and re-syncs the
    ///     counter to match) rather than being merely added to it — pass the *total* count so far
    ///     today, not just this call's increment. When omitted, falls back to this actor's own
    ///     process-local counter (see the type-level persistence note).
    ///   - date: The tap's timestamp. Defaults to `Date()`; parameterized so this stays
    ///     deterministically testable.
    ///   - calendar: Calendar used to compute "today" for the daily cap. Defaults to `.current`.
    /// - Returns: `.allow` if the tap is accepted (and it has now been recorded against both the
    ///   per-minute and daily counters), or `.reject` with the reason if not — a rejected tap is
    ///   never recorded, so it doesn't count against either limit.
    @discardableResult
    public func evaluate(
        key: UUID,
        policy: Policy = Policy(),
        knownTapsToday: Int? = nil,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Verdict {
        // 1. Rolling per-minute burst check (spec §3 Water row; §9.8 "rate limits on taps").
        let windowStart = date.addingTimeInterval(-60)
        var timestamps = (recentTaps[key] ?? []).filter { $0 > windowStart }
        if timestamps.count >= policy.maxTapsPerMinute {
            // Keep the pruned window even on rejection so a burst doesn't keep growing unbounded
            // in memory while someone hammers the tag.
            recentTaps[key] = timestamps
            return .reject(.tooFast)
        }

        // 2. Daily cap check (spec §3 Creatine "1 per day" / Protein "daily cap").
        let today = calendar.startOfDay(for: date)
        let existing = dailyCounts[key]
        let countBeforeThisTap: Int
        if let knownTapsToday {
            countBeforeThisTap = knownTapsToday
        } else if let existing, existing.day == today {
            countBeforeThisTap = existing.count
        } else {
            countBeforeThisTap = 0
        }

        if let cap = policy.maxTapsPerDay, countBeforeThisTap >= cap {
            dailyCounts[key] = DailyCount(day: today, count: countBeforeThisTap)
            return .reject(.dailyCapReached)
        }

        // Accepted — record against both windows.
        timestamps.append(date)
        recentTaps[key] = timestamps
        let newCount = countBeforeThisTap + 1
        dailyCounts[key] = DailyCount(day: today, count: newCount)

        let remaining = policy.maxTapsPerDay.map { max(0, $0 - newCount) }
        return .allow(tapsRemainingToday: remaining)
    }

    /// How many more taps `key` may make today under `policy` without changing any state —
    /// useful for UI ("2 taps left today") without side-effecting the counters the way
    /// `evaluate` does. `nil` means "no daily cap" (mirrors `Policy.maxTapsPerDay`); the returned
    /// `Int` is never negative.
    public func tapsRemainingToday(
        for key: UUID,
        policy: Policy,
        knownTapsToday: Int? = nil,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        guard let cap = policy.maxTapsPerDay else { return nil }
        let today = calendar.startOfDay(for: date)
        let count: Int
        if let knownTapsToday {
            count = knownTapsToday
        } else if let existing = dailyCounts[key], existing.day == today {
            count = existing.count
        } else {
            count = 0
        }
        return max(0, cap - count)
    }

    /// Clears all tracked state for `key` (both the rolling window and the daily counter).
    /// Intended for tests and for handling an explicit "undo my last log" flow, not for normal
    /// verification traffic.
    public func reset(key: UUID) {
        recentTaps[key] = nil
        dailyCounts[key] = nil
    }
}
