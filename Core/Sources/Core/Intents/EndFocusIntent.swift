// Core/Sources/Core/Intents/EndFocusIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | EndFocusIntent | — | Verifies if ≥ planned minutes |
//
// Calls `FocusSessionVerifier.shared.endSession(sessionID:)` with the exact signature from this
// task's system contracts — that method's return value (`Bool`) is exactly the "Verifies if ≥
// planned minutes" effect the spec describes; this intent just surfaces it as a dialog.
//
// Known gap (see this task's `knownIssues`, and CLAUDE.md's rule that a narrow TODO is fine at a
// genuine cross-module integration point): spec §14 lists no parameters for this intent, but the
// system contract's `endSession(sessionID:)` needs one, and there is no persisted `FocusSession`
// model in `Core/Sources/Core/Models` for this file to look an "active" id up from — session
// identity is entirely owned by `FocusSessionVerifier`, which this task doesn't own. Two real
// callers exist: (1) the in-app focus-timer view, which already holds the `UUID`
// `StartFocusIntent`/`FocusSessionVerifier.startSession` returned and can pass it straight
// through `sessionID`; (2) a Live Activity "End" button, which can be built with a *pre-filled*
// `EndFocusIntent(sessionID:)` value at the moment the Live Activity starts (a standard
// ActivityKit pattern), so it never needs to re-resolve "the active session" itself. Siri/typed
// Shortcuts (spec §6 doesn't list a phrase for this intent) fall back to
// `SharedDefaults.activeLockSessionID`-style ambient state, which doesn't exist for focus
// sessions yet — that's the integration point: `FocusSessionVerifier`'s owner is the right place
// to add a `SharedDefaults`-style "current focus session id" mirror (mirroring the pattern
// `Core/Sources/Core/Store/SharedDefaults.swift` already uses for `activeLockSessionID`) if a
// zero-parameter Siri phrase is wanted later. Flagged here rather than guessed.

import AppIntents
import Foundation

public struct EndFocusIntent: AppIntent {
    public static let title: LocalizedStringResource = "End Focus Session"

    public static var description: IntentDescription {
        IntentDescription(
            "Ends the current focus session and verifies it if you focused long enough.",
            categoryName: "Focus"
        )
    }

    public static let openAppWhenRun: Bool = false

    /// The `UUID` `StartFocusIntent`/`FocusSessionVerifier.startSession` returned, as a string
    /// (AppIntents' native `@Parameter` types don't include a raw `UUID` — see this task's
    /// `knownIssues`). Required: see the file header for why this can't default itself the way
    /// `EndLockIntent`/`EmergencyUnlockIntent` do.
    @Parameter(title: "Session ID", description: "The focus session to end.")
    public var sessionID: String

    public init() {}

    public init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: sessionID) else {
            throw ZanoIntentError.noActiveFocusSession
        }

        let verified = try await FocusSessionVerifier.shared.endSession(sessionID: id)

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_end_focus",
            properties: ["session_id": sessionID, "verified": verified]
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
