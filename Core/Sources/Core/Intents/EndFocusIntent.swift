// Core/Sources/Core/Intents/EndFocusIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | EndFocusIntent | — | Verifies if ≥ planned minutes |
//
// No required parameter (audit L8): `FocusSessionVerifier` persists the running session in the App
// Group, so this intent ends "the" running session (`endActiveSession()`), exactly like
// `EndLockIntent` ends the one active lock. `sessionID` stays as an optional override for callers
// that hold one. A `LiveActivityIntent`, so it runs in the app's process where the session lives —
// which also lets the Focus Live Activity use `Button(intent: EndFocusIntent())` instead of the
// `zano://focus/end` link (both work).

import AppIntents
import Foundation

public struct EndFocusIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "End Focus Session"

    public static var description: IntentDescription {
        IntentDescription(
            "Ends the current focus session and verifies it if you focused long enough.",
            categoryName: "Focus"
        )
    }

    public static let openAppWhenRun: Bool = false

    /// Optional: the `UUID` `FocusSessionVerifier.startSession` returned, as a string (AppIntents'
    /// `@Parameter` types don't include a raw `UUID`). Left empty, the running session is ended.
    @Parameter(title: "Session ID", description: "The focus session to end. Leave empty to end the running one.")
    public var sessionID: String?

    public init() {}

    public init(sessionID: UUID?) {
        self.sessionID = sessionID?.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let verifier = FocusSessionVerifier.shared
        let verified: Bool
        if let sessionID, !sessionID.isEmpty, let id = UUID(uuidString: sessionID) {
            verified = try await verifier.endSession(sessionID: id)
        } else if let result = try await verifier.endActiveSession() {
            verified = result
        } else {
            throw ZanoIntentError.noActiveFocusSession
        }

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_end_focus",
            properties: ["verified": verified]
        )

        let dialog: IntentDialog
        if verified {
            dialog = "Focus session verified. Nice work."
        } else {
            dialog = "Session ended early — it didn't reach the planned time, so it wasn't verified."
        }
        return .result(dialog: dialog)
    }
}
