// GymPresenceService.swift
// Core / Verification
//
// docs/spec.md §3 (Workout (gym), Tier A: geofence arrival + dwell), §5.11 (Dynamic Island during
// gym dwell), §24 (location: Always only after a clear explanation; manual fallback), §27 (region
// monitoring ~20 regions; Live Activities need the foreground to start and last ≤ 8 h).
//
// The app-side half of gym verification. `GymVerifier` owns the geofence and the dwell clock;
// this service turns its presence events into what the person sees:
//
//   * at launch, re-opens the gym `CLMonitor` for every confirmed gym (`start()` — call from
//     `ZANOApp.init()`, so a background relaunch for a region event is consumed immediately);
//   * on arrival, starts the Gym Dwell Live Activity (or, when iOS won't start one because the
//     app is in the background, posts an "At <gym>" notification) and schedules a "time's up"
//     notification for the dwell target, since nothing wakes the app at minute 35 on its own;
//   * while the app runs, ticks every 30 s: refreshes the snapshot, verifies once the target is
//     reached (which writes the completion and unlocks), updates the Live Activity;
//   * on verification or exit, ends the Live Activity and cancels pending notifications.
//
// Never asks for location permission (the Gym Setup UI does, after its primer) and never
// uploads a location: everything here runs on the phone.

import Foundation
import Observation
import SwiftData
import UserNotifications
import os

@MainActor
@Observable
public final class GymPresenceService {
    public static let shared = GymPresenceService()

    // MARK: Observable state

    /// Geofence answer per confirmed gym.
    public private(set) var regionStates: [UUID: GymRegionState] = [:]
    /// Today's dwell session per gym (running or finished).
    public private(set) var sessions: [UUID: GymDwellSnapshot] = [:]
    /// The dwell target in minutes (the gym goal's `targetValue`, else 35).
    public private(set) var requiredMinutes: Int = GymVerificationDefaults.requiredDwellMinutes
    /// The most recent presence event, for screens that react to a moment (arrival, exit, verify).
    public private(set) var lastEvent: GymPresenceEvent?
    /// Bumped on every verification — a `.sensoryFeedback` trigger.
    public private(set) var verificationCount = 0

    // MARK: Private

    private let verifier: GymVerifier
    private let activities: GymDwellActivityManager
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastHeartRateCheck: Date = .distantPast
    /// Gyms whose check-in the user just started from the app: their `.entered` event must not
    /// also post an "At <gym>" notification while they're looking at the screen.
    @ObservationIgnored private var userStartedGymIDs: Set<UUID> = []
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymPresenceService")

    private static let tickInterval: Duration = .seconds(30)
    private static let heartRateCheckInterval: TimeInterval = 120
    private static let arrivalNotificationPrefix = "zano.gym.arrival."
    private static let targetNotificationPrefix = "zano.gym.target."

    init() {
        verifier = .shared
        activities = .shared
    }

    // MARK: Lifecycle

    /// Idempotent. Re-opens the gym monitor for all confirmed gyms and starts listening. Call once
    /// from app launch (`ZANOApp.init()`); calling again is a no-op.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        activities.adoptRunningActivity()
        eventTask = Task { [weak self] in
            guard let self else { return }
            // Subscribe before syncing so an event fired by the sync itself isn't missed.
            let stream = await self.verifier.presenceEvents()
            await self.verifier.syncMonitoredGyms()
            await self.refresh()
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    /// Re-syncs the monitored geofences with SwiftData. Call after a gym is saved, edited,
    /// confirmed or deleted.
    public func refreshMonitoredGyms() async {
        start()
        await verifier.syncMonitoredGyms()
        await refresh()
    }

    /// Starts a check-in for `gymID` (the "Start check-in" button). Starts the Live Activity when
    /// the clock actually started — the app is in the foreground here, so ActivityKit allows it.
    public func startCheckIn(gymID: UUID) async -> GymCheckInStartResult {
        start()
        userStartedGymIDs.insert(gymID)
        let result = await verifier.startCheckIn(gymID: gymID)
        if result != .started {
            userStartedGymIDs.remove(gymID)
        }
        await refresh()
        if result == .started || result == .alreadyRunning {
            await startLiveActivity(for: gymID)
        }
        return result
    }

    /// Re-reads everything from `GymVerifier`, verifies a dwell that has reached its target, and
    /// updates the Live Activity. Screens call this on appear; the tick calls it while a dwell runs.
    public func refresh() async {
        requiredMinutes = await verifier.requiredDwellMinutes()
        let gymIDs = confirmedGyms().map(\.id)

        var states: [UUID: GymRegionState] = [:]
        var snapshots: [UUID: GymDwellSnapshot] = [:]
        for gymID in gymIDs {
            states[gymID] = await verifier.regionState(gymID: gymID)
            if var snapshot = await verifier.dwellSnapshot(gymID: gymID) {
                if snapshot.isActive, !snapshot.isVerified, snapshot.dwellMinutes >= requiredMinutes {
                    // `isVerified` writes the completion and emits `.verified` on success.
                    if await verifier.isVerified(gymID: gymID, requiredMinutes: requiredMinutes),
                       let updated = await verifier.dwellSnapshot(gymID: gymID) {
                        snapshot = updated
                    }
                }
                snapshots[gymID] = snapshot
            }
        }
        regionStates = states
        sessions = snapshots

        await refreshHeartRateIfDue()
        await updateLiveActivity()
        updateTicker()
    }

    // MARK: Events

    private func handle(_ event: GymPresenceEvent) async {
        lastEvent = event
        switch event {
        case .entered(let gymID):
            await refresh()
            // A second visit after today's workout already counted: no Live Activity or nudges.
            if isGymGoalCompleteToday() {
                userStartedGymIDs.remove(gymID)
                return
            }
            let startedByUser = userStartedGymIDs.remove(gymID) != nil
            let started = await startLiveActivity(for: gymID)
            if !started, !startedByUser {
                await postArrivalNotification(gymID: gymID)
            }
            await scheduleTargetNotification(gymID: gymID)
        case .exited(let gymID, _):
            cancelNotifications(gymID: gymID)
            await refresh()
            if activities.activeGymID == gymID {
                let final = contentState(for: gymID)
                await activities.end(finalState: final, lingerMinutes: final?.isVerified == true ? 15 : 0)
            }
        case .verified(let gymID, _):
            verificationCount += 1
            cancelNotifications(gymID: gymID)
            await refresh()
            if activities.activeGymID == gymID {
                await activities.end(finalState: contentState(for: gymID), lingerMinutes: 15)
            }
        }
    }

    // MARK: Live Activity

    @discardableResult
    private func startLiveActivity(for gymID: UUID) async -> Bool {
        guard let state = contentState(for: gymID), state.enteredAt != nil else { return false }
        return await activities.start(gymID: gymID, gymName: gymName(for: gymID), state: state)
    }

    private func updateLiveActivity() async {
        guard let gymID = activities.activeGymID, let state = contentState(for: gymID) else { return }
        if state.enteredAt == nil {
            // The session ended without us hearing the exit (e.g. across a relaunch).
            await activities.end(finalState: state, lingerMinutes: state.isVerified ? 15 : 0)
        } else {
            await activities.update(state)
        }
    }

    private func contentState(for gymID: UUID) -> GymDwellActivityAttributes.ContentState? {
        guard let snapshot = sessions[gymID] else { return nil }
        return GymDwellActivityAttributes.ContentState(
            elapsedMinutes: snapshot.dwellMinutes,
            verifiedAtMinutes: requiredMinutes,
            isVerified: snapshot.isVerified,
            enteredAt: snapshot.isActive ? snapshot.enteredAt : nil
        )
    }

    // MARK: Ticker

    private var hasRunningDwell: Bool {
        sessions.values.contains { $0.isActive && !$0.isVerified }
    }

    private func updateTicker() {
        if hasRunningDwell {
            guard tickTask == nil else { return }
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tickInterval)
                    guard let self, !Task.isCancelled else { return }
                    await self.refresh()
                }
            }
        } else {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func refreshHeartRateIfDue() async {
        guard Date.now.timeIntervalSince(lastHeartRateCheck) >= Self.heartRateCheckInterval else { return }
        let running = sessions.values.filter { $0.isActive && $0.heartRateCorroborated != true }
        guard !running.isEmpty else { return }
        lastHeartRateCheck = .now
        for snapshot in running {
            let result = await verifier.refreshHeartRateCorroboration(gymID: snapshot.gymID)
            if result != nil, let updated = await verifier.dwellSnapshot(gymID: snapshot.gymID) {
                sessions[snapshot.gymID] = updated
            }
        }
    }

    // MARK: Notifications

    private func postArrivalNotification(gymID: UUID) async {
        await scheduleNotification(
            identifier: Self.arrivalNotificationPrefix + gymID.uuidString,
            title: Copy.gym.arrivalNotificationTitle(gym: gymName(for: gymID)),
            body: Copy.gym.arrivalNotificationBody(minutes: requiredMinutes),
            after: nil
        )
    }

    private func scheduleTargetNotification(gymID: UUID) async {
        guard let snapshot = sessions[gymID], snapshot.isActive, !snapshot.isVerified else { return }
        let due = snapshot.enteredAt.addingTimeInterval(TimeInterval(requiredMinutes * 60))
        let interval = due.timeIntervalSinceNow
        guard interval > 1 else { return }
        await scheduleNotification(
            identifier: Self.targetNotificationPrefix + gymID.uuidString,
            title: Copy.gym.targetNotificationTitle(minutes: requiredMinutes),
            body: Copy.gym.targetNotificationBody,
            after: interval
        )
    }

    /// Builds and adds the request in one scope (same shape as `SunriseAlarmManager`'s fallback
    /// chain), so the non-`Sendable` request never crosses a function boundary before `add`.
    /// Doesn't ask for notification permission — onboarding does; if it's off, this is a no-op.
    private func scheduleNotification(identifier: String, title: String, body: String, after interval: TimeInterval?) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Same key/value `ZANONotificationDelegate` routes for shield notifications.
        content.userInfo = ["deepLink": "zano://today"]
        let trigger = interval.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.notice("Gym notification not scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    private func cancelNotifications(gymID: UUID) {
        let center = UNUserNotificationCenter.current()
        let identifiers = [
            Self.arrivalNotificationPrefix + gymID.uuidString,
            Self.targetNotificationPrefix + gymID.uuidString,
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: SwiftData

    private struct GymSummary {
        let id: UUID
        let name: String?
    }

    private func confirmedGyms() -> [GymSummary] {
        let context = ModelContext(ModelContainer.appGroup)
        let gyms = (try? context.fetch(FetchDescriptor<Gym>(predicate: #Predicate { $0.confirmed }))) ?? []
        return gyms.map { GymSummary(id: $0.id, name: $0.name) }
    }

    private func isGymGoalCompleteToday() -> Bool {
        let context = ModelContext(ModelContainer.appGroup)
        let goals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.active }))) ?? []
        guard let goalID = goals.filter({ $0.type == .workoutGym }).max(by: { $0.createdAt < $1.createdAt })?.id else {
            return false
        }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= startOfDay }
        ))) ?? []
        return events.contains { $0.goal?.id == goalID && $0.kind == .complete && $0.verified }
    }

    private func gymName(for gymID: UUID) -> String {
        let name = confirmedGyms().first { $0.id == gymID }?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return Copy.gym.fallbackName }
        return name
    }
}
