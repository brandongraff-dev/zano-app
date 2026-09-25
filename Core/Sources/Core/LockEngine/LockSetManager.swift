// Core/Sources/Core/LockEngine/LockSetManager.swift
//
// CRUD for `LockSet` — the named, reusable app selections a user locks together (spec §2 "App
// picker (FamilyActivityPicker) with saved 'lock sets' (e.g., Social, Games, All)", §11, §13
// `lock_sets`). `LockEngineManager` is the only thing that ever *applies*/removes a shield for a
// `LockSet`; this file only owns the rows themselves (create/rename/delete/set default, plus the
// reads a picker/settings screen needs).
//
// Not part of this task's SYSTEM CONTRACTS list (only `LockEngineManager`,
// `FocusSessionVerifier`, `GymVerifier`, `TimeBankEngine`, `StreakEngine`, and the LiveActivity
// attribute structs have a fixed public shape other agents build against) — but this file's public
// API is not a free choice either: `App/ZANO/Features/LockSetup/LockSetupView.swift` (same batch)
// already calls this type by name against one specific shape, documented in full in that file's
// header, and the Onboarding cluster's `OnboardingFlowState.swift` independently documents calling
// `LockSetManager.createLockSet(name:selection:)` the same (no `userID`) way. This file matches
// that shape exactly: `lockSetID:`-labeled `async throws` CRUD (matching `LockEngineManager`'s
// `sessionID:`/`lockSetID:` convention in this same folder), a synchronous `selection(for:)`
// decode, and — since neither known caller ever passes one — resolving the current device's one
// local `User` row internally rather than taking `userID` as a parameter, matching
// `LockEngineManager`/`TimeBankEngine`'s `fetchCurrentUser()` convention (same folder).

import Foundation
import SwiftData
import FamilyControls

/// Errors `LockSetManager` throws.
public enum LockSetManagerError: Error, Sendable, LocalizedError {
    /// No `LockSet` exists locally with this id.
    case lockSetNotFound(UUID)
    /// A create/rename call's name was empty (or all whitespace) after trimming.
    case nameEmpty
    /// `delete(lockSetID:)` guard: refused to delete the very last remaining `LockSet` for a
    /// user, so there is always at least one to fall back to as "default" — see
    /// `delete(lockSetID:)`.
    case cannotDeleteLastLockSet(UUID)
    /// No local `User` row exists yet to attribute a new `LockSet` to. Mirrors
    /// `LockEngineManager.LockEngineError.noSignedInUser` / `TimeBankEngineError.noSignedInUser`
    /// (same folder) — this device's local store is expected to hold exactly one `User` row
    /// (`Models/User.swift`) before any lock set can be created.
    case noSignedInUser
    /// `createLockSet(name:selection:makeDefault:)` refused: the user is on the Free tier (spec §21
    /// "Free: ... 1 lock set") and already has as many lock sets as
    /// `TierGating.canCreateAnotherLockSet(currentCount:)` allows. Never thrown for a Pro user
    /// (unlimited). A caller such as `LockSetupView` should route this to the paywall rather than
    /// show a generic save-failed alert — see this task's knownIssues.
    case freeTierLockSetLimitReached

    public var errorDescription: String? {
        switch self {
        case .lockSetNotFound(let id):
            "No LockSet found with id \(id)."
        case .nameEmpty:
            "A LockSet's name can't be empty."
        case .cannotDeleteLastLockSet(let id):
            "Refusing to delete LockSet \(id): it's the only LockSet this user has left."
        case .noSignedInUser:
            "No local User row exists yet."
        case .freeTierLockSetLimitReached:
            "You've reached the lock set limit on the Free plan. Upgrade to Pro for unlimited lock sets."
        }
    }
}

/// The sole owner of creating, renaming, deleting, and re-defaulting `LockSet` rows.
///
/// `@MainActor` for the same reason as `LockEngineManager` (see its doc comment): a plain
/// `final class` with `static let shared` needs either `Sendable` conformance or global-actor
/// isolation to satisfy Swift 6 strict concurrency, and every realistic caller (settings UI, the
/// app-picker flow, App Intents) is already on the main actor.
@MainActor
public final class LockSetManager {
    public static let shared = LockSetManager()

    private let modelContainer: ModelContainer
    private let context: ModelContext

    /// - Parameter modelContainer: Defaults to the shared App Group container (spec §11).
    ///   Overridable for unit tests (an in-memory container).
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
    }

    // MARK: - Create

    /// Creates a new `LockSet` for the current device's signed-in user (see `fetchCurrentUser()`
    /// below). If `makeDefault` is `true` (or this is the user's first `LockSet`), it becomes the
    /// default and every other `LockSet` for that user is un-defaulted (`LockSet.isDefault` is
    /// meant to be unique per user — see `Models/LockSet.swift`; SwiftData on iOS 17 can't express
    /// that as a composite constraint, so this file enforces it by hand).
    ///
    /// - Parameter selection: The `FamilyActivitySelection` to shield, JSON-encoded into
    ///   `LockSet.appTokensBlob` exactly as `Models/LockSet.swift`'s doc comment expects
    ///   (`try JSONEncoder().encode(selection)`). Pass `nil` to create an empty lock set the user
    ///   fills in later from the app picker.
    /// - Returns: the new `LockSet.id`.
    /// - Throws: `LockSetManagerError.nameEmpty`, `.noSignedInUser`,
    ///   `.freeTierLockSetLimitReached` (spec §21 tier gate — checked via
    ///   `TierGating.canCreateAnotherLockSet(currentCount:)` against the user's existing lock set
    ///   count; a user's first lock set is always allowed), or whatever `ModelContext.save()`
    ///   throws.
    @discardableResult
    public func createLockSet(
        name: String,
        selection: FamilyActivitySelection? = nil,
        makeDefault: Bool = false
    ) async throws -> UUID {
        let trimmed = try validated(name: name)
        let user = try fetchCurrentUser()
        let blob = try selection.map { try JSONEncoder().encode($0) }
        let existingCount = try await lockSets(for: user.id).count
        guard await TierGating.canCreateAnotherLockSet(currentCount: existingCount) else {
            throw LockSetManagerError.freeTierLockSetLimitReached
        }
        let isFirstLockSet = existingCount == 0
        let shouldDefault = makeDefault || isFirstLockSet

        let lockSet = LockSet(userID: user.id, name: trimmed, appTokensBlob: blob, isDefault: shouldDefault)
        context.insert(lockSet)
        if shouldDefault {
            try clearDefault(for: user.id, except: lockSet.id)
        }
        try context.save()
        await refreshMonitorMirrors()
        return lockSet.id
    }

    // MARK: - Update

    public func rename(lockSetID: UUID, to newName: String) async throws {
        let trimmed = try validated(name: newName)
        let lockSet = try requireLockSet(id: lockSetID)
        lockSet.name = trimmed
        try context.save()
    }

    /// Replaces a `LockSet`'s saved app selection (the app-picker flow, spec §2). Does **not**
    /// touch any shield currently applied for it — if this `LockSet` backs the active lock,
    /// re-apply via `LockEngineManager` (ending and restarting the lock) to pick up the change.
    public func updateSelection(_ selection: FamilyActivitySelection, for lockSetID: UUID) async throws {
        let lockSet = try requireLockSet(id: lockSetID)
        lockSet.appTokensBlob = try JSONEncoder().encode(selection)
        try context.save()
        LockEngineSharedState.setLockSetSelectionData(lockSet.appTokensBlob, for: lockSetID)
    }

    public func setDefault(lockSetID: UUID) async throws {
        let lockSet = try requireLockSet(id: lockSetID)
        try clearDefault(for: lockSet.userID, except: lockSetID)
        lockSet.isDefault = true
        try context.save()
        LockEngineSharedState.defaultLockSetID = lockSetID
    }

    // MARK: - Delete

    /// Deletes a `LockSet`. If it was the user's default, another remaining `LockSet` (if any) is
    /// promoted to default so `defaultLockSet(for:)` never silently goes from "some default" to
    /// "no default" just because the previous default was removed.
    ///
    /// - Throws: `LockSetManagerError.cannotDeleteLastLockSet` if this is the user's only
    ///   `LockSet` — an NFC tag, a schedule, or a manual-lock button could still reference it by
    ///   id, and a user should always have at least one lock set to fall back to (CLAUDE.md:
    ///   never trap the user — including via a dead-end "no lock sets left" state).
    public func delete(lockSetID: UUID) async throws {
        let lockSet = try requireLockSet(id: lockSetID)
        let userID = lockSet.userID
        let wasDefault = lockSet.isDefault

        let siblingCount = try await lockSets(for: userID).count - 1
        guard siblingCount > 0 else {
            throw LockSetManagerError.cannotDeleteLastLockSet(lockSetID)
        }

        context.delete(lockSet)
        try context.save()

        if wasDefault {
            try promoteAnyLockSet(toDefaultFor: userID)
        }
        // A deleted set's schedule and tiers must not keep locking anything.
        LockScheduler.shared.removeSchedule(for: lockSetID)
        PartialUnlockTierStore.removeTiers(for: lockSetID)
        await refreshMonitorMirrors()
    }

    // MARK: - ZANOMonitor mirrors (spec §27: the extension reads App Group state only)

    /// Copies every lock set's `appTokensBlob`, the default lock set id and the active goal count
    /// into the App Group so `ZANOMonitor` can shield a scheduled lock without opening SwiftData.
    /// Tokens stay on device (same container, never synced). Called after every mutation here and
    /// on each app foreground by `LockScheduler.reconcile`.
    public func refreshMonitorMirrors() async {
        guard let user = try? fetchCurrentUser(), let sets = try? await lockSets(for: user.id) else { return }
        var selections: [UUID: Data] = [:]
        for lockSet in sets {
            if let blob = lockSet.appTokensBlob { selections[lockSet.id] = blob }
        }
        LockEngineSharedState.replaceLockSetSelections(selections)
        LockEngineSharedState.defaultLockSetID = sets.first(where: \.isDefault)?.id
        if let goalIDs = try? IntentSupport.activeGoalIDs(for: user.id, in: context) {
            LockEngineSharedState.activeGoalCount = goalIDs.count
        }
    }

    // MARK: - Read

    public func lockSets(for userID: UUID) async throws -> [LockSet] {
        let descriptor = FetchDescriptor<LockSet>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func defaultLockSet(for userID: UUID) async throws -> LockSet? {
        var descriptor = FetchDescriptor<LockSet>(
            predicate: #Predicate { $0.userID == userID && $0.isDefault == true }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func lockSet(id: UUID) async throws -> LockSet? {
        var descriptor = FetchDescriptor<LockSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Synchronous, in-memory decode of `lockSet.appTokensBlob` into a `FamilyActivitySelection`
    /// — not a persistence operation, so unlike everything else in this file it takes the
    /// `LockSet` instance directly (not an id) and returns without `async`/`throws`.
    /// `LockSetupView` (`App/ZANO/Features/LockSetup/LockSetupView.swift`) calls this inline while
    /// building row summary text and while populating the edit sheet, so a `nil` or undecodable
    /// blob resolves to an empty `FamilyActivitySelection()` — matching
    /// `LockEngineManager.invalidAppTokensBlob`'s "never crash on a corrupt blob" handling of the
    /// same underlying property — rather than throwing mid-render.
    public func selection(for lockSet: LockSet) -> FamilyActivitySelection {
        guard let blob = lockSet.appTokensBlob,
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
        else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    // MARK: - Private

    private func validated(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LockSetManagerError.nameEmpty }
        return trimmed
    }

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one — matching
    /// `LockEngineManager`/`TimeBankEngine`'s identical helper in this same folder.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw LockSetManagerError.noSignedInUser
        }
        return user
    }

    private func requireLockSet(id: UUID) throws -> LockSet {
        var descriptor = FetchDescriptor<LockSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let lockSet = try context.fetch(descriptor).first else {
            throw LockSetManagerError.lockSetNotFound(id)
        }
        return lockSet
    }

    private func clearDefault(for userID: UUID, except keepID: UUID) throws {
        let descriptor = FetchDescriptor<LockSet>(
            predicate: #Predicate { $0.userID == userID && $0.isDefault == true && $0.id != keepID }
        )
        for lockSet in try context.fetch(descriptor) {
            lockSet.isDefault = false
        }
    }

    private func promoteAnyLockSet(toDefaultFor userID: UUID) throws {
        var descriptor = FetchDescriptor<LockSet>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        guard let remaining = try context.fetch(descriptor).first else { return }
        remaining.isDefault = true
        try context.save()
    }
}
