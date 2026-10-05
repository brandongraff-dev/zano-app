// Core/Sources/Core/LockEngine/LockHealthCheck.swift
//
// "Is the lock actually working?" — the trust pass on the lock (docs/spec.md §2 Lock, §24 "Never
// trap users", §27 "ManagedSettingsStore shields persist until removed").
//
// Two small, read-only helpers both the Today hero and the Lock tab use, so the two screens can
// never disagree about what the lock is doing:
//
//   - `LockHealthCheck`: notices when a lock is running (or scheduled) but ZANO can't actually
//     block anything — Screen Time access was turned off in Settings, or the ManagedSettings shield
//     is empty while a lock should be blocking. Views show a calm "Fix it" card for either.
//   - `LockBlockingSummary`: the one honest line under the hero — "Blocking 12 apps · ends when your
//     goals are done", "· ends at 9:00 PM" for a timed schedule, or "Apps open until 3:45 PM ·
//     locks again after" during a Time Bank window. Counts only: token *contents* are never read,
//     shown or sent anywhere (FamilyControls tokens never leave the device).
//
// Emergency unlock is untouched: nothing here ends, hides or gates a lock. The worst a health
// check can do is re-apply the shield the running lock already intends to show.
//
// The decisions are pure `nonisolated` functions (unit-tested, and callable from an extension
// with its own inputs); the `@MainActor` wrappers read live state (`AuthorizationCenter`,
// `ManagedSettingsStore`, App Group defaults) for the app's screens.

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - LockHealthStatus

/// What the self-check found. Ordered by how badly it breaks the lock: no Screen Time access
/// means nothing at all can be blocked, so it wins over a missing shield.
public enum LockHealthStatus: Sendable, Equatable {
    /// Nothing to worry about (or nothing running/scheduled to check).
    case ok
    /// A lock is running or scheduled but Screen Time access isn't approved: ZANO can't block apps.
    case screenTimeAccessOff
    /// A lock is running (and no Time Bank window is open) but ZANO's shield is empty.
    case shieldMissing

    public var needsAttention: Bool { self != .ok }
}

// MARK: - LockHealthCheck

public enum LockHealthCheck {

    /// The pure decision. `shieldPresent == nil` means "couldn't tell" and never reports
    /// `.shieldMissing` — an uncertain read must not raise a false alarm.
    public static func evaluate(
        isLockActive: Bool,
        hasEnabledSchedule: Bool,
        isAuthorized: Bool,
        isInSpendWindow: Bool,
        expectsShield: Bool,
        shieldPresent: Bool?
    ) -> LockHealthStatus {
        guard isLockActive || hasEnabledSchedule else { return .ok }
        guard isAuthorized else { return .screenTimeAccessOff }
        guard isLockActive, !isInSpendWindow, expectsShield, shieldPresent == false else { return .ok }
        return .shieldMissing
    }

    /// The live check. Call on every foreground and whenever the lock state changes.
    ///
    /// - Parameter isLockActive: the caller's own view of "a lock is running" (a SwiftUI `@Query`);
    ///   `nil` falls back to the App Group mirror (`SharedDefaults.activeLockSessionID`, or a
    ///   monitor-armed scheduled lock the app hasn't adopted yet).
    @MainActor
    public static func status(isLockActive: Bool? = nil, now: Date = .now) -> LockHealthStatus {
        let active = isLockActive
            ?? (SharedDefaults.activeLockSessionID != nil || LockEngineSharedState.pendingStart != nil)
        let window = LockEngineSharedState.spendWindow
        let intended = intendedSelection()
        return evaluate(
            isLockActive: active,
            hasEnabledSchedule: LockEngineSharedState.schedules.contains(where: \.isEnabled),
            isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved,
            isInSpendWindow: window.map { $0.endsAt > now } ?? false,
            expectsShield: intended.map(Self.hasAnyToken) ?? false,
            shieldPresent: active ? isZanoShieldApplied() : nil
        )
    }

    /// "Fix it" for `.screenTimeAccessOff`: asks for Screen Time access again (the system sheet),
    /// then — if it's back — re-applies the running lock's shield and re-registers schedules, since
    /// iOS may have dropped both while access was off. Returns the status afterwards.
    @MainActor
    public static func requestScreenTimeAccess(isLockActive: Bool? = nil) async -> LockHealthStatus {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            Analytics.shared.capture(event: "lock_health_fix_failed", properties: ["issue": "screen_time_access"])
            return status(isLockActive: isLockActive)
        }
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            LockEngineManager.shared.reapplyIntendedShield()
            LockScheduler.shared.rearmAll()
        }
        let result = status(isLockActive: isLockActive)
        Analytics.shared.capture(event: "lock_health_fixed", properties: ["issue": "screen_time_access", "ok": result == .ok])
        return result
    }

    /// "Fix it" for `.shieldMissing`: puts the running lock's intended shield back.
    @MainActor
    public static func repairShield(isLockActive: Bool? = nil) -> LockHealthStatus {
        LockEngineManager.shared.reapplyIntendedShield()
        let result = status(isLockActive: isLockActive)
        Analytics.shared.capture(event: "lock_health_fixed", properties: ["issue": "shield_missing", "ok": result == .ok])
        return result
    }

    // MARK: Internals

    static func hasAnyToken(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    private static func intendedSelection() -> FamilyActivitySelection? {
        guard let blob = LockEngineSharedState.intendedShieldSelection else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
    }

    /// Reads ZANO's named store back. UNVERIFIED on device: assumes a fresh
    /// `ManagedSettingsStore(named:)` reads the settings another instance (or the monitor
    /// extension) wrote, which is how Apple documents named stores.
    @MainActor
    private static func isZanoShieldApplied() -> Bool {
        let shield = ManagedSettingsStore(named: .zanoLock).shield
        return shield.applications?.isEmpty == false
            || shield.applicationCategories != nil
            || shield.webDomains?.isEmpty == false
    }
}

// MARK: - LockBlockingSummary

/// The facts behind "Blocking 12 apps · ends when your goals are done". Views turn it into words
/// with `Copy.lockStatus.blockingLine(_:)`.
public struct LockBlockingSummary: Sendable, Equatable {
    public enum Ending: Sendable, Equatable {
        /// Ends when every required goal is verified (both lock modes).
        case whenGoalsDone
        /// A timed schedule window: also ends at this time.
        case at(Date)
        /// No required goals: ends when the person ends it (manual or emergency).
        case whenEnded
    }

    /// `nil` = the selection couldn't be read (no blob, or it didn't decode).
    public var appCount: Int?
    public var categoryCount: Int?
    public var webDomainCount: Int?
    public var ending: Ending
    /// Set while a Time Bank window has the apps open for this lock.
    public var openUntil: Date?

    public init(appCount: Int?, categoryCount: Int?, webDomainCount: Int?, ending: Ending, openUntil: Date?) {
        self.appCount = appCount
        self.categoryCount = categoryCount
        self.webDomainCount = webDomainCount
        self.ending = ending
        self.openUntil = openUntil
    }

    /// Pure resolution, unit-tested.
    ///
    /// - Parameters:
    ///   - scheduleEndMinuteOfDay: the owning schedule's fixed end (`nil` for "until goals are done"
    ///     schedules and every non-scheduled lock).
    ///   - spendWindow: the shared window; only counts when it belongs to `sessionID` and is still open.
    public static func resolve(
        selection: FamilyActivitySelection?,
        sessionID: UUID,
        requiredGoalCount: Int,
        scheduleEndMinuteOfDay: Int?,
        spendWindow: SpendWindow?,
        now: Date,
        calendar: Calendar = .current
    ) -> LockBlockingSummary {
        let ending: Ending
        if let minute = scheduleEndMinuteOfDay,
           let end = LockSchedule.date(on: now, minuteOfDay: minute, calendar: calendar),
           end > now {
            ending = .at(end)
        } else if requiredGoalCount == 0 {
            ending = .whenEnded
        } else {
            ending = .whenGoalsDone
        }
        let openUntil = spendWindow.flatMap { $0.sessionID == sessionID && $0.endsAt > now ? $0.endsAt : nil }
        return LockBlockingSummary(
            appCount: selection?.applicationTokens.count,
            categoryCount: selection?.categoryTokens.count,
            webDomainCount: selection?.webDomainTokens.count,
            ending: ending,
            openUntil: openUntil
        )
    }

    /// The live summary for the running lock. Counts what is actually meant to be shielded right
    /// now (`intendedShieldSelection`, which partial unlock tiers narrow), falling back to the lock
    /// set's full selection.
    @MainActor
    public static func current(
        sessionID: UUID,
        lockSetSelectionBlob: Data?,
        requiredGoalCount: Int,
        now: Date = .now
    ) -> LockBlockingSummary {
        let blob = LockEngineSharedState.intendedShieldSelection ?? lockSetSelectionBlob
        let selection = blob.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
        var scheduleEnd: Int?
        if let owned = LockEngineSharedState.scheduleOwnedLock, owned.sessionID == sessionID {
            scheduleEnd = LockEngineSharedState.schedule(for: owned.lockSetID)?.endMinuteOfDay
        }
        return resolve(
            selection: selection,
            sessionID: sessionID,
            requiredGoalCount: requiredGoalCount,
            scheduleEndMinuteOfDay: scheduleEnd,
            spendWindow: LockEngineSharedState.spendWindow,
            now: now
        )
    }
}
