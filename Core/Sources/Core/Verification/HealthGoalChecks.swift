// Core/Sources/Core/Verification/HealthGoalChecks.swift
//
// Runs the HealthKit-verified goals' checks for every active goal, independent of any screen
// (docs/design/unfinished-audit-2026-10-02.md L6; spec section 3 Steps / home-workout rows, Tier A).
// Before this, only Today registered the steps observer and checked workouts, so a goal met while
// Today was never opened never verified — and never ended the lock waiting on it.
//
// Called from `ZANOApp.init` (so the `HKObserverQuery` exists early in a background relaunch for a
// HealthKit delivery, as HealthKit requires) and from every app foreground. Never prompts: a
// verifier whose Health request was never shown (`needsAuthorizationRequest`) is skipped, and
// Today's "Connect Apple Health" row stays the only place that asks. Local only, except the throttled
// Strava fetch (`StravaActivitySync`, session 40) when someone connected Strava.

import Foundation
import SwiftData
import os

@MainActor
public enum HealthGoalChecks {
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "HealthGoalChecks")

    /// Registers the steps observer for each active steps goal (idempotent per goal) and checks
    /// today's steps and Health workouts for every active goal they can verify: steps goals, home/
    /// outdoor workout goals, and the gym goal while travel mode is on. Each check is idempotent
    /// and reports a completion to `GoalCompletionCoordinator` itself.
    public static func run(modelContainer: ModelContainer = .appGroup) async {
        let context = ModelContext(modelContainer)
        // Only the `Bool` goes into `#Predicate`; the enum is matched in Swift.
        let active = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.active }))) ?? []
        let stepGoalIDs = active.filter { $0.type == .steps }.map(\.id)
        let travel = TravelMode.isActiveNow()
        let workoutGoalIDs = active
            .filter { $0.type == .workoutHomeOutdoor || ($0.type == .workoutGym && travel) }
            .map(\.id)

        if !stepGoalIDs.isEmpty, !(await StepsVerifier.shared.needsAuthorizationRequest()) {
            for goalID in stepGoalIDs {
                do {
                    // A no-op for a goal already observed in this process, hence the explicit
                    // check after it (idempotent: never logs a second completion).
                    try await StepsVerifier.shared.startObserving(goalID: goalID)
                    _ = try await StepsVerifier.shared.checkToday(goalID: goalID)
                } catch {
                    logger.error("Steps observer for \(goalID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        guard !workoutGoalIDs.isEmpty else { return }
        let healthAsked = !(await HomeWorkoutVerifier.shared.needsAuthorizationRequest())
        // Direct Strava link (session 40): pull recent Strava activities first (throttled, no-op when not
        // linked), so the workout check below sees them alongside Health's.
        await StravaActivitySync.refreshIfDue()
        if healthAsked || StravaActivityStore.isLinked {
            // Wake the app when a new workout lands in Health, so a run finished while the app was
            // closed unlocks without anyone opening ZANO (idempotent).
            if healthAsked { await HealthWorkoutObserver.shared.startObserving() }
            for goalID in workoutGoalIDs {
                do {
                    _ = try await HomeWorkoutVerifier.shared.checkToday(goalID: goalID)
                } catch {
                    logger.error("Workout check for \(goalID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
}
