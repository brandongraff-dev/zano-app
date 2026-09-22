// Core/Sources/Core/Retention/TravelMode.swift
//
// docs/spec.md §5.18 Travel & Comeback Modes:
//   "Travel mode (auto-suggested when the phone is in a new city): goals shift to
//   walking/steps/focus, gym optional."
// docs/spec.md §9.7 Schedule & Travel Awareness:
//   "New city detection (coarse) → Travel mode suggestion. Calendar density (opt-in) → suggest
//   lighter goals on packed days." — "coarse" is this file's load-bearing word (see the location
//   section below); the calendar-density half of §9.7 is a different signal/feature and not this
//   file's job.
// docs/spec.md §8 Retention Psychology Rules, rule 12 ("Friction is the feature, but only where
// the user asked for it"): Travel Mode never activates itself — `recordLocationSample` only ever
// produces a *suggestion*; nothing about goals, lock requirements, or streaks changes until the
// user explicitly calls `acceptTravelMode`. Rule 9 ("No shame"): declining or ignoring the
// suggestion has no penalty anywhere in this file — there is no "streak broken because you didn't
// accept Travel Mode" path.
// docs/spec.md §24 Safety, Legal & App Review ("Location: request 'When in Use' first; 'Always'
// only at gym setup with a clear explanation"): this file never requests location authorization or
// constructs a `CLLocationManager` itself — see the header note under "Cross-module integration"
// below for exactly why and what that implies.
//
// Not part of this task's SYSTEM CONTRACTS list (only `LockEngineManager`, `FocusSessionVerifier`,
// `GymVerifier`, `TimeBankEngine`, `StreakEngine`, `AdaptiveGoalEngine`, and the LiveActivity
// attribute structs have a fixed public shape other agents build against) — this file's public API
// is this task's own design choice, kept deliberately small (CLAUDE.md: "don't add abstractions...
// beyond what the current session's scope requires").
//
// Relationship to `ComebackMode.swift` (this same directory, read for the sibling pattern before
// writing this file): independent by design, same as `ComebackMode`/`StreakEngine` are independent
// of each other. Both files are `@MainActor` singletons that persist a small amount of their own
// state in the App-Group `UserDefaults` suite (never `Store/SharedDefaults.swift` itself — a file
// neither task owns) under a key namespace distinct from every other engine's, and both expose an
// explicit "accept" step rather than silently mutating state on detection. They differ in what
// "accepting" actually changes: `ComebackMode` rewrites `DailyPlan.plannedValue`/`planBValue`
// directly (a *difficulty* change — re-entry needs an easier daily bar) via its own `ModelContext`.
// This file does **not** touch `DailyPlan` at all — Travel Mode isn't about making today's target
// easier, it's about *which goal types are relevant right now* (walking/steps/focus vs. gym), and
// that's a concept `LockSession.requiredGoalIDs` (`LockEngine/LockEngineManager.swift`, read for
// this task, not owned) already owns: whichever call site builds that array is the correct place to
// apply "gym optional," not a `DailyPlan` row. See "Cross-module integration" below.
//
// Relationship to `GymAutoDetect.swift` (`Core/Sources/Core/Verification`, read for this task):
// this file borrows two of its patterns deliberately —
//   1. The "pure, synchronous, side-effect-free algorithm step" + "thin, effectful, persisted-state
//      shell around it" split (`GymAutoDetect.clusterVisits` vs. the class wrapping it). Here,
//      `TravelMode.evaluate(sample:state:)` is that pure step — no `UserDefaults`, no SwiftData, no
//      `Date.now` — so the actual "is this a new city yet" decision is unit-testable without a real
//      device's location stack, per CLAUDE.md rule 5 ("if an Apple API's surface is uncertain...
//      flag it; this environment can't compile-check any of this").
//   2. Public `Sendable` value types (`LocationSample`, `TravelSuggestion`, `TravelModeSession`)
//      store plain `Double` `latitude`/`longitude` fields rather than a raw `CLLocationCoordinate2D`
//      — the same choice `GymCandidate` makes — sidestepping any question about that CoreLocation
//      struct's own `Sendable` conformance on whatever SDK this eventually builds against.
//
// Cross-module integration (this file deliberately does NOT do these things — flagged here and in
// this task's `knownIssues`, mirroring `GymAutoDetect`'s own documented "not this file's job" gap
// for who collects raw `CLVisit`s, and `ComebackMode`'s TODO for `StreakEngine` wiring):
//   1. Location collection: `recordLocationSample(_:)` is pull-based — it takes whatever coarse
//      sample a caller hands it. The intended real source is
//      `CLLocationManager.startMonitoringSignificantLocationChanges()`: Apple's purpose-built,
//      battery-cheap "did the user meaningfully change location" service (cell-tower/Wi-Fi driven,
//      ~500 m-class resolution, not GPS tracking) — this is exactly what spec §9.7 means by
//      "coarse." A future session owns constructing the `CLLocationManager`, handling its delegate
//      callbacks, and requesting authorization (spec §24: "When in Use" first; only Gym Setup ever
//      asks for "Always") — then feeding each delivered `CLLocation` into
//      `TravelMode.shared.recordLocationSample(_:)`. UNVERIFIED: whether significant-location-change
//      updates keep arriving in the background under "When In Use" alone (vs. requiring "Always")
//      varies by iOS version and app state in ways this task cannot check without a device/current
//      Apple docs — flagged in `knownIssues`. Until that collector exists, Travel Mode simply never
//      fires, which is a safe (not broken) default.
//   2. Lock integration: whichever call site builds `LockEngineManager.startLock`'s
//      `requiredGoalIDs` array (Lock Set creation/App Intents, another session) should call
//      `TravelMode.shared.isGymOptional(asOf:)` and, if `true`, exclude that user's `.workoutGym`
//      goal ids from the array — that's the actual mechanism behind spec's "gym optional." This
//      file only exposes the read API and the resolved id lists (`TravelModeSession.
//      optionalGymGoalIDs`/`emphasizedGoalIDs`); it never calls into `LockEngineManager` itself.
//   3. Copy: any "Looks like you're in a new city — switch to Travel Mode?" string belongs in
//      Core/Sources/Core/Copy, not here (CLAUDE.md: no hardcoded user-facing strings outside
//      `Copy`). This file exposes the data (`TravelSuggestion`, incl. a best-effort reverse-
//      geocoded city name once accepted) a `Copy` composer can read from.

import Foundation
import CoreLocation
import SwiftData
import os

/// Detects a sustained "new city" coarse-location signal (docs/spec.md §5.18, §9.7) and, on
/// explicit user acceptance, resolves which of the signed-in user's goals the suggestion applies
/// to: the "walking/steps/focus" set to emphasize, and the `.workoutGym` goals that become
/// optional while the session is active.
///
/// `@MainActor`, matching every other engine in this codebase (`StreakEngine`, `ComebackMode`,
/// `AdaptiveGoalEngine`, `LockEngineManager`) for the same reason each documents at its own
/// declaration: a plain `final class` singleton needs either `Sendable` conformance (unrealistic
/// for a type owning a `ModelContext`) or global-actor isolation under Swift 6 strict concurrency,
/// and every realistic call site is already `@MainActor` or happy to `await` a hop onto it.
@MainActor
public final class TravelMode {
    public static let shared = TravelMode()

    // MARK: - Tunables (spec §5.18, §9.7 give the behavior, not exact numbers — every constant
    // below is this task's own calibration choice, flagged here rather than presented as spec text)

    /// A sample this far from the learned home anchor counts as "a new city," not a longer commute
    /// or a same-metro errand. ~100 miles: comfortably past a typical metro area, well short of
    /// actually needing to be a different country.
    public static let newCityDistanceThresholdMeters: CLLocationDistance = 160_000

    /// Samples within this radius of the learned home anchor are "at home": they refine the anchor
    /// and reset the away streak. Deliberately much smaller than
    /// `newCityDistanceThresholdMeters` so there's a wide neutral band between "home" and "new
    /// city" that does neither — a day trip 60 km out shouldn't quietly widen what counts as home,
    /// nor should it count toward a travel suggestion.
    public static let homeAnchorRadiusMeters: CLLocationDistance = 50_000

    /// How many "at home" samples the running home-anchor average is confident after — below this,
    /// a far-away sample is ignored rather than treated as "away" (protects a brand-new install,
    /// or a user who hasn't been home long enough yet to learn where home is, from a false
    /// suggestion on day one).
    public static let homeAnchorMinimumSamples = 3

    /// Caps the running average's effective sample weight so a home anchor that's been stable for
    /// months doesn't become permanently frozen — without this, sample #500's influence on the mean
    /// would be 1/500th, and a genuine permanent relocation could never out-vote years of history.
    /// Capping the weight keeps the anchor able to drift again after roughly this many "at home"
    /// samples following a sustained move, while still being very stable short-term.
    public static let homeAnchorMaxWeight = 60

    /// A single stray coarse fix (a bad cell-tower handoff, a layover) shouldn't flip the
    /// suggestion on by itself — the away signal must hold for this many consecutive qualifying
    /// samples. Not also time-windowed: `startMonitoringSignificantLocationChanges()` already only
    /// fires on genuine location changes, spaced naturally apart, so a same-direction second
    /// sample is itself already meaningful corroboration.
    public static let sustainedSampleCount = 2

    /// Spec §5.18's "walking/steps/focus," mapped onto the real `GoalType` catalog
    /// (`Core/Sources/Core/Models/Goal.swift`, read for this task, not redefined here): "walking"
    /// reads as `.workoutHomeOutdoor` (its own doc comment: "Home/outdoor workout... Core Motion
    /// active minutes" — the closest existing case to an unstructured walk, since there is no
    /// separate "walking" case), "steps" as `.steps`, "focus" as `.focusSession`. This mapping is
    /// this task's own reading of the prose, not exact spec text.
    public static let suggestedGoalTypes: [GoalType] = [.workoutHomeOutdoor, .steps, .focusSession]

    /// Spec §5.18's "gym optional."
    public static let optionalGoalType: GoalType = .workoutGym

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "TravelMode")

    /// Separate, App-Group-backed `UserDefaults` instance (same suite `Store/SharedDefaults.swift`
    /// uses, a different file this task does not own) — same convention `ComebackMode`/
    /// `StreakEngine` already use for their own small pieces of state that have nowhere else to
    /// live (no SwiftData model for a learned home anchor or an in-progress travel suggestion
    /// exists, and adding one is out of this task's file list). Keyed distinctly from every key
    /// those two files or `SharedDefaults` define so none of them can ever collide despite sharing
    /// the same underlying suite.
    private let travelDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum DefaultsKey {
        static let homeLatitude = "com.zano.app.travelMode.homeLatitude"
        static let homeLongitude = "com.zano.app.travelMode.homeLongitude"
        static let homeSampleCount = "com.zano.app.travelMode.homeSampleCount"
        static let awayStreakCount = "com.zano.app.travelMode.awayStreakCount"
        static let dismissedForCurrentTrip = "com.zano.app.travelMode.dismissedForCurrentTrip"
        static let pendingDetectedAt = "com.zano.app.travelMode.pending.detectedAt"
        static let pendingLatitude = "com.zano.app.travelMode.pending.latitude"
        static let pendingLongitude = "com.zano.app.travelMode.pending.longitude"
        static let pendingDistanceMeters = "com.zano.app.travelMode.pending.distanceMeters"
        static let activeStartDate = "com.zano.app.travelMode.active.startDate"
        static let activeCity = "com.zano.app.travelMode.active.city"
        static let activeDistanceMeters = "com.zano.app.travelMode.active.distanceMeters"
    }

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public shape

    /// One coarse location update, reduced to the plain `Sendable`-trivial fields this file's
    /// algorithm needs, taken right at the boundary the same way `GymAutoDetect.QualifyingVisit`
    /// reduces `CLVisit` — see this file's header note on why `latitude`/`longitude: Double`
    /// rather than a raw `CLLocationCoordinate2D`.
    public struct LocationSample: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double
        /// Meters; Apple's documented sentinel for "invalid fix" is negative (mirrors
        /// `GymAutoDetect`'s own `horizontalAccuracy > 0` check).
        public let horizontalAccuracy: CLLocationAccuracy
        public let timestamp: Date

        public init(latitude: Double, longitude: Double, horizontalAccuracy: CLLocationAccuracy, timestamp: Date = .now) {
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.timestamp = timestamp
        }
    }

    /// A detected-but-not-yet-accepted "you're in a new city" signal.
    public struct TravelSuggestion: Sendable, Equatable {
        public let detectedAt: Date
        public let latitude: Double
        public let longitude: Double
        public let distanceFromHomeMeters: Double
    }

    /// An accepted, in-progress Travel Mode session.
    public struct TravelModeSession: Sendable, Equatable {
        public let startDate: Date
        /// Best-effort reverse-geocoded locality (`nil` if geocoding failed or hasn't resolved) —
        /// never blocks acceptance; see `reverseGeocodeCityName(latitude:longitude:)`.
        public let detectedCity: String?
        public let distanceFromHomeMeters: Double
        /// `Goal.id`s of the signed-in user's active goals whose type is in
        /// `TravelMode.suggestedGoalTypes` — spec's "goals shift to walking/steps/focus."
        public let emphasizedGoalIDs: [UUID]
        /// `Goal.id`s of the signed-in user's active `.workoutGym` goals — spec's "gym optional."
        /// Still exist, still completable, just not required while this session is active; see
        /// this file's header note on the `LockEngineManager.requiredGoalIDs` integration point.
        public let optionalGymGoalIDs: [UUID]
    }

    // MARK: - Signal algorithm (pure, testable — mirrors `GymAutoDetect.clusterVisits`'s split)

    /// Everything `TravelMode` has learned so far, with no `UserDefaults`, no SwiftData, and no
    /// wall-clock reads of its own — a plain snapshot ``evaluate(sample:state:)`` reads and
    /// produces a new copy of.
    public struct TravelSignalState: Sendable, Equatable {
        public var homeLatitude: Double?
        public var homeLongitude: Double?
        public var homeSampleCount: Int
        public var awayStreakCount: Int
        public var hasPendingSuggestion: Bool
        public var isDismissedForCurrentTrip: Bool
        public var hasActiveSession: Bool

        public init(
            homeLatitude: Double? = nil,
            homeLongitude: Double? = nil,
            homeSampleCount: Int = 0,
            awayStreakCount: Int = 0,
            hasPendingSuggestion: Bool = false,
            isDismissedForCurrentTrip: Bool = false,
            hasActiveSession: Bool = false
        ) {
            self.homeLatitude = homeLatitude
            self.homeLongitude = homeLongitude
            self.homeSampleCount = homeSampleCount
            self.awayStreakCount = awayStreakCount
            self.hasPendingSuggestion = hasPendingSuggestion
            self.isDismissedForCurrentTrip = isDismissedForCurrentTrip
            self.hasActiveSession = hasActiveSession
        }
    }

    /// What ``evaluate(sample:state:)`` decided to do with one new sample.
    public enum TravelSignalOutcome: Sendable, Equatable {
        /// Home anchor seeded or refined; nothing else changed.
        case refinedHome
        /// Sample didn't change anything — an invalid fix, a mid-distance sample (neither clearly
        /// home nor clearly a new city), an unconfident home anchor, or a suggestion/session
        /// already pending/active/dismissed for this trip.
        case ignored
        /// Away streak advanced but hasn't reached `TravelMode.sustainedSampleCount` yet.
        case awayStreakAdvanced(count: Int)
        /// Crossed the sustained-away threshold — a new suggestion should be surfaced.
        case newSuggestion(TravelSuggestion)
        /// A sample landed back within the home radius while a suggestion/session/dismissal was
        /// outstanding — that state should be cleared.
        case returnedHome
    }

    /// Pure, synchronous, side-effect-free — see this file's header note on why this is split out
    /// from `recordLocationSample`. `nonisolated`: it touches no actor-isolated state (everything
    /// it needs is a parameter), so it's callable (and unit-testable) without a `@MainActor` hop.
    nonisolated public static func evaluate(
        sample: LocationSample,
        state: TravelSignalState
    ) -> (TravelSignalState, TravelSignalOutcome) {
        guard sample.horizontalAccuracy > 0 else { return (state, .ignored) } // negative = invalid fix

        var next = state

        guard let homeLat = state.homeLatitude, let homeLng = state.homeLongitude else {
            // No home learned yet at all — this sample seeds it outright.
            next.homeLatitude = sample.latitude
            next.homeLongitude = sample.longitude
            next.homeSampleCount = 1
            return (next, .refinedHome)
        }

        let home = CLLocation(latitude: homeLat, longitude: homeLng)
        let here = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
        let distance = home.distance(from: here)

        if distance <= Self.homeAnchorRadiusMeters {
            // "At home": refine the running-average anchor (same technique
            // `GymAutoDetect.VisitCluster.add` uses), capped so a long-stable anchor can still
            // drift after a genuine relocation — see `homeAnchorMaxWeight`'s doc comment.
            let weight = min(state.homeSampleCount, Self.homeAnchorMaxWeight)
            let n = Double(weight + 1)
            next.homeLatitude = homeLat + (sample.latitude - homeLat) / n
            next.homeLongitude = homeLng + (sample.longitude - homeLng) / n
            next.homeSampleCount = min(state.homeSampleCount + 1, Self.homeAnchorMaxWeight)
            next.awayStreakCount = 0

            let hadSomethingToClear = state.hasActiveSession || state.hasPendingSuggestion || state.isDismissedForCurrentTrip
            next.hasActiveSession = false
            next.hasPendingSuggestion = false
            next.isDismissedForCurrentTrip = false
            return (next, hadSomethingToClear ? .returnedHome : .refinedHome)
        }

        guard distance >= Self.newCityDistanceThresholdMeters else {
            return (next, .ignored) // outside the home radius, but not far enough to be "a new city."
        }
        guard state.homeSampleCount >= Self.homeAnchorMinimumSamples else {
            return (next, .ignored) // home anchor isn't confident enough yet to call anything "away."
        }
        guard !state.hasActiveSession, !state.hasPendingSuggestion, !state.isDismissedForCurrentTrip else {
            return (next, .ignored) // already suggested/active/dismissed for this same trip.
        }

        next.awayStreakCount = state.awayStreakCount + 1
        guard next.awayStreakCount >= Self.sustainedSampleCount else {
            return (next, .awayStreakAdvanced(count: next.awayStreakCount))
        }

        let suggestion = TravelSuggestion(
            detectedAt: sample.timestamp,
            latitude: sample.latitude,
            longitude: sample.longitude,
            distanceFromHomeMeters: distance
        )
        next.hasPendingSuggestion = true
        return (next, .newSuggestion(suggestion))
    }

    // MARK: - Public API

    /// Feed one coarse location update in. Persists whatever `evaluate` decided and returns a
    /// freshly-crossed-the-threshold suggestion, if this call is the one that produced it — `nil`
    /// otherwise (including when a suggestion was already pending from an earlier call; use
    /// `pendingSuggestion(asOf:)` to re-read that without waiting for a new sample).
    @discardableResult
    public func recordLocationSample(_ sample: LocationSample) async -> TravelSuggestion? {
        let previous = loadSignalState()
        let (next, outcome) = Self.evaluate(sample: sample, state: previous)
        saveSignalState(next)

        switch outcome {
        case .newSuggestion(let suggestion):
            persistPendingSuggestion(suggestion)
            logger.notice("Travel Mode: new-city suggestion at distance \(suggestion.distanceFromHomeMeters, privacy: .public)m.")
            return suggestion
        case .returnedHome:
            clearPendingSuggestionDefaults()
            clearActiveSessionDefaults()
            logger.notice("Travel Mode: back near home — cleared any pending suggestion/active session.")
            return nil
        case .refinedHome, .ignored, .awayStreakAdvanced:
            return nil
        }
    }

    /// The currently pending (not yet accepted or dismissed) suggestion, if any — independent of
    /// whichever `recordLocationSample` call originally produced it, so a relaunched app (or a UI
    /// surface other than the one that got the live callback) can still show it.
    public func pendingSuggestion(asOf date: Date = .now) async -> TravelSuggestion? {
        guard let detectedAt = travelDefaults.object(forKey: DefaultsKey.pendingDetectedAt) as? Date else {
            return nil
        }
        return TravelSuggestion(
            detectedAt: detectedAt,
            latitude: travelDefaults.double(forKey: DefaultsKey.pendingLatitude),
            longitude: travelDefaults.double(forKey: DefaultsKey.pendingLongitude),
            distanceFromHomeMeters: travelDefaults.double(forKey: DefaultsKey.pendingDistanceMeters)
        )
    }

    /// "Not now" — spec §8 rule 9 ("no shame"): this has no penalty anywhere in this file, it just
    /// stops re-suggesting for the rest of this same trip (until a sample lands back near home,
    /// which re-arms it for a future trip — see `evaluate`'s `.returnedHome` case).
    public func dismissSuggestion() async {
        guard travelDefaults.object(forKey: DefaultsKey.pendingDetectedAt) != nil else { return }
        clearPendingSuggestionDefaults()
        travelDefaults.set(true, forKey: DefaultsKey.dismissedForCurrentTrip)
    }

    /// The user tapped "Switch to Travel Mode." Resolves the goal ids the pending suggestion
    /// applies to and persists an active session. Throws rather than silently no-op-ing (unlike
    /// this file's read-only methods) because a caller explicitly asking to *accept* something
    /// needs to know why it couldn't, mirroring `ComebackMode.startChallengeIfEligible`'s own
    /// `throws` convention for the same reason.
    @discardableResult
    public func acceptTravelMode(on date: Date = .now) async throws -> TravelModeSession {
        guard let suggestion = await pendingSuggestion(asOf: date) else {
            throw TravelModeError.noPendingSuggestion
        }
        guard await activeSession(asOf: date) == nil else {
            throw TravelModeError.alreadyActive
        }
        let user = try fetchCurrentUser()
        let emphasizedIDs = fetchActiveGoals(userID: user.id, types: Set(Self.suggestedGoalTypes)).map(\.id)
        let optionalGymIDs = fetchActiveGoals(userID: user.id, types: [Self.optionalGoalType]).map(\.id)
        let city = await Self.reverseGeocodeCityName(latitude: suggestion.latitude, longitude: suggestion.longitude)

        clearPendingSuggestionDefaults()
        travelDefaults.set(false, forKey: DefaultsKey.dismissedForCurrentTrip)
        travelDefaults.set(date, forKey: DefaultsKey.activeStartDate)
        travelDefaults.set(suggestion.distanceFromHomeMeters, forKey: DefaultsKey.activeDistanceMeters)
        if let city {
            travelDefaults.set(city, forKey: DefaultsKey.activeCity)
        } else {
            travelDefaults.removeObject(forKey: DefaultsKey.activeCity)
        }

        logger.notice(
            "Travel Mode accepted: \(emphasizedIDs.count, privacy: .public) emphasized goal(s), \(optionalGymIDs.count, privacy: .public) gym goal(s) now optional."
        )
        return TravelModeSession(
            startDate: date,
            detectedCity: city,
            distanceFromHomeMeters: suggestion.distanceFromHomeMeters,
            emphasizedGoalIDs: emphasizedIDs,
            optionalGymGoalIDs: optionalGymIDs
        )
    }

    /// The currently active session, if any. Re-resolves `emphasizedGoalIDs`/`optionalGymGoalIDs`
    /// live on every call rather than trusting a stale snapshot from `acceptTravelMode` — the same
    /// choice `ComebackMode.activeChallenge` makes (deriving `goalIDs` live each call) and for the
    /// same reason: a goal added, deactivated, or retyped mid-trip should be reflected immediately,
    /// not just at the moment the user tapped "accept."
    public func activeSession(asOf date: Date = .now) async -> TravelModeSession? {
        guard let start = travelDefaults.object(forKey: DefaultsKey.activeStartDate) as? Date else {
            return nil
        }
        let distance = travelDefaults.double(forKey: DefaultsKey.activeDistanceMeters)
        let city = travelDefaults.string(forKey: DefaultsKey.activeCity)
        guard let user = try? fetchCurrentUser() else {
            return TravelModeSession(
                startDate: start, detectedCity: city, distanceFromHomeMeters: distance,
                emphasizedGoalIDs: [], optionalGymGoalIDs: []
            )
        }
        return TravelModeSession(
            startDate: start,
            detectedCity: city,
            distanceFromHomeMeters: distance,
            emphasizedGoalIDs: fetchActiveGoals(userID: user.id, types: Set(Self.suggestedGoalTypes)).map(\.id),
            optionalGymGoalIDs: fetchActiveGoals(userID: user.id, types: [Self.optionalGoalType]).map(\.id)
        )
    }

    /// Ends the active session (the user returned and dismissed it manually, or some other call
    /// site decided the trip is over). A sample landing back near the learned home anchor also
    /// clears it automatically via `recordLocationSample`'s `.returnedHome` outcome — this method
    /// is for the explicit, no-new-sample-required path (e.g. a Settings toggle, or a trip that
    /// ends somewhere `evaluate` never sees a sample from again because location permission was
    /// revoked mid-trip — see `knownIssues`). No-op if nothing is active.
    public func endTravelMode(on date: Date = .now) async {
        guard travelDefaults.object(forKey: DefaultsKey.activeStartDate) != nil else { return }
        clearActiveSessionDefaults()
        travelDefaults.set(0, forKey: DefaultsKey.awayStreakCount)
        logger.notice("Travel Mode ended.")
    }

    /// Cross-module read API (see this file's header note): `true` while a Travel Mode session is
    /// active, meaning whichever call site builds `LockEngineManager.startLock`'s
    /// `requiredGoalIDs` should treat the user's `.workoutGym` goals as not required. Never throws:
    /// mirrors every other read-only method in this codebase's engines.
    public func isGymOptional(asOf date: Date = .now) async -> Bool {
        await activeSession(asOf: date) != nil
    }

    // MARK: - Reverse geocoding (best-effort city-name enrichment, spec §5.18/§9.7 copy support)

    /// Resolves a coordinate to a locality name for display copy (composed in `Copy`, not here —
    /// see this file's header note). Runs once, only at `acceptTravelMode` time, not on every
    /// sample: this is the one network-backed step in this file, unlike everything else here which
    /// is pure/local math.
    ///
    /// UNVERIFIED (no Mac/compiler this task — CLAUDE.md rule 5): this task's training-knowledge
    /// best guess is that `CLGeocoder.reverseGeocodeLocation(_:)` has had an `async throws ->
    /// [CLPlacemark]` overload since iOS 15, comfortably under this package's iOS 17 minimum, but
    /// that has not been checked against current Apple documentation. If that overload doesn't
    /// exist as written on whatever SDK this actually builds against, fall back to the completion-
    /// handler `reverseGeocodeLocation(_:completionHandler:)` wrapped in `withCheckedContinuation`
    /// — the same adaptation `GymAutoDetect.hasElevatedHeartRate` already applies in this codebase
    /// for HealthKit's older callback API.
    private static func reverseGeocodeCityName(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return placemark.locality ?? placemark.administrativeArea ?? placemark.country
        } catch {
            // Best-effort only — a failed/timed-out geocode must never block acceptance itself.
            return nil
        }
    }

    // MARK: - UserDefaults persistence

    private func loadSignalState() -> TravelSignalState {
        let hasHome = travelDefaults.object(forKey: DefaultsKey.homeLatitude) != nil
        return TravelSignalState(
            homeLatitude: hasHome ? travelDefaults.double(forKey: DefaultsKey.homeLatitude) : nil,
            homeLongitude: hasHome ? travelDefaults.double(forKey: DefaultsKey.homeLongitude) : nil,
            homeSampleCount: travelDefaults.integer(forKey: DefaultsKey.homeSampleCount),
            awayStreakCount: travelDefaults.integer(forKey: DefaultsKey.awayStreakCount),
            hasPendingSuggestion: travelDefaults.object(forKey: DefaultsKey.pendingDetectedAt) != nil,
            isDismissedForCurrentTrip: travelDefaults.bool(forKey: DefaultsKey.dismissedForCurrentTrip),
            hasActiveSession: travelDefaults.object(forKey: DefaultsKey.activeStartDate) != nil
        )
    }

    /// Persists only the home-anchor/away-streak/dismissed fields. The pending-suggestion and
    /// active-session *payloads* (lat/lng/distance/city) are written separately by
    /// `persistPendingSuggestion`/`acceptTravelMode` — this only ever clears them here (via the
    /// `hasPendingSuggestion`/`hasActiveSession` booleans going `false`), it never sets them,
    /// since this state snapshot doesn't carry their full payload.
    private func saveSignalState(_ state: TravelSignalState) {
        if let lat = state.homeLatitude, let lng = state.homeLongitude {
            travelDefaults.set(lat, forKey: DefaultsKey.homeLatitude)
            travelDefaults.set(lng, forKey: DefaultsKey.homeLongitude)
        }
        travelDefaults.set(state.homeSampleCount, forKey: DefaultsKey.homeSampleCount)
        travelDefaults.set(state.awayStreakCount, forKey: DefaultsKey.awayStreakCount)
        travelDefaults.set(state.isDismissedForCurrentTrip, forKey: DefaultsKey.dismissedForCurrentTrip)
        if !state.hasPendingSuggestion {
            clearPendingSuggestionDefaults()
        }
        if !state.hasActiveSession {
            clearActiveSessionDefaults()
        }
    }

    private func persistPendingSuggestion(_ suggestion: TravelSuggestion) {
        travelDefaults.set(suggestion.detectedAt, forKey: DefaultsKey.pendingDetectedAt)
        travelDefaults.set(suggestion.latitude, forKey: DefaultsKey.pendingLatitude)
        travelDefaults.set(suggestion.longitude, forKey: DefaultsKey.pendingLongitude)
        travelDefaults.set(suggestion.distanceFromHomeMeters, forKey: DefaultsKey.pendingDistanceMeters)
    }

    private func clearPendingSuggestionDefaults() {
        travelDefaults.removeObject(forKey: DefaultsKey.pendingDetectedAt)
        travelDefaults.removeObject(forKey: DefaultsKey.pendingLatitude)
        travelDefaults.removeObject(forKey: DefaultsKey.pendingLongitude)
        travelDefaults.removeObject(forKey: DefaultsKey.pendingDistanceMeters)
    }

    private func clearActiveSessionDefaults() {
        travelDefaults.removeObject(forKey: DefaultsKey.activeStartDate)
        travelDefaults.removeObject(forKey: DefaultsKey.activeCity)
        travelDefaults.removeObject(forKey: DefaultsKey.activeDistanceMeters)
    }

    // MARK: - SwiftData

    /// Filters the `type`/`user` relationship in plain Swift after a `Bool`-only `#Predicate`
    /// fetch — the same conservative choice `ComebackMode.fetchActiveAdaptiveGoals` and
    /// `LockEngineManager.isGoalVerified` document: no Mac/Swift toolchain in this task to
    /// compile-verify `#Predicate`'s handling of a `CaseIterable` raw-value enum or optional-
    /// relationship chaining on this SDK version.
    private func fetchActiveGoals(userID: UUID, types: Set<GoalType>) -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active == true })
        guard let goals = try? context.fetch(descriptor) else { return [] }
        return goals.filter { $0.user?.id == userID && types.contains($0.type) }
    }

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `LockEngineManager.fetchCurrentUser()`/`StreakEngine.fetchCurrentUser()`/
    /// `ComebackMode.fetchCurrentUser()` use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw TravelModeError.noSignedInUser
        }
        return user
    }
}

/// Thrown only by `TravelMode.acceptTravelMode`/its private `fetchCurrentUser()`. Every other
/// public method on `TravelMode` swallows a missing-user/fetch failure and returns a safe default
/// (`nil`/`false`/an empty session) rather than throwing — mirroring `ComebackMode`'s and
/// `StreakEngine`'s own convention that only an explicit "start/accept" action needs to know why it
/// couldn't happen.
enum TravelModeError: Error, Sendable, LocalizedError {
    case noPendingSuggestion
    case alreadyActive
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noPendingSuggestion: "No pending Travel Mode suggestion to accept."
        case .alreadyActive: "Travel Mode is already active."
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
