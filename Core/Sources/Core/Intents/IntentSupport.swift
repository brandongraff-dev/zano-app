// Core/Sources/Core/Intents/IntentSupport.swift
//
// Shared plumbing for every file in this directory: model-context access, the one local `User`
// row lookup, the "active lock session" lookup, a localized error type, and the `AppEntity` /
// `EntityQuery` pairs (`LockSetEntity`, `GoalEntity`, `MealEntity`) that let Siri/Shortcuts offer
// a real picker over the user's saved lock sets, goals, and remembered meals instead of asking for
// a raw UUID string.
//
// docs/spec.md §11 (Architecture — "every user action → App Intent → Core → SwiftData (App
// Group)") and §14 (App Intents Catalog). CLAUDE.md: "Every user action is an App Intent... never
// duplicate the same logic in two places" — this file is where that shared logic lives so the 13
// intent files don't each reinvent it.
//
// Design note (see this task's `decisions` output): parameter types exposed to Siri/Shortcuts
// (`AppEnum`, `AppEntity` conformers) are declared fresh here in the Intents module rather than by
// retroactively conforming the `LockEngine`/`Models` types this file calls into (`LockMode`,
// `LockTrigger`, `UnlockKind`, `GoalType`, `GoalEventSource`) to `AppEnum`. Two reasons: (1) this
// task must never edit a file owned by another agent, and Swift's automatic `CaseIterable`
// synthesis for a plain `enum` only fires when the conformance is stated alongside the original
// declaration — an `extension SomeoneElsesEnum: AppEnum` in a different file would need a
// hand-written `allCases` and is exactly the kind of "guess at a cross-file synthesis corner case"
// this task was told to avoid; (2) it keeps `import AppIntents` confined to this directory, which
// matches the architecture's own module boundaries (Models/LockEngine/Verification/Retention stay
// framework-agnostic; only the Intents layer talks to Siri/Shortcuts).

import AppIntents
import Foundation
import SwiftData

// MARK: - Errors

/// Every error an intent in this directory can throw. Conforms to
/// `CustomLocalizedStringResourceConvertible` so AppIntents shows a readable message in Siri /
/// Shortcuts / the Shortcuts app instead of a generic failure, without this file hardcoding UI
/// copy for the app's own screens (`Core/Sources/Core/Copy` owns that; these strings only ever
/// surface inside the system's own intent-error UI, not a ZANO-designed screen).
public enum ZanoIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The local store has no `User` row yet (first launch, before onboarding finishes).
    case noUserFound
    /// No `LockSession` currently has `isActive == true`.
    case noActiveLock
    /// `LockEngineManager.evaluateUnlockEligibility` returned `false` — required goals aren't
    /// verified yet, so `EndLockIntent` (the non-emergency path) refuses to end the lock.
    case goalsNotYetComplete
    /// `StartLockIntent` was asked to use "the" default lock set but the user has none saved.
    case noDefaultLockSet
    /// `StartFocusIntent` couldn't find an active `Goal` of type `.focusSession` to attach the
    /// session to.
    case noFocusGoalConfigured
    /// `EndFocusIntent` was called with no `sessionID` and none could be resolved. See the doc
    /// comment on `EndFocusIntent` for why this is a real gap, not a guess.
    case noActiveFocusSession
    /// A referenced `Goal` (by id, via `GoalEntity`) no longer exists in the local store.
    case goalNotFound
    /// A referenced `Meal` (by id, via `MealEntity`) no longer exists in the local store.
    case mealNotFound

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noUserFound:
            "ZANO isn't set up yet. Finish onboarding first."
        case .noActiveLock:
            "Nothing is locked right now."
        case .goalsNotYetComplete:
            "Not all required goals are verified yet. Use Emergency Unlock if you need your phone now."
        case .noDefaultLockSet:
            "You don't have a default lock set yet. Pick one in ZANO first."
        case .noFocusGoalConfigured:
            "You don't have a Focus goal set up yet. Add one in ZANO first."
        case .noActiveFocusSession:
            "No focus session to end."
        case .goalNotFound:
            "That goal doesn't exist anymore."
        case .mealNotFound:
            "That meal isn't in your history anymore."
        }
    }
}

// MARK: - ModelContext / lookups

/// Namespace for the small pieces of SwiftData plumbing every intent in this directory needs.
/// Not a type any intent stores — every call builds (or receives) a fresh `ModelContext`, since
/// `ModelContext` is not `Sendable` and each `perform()` invocation should own its own.
public enum IntentSupport {

    /// A fresh `ModelContext` over the shared App Group store (`ModelContainer.appGroup`,
    /// `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`). Every intent's `perform()` calls
    /// this once at the top rather than sharing a context across calls.
    @MainActor
    public static func makeContext() -> ModelContext {
        ModelContext(ModelContainer.appGroup)
    }

    /// The signed-in (or anonymous, spec §4/§7) user. Per `Models/User.swift`'s own header
    /// comment, this device's local store holds exactly one `User` row, so "first fetched row" is
    /// the correct — not just convenient — way to resolve "the current user" anywhere in Core.
    @MainActor
    public static func currentUser(in context: ModelContext) throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw ZanoIntentError.noUserFound
        }
        return user
    }

    /// The one `LockSession` with `isActive == true` (`endedAt == nil && unlockKind == nil`, per
    /// `LockSession.isActive`'s own doc comment) — mirrored here as an explicit predicate because
    /// SwiftData's `#Predicate` macro operates over stored properties, not computed ones. Used by
    /// `EndLockIntent` and `EmergencyUnlockIntent`, neither of which take a session id parameter
    /// (spec §14: `EndLockIntent`'s only param is `reason`; `EmergencyUnlockIntent` takes none) —
    /// there is exactly one lock active at a time by construction of `LockEngineManager`, so "the"
    /// active session is unambiguous.
    @MainActor
    public static func activeLockSession(for userID: UUID, in context: ModelContext) throws -> LockSession? {
        var descriptor = FetchDescriptor<LockSession>(
            predicate: #Predicate { $0.userID == userID && $0.endedAt == nil && $0.unlockKind == nil }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The user's currently active `Goal` of a given type, if any. `active == true` mirrors
    /// `goals.active` (spec §13); when more than one active goal shares a type this returns the
    /// most recently created one, which is a reasonable single-goal default for intents (like
    /// `StartFocusIntent`) that need to pick one without asking the user.
    @MainActor
    public static func activeGoal(ofType type: GoalType, for userID: UUID, in context: ModelContext) throws -> Goal? {
        var descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.user?.id == userID && $0.active && $0.type == type }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// All of the user's currently active goal ids, used as `StartLockIntent`'s default
    /// `requiredGoalIDs` when the caller doesn't specify which goals gate the lock.
    @MainActor
    public static func activeGoalIDs(for userID: UUID, in context: ModelContext) throws -> [UUID] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.user?.id == userID && $0.active }
        )
        return try context.fetch(descriptor).map(\.id)
    }

    /// A specific `Goal` by id, scoped to `userID`. Used by intents that take a `GoalEntity`
    /// parameter (`LogCustomGoalIntent`) and need to re-resolve the actual model, not just trust
    /// the entity's cached `title`.
    @MainActor
    public static func goal(withID goalID: UUID, for userID: UUID, in context: ModelContext) throws -> Goal? {
        var descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.id == goalID && $0.user?.id == userID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Whether a `verified` `GoalEvent` already exists for `goal` since local midnight. Used by
    /// `LogCreatineIntent` for the "1 per day" anti-cheat rule (spec §3: Creatine row, "1 per
    /// day") — checked here once instead of re-implemented by every Tier B log intent that needs
    /// a daily cap.
    @MainActor
    public static func hasVerifiedEventToday(for goalID: UUID, in context: ModelContext) throws -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate { event in
                event.goal?.id == goalID && event.verified && event.ts >= startOfDay
            }
        )
        return try context.fetchCount(descriptor) > 0
    }

    /// Count of `GoalEvent`s already logged for `goal` (verified or not) in the last `seconds`,
    /// regardless of source. Backs the tap-rate-limit anti-cheat rule for Water (spec §3: "Tap
    /// rate limit (no 8 taps in a minute)").
    @MainActor
    public static func recentEventCount(for goalID: UUID, withinSeconds seconds: TimeInterval, in context: ModelContext) throws -> Int {
        let cutoff = Date.now.addingTimeInterval(-seconds)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate { event in event.goal?.id == goalID && event.ts >= cutoff }
        )
        return try context.fetchCount(descriptor)
    }
}

// MARK: - GoalLogSource (shared AppEnum for Log* intents)

/// The subset of `GoalEventSource` (`Core/Sources/Core/Models/GoalEvent.swift`) that a person or a
/// Shortcut could plausibly choose when logging protein/water/creatine directly (as opposed to
/// `.photo`/`.geofence`/`.healthKit`/`.timer`, which are only ever set by the verifier that owns
/// that path, never by a hand-built intent call). Declared once here and reused by
/// `LogProteinIntent`, `LogWaterIntent`, and `LogCreatineIntent` instead of one copy per file.
public enum GoalLogSource: String, AppEnum, Sendable {
    case nfc
    case widget
    case manual
    case siri
    case barcode

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Log Source")
    }

    public static let caseDisplayRepresentations: [GoalLogSource: DisplayRepresentation] = [
        .nfc: DisplayRepresentation(title: "NFC Tap"),
        .widget: DisplayRepresentation(title: "Widget"),
        .manual: DisplayRepresentation(title: "Manual"),
        .siri: DisplayRepresentation(title: "Siri"),
        .barcode: DisplayRepresentation(title: "Barcode"),
    ]

    /// Converts to the `Models/GoalEvent.swift` enum actually stored on `GoalEvent.source`.
    public var eventSource: GoalEventSource {
        switch self {
        case .nfc: .nfc
        case .widget: .widget
        case .manual: .manual
        case .siri: .siri
        case .barcode: .barcode
        }
    }
}

// MARK: - LockSetEntity

/// `AppEntity` wrapper over `Models/LockSet.swift` so `StartLockIntent` can offer Siri/Shortcuts a
/// real picker of the user's saved lock sets by name, instead of a raw UUID text field. Holds only
/// `id` and `name` — never `appTokensBlob` (`LockSet`'s own doc comment: FamilyControls tokens
/// never leave the device, and that includes never round-tripping them through an `AppEntity`
/// that Shortcuts/Siri could serialize into a shortcut definition).
public struct LockSetEntity: AppEntity {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Lock Set")
    }

    public static let defaultQuery = LockSetQuery()
}

/// `EntityQuery` backing `LockSetEntity`. Written from training knowledge of the AppIntents
/// `EntityQuery`/`EnumerableEntityQuery` protocols (see this task's `knownIssues`: the exact
/// requirement names — `entities(for:)`, `allEntities()`, `suggestedEntities()` — could not be
/// checked against a real SDK in this environment).
public struct LockSetQuery: EntityQuery, EnumerableEntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [LockSetEntity] {
        let context = await IntentSupport.makeContext()
        let descriptor = FetchDescriptor<LockSet>(predicate: #Predicate { identifiers.contains($0.id) })
        return try context.fetch(descriptor).map { LockSetEntity(id: $0.id, name: $0.name) }
    }

    public func allEntities() async throws -> [LockSetEntity] {
        let context = await IntentSupport.makeContext()
        let descriptor = FetchDescriptor<LockSet>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map { LockSetEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - GoalEntity

/// `AppEntity` wrapper over `Models/Goal.swift`, used by `StartLockIntent` (`requiredGoals`) and
/// `LogCustomGoalIntent` (`goal`) so Siri/Shortcuts can pick a goal by title.
public struct GoalEntity: AppEntity {
    public let id: UUID
    public var title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Goal")
    }

    public static let defaultQuery = GoalQuery()
}

public struct GoalQuery: EntityQuery, EnumerableEntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        let context = await IntentSupport.makeContext()
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { identifiers.contains($0.id) })
        return try context.fetch(descriptor).map { GoalEntity(id: $0.id, title: $0.title) }
    }

    public func allEntities() async throws -> [GoalEntity] {
        let context = await IntentSupport.makeContext()
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.active },
            sortBy: [SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor).map { GoalEntity(id: $0.id, title: $0.title) }
    }
}

// MARK: - MealEntity

/// `AppEntity` wrapper over `Models/Meal.swift`, used by `QuickRepeatMealIntent` (spec §5.19 Quick
/// Repeats & Food Memory: "Your usual chicken bowl (48g)?"). Only confirmed meals are offered —
/// an unconfirmed meal's protein estimate hasn't been reviewed yet (`Meal.confirmed`'s own doc
/// comment: "unconfirmed meals are pending review and should not count toward the Protein goal"),
/// so it shouldn't be offered as a one-tap repeat either.
public struct MealEntity: AppEntity {
    public let id: UUID
    public var label: String

    public init(id: UUID, label: String) {
        self.id = id
        self.label = label
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Meal")
    }

    public static let defaultQuery = MealQuery()
}

public struct MealQuery: EntityQuery, EnumerableEntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [MealEntity] {
        let context = await IntentSupport.makeContext()
        let descriptor = FetchDescriptor<Meal>(predicate: #Predicate { identifiers.contains($0.id) })
        return try context.fetch(descriptor).map { MealEntity(id: $0.id, label: Self.label(for: $0)) }
    }

    public func allEntities() async throws -> [MealEntity] {
        let context = await IntentSupport.makeContext()
        var descriptor = FetchDescriptor<Meal>(predicate: #Predicate { $0.confirmed })
        descriptor.sortBy = [SortDescriptor(\.ts, order: .reverse)]
        descriptor.fetchLimit = 25
        return try context.fetch(descriptor).map { MealEntity(id: $0.id, label: Self.label(for: $0)) }
    }

    private static func label(for meal: Meal) -> String {
        let name = meal.items.first?.name ?? "Meal"
        if let protein = meal.proteinG {
            return "\(name) (\(Int(protein))g)"
        }
        return name
    }
}
