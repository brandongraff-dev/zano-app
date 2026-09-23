// Core/Sources/Core/Intents/StartLockIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | StartLockIntent | lockSet, mode (full/earn), requiredGoals | Applies shields, opens lock_session |
// docs/spec.md §2 (The Core Loop — "Lock triggers: ... Manual button / Action Button / Control
// Center control") and §6 (Siri phrase: "Lock in with ZANO").
//
// Calls `LockEngineManager.shared.startLock(lockSetID:mode:requiredGoalIDs:trigger:)` with the
// exact signature from this task's system contracts. `trigger` is always `.manual` here — an App
// Intent invoked by a person (Siri, Shortcuts, a widget/Control button, the in-app "Lock In"
// button) is precisely what `LockTrigger.manual` means; `.schedule` is `ZANOMonitor`'s
// `DeviceActivityMonitor` firing on its own, `.nfc` is `SunriseKeyIntent`'s tag-triggered lock
// arm, and `.auto` is v2 geofence automation (spec §2) — none of those go through this intent.

import AppIntents
import Foundation
import SwiftData

/// Siri/Shortcuts-facing wrapper for `LockEngine/LockEngineManager.swift`'s `LockMode`. Declared
/// fresh here rather than retroactively conforming `LockMode` itself to `AppEnum` — see the
/// design note at the top of `IntentSupport.swift`.
public enum LockModeOption: String, AppEnum, Sendable {
    case full
    case earn

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Lock Mode")
    }

    public static let caseDisplayRepresentations: [LockModeOption: DisplayRepresentation] = [
        .full: DisplayRepresentation(
            title: "Full Lock",
            subtitle: "Apps stay shielded until every required goal is verified."
        ),
        .earn: DisplayRepresentation(
            title: "Earn Mode",
            subtitle: "Verified goals deposit minutes into today's Time Bank (spec §5.2)."
        ),
    ]

    /// Converts to the real `LockEngineManager.swift` enum this intent has to call with.
    var engineValue: LockMode {
        switch self {
        case .full: .full
        case .earn: .earn
        }
    }
}

public struct StartLockIntent: AppIntent {
    public static let title: LocalizedStringResource = "Lock In"

    public static var description: IntentDescription {
        IntentDescription(
            "Shields your locked apps until today's goals are verified.",
            categoryName: "Lock"
        )
    }

    public static let openAppWhenRun: Bool = false

    /// Which saved `LockSet` to apply. Defaults to the user's default lock set
    /// (`LockSet.isDefault`, spec §13) when left unspecified — the common case for the "Lock in
    /// with ZANO" Siri phrase, which doesn't name a set.
    @Parameter(title: "Lock Set", description: "Which saved app set to lock. Defaults to your default lock set.")
    public var lockSet: LockSetEntity?

    @Parameter(title: "Mode", description: "Full Lock or Earn Mode.", default: .full)
    public var mode: LockModeOption

    /// Goals that must be verified to unlock. Defaults to every currently active `Goal` when left
    /// unspecified, matching "Applies shields, opens lock_session" for the common all-goals case;
    /// a Shortcut or the in-app lock-set editor can narrow this for partial unlock tiers (spec
    /// §4 v2: "Partial unlock tiers — messaging vs social vs games").
    @Parameter(title: "Required Goals", description: "Goals that must be verified to unlock. Defaults to all active goals.")
    public var requiredGoals: [GoalEntity]?

    public init() {}

    public init(lockSet: LockSetEntity? = nil, mode: LockModeOption = .full, requiredGoals: [GoalEntity]? = nil) {
        self.lockSet = lockSet
        self.mode = mode
        self.requiredGoals = requiredGoals
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Lock in") {
            \.$lockSet
            \.$mode
            \.$requiredGoals
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        let resolvedLockSetID: UUID
        if let lockSet {
            resolvedLockSetID = lockSet.id
        } else {
            // Captured as a plain `UUID` rather than projecting `.id` off `user` (a SwiftData
            // model instance) from inside the `#Predicate` closure — the macro's capture analysis
            // wants simple Sendable literal-like values, not a property access through a
            // reference-type capture.
            let userID = user.id
            var descriptor = FetchDescriptor<LockSet>(
                predicate: #Predicate { $0.userID == userID && $0.isDefault }
            )
            descriptor.fetchLimit = 1
            guard let defaultSet = try context.fetch(descriptor).first else {
                throw ZanoIntentError.noDefaultLockSet
            }
            resolvedLockSetID = defaultSet.id
        }

        let resolvedGoalIDs: [UUID]
        if let requiredGoals, !requiredGoals.isEmpty {
            resolvedGoalIDs = requiredGoals.map(\.id)
        } else {
            resolvedGoalIDs = try IntentSupport.activeGoalIDs(for: user.id, in: context)
        }

        _ = try await LockEngineManager.shared.startLock(
            lockSetID: resolvedLockSetID,
            mode: mode.engineValue,
            requiredGoalIDs: resolvedGoalIDs,
            trigger: .manual
        )

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_start_lock",
            properties: [
                "mode": mode.rawValue,
                "lock_set_id": resolvedLockSetID.uuidString,
                "required_goal_count": resolvedGoalIDs.count,
            ]
        )

        let goalWord = resolvedGoalIDs.count == 1 ? "goal" : "goals"
        return .result(dialog: "Locked in. \(resolvedGoalIDs.count) \(goalWord) to go.")
    }
}
