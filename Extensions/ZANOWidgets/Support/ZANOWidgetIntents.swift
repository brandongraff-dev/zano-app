// ZANOWidgetIntents.swift
// Extensions/ZANOWidgets/Support
//
// App Intents defined *inside* this extension (not Core/Sources/Core/Intents) — a deliberate,
// narrow exception to CLAUDE.md's "every user action is an App Intent in Core/Sources/Core/
// Intents" rule, scoped to exactly two cases where this task has no frozen CONTRACTS name to
// build against:
//
//   1. Starting a lock from the Small Home Screen widget's "Start Lock" button (spec §6). Spec
//      §14's catalog names a `StartLockIntent`, but — unlike `LogProteinIntent`/`LogWaterIntent`/
//      `LogCreatineIntent`/`StartFocusIntent` — it was not distributed to this task as a frozen
//      CONTRACTS shape, and its likely real shape (an `AppEntity`-backed `lockSet` parameter for
//      Shortcuts/Siri, per spec §14) can't be guessed reliably enough to compile against.
//   2. The iOS 18 Lock On/Off Control (spec §6), which needs a `SetValueIntent<Bool>` — Apple's
//      own Controls sample code colocates this kind of intent directly with its `ControlWidget`
//      rather than centralizing it, since it's a thin, control-specific UI binding.
//
// Both intents below call `LockEngineManager.shared` directly — one of this task's given, frozen
// system CONTRACTS — so they're real, working, production logic, not stubs. Recommended follow-up
// (flagged in this task's knownIssues): once Core/Sources/Core/Intents/StartLockIntent.swift
// lands with its real shape, fold `ZANOStartLockIntent`'s body into it (or have this type delegate
// to it) so there's exactly one "start a lock" code path, per CLAUDE.md "build each [intent] once,
// reuse everywhere."
//
// UUIDs are passed through `@Parameter`-wrapped `String`s (`uuidString`), not `UUID` directly:
// AppIntents' documented `@Parameter` value types are primitives (Bool/Int/Double/String), Date/
// URL/Data, `AppEntity`/`AppEnum`, and arrays of those — `UUID` itself isn't among them, and a
// widget button's intent must be able to encode its parameters to be replayed when the system
// actually invokes it, not just compile.

import AppIntents
import Core
import Foundation

/// Thrown by the intents below when the App Group doesn't have enough state yet to act (e.g. no
/// lock set has been created in onboarding, or no lock is currently active). Never silently
/// no-ops — CLAUDE.md: never trap the user, but also never pretend an action happened.
enum ZANOControlError: LocalizedError {
    case noDefaultLockSet
    case noActiveLockSession

    var errorDescription: String? {
        switch self {
        case .noDefaultLockSet:
            WidgetCopy.controlNoDefaultLockSetMessage
        case .noActiveLockSession:
            "No active ZANO lock to end."
        }
    }
}

/// Starts Earn Mode with a given lock set + today's active goals (the Home Screen widget's
/// "Start Lock" button, spec §6). Always starts `.earn` mode with `trigger: .manual` — a one-tap
/// widget action has no UI to pick `.full` vs `.earn` or hand-pick goals, and Earn Mode (spec
/// §5.2) is the safer, least-surprising default for a single tap (it can only ever unlock, never
/// additionally restrict, matching CLAUDE.md's "no restrictive goals" spirit at the UX level too).
struct ZANOStartLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Lock"
    static let description = IntentDescription("Start your default ZANO lock in Earn Mode.")

    @Parameter(title: "Lock Set ID")
    var lockSetIDString: String?

    @Parameter(title: "Required Goal IDs")
    var requiredGoalIDStrings: [String]

    init() {
        self.lockSetIDString = nil
        self.requiredGoalIDStrings = []
    }

    init(lockSetID: UUID?, requiredGoalIDs: [UUID]) {
        self.lockSetIDString = lockSetID?.uuidString
        self.requiredGoalIDStrings = requiredGoalIDs.map(\.uuidString)
    }

    func perform() async throws -> some IntentResult {
        guard let idString = lockSetIDString, let lockSetID = UUID(uuidString: idString) else {
            throw ZANOControlError.noDefaultLockSet
        }
        let goalIDs = requiredGoalIDStrings.compactMap(UUID.init(uuidString:))
        _ = try await LockEngineManager.shared.startLock(
            lockSetID: lockSetID,
            mode: .earn,
            requiredGoalIDs: goalIDs,
            trigger: .manual
        )
        return .result()
    }
}

/// Backs the iOS 18 "Lock" Control Center/Lock Screen toggle (spec §6: "Toggle: Lock On/Off").
/// Turning it on starts Earn Mode exactly like `ZANOStartLockIntent`; turning it off calls
/// `LockEngineManager.endLock(unlockKind: .manual)` on whatever session `SharedDefaults.
/// activeLockSessionID` currently names.
///
/// Spec §6 lists this control as "(with confirmation for Off)" — `ControlWidgetToggle` has no
/// interstitial-confirmation affordance (Control Center controls are single-tap by OS design), so
/// there is no confirmation step here. `.manual` is one of `LockEngineManager`'s own supported
/// `UnlockKind`s (a deliberate, ordinary unlock, not a bypass), so this still honors CLAUDE.md's
/// "always keep an emergency-unlock path" rule — it just can't add the extra confirmation tap spec
/// §6 describes. Flagged in this task's knownIssues.
struct ZANOSetLockStateIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set ZANO Lock"

    @Parameter(title: "Locked")
    var value: Bool

    init() {
        self.value = false
    }

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        if value {
            let snapshot = ZANOWidgetDataStore.loadSnapshot()
            guard let lockSetID = snapshot.defaultLockSetID else {
                throw ZANOControlError.noDefaultLockSet
            }
            _ = try await LockEngineManager.shared.startLock(
                lockSetID: lockSetID,
                mode: .earn,
                requiredGoalIDs: snapshot.todaysActiveGoalIDs,
                trigger: .manual
            )
        } else {
            guard let sessionID = SharedDefaults.activeLockSessionID else {
                throw ZANOControlError.noActiveLockSession
            }
            try await LockEngineManager.shared.endLock(sessionID: sessionID, unlockKind: .manual)
        }
        return .result()
    }
}
