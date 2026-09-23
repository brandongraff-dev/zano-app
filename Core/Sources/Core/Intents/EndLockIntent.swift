// Core/Sources/Core/Intents/EndLockIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | EndLockIntent | reason | Only allowed if goals complete or via Emergency flow |
//
// This intent is deliberately the *non-emergency* unlock path: it calls
// `LockEngineManager.shared.evaluateUnlockEligibility(sessionID:)` first and refuses to end the
// lock if it returns `false`, exactly matching the spec's "Only allowed if goals complete" rule.
// The escape hatch for "I need my phone right now, goals or not" is `EmergencyUnlockIntent`, not
// this one — CLAUDE.md: "Any lock/shield feature must always keep an emergency-unlock path."
//
// No `sessionID` parameter: at most one `LockSession` is active at a time (see
// `IntentSupport.activeLockSession(for:in:)`), so "the" active lock is unambiguous and doesn't
// need to be spoken to Siri or picked in a Shortcut.

import AppIntents
import Foundation
import SwiftData

/// Why the lock is ending. Maps to `LockEngineManager.swift`'s `UnlockKind` (`.earned` /
/// `.scheduleEnd`) — never `.emergency` (that's `EmergencyUnlockIntent`'s job) or `.manual`
/// (reserved for an operator/support override this intent doesn't perform).
public enum EndLockReason: String, AppEnum, Sendable {
    /// The lock's required goals were completed and verified.
    case goalsComplete
    /// A scheduled end time (e.g. a `DeviceActivity` schedule window) was reached.
    case scheduleEnd

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Unlock Reason")
    }

    public static var caseDisplayRepresentations: [EndLockReason: DisplayRepresentation] = [
        .goalsComplete: DisplayRepresentation(title: "Goals Complete"),
        .scheduleEnd: DisplayRepresentation(title: "Schedule Ended"),
    ]

    var engineValue: UnlockKind {
        switch self {
        case .goalsComplete: .earned
        case .scheduleEnd: .scheduleEnd
        }
    }
}

public struct EndLockIntent: AppIntent {
    public static let title: LocalizedStringResource = "End Lock"

    public static var description: IntentDescription {
        IntentDescription(
            "Ends the current lock once its required goals are verified.",
            categoryName: "Lock"
        )
    }

    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Reason", default: .goalsComplete)
    public var reason: EndLockReason

    public init() {}

    public init(reason: EndLockReason = .goalsComplete) {
        self.reason = reason
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let session = try IntentSupport.activeLockSession(for: user.id, in: context) else {
            throw ZanoIntentError.noActiveLock
        }

        let eligible = await LockEngineManager.shared.evaluateUnlockEligibility(sessionID: session.id)
        guard eligible else {
            throw ZanoIntentError.goalsNotYetComplete
        }

        try await LockEngineManager.shared.endLock(sessionID: session.id, unlockKind: reason.engineValue)

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_end_lock",
            properties: ["reason": reason.rawValue, "session_id": session.id.uuidString]
        )

        return .result(dialog: "Unlocked. Nice work.")
    }
}
