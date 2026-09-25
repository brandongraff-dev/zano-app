// GymDwellActivityManager.swift
// Core / LiveActivity
//
// docs/spec.md §5.11 ("During gym dwell: elapsed time at the gym and 'verified in 12 min'") and
// §6 ("Gym dwell: 'At the gym · 22 min · verified at 35'"). Owns the one gym-dwell Live Activity:
// request, update, end. `GymPresenceService` decides *when*; this file only talks to ActivityKit.
//
// Mirrors `EarnMeterActivityManager` (same folder): `@MainActor`, one tracked `Activity`, the same
// `nonisolated(unsafe)` hop for `Activity`'s async `update`/`end` (the type isn't `Sendable`).
//
// ActivityKit limits that shape the callers (spec §27): a Live Activity can only be *started* while
// the app is in the foreground (`request` throws otherwise), needs the user's permission, and lives
// at most 8 hours. `start` therefore returns `false` rather than throwing, and the presence service
// falls back to a notification when it can't start one from the background.

import ActivityKit
import Foundation
import os

@MainActor
public final class GymDwellActivityManager {
    public static let shared = GymDwellActivityManager()

    private var activity: Activity<GymDwellActivityAttributes>?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymDwellActivityManager")

    init() {}

    /// The gym the running Activity tracks, if any.
    public var activeGymID: UUID? { activity?.attributes.gymID }

    public var isActive: Bool { activity != nil }

    /// Re-attaches to an Activity still running from a previous process (the app was killed or
    /// relaunched in the background mid-workout). Ends any extras so at most one is live.
    public func adoptRunningActivity() {
        let running = Activity<GymDwellActivityAttributes>.activities
        guard let first = running.first else { return }
        activity = first
        for extra in running.dropFirst() {
            nonisolated(unsafe) let unsafeExtra = extra
            Task { await unsafeExtra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Starts the Activity for `gymID`, or updates it if one is already running for that gym.
    /// Returns `false` when Live Activities are off or ActivityKit refused (e.g. app in background).
    @discardableResult
    public func start(
        gymID: UUID,
        gymName: String,
        state: GymDwellActivityAttributes.ContentState
    ) async -> Bool {
        if let activity, activity.attributes.gymID == gymID {
            await update(state)
            return true
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; gym dwell runs without one.")
            return false
        }
        if activity != nil {
            await end(finalState: nil)
        }
        do {
            let started = try Activity<GymDwellActivityAttributes>.request(
                attributes: GymDwellActivityAttributes(gymName: gymName, gymID: gymID),
                content: ActivityContent(state: state, staleDate: Self.staleDate(for: state))
            )
            activity = started
            return true
        } catch {
            logger.notice("Couldn't start gym dwell Live Activity: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Pushes a new state to the running Activity. No-op when none is running.
    public func update(_ state: GymDwellActivityAttributes.ContentState) async {
        guard let activity else { return }
        nonisolated(unsafe) let unsafeActivity = activity
        await unsafeActivity.update(ActivityContent(state: state, staleDate: Self.staleDate(for: state)))
    }

    /// Ends the running Activity. With a `finalState`, the ended Activity stays on the Lock Screen
    /// for `lingerMinutes` (so a verified workout reads as done) before the system removes it.
    public func end(finalState: GymDwellActivityAttributes.ContentState?, lingerMinutes: Int = 0) async {
        guard let activity else { return }
        self.activity = nil
        let policy: ActivityUIDismissalPolicy = lingerMinutes > 0
            ? .after(.now.addingTimeInterval(TimeInterval(lingerMinutes * 60)))
            : .immediate
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        nonisolated(unsafe) let unsafeActivity = activity
        await unsafeActivity.end(content, dismissalPolicy: policy)
    }

    /// A running (unverified) dwell's minute count is stale by the time it would have hit the
    /// target — tell the system so it can dim the value instead of showing it as current.
    private static func staleDate(for state: GymDwellActivityAttributes.ContentState) -> Date? {
        guard !state.isVerified, let enteredAt = state.enteredAt else { return nil }
        return enteredAt.addingTimeInterval(TimeInterval(state.verifiedAtMinutes * 60))
    }
}
