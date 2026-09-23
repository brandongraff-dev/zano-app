// StoreTests.swift
// Core / Tests / CoreTests
//
// Coverage for Core/Sources/Core/Store/*.swift: `SharedDefaults` (the App Group UserDefaults
// mirror, docs/spec.md §5.1/§5.2/§5.11/§27) and `ModelContainer+AppGroup` (the shared SwiftData
// store factory, docs/spec.md §11/§13).
//
// Environment note (see this task's knownIssues): `SharedDefaults` opens
// `UserDefaults(suiteName: AppGroup.identifier)` with `?? .standard` as its only fallback — there is
// no test seam to inject an isolated store. In a bare `swift test` process (no
// com.apple.security.application-groups entitlement), `UserDefaults(suiteName:)` most likely still
// succeeds (that initializer isn't documented to require the entitlement, only a non-empty suite
// name) and opens a *real*, persistent-on-disk preferences domain named "group.com.zano.app" that
// isn't actually shared with anything — the entitlement only matters for real cross-process
// sharing. That means these tests mutate real, persistent state on whatever machine runs them. Every
// test below captures the prior value and restores it via `defer`, and the suite is `.serialized` so
// concurrent tests never race the same keys, but this is a real limitation of the code under test,
// not a workaround this file can fully paper over — flagged rather than silently relied upon.
//
// `ModelContainer.appGroup`/`makeAppGroupContainer` have a cleaner test story: `inMemory: true`
// never touches the App Group container at all, and `appGroupStoreURL()`/`appGroup`'s fallback path
// are exercised exactly by running with no entitlement, which is what a bare `swift test` process
// already is.

import Testing
import SwiftData
import Foundation
@testable import Core

@Suite("Store — SharedDefaults & ModelContainer+AppGroup", .serialized)
struct StoreTests {

    // MARK: - SharedDefaults: Streak (spec §5.6, §5.9, §8)

    @Test func currentStreakAndBestStreakRoundTrip() {
        let originalCurrent = SharedDefaults.currentStreak
        let originalBest = SharedDefaults.bestStreak
        defer {
            SharedDefaults.currentStreak = originalCurrent
            SharedDefaults.bestStreak = originalBest
        }

        SharedDefaults.currentStreak = 14
        SharedDefaults.bestStreak = 21
        #expect(SharedDefaults.currentStreak == 14)
        #expect(SharedDefaults.bestStreak == 21)
    }

    // MARK: - SharedDefaults: Coach voice (spec §5.13)

    @Test func coachVoiceRoundTripsAsARawString() {
        let original = SharedDefaults.coachVoice
        defer { SharedDefaults.coachVoice = original }

        SharedDefaults.coachVoice = "tough_love"
        #expect(SharedDefaults.coachVoice == "tough_love")

        SharedDefaults.coachVoice = "data"
        #expect(SharedDefaults.coachVoice == "data")
    }

    // MARK: - SharedDefaults: Active lock (spec §5.1, §11, §27)

    @Test func activeLockSessionAndSetIDsRoundTripAsUUIDsAndClearToNil() {
        let originalSession = SharedDefaults.activeLockSessionID
        let originalSet = SharedDefaults.activeLockSetID
        defer {
            SharedDefaults.activeLockSessionID = originalSession
            SharedDefaults.activeLockSetID = originalSet
        }

        let sessionID = UUID()
        let setID = UUID()
        SharedDefaults.activeLockSessionID = sessionID
        SharedDefaults.activeLockSetID = setID
        #expect(SharedDefaults.activeLockSessionID == sessionID)
        #expect(SharedDefaults.activeLockSetID == setID)

        SharedDefaults.activeLockSessionID = nil
        SharedDefaults.activeLockSetID = nil
        #expect(SharedDefaults.activeLockSessionID == nil)
        #expect(SharedDefaults.activeLockSetID == nil)
    }

    @Test func activeLockSessionIDReturnsNilForAPreExistingNonUUIDStringInTheStore() {
        // `SharedDefaults`'s own setter can never write a malformed value — this exercises the
        // defensive `uuid(forKey:)` branch (returns nil instead of crashing) for a value that could
        // only get there some other way (a future schema change, a corrupted plist, ...).
        //
        // `Keys.activeLockSessionID` is `private` to `SharedDefaults`, so this pokes the same App
        // Group suite directly by its known raw key string ("shared.activeLockSessionID", read from
        // Core/Sources/Core/Store/SharedDefaults.swift) rather than through the type itself. If that
        // private key name is ever renamed, this test's coupling to it — not `SharedDefaults`'s
        // public contract — is what breaks; flagged here so a future reader knows why.
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.activeLockSessionID"
        let original = rawDefaults.string(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.set("not-a-uuid", forKey: key)
        #expect(SharedDefaults.activeLockSessionID == nil)
    }

    @Test func activeLockModeRoundTripsThroughItsRawValueAndClearsToNil() {
        let original = SharedDefaults.activeLockMode
        defer { SharedDefaults.activeLockMode = original }

        SharedDefaults.activeLockMode = .earn
        #expect(SharedDefaults.activeLockMode == .earn)

        SharedDefaults.activeLockMode = .full
        #expect(SharedDefaults.activeLockMode == .full)

        SharedDefaults.activeLockMode = nil
        #expect(SharedDefaults.activeLockMode == nil)
    }

    @Test func goalsRemainingForActiveLockRoundTrips() {
        let original = SharedDefaults.goalsRemainingForActiveLock
        defer { SharedDefaults.goalsRemainingForActiveLock = original }

        SharedDefaults.goalsRemainingForActiveLock = 3
        #expect(SharedDefaults.goalsRemainingForActiveLock == 3)

        SharedDefaults.goalsRemainingForActiveLock = 0
        #expect(SharedDefaults.goalsRemainingForActiveLock == 0)
    }

    // MARK: - SharedDefaults: Time Bank (spec §5.2, §5.11)

    @Test func earnedMinutesRemainingTodaySetterAlsoStampsTheMirrorDateAsToday() {
        let originalMinutes = SharedDefaults.earnedMinutesRemainingToday
        defer { SharedDefaults.earnedMinutesRemainingToday = originalMinutes }

        SharedDefaults.earnedMinutesRemainingToday = 25
        #expect(SharedDefaults.earnedMinutesRemainingToday == 25)
        // Writing the balance stamps today's date as a side effect (doc comment on the setter) —
        // this is what lets `earnedMinutesMirrorIsForToday` distinguish a fresh mirror from a stale
        // one left over from a previous day.
        #expect(SharedDefaults.earnedMinutesMirrorIsForToday)
    }

    // MARK: - SharedDefaults: Next scheduled lock

    @Test func nextScheduledLockAtRoundTripsAndClearsToNil() {
        let original = SharedDefaults.nextScheduledLockAt
        defer { SharedDefaults.nextScheduledLockAt = original }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        SharedDefaults.nextScheduledLockAt = date
        #expect(SharedDefaults.nextScheduledLockAt == date)

        SharedDefaults.nextScheduledLockAt = nil
        #expect(SharedDefaults.nextScheduledLockAt == nil)
    }

    // MARK: - ModelContainer+AppGroup: schema

    @Test func appGroupModelTypesIncludesEveryCoreEntityAndOutboxEvent() {
        // `OutboxEvent` has no remote Postgres counterpart (it's the local half of the Sync outbox
        // pattern) but must still be registered here, per the array's own doc comment, or the store
        // silently drops every outbox row at runtime. Checked as a subset (not exact equality) so
        // this doesn't spuriously fail if another in-flight session registers an additional model
        // type (e.g. KitchenStaple) in the same file this run didn't touch.
        let names = Set(ModelContainer.appGroupModelTypes.map { String(describing: $0) })
        let expected: Set<String> = [
            "User", "Goal", "DailyPlan", "GoalEvent", "LockSet", "LockSession", "TimeBank",
            "Streak", "Gym", "Meal", "Squad", "SquadMember", "Duel", "Badge", "Coin", "Recap",
            "Nudge", "RiskScore", "Subscription", "OutboxEvent"
        ]
        #expect(expected.isSubset(of: names))
    }

    @Test func appGroupSchemaIsBuiltFromAppGroupModelTypes() {
        let schema = ModelContainer.appGroupSchema
        let schemaNames = Set(schema.entities.map(\.name))
        let typeNames = Set(ModelContainer.appGroupModelTypes.map { String(describing: $0) })
        #expect(schemaNames == typeNames)
    }

    // MARK: - ModelContainer+AppGroup: in-memory container factory

    @Test func makeAppGroupContainerInMemoryBuildsAWorkingStore() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)

        let user = User()
        context.insert(user)
        try context.save()

        let userID = user.id
        let fetched = try context.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.id == userID }))
        #expect(fetched.count == 1)
    }

    @Test func inMemoryAppGroupContainersAreIndependentOfEachOther() throws {
        // Doc comment on `appGroupSchema`: building a second, independent container "never
        // accidentally shares Schema identity with the on-disk one" — this is the SwiftUI-preview /
        // unit-test guarantee that claim exists for.
        let containerA = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let containerB = try ModelContainer.makeAppGroupContainer(inMemory: true)

        let contextA = ModelContext(containerA)
        contextA.insert(User())
        try contextA.save()

        let contextB = ModelContext(containerB)
        #expect(try contextB.fetch(FetchDescriptor<User>()).isEmpty)
    }

    // MARK: - ModelContainer+AppGroup: on-disk path without the App Group entitlement

    @Test func appGroupStoreURLThrowsWithoutTheAppGroupEntitlement() {
        // A bare `swift test` process has no com.apple.security.application-groups entitlement, so
        // `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` should return nil —
        // exactly the condition `ModelContainerError.appGroupContainerUnavailable` documents.
        // Flagged as an environmental assumption in knownIssues since it can't be checked here.
        #expect(throws: ModelContainerError.self) {
            _ = try ModelContainer.appGroupStoreURL()
        }
    }

    @Test func sharedAppGroupContainerFallsBackToInMemoryInsteadOfCrashingWithoutTheEntitlement() throws {
        // `ModelContainer.appGroup`'s doc comment: "never trap the user" — if the on-disk App Group
        // store can't be opened it must fall back to a private in-memory container rather than
        // throwing or crashing. A bare `swift test` process is exactly that "no entitlement" case.
        let container = ModelContainer.appGroup
        let context = ModelContext(container)

        let user = User()
        context.insert(user)
        try context.save()
        #expect(!context.hasChanges)
    }

    // MARK: - SharedDefaults: activeLockMode with a stale/invalid raw string

    @Test func activeLockModeReturnsNilForAPreExistingInvalidRawStringInTheStore() {
        // Mirrors `activeLockSessionIDReturnsNilForAPreExistingNonUUIDStringInTheStore` above, but
        // for the `LockMode(rawValue:)` decode branch: a value that could only land in the store
        // some other way (a future `LockMode` case this build doesn't know about yet, a corrupted
        // plist) must read back as `nil` rather than trap.
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.activeLockMode"
        let original = rawDefaults.string(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.set("hybrid", forKey: key)
        #expect(SharedDefaults.activeLockMode == nil)
    }

    // MARK: - SharedDefaults: defaults when a key has never been written

    @Test func coachVoiceDefaultsToHypeWhenTheKeyHasNeverBeenSet() {
        // `coachVoice`'s doc comment: defaults to `"hype"`, matching onboarding's suggested default
        // voice (spec §7). Removes the raw key first (rather than trusting whatever a prior test in
        // this process left behind) so this actually exercises the "never set" branch, not just
        // "currently happens to be hype".
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.coachVoice"
        let original = rawDefaults.string(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.removeObject(forKey: key)
        #expect(SharedDefaults.coachVoice == "hype")
    }

    @Test func goalsRemainingForActiveLockDefaultsToZeroWhenTheKeyHasNeverBeenSet() {
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.goalsRemainingForActiveLock"
        let original = rawDefaults.object(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.removeObject(forKey: key)
        // `UserDefaults.integer(forKey:)` itself already defaults an absent key to 0 — this pins
        // that platform behavior down as part of `SharedDefaults`'s own documented contract rather
        // than leaving it implicit.
        #expect(SharedDefaults.goalsRemainingForActiveLock == 0)
    }

    @Test func nextScheduledLockAtDefaultsToNilWhenTheKeyHasNeverBeenSet() {
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.nextScheduledLockAt"
        let original = rawDefaults.object(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.removeObject(forKey: key)
        #expect(SharedDefaults.nextScheduledLockAt == nil)
    }

    @Test func earnedMinutesMirrorIsForTodayIsFalseWhenTheMirrorDateKeyHasNeverBeenSet() {
        // Distinct from `earnedMinutesRemainingTodaySetterAlsoStampsTheMirrorDateAsToday` above,
        // which only proves the *positive* case (freshly written ⇒ true). A device that has never
        // once written a Time Bank balance (e.g. right after install, before the first goal
        // verification) must read this as stale/false, per the property's own doc comment, not
        // default to true just because "no mirror date" technically isn't "today wasn't the date".
        let rawDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let key = "shared.earnedMinutesMirrorDate"
        let original = rawDefaults.object(forKey: key)
        defer {
            if let original {
                rawDefaults.set(original, forKey: key)
            } else {
                rawDefaults.removeObject(forKey: key)
            }
        }

        rawDefaults.removeObject(forKey: key)
        #expect(!SharedDefaults.earnedMinutesMirrorIsForToday)
    }

    // MARK: - ModelContainer+AppGroup: schema sanity

    @Test func appGroupModelTypesContainsNoDuplicateTypeNames() {
        // A type accidentally listed twice would still compile (the array is just literal
        // `PersistentModel.Type` values) and might not even fail at the `Schema` layer depending on
        // SwiftData's own de-duplication, so this checks the source list itself stays honest as more
        // model types are added by other in-flight sessions.
        let names = ModelContainer.appGroupModelTypes.map { String(describing: $0) }
        #expect(names.count == Set(names).count)
    }
}
