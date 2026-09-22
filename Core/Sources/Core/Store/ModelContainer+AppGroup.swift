import Foundation
import SwiftData
import os

/// The single App Group shared by the ZANO app and its five extensions (`ZANOWidgets`,
/// `ZANOShieldConfig`, `ZANOShieldAction`, `ZANOMonitor`, `ZANOReport`). Must exactly match
/// `com.apple.security.application-groups` on every target's entitlements in `project.yml`.
///
/// docs/spec.md §11 Architecture: "App Group: group.com.zano.app — SwiftData store + shared
/// UserDefaults live here. This is how extensions read state without networking."
public enum AppGroup {
    public static let identifier = "group.com.zano.app"
}

/// Errors raised while locating or opening the shared SwiftData store.
public enum ModelContainerError: LocalizedError {
    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returned `nil`. This
    /// only happens when the running target is missing (or has a misspelled) App Group
    /// entitlement — a build/signing problem, not something retryable at runtime.
    case appGroupContainerUnavailable(identifier: String)

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable(let identifier):
            "Could not resolve the App Group container for \"\(identifier)\". Confirm this " +
            "target has the com.apple.security.application-groups entitlement and that it " +
            "matches project.yml exactly."
        }
    }
}

/// Factory + process-wide shared instance for the one SwiftData store the ZANO app and every
/// extension read and write (docs/spec.md §11, §13). Named `+AppGroup` because the store's
/// defining trait is *where* it lives: a `.sqlite` file inside the App Group container
/// (`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`), not the app's
/// own sandboxed Application Support directory — that's what lets all six processes (main app +
/// 5 extensions) see the same data with no networking (§27: extensions do no networking).
extension ModelContainer {

    /// Every persistent model type the app and its extensions read or write, per docs/spec.md
    /// §13 Data Model. Listed here by name so `Schema` (and therefore this container) knows
    /// about all of them even though most of these files are being authored in parallel by
    /// other agents right now under `Core/Sources/Core/Models` — that's expected. If a model
    /// type is renamed, split, or added, this list must be updated in the same change or
    /// `ModelContainer(for:configurations:)` will not know its schema and queries/relationships
    /// against the missing type will fail at runtime (not at compile time, since `@Model` types
    /// don't have to be registered anywhere else to compile).
    ///
    /// Order mirrors the table order in spec §13 (`users` → `subscriptions`), with `OutboxEvent`
    /// appended at the end — it has no remote Postgres counterpart (spec §13 doesn't list it; it's
    /// the local half of the Sync outbox pattern, `Core/Sources/Core/Sync/OutboxEvent.swift`), but
    /// it is a `@Model` that must live in this same App Group store: an extension (e.g.
    /// `ZANOShieldAction` logging an emergency unlock) enqueues an `OutboxEvent` locally, and the
    /// main app's `SyncEngine.flush()` has to see it on next launch. Omitting it here would compile
    /// fine (as the comment above notes, `@Model` types don't have to be registered anywhere else
    /// to compile) but silently drop every outbox row at runtime — `ModelContainer(for:)` only
    /// knows about the types listed in this array's `Schema`, and fetching/inserting a type outside
    /// that schema fails at the `ModelContext` call site once you actually run it, not here.
    public static let appGroupModelTypes: [any PersistentModel.Type] = [
        User.self,
        Goal.self,
        DailyPlan.self,
        GoalEvent.self,
        LockSet.self,
        LockSession.self,
        TimeBank.self,
        Streak.self,
        Gym.self,
        Meal.self,
        Squad.self,
        SquadMember.self,
        Duel.self,
        Badge.self,
        Coin.self,
        Recap.self,
        Nudge.self,
        RiskScore.self,
        Subscription.self,
        OutboxEvent.self,
    ]

    /// The schema built from `appGroupModelTypes`. A `let`-style computed property (not cached)
    /// so building a second, independent container — e.g. an in-memory one for SwiftUI previews
    /// or unit tests — never accidentally shares `Schema` identity with the on-disk one.
    public static var appGroupSchema: Schema { Schema(appGroupModelTypes) }

    /// Filename of the on-disk SwiftData store inside the App Group container.
    private static let appGroupStoreFileName = "ZANOStore.sqlite"

    /// Resolves the on-disk location of the shared store inside the App Group container.
    /// Callers that just want the container should use ``makeAppGroupContainer(inMemory:)`` or
    /// ``appGroup`` instead; this is exposed for diagnostics/tests that need the raw URL (e.g.
    /// confirming the store file exists before shipping a debug "reset local data" action).
    public static func appGroupStoreURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) else {
            throw ModelContainerError.appGroupContainerUnavailable(identifier: AppGroup.identifier)
        }
        return containerURL.appending(path: appGroupStoreFileName)
    }

    /// Builds a fresh `ModelContainer` backed by the App Group store.
    ///
    /// - Parameter inMemory: `true` for SwiftUI previews and unit tests only — never in the app
    ///   or an extension target, since an in-memory store is private to this one process and
    ///   defeats the entire point of the App Group (every other process/extension would see an
    ///   empty store).
    /// - Throws: ``ModelContainerError/appGroupContainerUnavailable(identifier:)`` if the App
    ///   Group entitlement is missing, or a SwiftData error if the on-disk store exists but
    ///   can't be opened (e.g. corrupted file, migration failure against `appGroupSchema`).
    ///
    /// `cloudKitDatabase` is explicitly `.none`: ZANO syncs through the Supabase outbox (Sync
    /// module, spec §11/§12), not CloudKit, and this store's App Group location doesn't imply
    /// CloudKit sharing — leaving it at its default could silently turn on device-to-device sync
    /// through the user's iCloud account, which is not our sync story.
    public static func makeAppGroupContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(
                schema: appGroupSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: appGroupSchema, configurations: [configuration])
        }

        let storeURL = try appGroupStoreURL()
        let configuration = ModelConfiguration(
            schema: appGroupSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: appGroupSchema, configurations: [configuration])
    }

    /// The process-wide shared container. The app and every extension should fetch/save through
    /// a `ModelContext` built on *this* instance (`ModelContext(ModelContainer.appGroup)`) so all
    /// six processes observe the same store, per spec §11's data flow: "every user action → App
    /// Intent → Core → SwiftData (App Group) → widgets/shield read state instantly".
    ///
    /// Deliberately never throws or crashes the process: a Shield/Monitor/Report extension that
    /// traps here would brick the very shield it's supposed to configure or unlock, which
    /// violates the "never trap the user" rule (CLAUDE.md, spec §24) even though it's an
    /// infrastructure failure rather than a lock-logic one. If the App Group container can't be
    /// opened (missing/misconfigured entitlement — a packaging bug, not a recoverable runtime
    /// state) this logs a fault and falls back to a private in-memory container instead, so the
    /// extension keeps running with empty data rather than not running at all. That fallback is
    /// silent to the user by design, which is exactly why it's logged as a `.fault`: treat any
    /// occurrence of this log line as a shipped-build bug to fix, not a normal degraded mode.
    /// Call ``makeAppGroupContainer(inMemory:)`` directly and handle the `throws` at app launch
    /// instead, where surfacing a real "couldn't load your data" recovery screen is possible.
    public static let appGroup: ModelContainer = {
        do {
            return try makeAppGroupContainer()
        } catch {
            appGroupLogger.fault(
                "Falling back to an in-memory ModelContainer — App Group store unavailable: \(String(describing: error), privacy: .public)"
            )
            guard let fallback = try? makeAppGroupContainer(inMemory: true) else {
                // Only reachable if `appGroupSchema` itself is invalid (e.g. two model types
                // with a conflicting name/version) — a programmer error in `appGroupModelTypes`
                // or one of the `@Model` definitions it references, not an environment one.
                fatalError(
                    "appGroupSchema is invalid — an in-memory ModelContainer also failed to build: \(error)"
                )
            }
            return fallback
        }
    }()

    private static let appGroupLogger = Logger(subsystem: "com.zano.app.Core", category: "ModelContainer+AppGroup")
}
