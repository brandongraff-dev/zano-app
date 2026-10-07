// WorkoutDedupe.swift
// Core / Verification
//
// Session 40 (direct Strava link). docs/spec.md §3 "Workout (home/outdoor)": verified by a logged workout,
// "Min 20 min; HR if Watch present"; §9.8: "Never accuse — just don't count, and show 'not counted'
// transparently."
//
// A workout can now arrive twice: from Apple Health (Watch, Fitness, or Strava writing to Health) and from
// the direct Strava link. Everything here is pure so it is unit tested (`StravaTests`):
//   - `WorkoutCandidate`        one workout from either source, as the goal check sees it
//   - `StravaWorkoutMapping`    a Strava activity -> a candidate, or the reason it doesn't count
//   - `WorkoutDedupe`           "is this the same workout?" by start time + duration overlap, and the merge
//                               the home-workout check uses (Health wins; an overlapping Strava copy is
//                               dropped), so one workout never counts twice.

import Foundation

/// Where a `WorkoutCandidate` came from.
public enum WorkoutEvidenceSource: String, Codable, Sendable, Equatable {
    case healthKit
    case strava
}

/// One recorded workout, from Health or Strava.
public struct WorkoutCandidate: Sendable, Equatable {
    public let start: Date
    /// Wall-clock end (start + elapsed time). Used only for overlap.
    public let end: Date
    /// The time that counts toward the goal: HealthKit `duration`, Strava `moving_time`.
    public let activeSeconds: TimeInterval
    public let source: WorkoutEvidenceSource
    /// Elevated-heart-rate corroboration; `nil` when there is no heart-rate data (never read as `false`,
    /// same rule as `HomeWorkoutVerificationResult.heartRateCorroboration`).
    public let heartRateCorroboration: Bool?
    /// Strava activity id; `nil` for Health.
    public let externalID: String?

    public init(
        start: Date,
        end: Date,
        activeSeconds: TimeInterval,
        source: WorkoutEvidenceSource,
        heartRateCorroboration: Bool? = nil,
        externalID: String? = nil
    ) {
        self.start = start
        self.end = max(start, end)
        self.activeSeconds = max(0, activeSeconds)
        self.source = source
        self.heartRateCorroboration = heartRateCorroboration
        self.externalID = externalID
    }

    public var wholeMinutes: Int { Int(activeSeconds / 60) }
}

/// Why a Strava activity was not counted (shown in the Strava screen, never as an accusation).
public enum StravaNotCountedReason: String, Codable, Sendable, Equatable {
    /// Typed in by hand on Strava (`manual: true`). The workout goal is Tier A (recorded, not typed), so a
    /// hand-entered workout doesn't unlock anything, same as there being no workout at all.
    case enteredByHand
    /// No moving time at all (a zero-length or broken upload).
    case noDuration
}

public enum StravaWorkoutMapping {
    /// The verdict for one activity.
    public enum Verdict: Sendable, Equatable {
        case counts(WorkoutCandidate)
        case notCounted(StravaNotCountedReason)
    }

    public static func verdict(for activity: StravaActivity) -> Verdict {
        if activity.manual { return .notCounted(.enteredByHand) }
        guard activity.movingSeconds > 0 else { return .notCounted(.noDuration) }
        // Some uploads report elapsed < moving; the wall-clock span is at least the moving time.
        let span = TimeInterval(max(activity.elapsedSeconds, activity.movingSeconds))
        let heartRate: Bool? = {
            guard activity.hasHeartrate, let maxHR = activity.maxHeartrate else { return nil }
            return maxHR >= HomeWorkoutVerificationDefaults.elevatedHeartRateBPM
        }()
        return .counts(WorkoutCandidate(
            start: activity.startDate,
            end: activity.startDate.addingTimeInterval(span),
            activeSeconds: TimeInterval(activity.movingSeconds),
            source: .strava,
            heartRateCorroboration: heartRate,
            externalID: activity.id
        ))
    }

    /// The activities that count, as candidates.
    public static func countedCandidates(_ activities: [StravaActivity]) -> [WorkoutCandidate] {
        activities.compactMap {
            if case .counts(let candidate) = verdict(for: $0) { return candidate }
            return nil
        }
    }
}

public enum WorkoutDedupe {
    /// Two workouts are the same when their overlap covers at least this share of the shorter one. Half is
    /// generous on purpose: Strava and Health can disagree by a minute or two on start and end (auto-pause,
    /// upload trimming), but two genuinely separate sessions back to back barely overlap at all.
    public static let minimumOverlapFraction = 0.5
    /// For zero-length spans (no duration on one side): same workout if they start this close together.
    public static let startTolerance: TimeInterval = 2 * 60

    /// Start time + duration overlap.
    public static func isSameWorkout(_ a: WorkoutCandidate, _ b: WorkoutCandidate) -> Bool {
        let lengthA = a.end.timeIntervalSince(a.start)
        let lengthB = b.end.timeIntervalSince(b.start)
        let shorter = min(lengthA, lengthB)
        guard shorter > 0 else { return abs(a.start.timeIntervalSince(b.start)) <= startTolerance }
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard overlap > 0 else { return false }
        return overlap / shorter >= minimumOverlapFraction
    }

    /// Health workouts first, then every Strava workout that isn't a copy of one of them (or of an earlier
    /// Strava workout in the list). Health wins a tie because it can carry the Watch's heart-rate samples
    /// and it is the record the existing check already trusts.
    public static func merge(health: [WorkoutCandidate], strava: [WorkoutCandidate]) -> [WorkoutCandidate] {
        var merged = health
        for candidate in strava where !merged.contains(where: { isSameWorkout($0, candidate) }) {
            merged.append(candidate)
        }
        return merged
    }

    /// The Strava workout that verifies the goal when no Health workout did: the first Strava workout (in
    /// the order given) of at least `requiredMinutes` that is not a copy of a Health workout. If its Health
    /// copy existed and was too short, the Strava copy doesn't get a second chance (one workout, one vote).
    public static func qualifyingStravaWorkout(
        health: [WorkoutCandidate],
        strava: [WorkoutCandidate],
        requiredMinutes: Int
    ) -> WorkoutCandidate? {
        let required = TimeInterval(requiredMinutes * 60)
        return merge(health: health, strava: strava)
            .first { $0.source == .strava && $0.activeSeconds >= required }
    }
}
