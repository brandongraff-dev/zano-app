// StravaActivitySync.swift
// Core / Strava
//
// Fetches recent Strava activities into `StravaActivityStore` (session 40). Called from
// `HealthGoalChecks.run()`, which already runs at launch, on every foreground and when HealthKit wakes the
// app for a new workout, so Strava workouts are picked up on the same occasions Health workouts are. There
// is no separate background-refresh task: that would need the `fetch` background mode and a
// `BGTaskScheduler` registration this app deliberately doesn't declare (project.yml). The optional
// `strava-webhook` only handles deauthorization; nothing is pushed to the phone.
//
// Throttled to one fetch per `minimumInterval`: Strava's rate limit is per API app (shared by every user),
// so one fetch per user per quarter hour at most keeps well inside it.

import Foundation
import os

@MainActor
public enum StravaActivitySync {
    nonisolated public static let minimumInterval: TimeInterval = 15 * 60
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "StravaActivitySync")

    /// `true` when a fetch is due. Pure, unit tested.
    nonisolated static func isDue(lastFetch: Date?, now: Date, force: Bool) -> Bool {
        guard !force, let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minimumInterval || now < lastFetch
    }

    /// The fetch window starts at the beginning of yesterday: Strava's `after` filters by start time, so a
    /// run from this morning that was uploaded late is still inside it.
    nonisolated static func fetchStart(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    /// Fetches when linked, available and due. Never throws; a failure just waits for the next occasion.
    public static func refreshIfDue(now: Date = .now, force: Bool = false) async {
        guard StravaActivityStore.isLinked else { return }
        guard isDue(lastFetch: StravaActivityStore.lastFetch, now: now, force: force) else { return }
        guard await StravaClient.shared.isAvailable() else { return }

        let start = fetchStart(now: now)
        do {
            let fetched = try await StravaClient.shared.activities(after: start)
            StravaActivityStore.save(fetched, keepSince: start)
            StravaActivityStore.lastFetch = now
        } catch StravaLinkError.notLinked {
            logger.notice("Strava link is gone (removed on Strava or server side); clearing it.")
            StravaActivityStore.isLinked = false
        } catch {
            logger.error("Strava fetch failed: \(String(describing: error), privacy: .public)")
        }
    }
}
