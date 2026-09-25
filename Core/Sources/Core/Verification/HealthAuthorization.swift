// Core/Sources/Core/Verification/HealthAuthorization.swift
//
// The one place the app asks for HealthKit read access (docs/spec.md §3 verification table, §24
// "Health data: HealthKit data stays on device"). Read-only: `toShare` is always empty. Only the
// types a goal actually verifies with are requested, and only for goals the user has:
//   - steps               → step count (`StepsVerifier`)
//   - home/outdoor workout → workouts + heart rate (`HomeWorkoutVerifier`)
//   - gym workout          → workouts + heart rate (`GymVerifier` / `GymAutoDetect` HR corroboration)
//   - sleep on time        → sleep analysis (spec §3 "HealthKit sleep"; no verifier reads it yet)
//
// HealthKit never reveals whether *read* access was granted — a denied read looks exactly like "no
// data". So this file can only answer "has the permission sheet been shown for these types"
// (`hasRequestedRead`), never "was it allowed". Callers explain how to change it in the Health app.
//
// Uses the completion-handler `requestAuthorization(toShare:read:completion:)` and
// `getRequestStatusForAuthorization(toShare:read:completion:)` (iOS 8 / iOS 12), wrapped in
// continuations — the same long-stable surface `StepsVerifier` uses. A fresh `HKHealthStore` per
// call keeps this a stateless, `Sendable`-clean namespace (no shared non-Sendable static).

import Foundation
import HealthKit

public enum HealthAuthorizationError: Error, Sendable, Equatable {
    /// HealthKit isn't available on this device (e.g. some iPads).
    case unavailable
}

public enum HealthAuthorization {
    /// `false` on devices without HealthKit.
    public static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Whether a goal of `type` reads anything from Apple Health.
    public static func usesHealth(_ type: GoalType) -> Bool {
        !readTypes(for: [type]).isEmpty
    }

    /// The HealthKit types the given goal types verify with. Empty when none of them use Health.
    public static func readTypes(for goalTypes: some Sequence<GoalType>) -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for goalType in goalTypes {
            switch goalType {
            case .steps:
                if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
            case .workoutGym, .workoutHomeOutdoor:
                types.insert(HKObjectType.workoutType())
                if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
            case .sleepOnTime:
                if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
            case .focusSession, .protein, .water, .creatine, .sunriseAlarm, .reading, .mealPrep,
                 .stretchMobility, .coldShowerSauna, .custom:
                break
            }
        }
        return types
    }

    /// Shows the Health permission sheet for the read types `goalTypes` need. Returns without
    /// asking when none of them use Health. Returning normally does NOT mean access was granted —
    /// only that the sheet was shown (or had already been answered).
    ///
    /// - Throws: `HealthAuthorizationError.unavailable`, or HealthKit's own error if the sheet
    ///   couldn't be presented.
    public static func requestRead(for goalTypes: [GoalType]) async throws {
        guard isAvailable else { throw HealthAuthorizationError.unavailable }
        let read = readTypes(for: goalTypes)
        guard !read.isEmpty else { return }

        let store = HKHealthStore()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: read) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// `true` once the Health sheet has been answered for every read type `goalTypes` need (or
    /// when they need none). `false` when there is still something to ask, or Health is unavailable.
    public static func hasRequestedRead(for goalTypes: [GoalType]) async -> Bool {
        let read = readTypes(for: goalTypes)
        guard !read.isEmpty else { return true }
        guard isAvailable else { return false }

        let store = HKHealthStore()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.getRequestStatusForAuthorization(toShare: [], read: read) { status, error in
                continuation.resume(returning: error == nil && status == .unnecessary)
            }
        }
    }
}
