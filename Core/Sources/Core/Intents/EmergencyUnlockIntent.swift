// Core/Sources/Core/Intents/EmergencyUnlockIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | EmergencyUnlockIntent | — | 60-sec hold in app; records unlock_kind=emergency |
// docs/spec.md §5.1 Living Shield: the shield's "Emergency" button "starts 60-sec hold flow via
// notification". CLAUDE.md / spec §24: "Any lock/shield feature must always keep an
// emergency-unlock path. Never trap the user."
//
// Scope split (Core vs. App-only UI, CLAUDE.md's target boundaries): the 60-second hold gesture
// itself is a SwiftUI interaction — it lives in an App/ZANO/Features view, not here. That view
// runs the hold, and only once it completes does it invoke this intent (e.g.
// `Button(intent: EmergencyUnlockIntent())`) or call `LockEngineManager.shared.emergencyUnlock`
// directly. This intent's job, per the system contract, is just the second half: call
// `LockEngineManager.shared.emergencyUnlock(sessionID:)` for the active session. It's still an
// `AppIntent` (not a plain function) so the same one path also works from a shield notification
// action and from Shortcuts/automations that already know to gate it behind their own friction.
//
// `isDiscoverable = false` and no phrase in `ZanoShortcuts`: spec §6 lists exactly four Siri
// phrases ("Lock in with ZANO", "Log a shake", "Log water", "How am I doing today") and emergency
// unlock isn't one of them — a bare voice command bypassing the deliberate hold-to-confirm
// friction would undercut the whole point of that friction, so this intent stays reachable only
// from the in-app button and the shield notification action, never a spoken shortcut.

import AppIntents
import Foundation
import SwiftData

public struct EmergencyUnlockIntent: AppIntent {
    public static let title: LocalizedStringResource = "Emergency Unlock"

    public static var description: IntentDescription {
        IntentDescription(
            "Ends the current lock immediately without completing your goals. Use only when you really need your phone.",
            categoryName: "Lock"
        )
    }

    /// Kept out of Siri/Shortcuts suggestions and search — see the file header. Still callable
    /// directly by the in-app hold-to-confirm view and by a shield notification action.
    public static let isDiscoverable: Bool = false

    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let session = try IntentSupport.activeLockSession(for: user.id, in: context) else {
            throw ZanoIntentError.noActiveLock
        }

        try await LockEngineManager.shared.emergencyUnlock(sessionID: session.id)

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_emergency_unlock",
            properties: ["session_id": session.id.uuidString]
        )

        return .result(dialog: "Unlocked early. That's okay — tomorrow's a new lock.")
    }
}
