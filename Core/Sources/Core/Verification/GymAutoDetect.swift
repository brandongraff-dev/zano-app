// Core/Sources/Core/Verification/GymAutoDetect.swift
//
// docs/spec.md §9.4 "Gym Auto-Detection":
//   "Cluster CLVisits (DBSCAN on lat/lon, min dwell 40 min, recurring ≥ 2×/14 days) → candidate
//   places. If HealthKit HR was elevated during visits → confidence up. Ask once: 'Is this your
//   gym?' Store as geofence."
//   "Anti-cheat: dwell inside radius, Core Motion not automotive, optional HR."
// Feeds docs/spec.md §3's "Workout (gym)" row and §4 v1 scope: "Gym setup: pick on map OR
// auto-detect suggestion ('Is this your gym?')". `GymVerifier.swift` (same session/folder) is
// the live-tracking counterpart this module's output eventually gets tracked by, once a
// candidate is confirmed into a `Gym` row.
//
// This file's public shape is NOT fixed by the orchestrator's CONTRACTS block (only
// GymVerifier/TimeBankEngine/etc. are) — it is this session's own design, documented thoroughly
// since Gym Setup (another session) is expected to call it by reading this file rather than a
// shared contract.
//
// Anti-cheat note: the "Core Motion not automotive" / "dwell inside radius" checks from spec
// §9.4's anti-cheat line are `GymVerifier`'s job (they apply to a *live*, in-progress dwell
// session with a real region to check against) — this file only clusters *historical* `CLVisit`
// dwell/recurrence, which is the one anti-cheat signal that makes sense before a geofence even
// exists yet to check "inside radius" against.

import Foundation
import CoreLocation
import HealthKit
import os

/// One clustered, candidate gym location surfaced by ``GymAutoDetect`` — not yet a saved `Gym`
/// row. Gym Setup is expected to turn an accepted candidate into
/// `Gym(userID: <signed-in user's id>, lat: latitude, lng: longitude, radiusMeters:
/// suggestedRadiusMeters, name: ..., autoDetected: true, confirmed: true)` via the "Is this your
/// gym?" prompt (spec §9.4), or simply discard it on "No". (`Gym.init`'s `userID` parameter has
/// no default — `Core/Sources/Core/Models/Gym.swift` — so it must be supplied explicitly; this
/// type has no reference to the signed-in user to fill it in itself.)
public struct GymCandidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    /// Suggested geofence radius in meters, derived from the visit cluster's own GPS accuracy
    /// spread and clamped to a sane range (spec §3 anti-cheat: "parking-lot detection via GPS
    /// accuracy radius" — too generous a radius risks catching the parking lot or the road next
    /// to the gym). Gym Setup should let the user drag-adjust this before confirming; this is a
    /// starting point, not a final answer.
    public let suggestedRadiusMeters: Int
    /// How many qualifying visits (≥ `GymAutoDetect.minimumDwellMinutes`, within the lookback
    /// window) landed in this cluster.
    public let visitCount: Int
    public let averageDwellMinutes: Int
    public let firstVisitDate: Date
    public let lastVisitDate: Date
    /// `true` if at least one clustered visit overlapped a HealthKit-reported elevated heart
    /// rate window — spec §9.4: "If HealthKit HR was elevated during visits → confidence up."
    /// `false` until/unless ``GymAutoDetect/enrichWithHealthKitSignal(_:)`` has run — this method
    /// never sets it itself, since HealthKit access needs `async`/a live `HKHealthStore` query
    /// (see that method's doc comment).
    public let hasElevatedHeartRateSignal: Bool
    /// `0...1`, used only to sort/prioritize candidates for the "Is this your gym?" prompt — Gym
    /// Setup decides its own UI cutoff for what to surface (e.g. only show the top one or two).
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        suggestedRadiusMeters: Int,
        visitCount: Int,
        averageDwellMinutes: Int,
        firstVisitDate: Date,
        lastVisitDate: Date,
        hasElevatedHeartRateSignal: Bool = false,
        confidence: Double
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.suggestedRadiusMeters = suggestedRadiusMeters
        self.visitCount = visitCount
        self.averageDwellMinutes = averageDwellMinutes
        self.firstVisitDate = firstVisitDate
        self.lastVisitDate = lastVisitDate
        self.hasElevatedHeartRateSignal = hasElevatedHeartRateSignal
        self.confidence = confidence
    }

    fileprivate func withElevatedHeartRateSignal(_ hasSignal: Bool) -> GymCandidate {
        GymCandidate(
            id: id,
            latitude: latitude,
            longitude: longitude,
            suggestedRadiusMeters: suggestedRadiusMeters,
            visitCount: visitCount,
            averageDwellMinutes: averageDwellMinutes,
            firstVisitDate: firstVisitDate,
            lastVisitDate: lastVisitDate,
            hasElevatedHeartRateSignal: hasSignal,
            // Small, capped bump — HR is corroboration, not the primary signal (visit
            // recurrence + dwell already did most of the scoring in `confidence(visitCount:
            // averageDwellMinutes:)`).
            confidence: hasSignal ? min(1.0, confidence + 0.1) : confidence
        )
    }
}

/// Clusters `CLVisit` history into gym candidates (docs/spec.md §9.4) and, opportunistically,
/// checks HealthKit for elevated heart rate during each candidate's visits.
///
/// Two-step API by design, not one combined call: ``clusterVisits(_:now:lookbackDays:)`` is a
/// pure, synchronous, side-effect-free function over plain data (easy to unit test, and never
/// crosses an `async` boundary with a raw `CLVisit` — see this session's `decisions` for why that
/// matters under Swift 6 strict concurrency); ``enrichWithHealthKitSignal(_:)`` is the only
/// `async`, I/O-touching step, and it only ever takes/returns `[GymCandidate]` (a plain,
/// `Sendable` struct). Typical caller (Gym Setup, another session):
/// ```swift
/// let candidates = GymAutoDetect.shared.clusterVisits(visits)
/// let ranked = await GymAutoDetect.shared.enrichWithHealthKitSignal(candidates)
/// ```
public final class GymAutoDetect: Sendable {
    public static let shared = GymAutoDetect()

    /// docs/spec.md §9.4: "min dwell 40 min".
    public static let minimumDwellMinutes = 40
    /// docs/spec.md §9.4: "recurring ≥ 2×/14 days".
    public static let minimumRecurringVisits = 2
    /// docs/spec.md §9.4: "...14 days".
    public static let lookbackDays = 14
    /// Visits within this distance of each other are treated as "the same place". Looser than
    /// `Gym`'s own default geofence radius (150 m, `Gym.init(radiusMeters:)`) since `CLVisit`
    /// coordinates already carry their own smoothing/accuracy error; clustering slightly wider
    /// avoids splitting one real gym into two candidates purely from GPS drift between visits.
    public static let clusterRadiusMeters: CLLocationDistance = 120

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymAutoDetect")

    private init() {}

    /// Pure, synchronous clustering step. `visits` should be whatever `CLLocationManager`'s
    /// `startMonitoringVisits()` has delivered to the app over time — Apple does not expose a
    /// bulk "visit history" API, so the caller (a background `CLLocationManagerDelegate`
    /// collector that persists each `CLVisit` as it arrives — not this file's job; see
    /// knownIssues) is responsible for accumulating the window handed to this method.
    ///
    /// Clustering here is a **simplified single-pass greedy** algorithm, not a literal DBSCAN:
    /// each qualifying visit, taken in chronological order, joins the nearest existing cluster
    /// within `clusterRadiusMeters` of that cluster's running centroid, or starts a new one. This
    /// approximates DBSCAN's "recurring visits at roughly the same place become one cluster"
    /// outcome (spec §9.4) without a general-purpose DBSCAN implementation (no epsilon-neighbor /
    /// noise-point formalism, and the result can depend on visit order in pathological
    /// equidistant cases). Flagged explicitly as a deliberate v1 simplification rather than
    /// presented as a real DBSCAN — acceptable at this scale, since one person's 14-day visit
    /// history is a handful of distinct places, not a dataset that needs a rigorous clustering
    /// library.
    public func clusterVisits(
        _ visits: [CLVisit],
        now: Date = .now,
        lookbackDays: Int = GymAutoDetect.lookbackDays
    ) -> [GymCandidate] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? .distantPast

        let qualifying: [QualifyingVisit] = visits.compactMap { visit in
            guard visit.arrivalDate >= cutoff, visit.arrivalDate != .distantPast else { return nil }
            // `departureDate` is `.distantFuture` while a visit is still ongoing (Apple's
            // documented sentinel for "hasn't left yet") — treat that as "still there as of
            // `now`" for dwell purposes rather than excluding it outright.
            let departure = visit.departureDate == .distantFuture ? now : visit.departureDate
            let dwellMinutes = Int(departure.timeIntervalSince(visit.arrivalDate) / 60)
            guard dwellMinutes >= Self.minimumDwellMinutes else { return nil }
            guard visit.horizontalAccuracy > 0 else { return nil } // negative = invalid fix
            return QualifyingVisit(
                coordinate: visit.coordinate,
                arrivalDate: visit.arrivalDate,
                dwellMinutes: dwellMinutes,
                horizontalAccuracy: visit.horizontalAccuracy
            )
        }

        var clusters: [VisitCluster] = []
        for visit in qualifying.sorted(by: { $0.arrivalDate < $1.arrivalDate }) {
            let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
            if let index = clusters.firstIndex(where: { $0.centroidLocation.distance(from: location) <= Self.clusterRadiusMeters }) {
                clusters[index].add(visit)
            } else {
                clusters.append(VisitCluster(first: visit))
            }
        }

        return clusters
            .filter { $0.visits.count >= Self.minimumRecurringVisits }
            .map { $0.makeCandidate() }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Opportunistically checks HealthKit for elevated heart rate overlapping each candidate's
    /// visit span (spec §9.4's confidence-up signal) and returns a new, re-sorted array.
    /// Degrades silently to leaving `hasElevatedHeartRateSignal = false` (i.e. no confidence
    /// bump, not a penalty) per candidate when HealthKit is unavailable or has nothing to say —
    /// same "never turn a missing optional signal into a negative result" reasoning as
    /// `GymVerifier.elevatedHeartRateDuringDwell`. Deliberately takes/returns `[GymCandidate]`
    /// rather than re-deriving from raw `CLVisit`s — see the type's doc comment.
    public func enrichWithHealthKitSignal(_ candidates: [GymCandidate]) async -> [GymCandidate] {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return candidates
        }

        let healthStore = HKHealthStore()
        var enriched: [GymCandidate] = []
        enriched.reserveCapacity(candidates.count)
        for candidate in candidates {
            let elevated = await Self.hasElevatedHeartRate(
                healthStore: healthStore,
                type: heartRateType,
                start: candidate.firstVisitDate,
                end: candidate.lastVisitDate
            )
            enriched.append(candidate.withElevatedHeartRateSignal(elevated))
        }
        return enriched.sorted { $0.confidence > $1.confidence }
    }

    /// Explainable v1 confidence heuristic — spec §9.4 prescribes the qualifying thresholds and
    /// that elevated HR "confidence up", but not an exact formula. More recurring visits and a
    /// longer average dwell both raise confidence, each saturating so visit history alone can't
    /// exceed 0.9 before `enrichWithHealthKitSignal`'s HR bonus.
    fileprivate static func confidence(visitCount: Int, averageDwellMinutes: Int) -> Double {
        let visitScore = min(Double(visitCount) / 6.0, 1.0)        // saturates at 6 visits/14 days
        let dwellScore = min(Double(averageDwellMinutes) / 90.0, 1.0) // saturates at 90 min avg
        return min(0.9, 0.5 * visitScore + 0.4 * dwellScore)
    }

    private static func hasElevatedHeartRate(
        healthStore: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async -> Bool {
        guard end > start else { return false }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil, let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    continuation.resume(returning: false)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let elevated = quantitySamples.contains {
                    $0.quantity.doubleValue(for: bpmUnit) >= GymVerificationDefaults.elevatedHeartRateBPM
                }
                continuation.resume(returning: elevated)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Clustering internals

/// A `CLVisit` reduced to the plain, `Sendable`-trivial fields clustering actually needs, taken
/// right at the boundary of `clusterVisits` so nothing downstream (including the async
/// `enrichWithHealthKitSignal` path) ever has to reason about `CLVisit`'s own concurrency story.
private struct QualifyingVisit {
    let coordinate: CLLocationCoordinate2D
    let arrivalDate: Date
    let dwellMinutes: Int
    let horizontalAccuracy: CLLocationAccuracy
}

private struct VisitCluster {
    private(set) var visits: [QualifyingVisit]
    private var centroidLatitude: Double
    private var centroidLongitude: Double

    init(first visit: QualifyingVisit) {
        visits = [visit]
        centroidLatitude = visit.coordinate.latitude
        centroidLongitude = visit.coordinate.longitude
    }

    var centroidLocation: CLLocation { CLLocation(latitude: centroidLatitude, longitude: centroidLongitude) }

    mutating func add(_ visit: QualifyingVisit) {
        visits.append(visit)
        // Running average keeps the centroid representative without storing/re-summing every
        // point on each insert.
        let n = Double(visits.count)
        centroidLatitude += (visit.coordinate.latitude - centroidLatitude) / n
        centroidLongitude += (visit.coordinate.longitude - centroidLongitude) / n
    }

    /// Safe: every `VisitCluster` holds at least one visit (`init(first:)`), and `add` only ever
    /// appends — `visits` is never empty when this runs.
    func makeCandidate() -> GymCandidate {
        let dwellMinutesAverage = visits.reduce(0) { $0 + $1.dwellMinutes } / visits.count
        let sortedByDate = visits.sorted { $0.arrivalDate < $1.arrivalDate }
        // Suggested radius: generous enough to cover this cluster's GPS accuracy spread, clamped
        // to a sane range so it's neither a pinhole nor a neighborhood. 150 mirrors `Gym.init`'s
        // own default radius, used here only as the fallback when no accuracy reading exists.
        let accuracySpread = visits.map(\.horizontalAccuracy).max() ?? 150
        let suggestedRadius = Int(min(max(accuracySpread, 60), 250))

        return GymCandidate(
            latitude: centroidLatitude,
            longitude: centroidLongitude,
            suggestedRadiusMeters: suggestedRadius,
            visitCount: visits.count,
            averageDwellMinutes: dwellMinutesAverage,
            firstVisitDate: sortedByDate.first!.arrivalDate,
            lastVisitDate: sortedByDate.last!.arrivalDate,
            confidence: GymAutoDetect.confidence(visitCount: visits.count, averageDwellMinutes: dwellMinutesAverage)
        )
    }
}
