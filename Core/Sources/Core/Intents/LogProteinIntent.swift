// Core/Sources/Core/Intents/LogProteinIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | LogProteinIntent | grams, source | Writes goal_event |
// docs/spec.md §3 (Goal Catalog: Protein, Tier B — "NFC tap on shaker/tub (+ preset grams), meal
// photo → vision model estimate, barcode scan, quick-repeat of recent meals"; anti-cheat: "Daily
// cap on identical NFC taps; photo dedupe"). §6 NFC section: "Log Shake 25g" is one of the
// example tag actions — this intent's `grams` default (25) matches that exactly. §6 Siri phrase:
// "Log a shake" (wired up in `ZanoShortcuts.swift`).
//
// No `LockEngineManager`/engine contract exists for "log a goal event" — per this task's
// instructions, intents outside the lock/focus pair read and write `Models` directly through the
// shared `ModelContainer`. A Tier B goal's one tap *is* its verification (spec §3: "Auto-verify if
// possible. One tap if not."), so this writes `GoalEvent(kind: .verify, verified: true)` — not
// `.complete`, since reaching the day's full protein target is a multi-tap accumulation judged
// against `DailyPlan.plannedValue`, which is outside this intent's scope (spec §9 Adaptive Goal
// Engine's job, not the Intents layer's).

import AppIntents
import Foundation
import SwiftData

public struct LogProteinIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Protein"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs protein toward today's goal.",
            categoryName: "Log"
        )
    }

    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Grams", description: "Grams of protein.", default: 25)
    public var grams: Double

    @Parameter(title: "Source", default: .manual)
    public var source: GoalLogSource

    public init() {}

    public init(grams: Double = 25, source: GoalLogSource = .manual) {
        self.grams = grams
        self.source = source
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$grams)g of protein")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let goal = try IntentSupport.activeGoal(ofType: .protein, for: user.id, in: context) else {
            throw ZanoIntentError.goalNotFound
        }

        // Anti-cheat (spec §3 Protein row: "Daily cap on identical NFC taps"). Only NFC taps are
        // deduped — a widget/manual/Siri log is a deliberate action each time, and barcode scans
        // are already gated by scanning a physical product.
        var isDuplicateTap = false
        if source == .nfc {
            let recentIdentical = try recentIdenticalNFCTap(goalID: goal.id, grams: grams, in: context)
            isDuplicateTap = recentIdentical
        }

        let event = GoalEvent(
            kind: .verify,
            value: grams,
            source: source.eventSource,
            verified: !isDuplicateTap,
            meta: isDuplicateTap ? .object(["notCounted": .string("duplicate_tap")]) : .object([:]),
            user: user,
            goal: goal
        )
        context.insert(event)
        try context.save()

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_log_protein",
            properties: ["grams": grams, "source": source.rawValue, "counted": !isDuplicateTap]
        )

        if isDuplicateTap {
            // Transparent, not accusatory — spec §9.8 Anti-Cheat Signals: "Never accuse — just
            // don't count, and show 'not counted: too quick' transparently."
            return .result(dialog: "Already logged that shake a moment ago — not counted twice.")
        }
        return .result(dialog: "Logged \(Int(grams))g of protein.")
    }

    private func recentIdenticalNFCTap(goalID: UUID, grams: Double, in context: ModelContext) throws -> Bool {
        let cutoff = Date.now.addingTimeInterval(-120)
        // Kept deliberately simple: the original four-clause #Predicate (optional chaining, an enum
        // compare and a Double compare) made the Swift type checker time out. Narrow by date in the
        // store, then apply the remaining clauses in memory.
        let descriptor = FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.ts >= cutoff })
        let recent = try context.fetch(descriptor)
        return recent.contains { $0.goal?.id == goalID && $0.source == .nfc && $0.value == grams }
    }
}
