// Core/Sources/Core/Watch/WatchSyncManager.swift
//
// docs/spec.md §5.21 (Apple Watch: "Complication with rings; start focus/lock from the wrist; ...
// haptic 'verified' tap when the gym dwell threshold is hit") and §11 (Architecture — ZANOWatch is
// a sibling target of the app; "local-first, unlock must be instant and offline" — nothing here is
// ever on the unlock path, this only mirrors state to the wrist and relays wrist actions).
//
// This is the iPhone half of the WatchConnectivity contract whose watch half is
// `Watch/ZANOWatch/WatchConnectivityBridge.swift` + `WatchStateModels.swift` (both read in full
// before this file was written; that bridge's own header flags this file's absence as its "KNOWN
// GAP"). `Watch/ZANOWatch` cannot `import Core` and `Core` cannot see that target's types either, so
// the wire shapes below are hand-mirrored — every key name, raw value, and envelope key here is a
// verbatim copy of what the watch encodes/decodes and must be kept in lockstep with it:
//
//   phone -> watch  `WCSession.updateApplicationContext([ "zano.watchStateSnapshot": <JSON Data> ])`
//                   where the Data is a default-strategy `JSONEncoder` encoding of
//                   `WatchStateSnapshotPayload` (mirrors the watch's `WatchStateSnapshot` field for
//                   field; see that type's doc comment for the one intentional extra field).
//   watch -> phone  a plain `[String: Any]` built by the watch's `WatchToPhoneRequest.asMessage`,
//                   delivered via `sendMessage` (with a reply handler), or — when the phone was
//                   unreachable — `transferUserInfo`. `WatchSyncRequest(message:)` below decodes it.
//
// Public surface is exactly `WatchSyncManager.shared.activate()`. Everything else is file-private.
//
// Why a thin public facade + a private `@MainActor` coordinator instead of one class: (1) the call
// site (a later phase wires it into `ZANOApp`) can then call `activate()` synchronously from any
// isolation domain with no `await`; (2) `WCSessionDelegate` callbacks arrive on WatchConnectivity's
// own private queue, so the delegate conformance lives on a separate non-isolated object that turns
// each callback into a `Sendable` value *before* hopping to the main actor — the `[String: Any]`
// message dictionaries (not `Sendable`) never cross an isolation boundary, only the decoded
// `WatchSyncRequest` does.
//
// User-facing copy: none. Ring value text is composed numeric data ("72/150g", "12/25 min" — the
// same numbers and unit spacing `TodayView` shows, in a compact one-line form for the wrist), a goal
// without a numeric target is sent as a bare ring (`nil` value text), and the unnamed-gym fallback
// is an empty string; anything the wrist displays as prose comes from the watch's own
// `Copy.watch`. The `code` strings in wrist replies are machine-readable diagnostics the watch
// never renders.

import ActivityKit
import FamilyControls
import Foundation
import SwiftData
import WatchConnectivity
import os

// MARK: - Public entry point

/// Mirrors ZANO state to the paired Apple Watch and carries out actions the wrist asks for.
///
/// Call `WatchSyncManager.shared.activate()` once, early at launch (the watch may be waiting on the
/// phone to wake it). Safe to call from any thread/actor and safe to call more than once — only the
/// first call does anything. On a device that can't pair a watch (`WCSession.isSupported() ==
/// false`, e.g. iPad) it logs once and does nothing else.
public final class WatchSyncManager: Sendable {
    public static let shared = WatchSyncManager()

    private init() {}

    /// Starts `WCSession.default` and begins pushing state to the watch. The work itself runs on the
    /// main actor a moment after this returns (never blocks the caller).
    public func activate() {
        Task { @MainActor in
            WatchSyncCoordinator.shared.start()
        }
    }
}

// MARK: - Coordinator

@MainActor
private final class WatchSyncCoordinator {
    static let shared = WatchSyncCoordinator()

    // MARK: Constants

    /// The one dictionary key the watch reads the snapshot under
    /// (`WatchConnectivityBridge.snapshotPayloadKey`). Must match exactly.
    private static let snapshotPayloadKey = "zano.watchStateSnapshot"

    /// Poll cadence when nothing time-sensitive is on screen. Polling is required regardless of the
    /// change notifications below: goal logging, shield-action and widget-intent processes write
    /// the shared App Group store from *other processes*, which no in-process notification reports.
    private static let idlePollInterval: Double = 60
    /// Poll cadence while a wrist-started focus countdown or a gym dwell is being shown, since the
    /// watch renders those values straight from the last snapshot (it does not tick locally).
    private static let activePollInterval: Double = 15
    /// An unchanged snapshot is re-sent at least this often so its `updatedAt` stays meaningful
    /// ("last synced" — `WatchStateModels.swift`) instead of ageing while nothing has changed.
    private static let heartbeatInterval: TimeInterval = 15 * 60
    /// `GymVerifier` has no "still inside the geofence" query. Its dwell minutes only ever grow
    /// while the person is inside and freeze once they leave, so a dwell that hasn't advanced for
    /// this long (comfortably > one minute-tick plus a poll interval) is treated as "left the gym"
    /// and hidden from the wrist instead of showing a frozen "at the gym" state for the rest of the
    /// day.
    private static let gymDwellFreezeTimeout: TimeInterval = 150

    /// The mode the wrist's one-tap "Start Lock" suggests. `StartLockIntent`, onboarding's first win
    /// and NFC-mapped locks all default to `.full`, as does the watch's own
    /// `WatchStateSnapshot.suggestedLockMode` default; `TodayView`'s "Begin lock" is the one
    /// outlier (`.earn`). docs/spec.md's open question "Earn Mode default: on or off for new users?"
    /// is unresolved, so this follows the majority. Flip here if product decides otherwise.
    private static let suggestedLockMode: LockMode = .full

    /// Placeholder for a lock whose `LockSession.lockSetID` was never recorded. The watch only uses
    /// an active lock's `sessionID` (for Emergency Unlock) and `goalsRemaining`, so sending a zero
    /// UUID is far better than dropping the lock — and with it the wrist's way out.
    private static let unknownLockSetID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    // MARK: State

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "WatchSyncManager")

    private var hasStarted = false
    private var session: WCSession?
    /// `WCSession.delegate` is a weak reference, so this is what keeps the delegate alive.
    private var sessionDelegate: WatchSessionDelegate?
    private var defaultsObserver: (any NSObjectProtocol)?
    private var pollTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    /// Tail of the serial chain wrist requests run on (see `enqueue`).
    private var requestTail: Task<Void, Never>?

    private var isPushing = false
    private var pushRequestedWhilePushing = false
    private var lastPushedSnapshot: WatchStateSnapshotPayload?
    private var pollInterval: Double = 60

    /// Focus sessions this coordinator started on the wrist's behalf. `FocusSessionVerifier` keeps
    /// its running sessions private and exposes no way to list them, so this is the only way the
    /// watch snapshot can carry a real `sessionID` for the wrist's "End Session" button. Sessions
    /// started from the phone UI, a widget, or Siri are therefore not reflected on the wrist (see
    /// this task's knownIssues) — inventing an id for them would make "End Session" fail silently.
    private var trackedFocusSessions: [UUID: TrackedFocusSession] = [:]

    private struct TrackedFocusSession {
        let id: UUID
        let goalID: UUID
        let plannedMinutes: Int
        let startedAt: Date
    }

    private struct GymObservation {
        var minutes: Int
        var changedAt: Date
    }
    private var gymObservations: [UUID: GymObservation] = [:]

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard WCSession.isSupported() else {
            logger.notice("WatchConnectivity is unsupported on this device; watch sync is disabled.")
            return
        }

        let session = WCSession.default
        let delegate = WatchSessionDelegate { event in
            Task { @MainActor in
                WatchSyncCoordinator.shared.handle(event)
            }
        }
        session.delegate = delegate
        self.session = session
        self.sessionDelegate = delegate
        session.activate()

        startObservingState()
    }

    private func handle(_ event: WatchSyncEvent) {
        switch event {
        case .activationDidComplete(let isActivated, let errorDescription):
            if let errorDescription {
                logger.error("WCSession activation finished with an error: \(errorDescription, privacy: .public)")
            }
            if isActivated {
                lastPushedSnapshot = nil
                schedulePush(after: .milliseconds(200))
            }

        case .reachabilityChanged:
            schedulePush(after: .seconds(1))

        case .watchStateChanged:
            // A different/re-installed watch has none of what we last sent: forget it so the next
            // build is pushed even though nothing on the phone changed.
            lastPushedSnapshot = nil
            schedulePush(after: .milliseconds(500))

        case .didDeactivate:
            // Required by the iOS `WCSessionDelegate` contract: after the user switches to a new
            // paired watch the old session deactivates and must be re-activated to talk to the new
            // one.
            session?.activate()

        case .received(let request, let reply):
            enqueue(request, reply: reply)

        case .unrecognized(let reply):
            // Answer anyway so the watch's `replyHandler` isn't left hanging until it times out.
            logger.notice("Ignoring an unrecognized or malformed message from the watch.")
            reply?.send(.failure("unrecognized_request"))
        }
    }

    // MARK: - Observing state

    private func startObservingState() {
        // SharedDefaults mirrors (active lock, streak, Time Bank) are written in-process by the
        // engines that own them; this makes lock start/end reach the wrist within seconds instead
        // of waiting for the next poll. Deliberately unfiltered (`SharedDefaults`' suite is
        // private) and heavily debounced — building a snapshot is cheap and unchanged snapshots are
        // never sent.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in
                WatchSyncCoordinator.shared.schedulePush(after: .seconds(2))
            }
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                self.schedulePush(after: .zero)
            }
        }
    }

    // MARK: - Pushing snapshots (phone -> watch)

    /// Coalesces bursts of triggers (a save, a defaults write, a reachability flip) into one build.
    private func schedulePush(after delay: Duration) {
        guard pushTask == nil else { return }
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            self.pushTask = nil
            await self.pushSnapshot()
        }
    }

    /// Serializes builds: a trigger that lands while one is in flight just asks for one more pass.
    private func pushSnapshot() async {
        if isPushing {
            pushRequestedWhilePushing = true
            return
        }
        isPushing = true
        defer { isPushing = false }

        repeat {
            pushRequestedWhilePushing = false
            await buildAndSend()
        } while pushRequestedWhilePushing
    }

    private func buildAndSend() async {
        // `updateApplicationContext` throws unless the session is activated, a watch is paired, and
        // the watch app is installed — skip quietly (and skip the SwiftData work) until they are.
        // `sessionWatchStateDidChange`/activation re-trigger a push when that changes.
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }

        guard let snapshot = await buildSnapshot() else { return }

        if let last = lastPushedSnapshot,
           last.hasSameContent(as: snapshot),
           snapshot.updatedAt.timeIntervalSince(last.updatedAt) < Self.heartbeatInterval {
            return
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            // Application context: "latest wins", delivered even if the watch app isn't running,
            // and — unlike `sendMessage` racing it — can never leave the watch on an older snapshot
            // (the watch does not compare `updatedAt` before applying).
            try session.updateApplicationContext([Self.snapshotPayloadKey: data])
            lastPushedSnapshot = snapshot
        } catch {
            lastPushedSnapshot = nil
            logger.error("updateApplicationContext failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Building a snapshot

    /// Reads current state from the shared App Group store and `SharedDefaults`, or `nil` when there
    /// is nothing worth sending yet (no `User` row — pre-onboarding) or a read failed (better to
    /// leave the watch on its last good snapshot than to overwrite it with a half-empty one).
    private func buildSnapshot() async -> WatchStateSnapshotPayload? {
        // A fresh context per build (as the App Intents do): a long-lived one can serve stale
        // objects for rows another context or process has since changed.
        let context = ModelContext(ModelContainer.appGroup)
        // Every `Goal`/`GoalEvent`/`Gym`/... below is read (relationships included) well after the
        // last explicit use of `context`, some of it across an `await`. Swift may release a local
        // after its last use, and SwiftData model objects do not keep their context alive, so pin
        // it until this function returns rather than trust the optimizer's lifetime for it.
        defer { withExtendedLifetime(context) {} }
        guard let user = try? IntentSupport.currentUser(in: context) else { return nil }
        let userID = user.id

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

        let goals: [Goal]
        let events: [GoalEvent]
        let plans: [DailyPlan]
        let lockSets: [LockSet]
        let gyms: [Gym]
        let activeSession: LockSession?
        do {
            goals = try context.fetch(FetchDescriptor<Goal>(
                predicate: #Predicate { $0.user?.id == userID },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            events = try context.fetch(FetchDescriptor<GoalEvent>(
                predicate: #Predicate { $0.ts >= startOfDay }
            ))
            plans = try context.fetch(FetchDescriptor<DailyPlan>(
                predicate: #Predicate { $0.date >= startOfDay && $0.date < startOfTomorrow }
            ))
            lockSets = try context.fetch(FetchDescriptor<LockSet>(
                predicate: #Predicate { $0.userID == userID },
                sortBy: [SortDescriptor(\.name)]
            ))
            gyms = try context.fetch(FetchDescriptor<Gym>(
                predicate: #Predicate { $0.userID == userID && $0.confirmed }
            ))
            activeSession = try IntentSupport.activeLockSession(for: userID, in: context)
        } catch {
            logger.error("Snapshot read failed; leaving the watch on its last snapshot: \(String(describing: error), privacy: .public)")
            return nil
        }

        pruneFinishedFocusSessions(in: context)

        var eventsByGoal: [UUID: [GoalEvent]] = [:]
        for event in events {
            if let goalID = event.goal?.id {
                eventsByGoal[goalID, default: []].append(event)
            }
        }
        var planByGoal: [UUID: DailyPlan] = [:]
        for plan in plans {
            if let goalID = plan.goal?.id, planByGoal[goalID] == nil {
                planByGoal[goalID] = plan
            }
        }
        let goalsByID = Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let activeGoals = goals.filter(\.active)

        // Rings: only goals the person actually has. An unconfigured ring is omitted rather than
        // sent as a misleading 0% (the watch and its complication both tolerate a missing kind).
        // Same goal-per-ring selection and progress math as `TodayView`, so the wrist always agrees
        // with the Today screen.
        var rings: [WatchStateSnapshotPayload.Ring] = []
        var workoutGoal: Goal?
        var focusGoal: Goal?
        for kind in WatchStateSnapshotPayload.Ring.Kind.allCases {
            guard let goal = activeGoals.first(where: { Self.ringKind(for: $0.type) == kind }) else { continue }
            let progress = Self.progress(for: goal, events: eventsByGoal[goal.id] ?? [], plan: planByGoal[goal.id])
            rings.append(WatchStateSnapshotPayload.Ring(kind: kind, progress: progress.fraction, valueText: progress.valueText))
            if kind == .workout { workoutGoal = goal }
            if kind == .focus { focusGoal = goal }
        }

        var activeLock: WatchStateSnapshotPayload.ActiveLock?
        if let activeSession {
            // Live count from today's progress (what `TodayView` shows) rather than
            // `SharedDefaults.goalsRemainingForActiveLock`, which is only refreshed when something
            // calls `evaluateUnlockEligibility`.
            let goalsRemaining = activeSession.requiredGoalIDs.filter { goalID in
                guard let goal = goalsByID[goalID] else { return false }
                let progress = Self.progress(for: goal, events: eventsByGoal[goalID] ?? [], plan: planByGoal[goalID])
                return progress.fraction < 1
            }.count
            activeLock = WatchStateSnapshotPayload.ActiveLock(
                sessionID: activeSession.id,
                lockSetID: activeSession.lockSetID ?? SharedDefaults.activeLockSetID ?? Self.unknownLockSetID,
                mode: activeSession.mode ?? SharedDefaults.activeLockMode ?? .full,
                goalsRemaining: goalsRemaining
            )
        }

        // Suggest a lock only when tapping it could actually work: authorized, at least one goal to
        // gate it on (`TodayView`'s `.setupIncomplete` rule — a goal-less lock can only end via
        // emergency/manual), and a lock set that has an app selection to shield. The watch shows no
        // error when the phone fails a request, so it must not be offered one that would.
        var suggestedLockSetID: UUID?
        var suggestedLockRequiredGoalIDs: [UUID] = []
        if AuthorizationCenter.shared.authorizationStatus == .approved, !activeGoals.isEmpty {
            let shieldable = lockSets.filter { $0.appTokensBlob != nil }
            if let lockSet = shieldable.first(where: \.isDefault) ?? shieldable.first {
                suggestedLockSetID = lockSet.id
                suggestedLockRequiredGoalIDs = activeGoals.map(\.id)
            }
        }

        let requiredGymMinutes = Self.requiredGymDwellMinutes(for: workoutGoal)
        let gymDwell = await gymDwellSnapshot(gyms: gyms, requiredMinutes: requiredGymMinutes, now: now)
        let focusSession = focusSessionSnapshot(goalsByID: goalsByID, now: now)

        pollInterval = (gymDwell != nil || focusSession != nil)
            ? Self.activePollInterval
            : Self.idlePollInterval

        return WatchStateSnapshotPayload(
            rings: rings,
            currentStreak: SharedDefaults.currentStreak,
            activeLock: activeLock,
            gymDwell: gymDwell,
            focusSession: focusSession,
            suggestedLockSetID: suggestedLockSetID,
            suggestedLockRequiredGoalIDs: suggestedLockRequiredGoalIDs,
            suggestedLockMode: Self.suggestedLockMode,
            suggestedFocusGoalID: focusGoal?.id,
            suggestedFocusGoalTitle: focusGoal?.title,
            // `SharedDefaults` documents this pair: a balance mirrored before local midnight is
            // stale and must read as 0 ("no hoarding", spec §5.2).
            timeBankRemainingMinutes: SharedDefaults.earnedMinutesMirrorIsForToday
                ? SharedDefaults.earnedMinutesRemainingToday
                : 0,
            updatedAt: now
        )
    }

    private static func ringKind(for type: GoalType) -> WatchStateSnapshotPayload.Ring.Kind? {
        switch type {
        case .workoutGym, .workoutHomeOutdoor: .workout
        case .protein: .protein
        case .focusSession: .focus
        case .water: .water
        default: nil
        }
    }

    private struct GoalProgress {
        let fraction: Double
        let valueText: String?
    }

    /// The same formula as `TodayView.progress(for:)` (private to that view, in the app target, so
    /// it can't be called from here): a `.complete`/`.verify`/`.planB` event today counts as done
    /// (Plan B days still count, spec §8); otherwise logged value over today's planned target (the
    /// `DailyPlan` if there is one, else `Goal.targetValue`). A goal with no numeric target is
    /// binary and gets no value text.
    private static func progress(for goal: Goal, events: [GoalEvent], plan: DailyPlan?) -> GoalProgress {
        let hasCompletion = events.contains { $0.kind == .complete || $0.kind == .verify || $0.kind == .planB }
        let target = plan?.plannedValue ?? goal.targetValue

        guard let target, target.isFinite, target > 0 else {
            return GoalProgress(fraction: hasCompletion ? 1 : 0, valueText: nil)
        }

        let summed = events.compactMap(\.value).reduce(0, +)
        let logged = summed.isFinite ? summed : 0
        let fraction = hasCompletion ? 1 : max(0, min(1, logged / target))
        let unit = goal.unit ?? ""
        return GoalProgress(
            fraction: fraction,
            valueText: "\(wholeNumber(logged))/\(amountText(wholeNumber(target), unit: unit))"
        )
    }

    /// `Int(_: Double)` traps on NaN/infinity/out-of-range; user-entered targets shouldn't be able to
    /// crash a background sync.
    private static func wholeNumber(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(max(-1_000_000_000, min(1_000_000_000, value.rounded())))
    }

    /// `"150g"` for a short symbol, `"25 min"` / `"3 workouts"` for a word — the same rule as the
    /// app target's `Copy.today.amount(_:unit:)` (internal to that module, so it can't be called
    /// from Core). Without the space a unit word runs into the number ("3workouts").
    private static func amountText(_ value: Int, unit: String) -> String {
        unit.count <= 2 ? "\(value)\(unit)" : "\(value) \(unit)"
    }

    /// How many minutes of gym dwell the wrist shows as "verified at N" and hands to
    /// `GymVerifier.isVerified`. Only a `.workoutGym` goal whose unit is minutes can override the
    /// spec default (§3: 35 min). Onboarding's Plan Reveal creates that goal with `targetValue` =
    /// workouts per week and unit `"workouts"`, so reading `targetValue` blindly (as
    /// `TodayView.pollGymDwell` does) would put a 3-minute dwell on the wrist and fire the
    /// "verified" haptic three minutes after arriving.
    private static func requiredGymDwellMinutes(for goal: Goal?) -> Int {
        let fallback = GymVerificationDefaults.requiredDwellMinutes
        guard let goal,
              goal.type == .workoutGym,
              let target = goal.targetValue, target.isFinite, target > 0,
              let unit = goal.unit?.lowercased(), unit.hasPrefix("min")
        else { return fallback }
        return max(1, wholeNumber(target))
    }

    // MARK: Gym dwell

    /// The gym the person is currently dwelling at, if any, in the shape `GymVerifier.
    /// currentContentState` produces (plus the gym's name). `GymVerifier` can only be asked about a
    /// specific `gymID` — `0` minutes means "not tracking" or "just started" — so this asks about
    /// each confirmed gym and hides a dwell that has stopped advancing (see
    /// `gymDwellFreezeTimeout`). The expensive anti-cheat check inside `isVerified` (Core Motion +
    /// HealthKit) is only run for the one gym that is actually being shown.
    private func gymDwellSnapshot(gyms: [Gym], requiredMinutes: Int, now: Date) async -> WatchStateSnapshotPayload.GymDwell? {
        var best: (gym: Gym, minutes: Int)?

        for gym in gyms {
            let minutes = await GymVerifier.shared.currentDwellMinutes(gymID: gym.id)
            if gymObservations[gym.id]?.minutes != minutes {
                gymObservations[gym.id] = GymObservation(minutes: minutes, changedAt: now)
            }
            guard minutes > 0,
                  let observation = gymObservations[gym.id],
                  now.timeIntervalSince(observation.changedAt) < Self.gymDwellFreezeTimeout
            else { continue }

            if best == nil || minutes > best?.minutes ?? 0 {
                best = (gym, minutes)
            }
        }

        guard let best else { return nil }
        let verified = await GymVerifier.shared.isVerified(gymID: best.gym.id, requiredMinutes: requiredMinutes)
        return WatchStateSnapshotPayload.GymDwell(
            gymName: best.gym.name ?? "",
            elapsedMinutes: best.minutes,
            verifiedAtMinutes: requiredMinutes,
            isVerified: verified
        )
    }

    // MARK: Focus session

    private func focusSessionSnapshot(goalsByID: [UUID: Goal], now: Date) -> WatchStateSnapshotPayload.FocusSession? {
        guard let tracked = trackedFocusSessions.values.max(by: { $0.startedAt < $1.startedAt }) else {
            return nil
        }
        let goalTitle = goalsByID[tracked.goalID]?.title ?? ""

        // Prefer the Live Activity's own state (real countdown + pause state, kept current by
        // `FocusSessionVerifier`'s tick loop). Matched by the attributes it was created from, since
        // the verifier's session id isn't exposed on the Activity.
        let liveActivity = Activity<FocusActivityAttributes>.activities.first {
            $0.attributes.goalTitle == goalTitle && $0.attributes.plannedMinutes == tracked.plannedMinutes
        }
        if let state = liveActivity?.content.state {
            return WatchStateSnapshotPayload.FocusSession(
                sessionID: tracked.id,
                goalTitle: goalTitle,
                plannedMinutes: tracked.plannedMinutes,
                secondsRemaining: state.secondsRemaining,
                isPaused: state.isPaused
            )
        }

        // No Live Activity (disabled, or the session began while the app was backgrounded, where
        // ActivityKit refuses to start one): estimate from wall-clock time. Cannot know about a
        // pause — `FocusSessionVerifier` doesn't expose it — so this reports "not paused".
        let elapsed = Int(now.timeIntervalSince(tracked.startedAt))
        return WatchStateSnapshotPayload.FocusSession(
            sessionID: tracked.id,
            goalTitle: goalTitle,
            plannedMinutes: tracked.plannedMinutes,
            secondsRemaining: max(0, tracked.plannedMinutes * 60 - elapsed),
            isPaused: false
        )
    }

    /// Forgets a tracked session once `FocusSessionVerifier` has ended it by any route. Its
    /// `endSession` always logs exactly one `.timer`-sourced `GoalEvent` (`.complete` or `.miss`)
    /// against the goal, so such an event newer than the session's start means it is over. (The
    /// verifier's process-lifetime `runningSessions` dies with the app, and so does this dictionary,
    /// so the two can't drift apart across a relaunch.)
    private func pruneFinishedFocusSessions(in context: ModelContext) {
        guard let earliest = trackedFocusSessions.values.map(\.startedAt).min() else { return }
        let descriptor = FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.ts >= earliest })
        guard let events = try? context.fetch(descriptor) else { return }

        var finished: [UUID] = []
        for tracked in trackedFocusSessions.values {
            let ended = events.contains {
                $0.source == .timer && $0.goal?.id == tracked.goalID && $0.ts >= tracked.startedAt
            }
            if ended { finished.append(tracked.id) }
        }
        for id in finished {
            trackedFocusSessions[id] = nil
        }
    }

    // MARK: - Handling wrist requests (watch -> phone)

    /// Runs requests strictly one after another, in arrival order. `transferUserInfo` deliveries can
    /// arrive back-to-back after a period out of range, and e.g. a queued "start" followed by "end"
    /// must not race.
    private func enqueue(_ request: WatchSyncRequest, reply: WatchSyncReplyBox?) {
        let previous = requestTail
        requestTail = Task { [weak self] in
            _ = await previous?.value
            guard let self else {
                reply?.send(.failure("unavailable"))
                return
            }
            let outcome = await self.perform(request)
            reply?.send(outcome)
            // Show the result on the wrist right away instead of at the next poll.
            self.schedulePush(after: .milliseconds(300))
        }
    }

    private func perform(_ request: WatchSyncRequest) async -> WatchSyncOutcome {
        switch request {
        case .startFocusSession(let goalID, let plannedMinutes):
            return await performStartFocusSession(goalID: goalID, plannedMinutes: plannedMinutes)
        case .endFocusSession(let sessionID):
            return await performEndFocusSession(sessionID: sessionID)
        case .startLock(let lockSetID, let mode, let requiredGoalIDs, let trigger):
            return await performStartLock(lockSetID: lockSetID, mode: mode, requiredGoalIDs: requiredGoalIDs, trigger: trigger)
        case .emergencyUnlock(let sessionID):
            return await performEmergencyUnlock(sessionID: sessionID)
        }
    }

    /// Direct pass-through to `FocusSessionVerifier.startSession(goalID:plannedMinutes:)` (the
    /// watch's `.startFocusSession` mirrors that signature 1:1), plus bookkeeping so the resulting
    /// session can be shown and ended from the wrist.
    private func performStartFocusSession(goalID: UUID, plannedMinutes: Int) async -> WatchSyncOutcome {
        guard plannedMinutes > 0 else { return .failure("invalid_planned_minutes") }

        pruneFinishedFocusSessions(in: ModelContext(ModelContainer.appGroup))
        // A repeated delivery (a queued request replayed after the wrist retried) must not start a
        // second concurrent session.
        if trackedFocusSessions.values.contains(where: { $0.goalID == goalID }) {
            return .success("already_running")
        }

        do {
            let sessionID = try await FocusSessionVerifier.shared.startSession(goalID: goalID, plannedMinutes: plannedMinutes)
            trackedFocusSessions[sessionID] = TrackedFocusSession(
                id: sessionID,
                goalID: goalID,
                plannedMinutes: plannedMinutes,
                startedAt: .now
            )
            Analytics.shared.capture(
                event: "watch_start_focus",
                properties: ["minutes": plannedMinutes, "goal_id": goalID.uuidString]
            )
            return .success("started")
        } catch {
            logger.error("Wrist focus start failed: \(String(describing: error), privacy: .public)")
            return .failure("start_focus_failed")
        }
    }

    /// Direct pass-through to `FocusSessionVerifier.endSession(sessionID:)`. Ending a session that is
    /// already gone (ended on the phone, or the app was relaunched) is a success as far as the wrist
    /// is concerned — there is nothing left to end.
    private func performEndFocusSession(sessionID: UUID) async -> WatchSyncOutcome {
        do {
            let verified = try await FocusSessionVerifier.shared.endSession(sessionID: sessionID)
            trackedFocusSessions[sessionID] = nil
            Analytics.shared.capture(
                event: "watch_end_focus",
                properties: ["session_id": sessionID.uuidString, "verified": verified]
            )
            return .success("ended")
        } catch let error as FocusSessionVerifierError {
            if case .sessionNotFound = error {
                trackedFocusSessions[sessionID] = nil
                return .success("already_ended")
            }
            logger.error("Wrist focus end failed: \(String(describing: error), privacy: .public)")
            return .failure("end_focus_failed")
        } catch {
            logger.error("Wrist focus end failed: \(String(describing: error), privacy: .public)")
            return .failure("end_focus_failed")
        }
    }

    /// Pass-through to `LockEngineManager.startLock(lockSetID:mode:requiredGoalIDs:trigger:)`, with
    /// the same defaults `StartLockIntent` applies (an empty goal list means "every active goal" —
    /// a lock with no required goals could only ever end manually) and one guard it lacks: never
    /// stack a second lock on top of an active one (that would orphan the first session's shield
    /// mirror), which a replayed queued request could otherwise cause.
    private func performStartLock(
        lockSetID: UUID,
        mode: LockMode,
        requiredGoalIDs: [UUID],
        trigger: LockTrigger
    ) async -> WatchSyncOutcome {
        let context = ModelContext(ModelContainer.appGroup)
        guard let user = try? IntentSupport.currentUser(in: context) else {
            return .failure("no_user")
        }
        if (try? IntentSupport.activeLockSession(for: user.id, in: context)) != nil {
            return .success("already_locked")
        }

        let goalIDs: [UUID]
        if requiredGoalIDs.isEmpty {
            goalIDs = (try? IntentSupport.activeGoalIDs(for: user.id, in: context)) ?? []
        } else {
            goalIDs = requiredGoalIDs
        }

        do {
            _ = try await LockEngineManager.shared.startLock(
                lockSetID: lockSetID,
                mode: mode,
                requiredGoalIDs: goalIDs,
                trigger: trigger
            )
            Analytics.shared.capture(
                event: "watch_start_lock",
                properties: [
                    "mode": mode.rawValue,
                    "lock_set_id": lockSetID.uuidString,
                    "required_goal_count": goalIDs.count,
                ]
            )
            return .success("started")
        } catch {
            logger.error("Wrist lock start failed: \(String(describing: error), privacy: .public)")
            return .failure("start_lock_failed")
        }
    }

    /// Direct pass-through to `LockEngineManager.emergencyUnlock(sessionID:)` — the watch's
    /// `.emergencyUnlock` documents itself as mirroring exactly that call, and CLAUDE.md's "never
    /// ship a lock with no way out" means nothing here may add a condition that could refuse it.
    ///
    /// Deliberately NOT added here (product decisions flagged in this task's knownIssues): the phone
    /// flow's 60-second hold and its default streak-miss penalty (`EmergencyUnlock`). The wrist
    /// confirms with a 2-second hold and shows no penalty disclosure, so silently recording a
    /// streak miss the person was never told about seemed worse than the gap.
    ///
    /// A session that is already over (`sessionAlreadyEnded`/`sessionNotFound`) is reported as
    /// success — the snapshot pushed right after this reflects whatever is actually locked now, so
    /// a stale session id can never make the wrist believe it unlocked something it didn't.
    private func performEmergencyUnlock(sessionID: UUID) async -> WatchSyncOutcome {
        do {
            try await LockEngineManager.shared.emergencyUnlock(sessionID: sessionID)
            Analytics.shared.capture(
                event: "watch_emergency_unlock",
                properties: ["session_id": sessionID.uuidString]
            )
            return .success("unlocked")
        } catch let error as LockEngineError {
            switch error {
            case .sessionAlreadyEnded, .sessionNotFound:
                logger.notice("Wrist emergency unlock for a session that is already over: \(sessionID.uuidString, privacy: .public)")
                return .success("already_ended")
            default:
                logger.error("Wrist emergency unlock failed: \(String(describing: error), privacy: .public)")
                return .failure("emergency_unlock_failed")
            }
        } catch {
            logger.error("Wrist emergency unlock failed: \(String(describing: error), privacy: .public)")
            return .failure("emergency_unlock_failed")
        }
    }
}

// MARK: - Wire types

/// The JSON the watch decodes as `WatchStateSnapshot` (`Watch/ZANOWatch/WatchStateModels.swift`).
/// Property names, nesting, and raw values are deliberately identical to the watch's types because
/// Swift's synthesized `Codable` keys are the property names. Encoded with a default `JSONEncoder`
/// (the watch decodes with a default `JSONDecoder`), so dates are the default seconds-since-2001
/// numbers and UUIDs are strings — do not add a custom strategy on either side.
///
/// `LockMode` is used directly for the watch's `WatchLockModeMirror` fields: the watch mirrors its
/// raw values (`full`/`earn`) on purpose. `Ring.Kind` mirrors `WatchRingKind`.
///
/// The one deliberate difference: `timeBankRemainingMinutes` does not exist in the watch's
/// `WatchStateSnapshot` today. The watch's synthesized decoder ignores unknown keys, so it is
/// harmless now, and it gives the wrist the Time Bank balance (`SharedDefaults.
/// earnedMinutesRemainingToday`, spec §5.2/§5.11) the day the watch adds a matching
/// `timeBankRemainingMinutes: Int` property — no phone change needed.
private struct WatchStateSnapshotPayload: Codable, Equatable, Sendable {
    struct Ring: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable, CaseIterable {
            case workout, protein, focus, water
        }

        var kind: Kind
        var progress: Double
        var valueText: String?
    }

    struct ActiveLock: Codable, Equatable, Sendable {
        var sessionID: UUID
        var lockSetID: UUID
        var mode: LockMode
        var goalsRemaining: Int
    }

    struct GymDwell: Codable, Equatable, Sendable {
        var gymName: String
        var elapsedMinutes: Int
        var verifiedAtMinutes: Int
        var isVerified: Bool
    }

    struct FocusSession: Codable, Equatable, Sendable {
        var sessionID: UUID
        var goalTitle: String
        var plannedMinutes: Int
        var secondsRemaining: Int
        var isPaused: Bool
    }

    var rings: [Ring]
    var currentStreak: Int
    var activeLock: ActiveLock?
    var gymDwell: GymDwell?
    var focusSession: FocusSession?
    var suggestedLockSetID: UUID?
    var suggestedLockRequiredGoalIDs: [UUID]
    var suggestedLockMode: LockMode
    var suggestedFocusGoalID: UUID?
    var suggestedFocusGoalTitle: String?
    var timeBankRemainingMinutes: Int
    var updatedAt: Date

    /// Equality ignoring `updatedAt` — what "nothing changed since the last push" means.
    func hasSameContent(as other: WatchStateSnapshotPayload) -> Bool {
        var aligned = other
        aligned.updatedAt = updatedAt
        return aligned == self
    }
}

/// A wrist action, decoded from the `[String: Any]` the watch's `WatchToPhoneRequest.asMessage`
/// builds. Same keys, same `type` strings, same value encodings (UUIDs as strings; `mode`/`trigger`
/// as `LockMode`/`LockTrigger` raw values — identical by construction on both sides). Maps straight
/// onto the real Core types, so no translation table exists to drift.
private enum WatchSyncRequest: Sendable {
    case startFocusSession(goalID: UUID, plannedMinutes: Int)
    case endFocusSession(sessionID: UUID)
    case startLock(lockSetID: UUID, mode: LockMode, requiredGoalIDs: [UUID], trigger: LockTrigger)
    case emergencyUnlock(sessionID: UUID)

    private enum Key {
        static let type = "type"
        static let goalID = "goalID"
        static let plannedMinutes = "plannedMinutes"
        static let sessionID = "sessionID"
        static let lockSetID = "lockSetID"
        static let mode = "mode"
        static let requiredGoalIDs = "requiredGoalIDs"
        static let trigger = "trigger"
    }

    private enum TypeValue {
        static let startFocusSession = "startFocusSession"
        static let endFocusSession = "endFocusSession"
        static let startLock = "startLock"
        static let emergencyUnlock = "emergencyUnlock"
    }

    /// `nil` for anything malformed or unrecognized (an older/newer watch build's message shape) —
    /// the caller ignores and logs it, never crashes.
    init?(message: [String: Any]) {
        guard let type = message[Key.type] as? String else { return nil }
        switch type {
        case TypeValue.startFocusSession:
            guard let goalIDString = message[Key.goalID] as? String,
                  let goalID = UUID(uuidString: goalIDString),
                  let plannedMinutes = message[Key.plannedMinutes] as? Int
            else { return nil }
            self = .startFocusSession(goalID: goalID, plannedMinutes: plannedMinutes)

        case TypeValue.endFocusSession:
            guard let sessionIDString = message[Key.sessionID] as? String,
                  let sessionID = UUID(uuidString: sessionIDString)
            else { return nil }
            self = .endFocusSession(sessionID: sessionID)

        case TypeValue.startLock:
            guard let lockSetIDString = message[Key.lockSetID] as? String,
                  let lockSetID = UUID(uuidString: lockSetIDString),
                  let modeRaw = message[Key.mode] as? String,
                  let mode = LockMode(rawValue: modeRaw),
                  let requiredGoalIDStrings = message[Key.requiredGoalIDs] as? [String],
                  let triggerRaw = message[Key.trigger] as? String,
                  let trigger = LockTrigger(rawValue: triggerRaw)
            else { return nil }
            self = .startLock(
                lockSetID: lockSetID,
                mode: mode,
                requiredGoalIDs: requiredGoalIDStrings.compactMap(UUID.init(uuidString:)),
                trigger: trigger
            )

        case TypeValue.emergencyUnlock:
            guard let sessionIDString = message[Key.sessionID] as? String,
                  let sessionID = UUID(uuidString: sessionIDString)
            else { return nil }
            self = .emergencyUnlock(sessionID: sessionID)

        default:
            return nil
        }
    }
}

/// What a wrist request came to, as sent back through the watch's `replyHandler`. The watch only
/// uses the *arrival* of a reply (it clears its "couldn't reach iPhone" banner), so `code` is a
/// machine-readable diagnostic for logs and a future watch build — never user-facing prose.
private struct WatchSyncOutcome: Sendable {
    let succeeded: Bool
    let code: String

    static func success(_ code: String) -> WatchSyncOutcome {
        WatchSyncOutcome(succeeded: true, code: code)
    }

    static func failure(_ code: String) -> WatchSyncOutcome {
        WatchSyncOutcome(succeeded: false, code: code)
    }

    /// Plist-safe reply dictionary. Built only at the moment of sending, so the non-`Sendable`
    /// `[String: Any]` never crosses an isolation boundary.
    var asReply: [String: Any] {
        ["ok": succeeded, "code": code]
    }
}

/// Carries WatchConnectivity's reply handler across the hop from the delegate queue to the main
/// actor. `@unchecked Sendable` because the closure is a legacy, un-annotated ObjC block: it is
/// created once per message, only ever *called* (never mutated or shared), and exactly once.
private struct WatchSyncReplyBox: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func send(_ outcome: WatchSyncOutcome) {
        handler(outcome.asReply)
    }
}

/// Everything `WatchSessionDelegate` reports to the coordinator, reduced to `Sendable` values.
private enum WatchSyncEvent: Sendable {
    case activationDidComplete(isActivated: Bool, errorDescription: String?)
    case reachabilityChanged
    case watchStateChanged
    case didDeactivate
    case received(WatchSyncRequest, reply: WatchSyncReplyBox?)
    case unrecognized(reply: WatchSyncReplyBox?)
}

// MARK: - WCSessionDelegate

/// The iOS `WCSessionDelegate`. Deliberately not actor-isolated: WatchConnectivity calls it on its
/// own private queue, so every callback converts its arguments into a `Sendable` `WatchSyncEvent`
/// on the spot (decoding wrist messages into `WatchSyncRequest` right here) and hands only that to
/// `onEvent`, which hops to the main actor. `@unchecked Sendable` only because it inherits
/// `NSObject`; its sole stored property is an immutable `@Sendable` closure.
private final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onEvent: @Sendable (WatchSyncEvent) -> Void

    init(onEvent: @escaping @Sendable (WatchSyncEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    // MARK: Session lifecycle

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        onEvent(.activationDidComplete(
            isActivated: activationState == .activated,
            errorDescription: error.map { String(describing: $0) }
        ))
    }

    /// Required on iOS. Nothing to do: the session keeps delivering what was already in flight and
    /// `sessionDidDeactivate` is where a new watch takes over.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        onEvent(.didDeactivate)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        onEvent(.reachabilityChanged)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        onEvent(.watchStateChanged)
    }

    // MARK: Wrist requests

    /// Interactive message sent without a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message, reply: nil)
    }

    /// Interactive message sent WITH a reply handler — which is how the watch's
    /// `WatchConnectivityBridge.send` always sends while the phone is reachable. Without this
    /// overload WatchConnectivity would fail every such message back to the watch as unhandled.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        deliver(message, reply: WatchSyncReplyBox(replyHandler))
    }

    /// The watch's fallback when the phone was out of range: `transferUserInfo`, queued and
    /// delivered here once connectivity resumes.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliver(userInfo, reply: nil)
    }

    private func deliver(_ payload: [String: Any], reply: WatchSyncReplyBox?) {
        if let request = WatchSyncRequest(message: payload) {
            onEvent(.received(request, reply: reply))
        } else {
            onEvent(.unrecognized(reply: reply))
        }
    }
}
