// HealthWorkoutObserver.swift
// Core / Verification
//
// Unlocks on a workout you already did (session 20; docs/spec.md §3 "Workout (home/outdoor)": "HealthKit
// workout logged (Apple Watch, Strava, Nike Run Club, etc.)"). Before this, a workout was only noticed
// when the app was opened, so someone who ran at 6 am and picked up their phone at noon was still
// locked until they opened ZANO. This registers an `HKObserverQuery` on workouts with background
// delivery (the entitlement is already in `project.yml`), so HealthKit wakes the app when a new workout
// lands and `HealthGoalChecks.run()` verifies it and ends the lock waiting on it.
//
// Anything that writes workouts to Apple Health counts: Apple Watch, Fitness, and any app that saves to
// Health (whether Strava does so on a given account is not something this file can know; a direct Strava
// link would need a Strava API app and a backend OAuth exchange, which is blocked on keys).
//
// Mirrors `StepsVerifier`'s observer: a small actor owns the query; the handler always calls the
// completion handler; the check itself is the existing, idempotent `HealthGoalChecks.run()`.
//
// UNVERIFIED (no Mac/device): background delivery for workouts waking a terminated app is documented
// HealthKit behaviour but has not been seen working here.

import Foundation
import HealthKit
import os

public final class HealthWorkoutObserver: Sendable {
    public static let shared = HealthWorkoutObserver()

    private let state = WorkoutObserverState()

    private init() {}

    /// Starts watching for new workouts (idempotent). Only called once Health access was already
    /// answered; it never shows a permission sheet.
    public func startObserving() async {
        await state.startObserving()
    }
}

actor WorkoutObserverState {
    private let healthStore = HKHealthStore()
    private var query: HKObserverQuery?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "HealthWorkoutObserver")

    func startObserving() async {
        guard HKHealthStore.isHealthDataAvailable(), query == nil else { return }
        let workoutType = HKObjectType.workoutType()
        let observer = HKObserverQuery(sampleType: workoutType, predicate: nil) { @Sendable _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else { return }
            Task { await HealthGoalChecks.run() }
        }
        healthStore.execute(observer)
        query = observer
        await enableBackgroundDelivery(for: workoutType)
        logger.notice("Watching for new workouts.")
    }

    private func enableBackgroundDelivery(for type: HKObjectType) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in
                continuation.resume()
            }
        }
    }
}
