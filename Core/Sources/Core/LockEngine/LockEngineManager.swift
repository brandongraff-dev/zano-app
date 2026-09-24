// Core/Sources/Core/LockEngine/LockEngineManager.swift
//
// The engine that actually locks and unlocks the phone: docs/spec.md §2 (The Core Loop —
// "LOCK → DO THE GOAL → VERIFIED → UNLOCK + STREAK"), §11 (Architecture — "LockEngine (shields,
// schedules, unlock rules, Time Bank)"), and §24 (Safety — "Any lock/shield feature must always
// keep an emergency-unlock path. Never trap the user.", mirrored in CLAUDE.md).
//
// This file owns:
//   - Applying/removing the ManagedSettings shield for a `LockSet`'s app tokens.
//   - Registering/deregistering `DeviceActivityCenter` monitoring for schedule-triggered locks.
//   - Persisting `LockSession` rows (the local + remote source of truth, spec §13 `lock_sessions`).
//   - Deciding unlock eligibility ("all required goals verified" — spec §2 "Unlock").
//
// `LockMode`, `LockTrigger`, and `UnlockKind` are declared here (not in `Models/LockSession.swift`)
// per this codebase's SYSTEM CONTRACTS: `LockSession` reuses these exact types rather than
// redeclaring them, so the two files can never drift apart (see `Models/LockSession.swift`'s doc
// comment).

import Foundation
import Observation
import SwiftData
import FamilyControls
import ManagedSettings
import DeviceActivity
import os

// MARK: - Shared enums (SYSTEM CONTRACTS shape — reused by `Models/LockSession.swift`)

/// Matches `lock_sessions.mode` (spec §13): whether a lock is a hard block until goals are done
/// (`.full`) or a Time Bank–style "earn minutes, spend minutes" lock (`.earn`, spec §5.2).
///
/// Explicitly `Sendable` (not just `String, Codable`, which is all CONTRACTS' shorthand spells
/// out): every other plain raw-value enum in `Core/Sources/Core/Models` (`GoalType`,
/// `VerificationTier`, `CoachVoice`, `GoalEventKind`, ...) declares `Sendable` explicitly, and
/// Swift only *implicitly* synthesizes `Sendable` for non-`public` types — a `public enum` like
/// this one needs it stated to actually get the conformance. This isn't optional here: `Core/
/// Sources/Core/Copy/ShieldCopy.swift`'s `ShieldContext: Sendable` stores a `LockMode?`, so
/// without this the whole struct fails to compile as `Sendable`.
public enum LockMode: String, Codable, Sendable {
    case full
    case earn
}

/// Matches `lock_sessions.trigger` (spec §2 "Lock triggers", §13): what caused this lock to
/// start. `Sendable` for the same reason as `LockMode` above (codebase-wide convention + a
/// `public` type needs it stated explicitly to get the conformance).
public enum LockTrigger: String, Codable, Sendable {
    case nfc
    case schedule
    case manual
    case auto
}

/// Matches `lock_sessions.unlock_kind` (spec §13, §14 `EndLockIntent`/`EmergencyUnlockIntent`):
/// how a lock ended. `Sendable` for the same reason as `LockMode` above.
public enum UnlockKind: String, Codable, Sendable {
    case earned
    case emergency
    case scheduleEnd
    case manual
}

// MARK: - Errors

/// Errors `LockEngineManager` throws. Kept as plain, developer-facing diagnostics (mirroring the
/// existing `ModelContainerError` convention in `Store/ModelContainer+AppGroup.swift`) rather than
/// routed through `Core/Sources/Core/Copy` — these describe engine/integration failures for logs
/// and `catch` sites, not copy meant to be shown verbatim in the shield or lock UI. Whatever
/// user-facing message a view chooses to show for one of these belongs in `Copy`, per CLAUDE.md.
public enum LockEngineError: Error, Sendable, LocalizedError {
    /// `AuthorizationCenter.shared.authorizationStatus != .approved`. Requesting authorization is
    /// deliberately NOT done here — see `knownIssues` — it belongs to onboarding/Family Controls
    /// setup, not to every `startLock` call.
    case authorizationNotGranted
    /// No `LockSet` exists locally with this id.
    case lockSetNotFound(UUID)
    /// The `LockSet` has no saved `FamilyActivitySelection` (`appTokensBlob` is `nil`) — nothing
    /// to shield.
    case noAppTokensSelected(lockSetID: UUID)
    /// `LockSet.appTokensBlob` exists but didn't decode as a `FamilyActivitySelection`.
    case invalidAppTokensBlob(lockSetID: UUID)
    /// No `LockSession` exists locally with this id.
    case sessionNotFound(UUID)
    /// The session was already ended (`endedAt`/`unlockKind` already set).
    case sessionAlreadyEnded(UUID)
    /// No local `User` row exists yet to attribute this session to.
    case noSignedInUser
    /// `DeviceActivityCenter.startMonitoring` threw for a schedule-triggered lock. The lock and
    /// its shield are still applied — see `startLock` — this only means the extra "keep
    /// monitoring even if the app is killed" registration didn't take.
    case deviceActivitySchedulingFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .authorizationNotGranted:
            "Family Controls authorization has not been granted."
        case .lockSetNotFound(let id):
            "No LockSet found with id \(id)."
        case .noAppTokensSelected(let lockSetID):
            "LockSet \(lockSetID) has no app selection to shield."
        case .invalidAppTokensBlob(let lockSetID):
            "LockSet \(lockSetID)'s saved app selection could not be decoded."
        case .sessionNotFound(let id):
            "No LockSession found with id \(id)."
        case .sessionAlreadyEnded(let id):
            "LockSession \(id) has already ended."
        case .noSignedInUser:
            "No local User row exists yet."
        case .deviceActivitySchedulingFailed(let reason):
            "Could not schedule DeviceActivity monitoring: \(reason)"
        }
    }
}

// MARK: - ManagedSettingsStore / DeviceActivity naming

extension ManagedSettingsStore.Name {
    /// The single named store ZANO uses to shield apps for whichever `LockSession` is currently
    /// active (spec §2, §11). A named store (rather than the default, unnamed one) keeps ZANO's
    /// managed settings scoped to this one purpose, so `clearAllSettings()` can fully reset the
    /// shield without risk of touching settings some other store/feature might set later.
    public nonisolated(unsafe) static let zanoLock = Self("com.zano.app.lockEngine")
}

extension DeviceActivityName {
    /// The `DeviceActivityCenter` monitoring name registered for a schedule-triggered
    /// `LockSession`, so `ZANOMonitor`'s `DeviceActivityMonitor` extension (spec §11 — a
    /// different target, not owned by this file) has a stable name to observe per session.
    static func zanoLockSession(_ sessionID: UUID) -> DeviceActivityName {
        DeviceActivityName("com.zano.app.lock.\(sessionID.uuidString)")
    }
}

// MARK: - LockEngineManager

/// The sole owner of creating and mutating `LockSession` rows (see `Models/LockSession.swift`'s
/// doc comment) and of the one `ManagedSettingsStore` ZANO shields apps through.
///
/// Declared `@MainActor` rather than as a bare `final class` with no isolation, or as an `actor`:
/// the SYSTEM CONTRACTS shape is a plain `final class` with a trivial `static let shared`, which
/// under Swift 6 strict concurrency requires either `Sendable` conformance (not realistic for a
/// class that owns a `ModelContext`, a `ManagedSettingsStore`, and a `DeviceActivityCenter`) or
/// isolation to a global actor. `@MainActor` is the natural choice here: `ManagedSettingsStore`
/// and `DeviceActivityCenter` are Apple APIs that Apple's own sample code always drives from the
/// main thread/actor, and every call site in this app (SwiftUI views, App Intents, which are
/// themselves commonly `@MainActor`-perform their side effects) is already on the main actor. This
/// is this file's one cross-cutting architectural assumption not spelled out in CONTRACTS — see
/// `decisions` in this task's report for the same note.
///
/// `@Observable` (added when the app shell was wired, `App/ZANO/ContentView.swift`) purely so
/// `lastUnlockedSessionID` below is trackable by SwiftUI — the same `@MainActor @Observable
/// public final class` shape `Verification/SunriseAlarmManager.swift` already uses. Every other
/// stored property here is a `let`, which the macro leaves untouched.
@MainActor
@Observable
public final class LockEngineManager {
    public static let shared = LockEngineManager()

    /// The `LockSession.id` of the lock that most recently ended, by *any* `UnlockKind` — the
    /// listener decides what a given kind deserves (the app shell only celebrates `.earned`, per
    /// spec §16 P3). `nil` until the first `endLock` of this process's lifetime. In-process only:
    /// a lock ended from another process (a widget/extension intent) never sets this on the app's
    /// own instance, so this is a live-UI signal, not a source of truth — `LockSession` rows are.
    public private(set) var lastUnlockedSessionID: UUID?

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let store: ManagedSettingsStore
    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "LockEngineManager")

    /// - Parameters:
    ///   - modelContainer: Defaults to the shared App Group container (spec §11). Overridable for
    ///     unit tests (an in-memory container) — nothing else in this initializer talks to disk.
    ///   - store: Defaults to the single named store this file always shields through (see
    ///     `ManagedSettingsStore.Name.zanoLock` above).
    ///   - activityCenter: Defaults to a fresh `DeviceActivityCenter`.
    init(
        modelContainer: ModelContainer = .appGroup,
        store: ManagedSettingsStore = ManagedSettingsStore(named: .zanoLock),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter()
    ) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.store = store
        self.activityCenter = activityCenter
    }

    // MARK: - Start / end (CONTRACTS)

    /// Applies the shield for `lockSetID`'s saved app selection, persists a new `LockSession`
    /// row, and — for `trigger == .schedule` — registers `DeviceActivityCenter` monitoring so
    /// `ZANOMonitor` can keep observing this lock even if the app isn't running.
    ///
    /// - Returns: the new `LockSession.id`.
    /// - Throws: `LockEngineError` (see cases above), or whatever `ModelContext.save()`/
    ///   `DeviceActivityCenter.startMonitoring` throw.
    @discardableResult
    public func startLock(
        lockSetID: UUID,
        mode: LockMode,
        requiredGoalIDs: [UUID],
        trigger: LockTrigger
    ) async throws -> UUID {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            throw LockEngineError.authorizationNotGranted
        }
        guard let lockSet = try fetchLockSet(id: lockSetID) else {
            throw LockEngineError.lockSetNotFound(lockSetID)
        }
        let selection = try decodeSelection(from: lockSet)
        applyShield(selection)
        // The screen-time report (ZANOReport) marks these apps' usage as locked-app time.
        SharedDefaults.lockedSelectionData = lockSet.appTokensBlob

        let user = try fetchCurrentUser()
        let session = LockSession(
            userID: user.id,
            lockSetID: lockSetID,
            startedAt: .now,
            trigger: trigger,
            mode: mode,
            requiredGoalIDs: requiredGoalIDs
        )
        context.insert(session)
        do {
            try context.save()
        } catch {
            // Roll back the shield we just applied — never leave the phone shielded with no
            // corresponding LockSession the user could ever end (CLAUDE.md: never trap them).
            removeShield()
            throw error
        }

        if trigger == .schedule {
            do {
                try armScheduleMonitoring(sessionID: session.id)
            } catch {
                // Non-fatal: the immediate shield + LockSession are already durable. Log and
                // surface via the thrown error so a caller can retry/report it, but the lock
                // itself is real and in effect either way.
                logger.error(
                    "startLock: DeviceActivity monitoring registration failed for session \(session.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                mirrorActiveLock(session)
                throw LockEngineError.deviceActivitySchedulingFailed(reason: String(describing: error))
            }
        }

        mirrorActiveLock(session)
        return session.id
    }

    /// Ends a `LockSession`: removes the shield, stops any `DeviceActivity` monitoring
    /// registered for it, and records how it ended.
    ///
    /// This does **not** itself re-validate `unlockKind` against `evaluateUnlockEligibility` —
    /// that check is `evaluateUnlockEligibility`'s job, and per spec §14 `EndLockIntent`
    /// ("Only allowed if goals complete or via Emergency flow") is the caller's (the App Intents
    /// layer's) responsibility to run before calling this with `.earned`/`.scheduleEnd`. Calling
    /// this with `.emergency` is always allowed unconditionally — see `emergencyUnlock` below —
    /// which is what keeps the emergency-unlock guarantee real.
    public func endLock(sessionID: UUID, unlockKind: UnlockKind) async throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw LockEngineError.sessionNotFound(sessionID)
        }
        guard session.isActive else {
            throw LockEngineError.sessionAlreadyEnded(sessionID)
        }

        session.endedAt = .now
        session.unlockKind = unlockKind
        try context.save()

        removeShield()
        if session.trigger == .schedule {
            activityCenter.stopMonitoring([.zanoLockSession(sessionID)])
        }
        clearActiveLockMirror(endedSessionID: sessionID)
        lastUnlockedSessionID = sessionID
    }

    /// `true` once every id in the session's `requiredGoalIDs` has a verified completion
    /// (`GoalEvent.kind` of `.complete`, `.planB`, or `.freeze`, with `verified == true`) logged
    /// since the start of the calendar day the session began — spec §2: "Unlock: when all
    /// *required* goals for the current lock are verified, shields drop." A session with an
    /// empty `requiredGoalIDs` (a pure full-mode lock with no earn condition) returns `false`,
    /// not vacuously `true`: it has nothing to "earn" its way out of and must end via schedule
    /// end / manual / emergency instead.
    ///
    /// Never throws: an inactive or missing session, or any fetch failure, is treated as "not
    /// eligible" rather than propagating an error — this is read by shield/widget copy that must
    /// never crash the caller for a stale id.
    public func evaluateUnlockEligibility(sessionID: UUID) async -> Bool {
        guard let session = try? fetchSession(id: sessionID), session.isActive else { return false }
        guard !session.requiredGoalIDs.isEmpty else { return false }

        let remaining = session.requiredGoalIDs.filter {
            !isGoalVerified(goalID: $0, coveringDayOf: session.startedAt)
        }
        SharedDefaults.goalsRemainingForActiveLock = remaining.count
        return remaining.isEmpty
    }

    /// Always-available escape hatch (spec §24, CLAUDE.md: "Any lock/shield feature must always
    /// keep an emergency-unlock path. Never trap the user."). Unconditionally ends the session
    /// with `unlockKind: .emergency` — no eligibility check, no authorization/shield-state
    /// precondition beyond the session existing and being active. The 60-second hold + optional
    /// streak-penalty UX in front of this call lives in `EmergencyUnlock.swift`.
    public func emergencyUnlock(sessionID: UUID) async throws {
        try await endLock(sessionID: sessionID, unlockKind: .emergency)
    }

    // MARK: - ManagedSettings

    private func applyShield(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    private func removeShield() {
        store.clearAllSettings()
    }

    // MARK: - DeviceActivity

    /// Registers a bounded (rest-of-day, non-repeating) `DeviceActivitySchedule` for this
    /// session so `ZANOMonitor` can observe it independent of the app's lifetime.
    ///
    /// Best-effort against the real `DeviceActivity` API surface (no Mac/compiler available in
    /// this session to verify against — see knownIssues): the *recurring* daily/weekly schedule
    /// a user configures for a `LockSet` (e.g. "lock at 7 AM every weekday") has no model yet in
    /// `Core/Sources/Core/Models` as of this task, so this only arms monitoring for the session
    /// that's starting right now, keyed by `sessionID`, rather than a recurring calendar rule.
    /// The recurring-schedule model/UI is a cross-module integration point for a future session.
    private func armScheduleMonitoring(sessionID: UUID) throws {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
        var endOfDay = DateComponents()
        endOfDay.hour = 23
        endOfDay.minute = 59
        endOfDay.second = 59
        let schedule = DeviceActivitySchedule(intervalStart: now, intervalEnd: endOfDay, repeats: false)
        try activityCenter.startMonitoring(.zanoLockSession(sessionID), during: schedule)
    }

    // MARK: - SwiftData

    private func fetchLockSet(id: UUID) throws -> LockSet? {
        var descriptor = FetchDescriptor<LockSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchSession(id: UUID) throws -> LockSession? {
        var descriptor = FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw LockEngineError.noSignedInUser
        }
        return user
    }

    private func decodeSelection(from lockSet: LockSet) throws -> FamilyActivitySelection {
        guard let blob = lockSet.appTokensBlob else {
            throw LockEngineError.noAppTokensSelected(lockSetID: lockSet.id)
        }
        do {
            return try JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
        } catch {
            throw LockEngineError.invalidAppTokensBlob(lockSetID: lockSet.id)
        }
    }

    /// Whether a verified completion of `goalID` was logged on the calendar day `date` falls on.
    ///
    /// Fetches `GoalEvent`s for the day by the cheap, `#Predicate`-safe fields only (`verified`,
    /// `ts`) and filters the rest (the `goal?.id` relationship lookup, and the `kind` enum
    /// comparison) in plain Swift. This is deliberately more conservative than pushing the whole
    /// filter into `#Predicate`: this session has no Mac/Swift toolchain to compile-verify how
    /// SwiftData's `#Predicate` macro handles optional-relationship chaining
    /// (`event.goal?.id == goalID`) or direct equality against a custom `Codable` enum on this
    /// SDK version, so the parts that are unambiguous (`Bool`/`Date` comparisons) stay in the
    /// predicate and the rest is filtered after the fetch. Flagged in knownIssues.
    private func isGoalVerified(goalID: UUID, coveringDayOf date: Date) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains { event in
            event.goal?.id == goalID
                && (event.kind == .complete || event.kind == .planB || event.kind == .freeze)
        }
    }

    // MARK: - SharedDefaults mirror (spec §5.1 Living Shield, §27 extensions read App Group only)

    private func mirrorActiveLock(_ session: LockSession) {
        SharedDefaults.activeLockSessionID = session.id
        SharedDefaults.activeLockSetID = session.lockSetID
        SharedDefaults.activeLockMode = session.mode
        SharedDefaults.goalsRemainingForActiveLock = session.requiredGoalIDs.count
    }

    private func clearActiveLockMirror(endedSessionID: UUID) {
        guard SharedDefaults.activeLockSessionID == endedSessionID else { return }
        SharedDefaults.activeLockSessionID = nil
        SharedDefaults.activeLockSetID = nil
        SharedDefaults.activeLockMode = nil
        SharedDefaults.goalsRemainingForActiveLock = 0
    }
}
