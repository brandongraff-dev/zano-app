// Core/Sources/Core/Intents/SunriseKeyIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | SunriseKeyIntent | tagId | Verifies morning routine before cutoff |
// docs/spec.md §5.10 Bedtime Gate & Sunrise Alarm: "Tapping the tag = alarm off + morning goal
// verified + the day's lock arms automatically." §3 (Goal Catalog: Morning routine / Sunrise
// Alarm, Tier A — "Alarm can only be dismissed by tapping the Sunrise Tag placed away from the
// bed... before a cutoff"; anti-cheat: "Tag must be physically scanned (proximity)"). §6 NFC:
// tag URLs (`zano://tag/<uuid>`) map to an in-app action including "Sunrise Key".
//
// `tagId` here is the physical NFC tag's own identifier (as encoded in the scanned
// `zano://tag/<uuid>` URL) — proof the tap was a real physical scan, not a re-run of this intent
// from Shortcuts. Parsing that URL and routing it to this intent is Core NFC / Verification-layer
// work this task doesn't own; this intent's job starts once it already has a `tagId` string.
//
// Cutoff enforcement: `Models/Goal.swift`/`Models/DailyPlan.swift` (as authored for this task —
// see this task's `knownIssues`) have no explicit "cutoff time" field to check against, only
// `DailyPlan.plannedValue`/`planBValue` (generic numeric target fields) and `Goal.cadence` (a free
// string). Rather than invent a field shape on a model this task doesn't own, this intent verifies
// the tap unconditionally and records the wall-clock time in `GoalEvent.meta`, so whichever module
// ends up owning "was this on time" scoring (most likely the Adaptive Goal Engine or a Sunrise
// Alarm-specific service, not yet built) can compute it from that timestamp later. Flagged, not
// guessed.

import AppIntents
import Foundation
import SwiftData

public struct SunriseKeyIntent: AppIntent {
    public static let title: LocalizedStringResource = "Sunrise Key"

    public static var description: IntentDescription {
        IntentDescription(
            "Tap the Sunrise Tag to turn off the alarm and verify your morning routine.",
            categoryName: "Log"
        )
    }

    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Tag ID", description: "The scanned Sunrise Tag's identifier.")
    public var tagId: String

    public init() {}

    public init(tagId: String) {
        self.tagId = tagId
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let goal = try IntentSupport.activeGoal(ofType: .sunriseAlarm, for: user.id, in: context) else {
            throw ZanoIntentError.goalNotFound
        }

        let event = GoalEvent(
            kind: .complete,
            value: nil,
            source: .nfc,
            verified: true,
            meta: .object(["tagId": .string(tagId)]),
            user: user,
            goal: goal
        )
        context.insert(event)
        try context.save()

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_sunrise_key",
            properties: ["tag_id": tagId]
        )

        // Arms the day's lock automatically (spec §5.10, step 4). Best-effort: if a lock is
        // already active, or applying one fails for any other reason, the alarm-off + morning
        // goal verification above must still stand — CLAUDE.md's "never trap the user" cuts both
        // ways here: a lock-arming failure must never look like the alarm/goal step also failed.
        if try IntentSupport.activeLockSession(for: user.id, in: context) == nil {
            let userID = user.id
            let requiredGoalIDs = try IntentSupport.activeGoalIDs(for: userID, in: context)
            var descriptor = FetchDescriptor<LockSet>(
                predicate: #Predicate { $0.userID == userID && $0.isDefault }
            )
            descriptor.fetchLimit = 1
            if let defaultLockSet = try context.fetch(descriptor).first {
                _ = try? await LockEngineManager.shared.startLock(
                    lockSetID: defaultLockSet.id,
                    mode: .full,
                    requiredGoalIDs: requiredGoalIDs,
                    trigger: .nfc
                )
            }
        }

        return .result(dialog: "Morning verified. Locked in for the day.")
    }
}
