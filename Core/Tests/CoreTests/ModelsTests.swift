// ModelsTests.swift
// Core / Tests / CoreTests
//
// Coverage for Core/Sources/Core/Models/*.swift against docs/spec.md §13 (Data Model): SwiftData
// relationship wiring (inverse relationships resolve both ways, cascade deletes match the FK
// `on delete` behavior each model's doc comments describe) and jsonb-mirrored fields (GoalEvent.meta,
// Meal.items, Recap.stats, Nudge.arm) round-trip through SwiftData the same way they'd round-trip
// through Postgres.
//
// These tests build their own in-memory `ModelContainer` per test (never the on-disk App Group
// store) using `ModelContainer.appGroupSchema`, so relationship/cascade behavior is exercised
// against the exact schema the real app registers (Core/Sources/Core/Store/ModelContainer+AppGroup
// .swift) rather than an ad hoc subset. Cannot run without a Swift toolchain (no Mac in this
// environment) — see this task's knownIssues for what's unverified.

import Testing
import SwiftData
import Foundation
@testable import Core

@Suite("Models — SwiftData relationships & jsonb round-trips")
struct ModelsTests {

    /// A fresh, isolated in-memory store per test — using the full App Group schema so foreign
    /// relationships (User ↔ Goal ↔ DailyPlan ↔ GoalEvent, plus every other registered model)
    /// resolve exactly as they would against `ModelContainer.appGroup` in the real app.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: ModelContainer.appGroupSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: ModelContainer.appGroupSchema, configurations: [configuration])
    }

    // MARK: - User / Goal / DailyPlan / GoalEvent graph

    @Test func userGoalGoalEventGraphWiresInverseRelationshipsBothWays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User(tz: "America/Chicago", coachVoice: .toughLove)
        let goal = Goal(type: .protein, title: "Hit protein", verificationTier: .b, user: user)
        let event = GoalEvent(kind: .complete, value: 42, source: .manual, verified: true, user: user, goal: goal)

        context.insert(user)
        context.insert(goal)
        context.insert(event)
        try context.save()

        // Forward references set at construction time.
        #expect(goal.user?.id == user.id)
        #expect(event.user?.id == user.id)
        #expect(event.goal?.id == goal.id)

        // SwiftData-maintained inverses resolve the other direction too, after a save.
        #expect(user.goals.map(\.id) == [goal.id])
        #expect(user.goalEvents.map(\.id) == [event.id])
        #expect(goal.events.map(\.id) == [event.id])
    }

    @Test func deletingUserCascadesToGoalsDailyPlansAndGoalEvents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User()
        let goal = Goal(type: .steps, title: "10k steps", verificationTier: .a, user: user)
        let dailyPlan = DailyPlan(date: .now, plannedValue: 10_000, source: .rules, user: user, goal: goal)
        let event = GoalEvent(kind: .log, source: .healthKit, user: user, goal: goal)

        context.insert(user)
        context.insert(goal)
        context.insert(dailyPlan)
        context.insert(event)
        try context.save()

        let goalID = goal.id
        let dailyPlanID = dailyPlan.id
        let eventID = event.id

        context.delete(user)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == goalID })).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyPlan>(predicate: #Predicate { $0.id == dailyPlanID })).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.id == eventID })).isEmpty)
    }

    @Test func deletingGoalCascadesToItsDailyPlansAndEventsButLeavesUserIntact() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User()
        let goal = Goal(type: .water, title: "Gallon a day", verificationTier: .b, user: user)
        let dailyPlan = DailyPlan(date: .now, source: .rules, user: user, goal: goal)
        let event = GoalEvent(kind: .verify, source: .widget, user: user, goal: goal)

        context.insert(user)
        context.insert(goal)
        context.insert(dailyPlan)
        context.insert(event)
        try context.save()

        let userID = user.id
        let dailyPlanID = dailyPlan.id
        let eventID = event.id

        // Deleting the goal only — the `user` FK on Goal has no cascade rule declared on it
        // (unlike `User.goals`'s cascade back onto Goal), so this must not touch the user row.
        context.delete(goal)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.id == userID })).count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyPlan>(predicate: #Predicate { $0.id == dailyPlanID })).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.id == eventID })).isEmpty)
    }

    @Test func dailyPlanSourceDefaultsToRulesAndCarriesPlanBValue() {
        let plan = DailyPlan(date: .now, plannedValue: 60, planBValue: 20)
        #expect(plan.source == .rules)
        #expect(plan.difficultyStep == 0)
        #expect(plan.planBValue == 20)
    }

    // MARK: - GoalEvent.meta ↔ metaData JSON round-trip

    @Test func goalEventMetaRoundTripsThroughMetaData() throws {
        let meta: JSONValue = .object([
            "tagID": .string("nfc-abc123"),
            "confidence": .number(0.87),
            "verified": .bool(true),
            "items": .array([.string("chicken"), .string("rice")]),
            "extra": .null
        ])
        let event = GoalEvent(kind: .verify, source: .nfc, meta: meta)

        // Decode the backing `Data` independently of the `meta` computed property, to confirm the
        // initializer actually persisted the structured value into `metaData` (not just held it in
        // some other in-memory field).
        let decodedFromStorage = try JSONDecoder().decode(JSONValue.self, from: event.metaData)
        #expect(decodedFromStorage == meta)
        #expect(event.meta == meta)

        // Mutating `meta` re-encodes into `metaData`.
        event.meta = .object(["updated": .bool(true)])
        let redecoded = try JSONDecoder().decode(JSONValue.self, from: event.metaData)
        #expect(redecoded == .object(["updated": .bool(true)]))
    }

    @Test func goalEventMetaDefaultsToEmptyObjectWhenMetaDataIsNotValidJSON() {
        let event = GoalEvent(kind: .log, source: .manual)
        event.metaData = Data("not valid json".utf8)
        #expect(event.meta == .object([:]))
    }

    @Test func goalEventMetaDefaultsToEmptyObjectWhenNeverSet() {
        // `goal_events.meta jsonb not null default '{}'` — the local mirror's initializer default
        // (`meta: JSONValue = .object([:])`) must match that.
        let event = GoalEvent(kind: .log, source: .manual)
        #expect(event.meta == .object([:]))
    }

    @Test func goalEventMetaSurvivesAModelContainerRoundTripThroughADifferentContext() throws {
        let container = try makeContainer()
        let insertingContext = ModelContext(container)

        let meta: JSONValue = .object(["barcode": .string("012345678905"), "grams": .number(42)])
        let event = GoalEvent(kind: .verify, source: .barcode, meta: meta)
        insertingContext.insert(event)
        try insertingContext.save()

        let eventID = event.id
        // Fetch through a *separate* context against the same container, so this actually proves
        // the JSON persisted to the store rather than only living on the original in-memory object.
        let readingContext = ModelContext(container)
        let fetched = try #require(
            try readingContext.fetch(FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.id == eventID })).first
        )
        #expect(fetched.meta == meta)
    }

    // MARK: - LockSet / LockSession

    @Test func lockSetPersistsAppTokensBlobAsOpaqueDeviceLocalData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let blob = Data([0x01, 0x02, 0x03])
        let lockSet = LockSet(userID: UUID(), name: "Distractions", appTokensBlob: blob, isDefault: true)
        context.insert(lockSet)
        try context.save()

        let lockSetID = lockSet.id
        let fetched = try #require(
            try context.fetch(FetchDescriptor<LockSet>(predicate: #Predicate { $0.id == lockSetID })).first
        )
        #expect(fetched.appTokensBlob == blob)
        #expect(fetched.isDefault)
    }

    @Test func lockSessionIsActiveRequiresBothEndedAtAndUnlockKindToBeNil() {
        let stillActive = LockSession(userID: UUID(), mode: .earn, requiredGoalIDs: [UUID()])
        #expect(stillActive.isActive)

        let endedOnly = LockSession(userID: UUID(), mode: .full)
        endedOnly.endedAt = .now
        #expect(!endedOnly.isActive)

        let unlockKindOnly = LockSession(userID: UUID(), mode: .full)
        unlockKindOnly.unlockKind = .emergency
        #expect(!unlockKindOnly.isActive)

        let fullyEnded = LockSession(userID: UUID(), mode: .full)
        fullyEnded.endedAt = .now
        fullyEnded.unlockKind = .earned
        #expect(!fullyEnded.isActive)
    }

    @Test func lockSessionStoresLooseUUIDForeignKeysNotRelationships() throws {
        // Per LockSession's doc comment: lockSetID/requiredGoalIDs are plain UUIDs, deliberately
        // not `@Relationship`s, so they must survive a container round-trip as-is.
        let container = try makeContainer()
        let context = ModelContext(container)

        let lockSetID = UUID()
        let requiredGoalIDs = [UUID(), UUID()]
        let session = LockSession(
            userID: UUID(),
            lockSetID: lockSetID,
            trigger: .nfc,
            mode: .earn,
            requiredGoalIDs: requiredGoalIDs
        )
        context.insert(session)
        try context.save()

        let sessionID = session.id
        let fetched = try #require(
            try context.fetch(FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        #expect(fetched.lockSetID == lockSetID)
        #expect(Set(fetched.requiredGoalIDs) == Set(requiredGoalIDs))
        #expect(fetched.trigger == .nfc)
    }

    // MARK: - Streak

    @Test func streakDefaultsMatchTheFreeTierNewUserBaseline() {
        // spec §8/§13: `freezes_left integer not null default 1`, no streak yet.
        let streak = Streak(userID: UUID())
        #expect(streak.current == 0)
        #expect(streak.best == 0)
        #expect(streak.freezesLeft == 1)
        #expect(streak.lastEarnedDate == nil)
        #expect(!streak.neverMissTwiceArmed)
    }

    // MARK: - TimeBank

    @Test func timeBankRemainingMinNeverGoesNegative() {
        let timeBank = TimeBank(userID: UUID(), date: .now, earnedMin: 10, spentMin: 25)
        #expect(timeBank.remainingMin == 0)

        let positive = TimeBank(userID: UUID(), date: .now, earnedMin: 30, spentMin: 12)
        #expect(positive.remainingMin == 18)
    }

    @Test func timeBankDayKeyCombinesUserAndUTCCalendarDay() {
        let userID = UUID()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        // 23:00 UTC on March 15th — chosen close to a day boundary to make sure the key is keyed
        // off the UTC calendar day, not local time.
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 23))!

        let timeBank = TimeBank(userID: userID, date: date)
        #expect(timeBank.dayKey == "\(userID.uuidString)_2026-3-15")
    }

    @Test func timeBankRefreshDayKeyRecomputesAfterMutatingDate() {
        let userID = UUID()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let originalDate = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let timeBank = TimeBank(userID: userID, date: originalDate)
        let originalKey = timeBank.dayKey

        let newDate = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        timeBank.date = newDate
        timeBank.refreshDayKey()

        #expect(timeBank.dayKey != originalKey)
        #expect(timeBank.dayKey == "\(userID.uuidString)_2026-1-2")
    }

    @Test func timeBankDayKeyUniqueAttributeUpsertsADuplicateUserAndDatePair() throws {
        // Mirrors the remote `unique (user_id, date)` constraint (spec §13) — see TimeBank's own
        // doc comment on `dayKey`. Verified on a real toolchain (CI): SwiftData's
        // `@Attribute(.unique)` does NOT throw on a conflicting insert — it UPSERTS (the new row
        // replaces the existing one). So the local store can never hold two rows for one (user,
        // day), which is the property that matters.
        let container = try makeContainer()
        let context = ModelContext(container)
        let userID = UUID()
        let date = Date()

        context.insert(TimeBank(userID: userID, date: date, earnedMin: 5))
        try context.save()

        context.insert(TimeBank(userID: userID, date: date, earnedMin: 10))
        try context.save()

        let rows = try context.fetch(FetchDescriptor<TimeBank>())
        #expect(rows.count == 1)
        #expect(rows.first?.earnedMin == 10)
    }

    // MARK: - Gym

    @Test func gymDefaultsMatchTheRemoteColumnDefaults() {
        let gym = Gym(userID: UUID(), lat: 41.8781, lng: -87.6298)
        #expect(gym.radiusMeters == 150)
        #expect(!gym.autoDetected)
        #expect(!gym.confirmed)
    }

    // MARK: - Meal (jsonb `items` round-trip)

    @Test func mealItemsArraySurvivesAModelContainerRoundTrip() throws {
        let container = try makeContainer()
        let insertingContext = ModelContext(container)

        let items = [
            MealItem(name: "grilled chicken breast", proteinGramsEstimate: 38, confidence: 0.91),
            MealItem(name: "white rice", proteinGramsEstimate: 4, confidence: 0.75)
        ]
        let meal = Meal(userID: UUID(), items: items, proteinG: 42, confirmed: true)
        insertingContext.insert(meal)
        try insertingContext.save()

        let mealID = meal.id
        let readingContext = ModelContext(container)
        let fetched = try #require(
            try readingContext.fetch(FetchDescriptor<Meal>(predicate: #Predicate { $0.id == mealID })).first
        )
        #expect(fetched.items == items)
        #expect(fetched.proteinG == 42)
        #expect(fetched.confirmed)
    }

    // MARK: - Squad / SquadMember / Duel

    @Test func squadAndSquadMemberPersistCompositeIdentityFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let squad = Squad(name: "Leg Day Crew", createdBy: UUID(), inviteCode: "LEGDAY1")
        let ownerID = squad.createdBy
        let member = SquadMember(squadID: squad.id, userID: ownerID, role: .owner)

        context.insert(squad)
        context.insert(member)
        try context.save()

        let squadID = squad.id
        let fetchedMember = try #require(
            try context.fetch(FetchDescriptor<SquadMember>(predicate: #Predicate { $0.squadID == squadID })).first
        )
        #expect(fetchedMember.userID == ownerID)
        #expect(fetchedMember.role == .owner)
    }

    @Test func duelStatusDefaultsToPendingAndScoresStartAtZero() {
        let duel = Duel(aUser: UUID(), bUser: UUID(), startDate: .now, endDate: .now.addingTimeInterval(7 * 86_400))
        #expect(duel.status == .pending)
        #expect(duel.aPoints == 0)
        #expect(duel.bPoints == 0)

        duel.status = .active
        duel.aPoints = 3
        #expect(duel.status == .active)
        #expect(duel.aPoints == 3)
    }

    // MARK: - Badge / Coin

    @Test func badgeAndCoinPersistThroughAModelContainer() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let userID = UUID()
        let badge = Badge(userID: userID, key: "streak_14")
        let coin = Coin(userID: userID, balance: 120)
        context.insert(badge)
        context.insert(coin)
        try context.save()

        let badgeID = badge.id
        let fetchedBadge = try #require(
            try context.fetch(FetchDescriptor<Badge>(predicate: #Predicate { $0.id == badgeID })).first
        )
        #expect(fetchedBadge.key == "streak_14")

        let fetchedCoin = try #require(
            try context.fetch(FetchDescriptor<Coin>(predicate: #Predicate { $0.userID == userID })).first
        )
        #expect(fetchedCoin.balance == 120)
    }

    // MARK: - Recap (jsonb `stats` round-trip)

    @Test func recapStatsSurviveAModelContainerRoundTrip() throws {
        let container = try makeContainer()
        let insertingContext = ModelContext(container)

        let stats = RecapStats(
            goalCompletionRings: ["protein": 0.8, "steps": 1.0],
            bestDay: "Tuesday",
            timeReclaimedMinutes: 245,
            streak: 14,
            rankMovement: 2,
            goalsCompleted: 18,
            goalsPlanned: 21
        )
        let recap = Recap(userID: UUID(), weekStart: .now, text: "Great week.", stats: stats)
        insertingContext.insert(recap)
        try insertingContext.save()

        let recapID = recap.id
        let readingContext = ModelContext(container)
        let fetched = try #require(
            try readingContext.fetch(FetchDescriptor<Recap>(predicate: #Predicate { $0.id == recapID })).first
        )
        #expect(fetched.stats == stats)
        #expect(fetched.text == "Great week.")
    }

    // MARK: - Nudge (jsonb `arm` round-trip)

    @Test func nudgeArmSurvivesAModelContainerRoundTrip() throws {
        let container = try makeContainer()
        let insertingContext = ModelContext(container)

        let arm = NudgeArm(tone: .hype, timingSlot: .preGymWindow, format: .widgetCopy)
        let nudge = Nudge(userID: UUID(), arm: arm, delivered: true, actedWithin3h: false)
        insertingContext.insert(nudge)
        try insertingContext.save()

        let nudgeID = nudge.id
        let readingContext = ModelContext(container)
        let fetched = try #require(
            try readingContext.fetch(FetchDescriptor<Nudge>(predicate: #Predicate { $0.id == nudgeID })).first
        )
        #expect(fetched.arm == arm)
        #expect(fetched.delivered)
        #expect(fetched.actedWithin3h == false)
    }

    // MARK: - RiskScore / Subscription

    @Test func riskScoreAndSubscriptionPersistOptionalFieldsAsNilUntilSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let userID = UUID()
        let riskScore = RiskScore(userID: userID, date: .now)
        let subscription = Subscription(userID: userID)
        context.insert(riskScore)
        context.insert(subscription)
        try context.save()

        #expect(riskScore.pMiss == nil)
        #expect(riskScore.modelVersion == nil)
        #expect(subscription.status == nil)
        #expect(subscription.renewsAt == nil)

        riskScore.pMiss = 0.42
        riskScore.modelVersion = "logreg-coldstart-1"
        subscription.status = "active"
        subscription.product = "pro_annual"
        try context.save()

        #expect(riskScore.pMiss == 0.42)
        #expect(subscription.status == "active")
    }

    // MARK: - JSONValue: direct Codable/Hashable correctness (independent of GoalEvent/SwiftData)

    @Test func jsonValueRoundTripsEveryCaseThroughStandardJSONCodersDirectly() throws {
        // Exercises `JSONValue`'s own `Codable` conformance in isolation — every case, including a
        // nested object-inside-array-inside-object shape — rather than only ever going through
        // `GoalEvent.meta`'s `metaData` indirection like the tests above do.
        let value: JSONValue = .object([
            "name": .string("chicken"),
            "grams": .number(180.5),
            "confirmed": .bool(true),
            "tags": .array([.string("protein"), .number(2), .null]),
            "nested": .object(["deeper": .array([.object(["leaf": .bool(false)])])])
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func jsonValueEqualityDoesNotConflateANumberWithAStringOfTheSameDigits() {
        // A naive Hashable/Equatable derivation over associated values would still get this right
        // (different enum cases are never equal), but this pins down that guarantee explicitly since
        // `meta`'s round-trip tests above rely on it to catch a real corruption, not just a case-tag
        // mismatch.
        let asNumber: JSONValue = .number(1)
        let asString: JSONValue = .string("1")
        #expect(asNumber != asString)
        #expect(asNumber.hashValue != asString.hashValue || asNumber != asString)
    }

    // MARK: - GoalType / VerificationTier: catalog integrity (docs/spec.md §3)

    @Test func goalTypeRawValuesMatchTheSnakeCaseCatalogFromSpecSection3() {
        // Pins the exact wire values §13/§9 ML systems and the remote `goals.type` column depend on
        // — a renamed Swift case is silent and compiles fine, but would desync every already-synced
        // remote row from what this client sends next.
        #expect(GoalType.workoutGym.rawValue == "workout_gym")
        #expect(GoalType.workoutHomeOutdoor.rawValue == "workout_home_outdoor")
        #expect(GoalType.focusSession.rawValue == "focus_session")
        #expect(GoalType.protein.rawValue == "protein")
        #expect(GoalType.water.rawValue == "water")
        #expect(GoalType.steps.rawValue == "steps")
        #expect(GoalType.creatine.rawValue == "creatine")
        #expect(GoalType.sunriseAlarm.rawValue == "sunrise_alarm")
        #expect(GoalType.sleepOnTime.rawValue == "sleep_on_time")
        #expect(GoalType.reading.rawValue == "reading")
        #expect(GoalType.mealPrep.rawValue == "meal_prep")
        #expect(GoalType.stretchMobility.rawValue == "stretch_mobility")
        #expect(GoalType.coldShowerSauna.rawValue == "cold_shower_sauna")
        #expect(GoalType.custom.rawValue == "custom")
        // Catches an added/removed case going unnoticed by the explicit checks above.
        #expect(GoalType.allCases.count == 14)
    }

    @Test func verificationTierRawValuesAreUppercaseSingleLettersMatchingTheCheckConstraint() {
        #expect(VerificationTier.a.rawValue == "A")
        #expect(VerificationTier.b.rawValue == "B")
        #expect(VerificationTier.c.rawValue == "C")
        #expect(VerificationTier.allCases.count == 3)
    }

    // MARK: - Goal: construction defaults

    @Test func goalDefaultsActiveAndAdaptiveToTrueWithNoOptionalFieldsSet() {
        let goal = Goal(type: .custom, title: "Read 20 min", verificationTier: .c)
        #expect(goal.active)
        #expect(goal.adaptive)
        #expect(goal.targetValue == nil)
        #expect(goal.unit == nil)
        #expect(goal.cadence == nil)
        #expect(goal.user == nil)
        #expect(goal.dailyPlans.isEmpty)
        #expect(goal.events.isEmpty)
    }

    // MARK: - User ↔ Goal ↔ GoalEvent: multi-child fan-out

    @Test func userWithMultipleGoalsFansEventsOutToTheCorrectOwningGoalOnly() throws {
        // The single-goal graph test above proves the wiring works once; this proves `Goal.events`
        // actually partitions by goal rather than every event landing on whichever goal happened to
        // be inserted first (a bug a single-goal fixture could never catch).
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User()
        let goalA = Goal(type: .protein, title: "Protein", verificationTier: .b, user: user)
        let goalB = Goal(type: .steps, title: "Steps", verificationTier: .a, user: user)
        let eventA1 = GoalEvent(kind: .log, source: .nfc, user: user, goal: goalA)
        let eventA2 = GoalEvent(kind: .complete, source: .manual, user: user, goal: goalA)
        let eventB1 = GoalEvent(kind: .complete, source: .healthKit, user: user, goal: goalB)

        // Inserted individually (rather than via a `[any PersistentModel]` existential array) to
        // match the same call shape `ModelContext.insert<T: PersistentModel>(_:)` is used with
        // everywhere else in this file — implicit-existential-opening through a generic parameter
        // is not something worth relying on here with no compiler available to confirm it.
        context.insert(user)
        context.insert(goalA)
        context.insert(goalB)
        context.insert(eventA1)
        context.insert(eventA2)
        context.insert(eventB1)
        try context.save()

        #expect(Set(user.goals.map(\.id)) == Set([goalA.id, goalB.id]))
        #expect(user.goalEvents.count == 3)
        #expect(Set(goalA.events.map(\.id)) == Set([eventA1.id, eventA2.id]))
        #expect(goalB.events.map(\.id) == [eventB1.id])
    }

    // MARK: - GoalEvent: construction defaults

    @Test func goalEventValueAndVerifiedDefaultToNilAndFalse() {
        let event = GoalEvent(kind: .log, source: .manual)
        #expect(event.value == nil)
        #expect(event.verified == false)
    }

    // MARK: - LockSet / LockSession: loose-FK independence (see LockSession's own doc comment)

    @Test func deletingALockSetLeavesLockSessionsThatReferenceItIntactWithTheirStaleID() throws {
        // `LockSession.lockSetID` is deliberately a plain `UUID`, not a `@Relationship` — per its
        // doc comment, that's specifically because Postgres's `on delete set null` for
        // `lock_sessions.lock_set_id` "doesn't map onto 1:1" with SwiftData delete rules. This pins
        // down what that tradeoff actually means locally: deleting the `LockSet` does NOT cascade
        // (there's no relationship to cascade through) and does NOT null out the now-dangling id —
        // the session just keeps pointing at an id that no longer resolves to anything. Any code
        // that resolves `lockSetID` to a `LockSet` must handle a miss; this test is what pins that
        // requirement down for future readers rather than assuming Postgres's semantics apply here.
        let container = try makeContainer()
        let context = ModelContext(container)

        let lockSet = LockSet(userID: UUID(), name: "Distractions")
        let session = LockSession(userID: UUID(), lockSetID: lockSet.id, mode: .full)
        context.insert(lockSet)
        context.insert(session)
        try context.save()

        let lockSetID = lockSet.id
        let sessionID = session.id

        context.delete(lockSet)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<LockSet>(predicate: #Predicate { $0.id == lockSetID })).isEmpty)
        let survivingSession = try #require(
            try context.fetch(FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        #expect(survivingSession.lockSetID == lockSetID)
    }

    // MARK: - Gym: container round trip

    @Test func gymPersistsAllFieldsThroughAModelContainerRoundTrip() throws {
        let container = try makeContainer()
        let insertingContext = ModelContext(container)

        let userID = UUID()
        let gym = Gym(
            userID: userID,
            lat: 40.7484,
            lng: -73.9857,
            radiusMeters: 100,
            name: "Equinox Downtown",
            autoDetected: true,
            confirmed: true
        )
        insertingContext.insert(gym)
        try insertingContext.save()

        let gymID = gym.id
        let readingContext = ModelContext(container)
        let fetched = try #require(
            try readingContext.fetch(FetchDescriptor<Gym>(predicate: #Predicate { $0.id == gymID })).first
        )
        #expect(fetched.userID == userID)
        #expect(fetched.lat == 40.7484)
        #expect(fetched.lng == -73.9857)
        #expect(fetched.radiusMeters == 100)
        #expect(fetched.name == "Equinox Downtown")
        #expect(fetched.autoDetected)
        #expect(fetched.confirmed)
    }

    // MARK: - Squad: multiple members, distinct roles

    @Test func squadSupportsMultipleMembersEachWithTheirOwnRole() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let squad = Squad(name: "Leg Day Crew", createdBy: UUID(), inviteCode: "LEGDAY2")
        let owner = SquadMember(squadID: squad.id, userID: squad.createdBy, role: .owner)
        let member = SquadMember(squadID: squad.id, userID: UUID(), role: .member)

        context.insert(squad)
        context.insert(owner)
        context.insert(member)
        try context.save()

        let squadID = squad.id
        let fetchedMembers = try context.fetch(
            FetchDescriptor<SquadMember>(predicate: #Predicate { $0.squadID == squadID })
        )
        #expect(fetchedMembers.count == 2)
        // Compared by `rawValue` rather than putting `SquadRole` itself in a `Set` — `SquadRole`
        // only declares `Codable, Sendable` (not `Hashable`) in its own definition, and whether a
        // raw-value enum without an explicit `Hashable` conformance is usable in a `Set` isn't
        // something this environment can compile-check (no Swift toolchain here — see
        // knownIssues), so this sticks to the part of the assertion that's unambiguous either way.
        #expect(fetchedMembers.map(\.role.rawValue).sorted() == ["member", "owner"])
    }

    @Test func squadInviteCodeUniqueAttributeUpsertsACollidingCode() throws {
        // `Squad.inviteCode` is `@Attribute(.unique)`, mirroring the remote `unique not null`
        // constraint. Verified on a real toolchain (CI): SwiftData upserts rather than throws, so a
        // colliding code REPLACES the first squad locally instead of failing. Collisions are
        // astronomically unlikely (32^7 codes) and the backend's Postgres `unique` constraint is the
        // real guard (ReferralBackend.register); this test pins the actual local behavior.
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(Squad(name: "Crew One", createdBy: UUID(), inviteCode: "DUPE001"))
        try context.save()

        context.insert(Squad(name: "Crew Two", createdBy: UUID(), inviteCode: "DUPE001"))
        try context.save()

        let squads = try context.fetch(FetchDescriptor<Squad>())
        #expect(squads.count == 1)
        #expect(squads.first?.name == "Crew Two")
    }

    // MARK: - RecapStats / NudgeArm: Codable shape independent of SwiftData

    @Test func recapStatsRoundTripsThroughJSONEncoderIndependentlyOfSwiftData() throws {
        // Confirms `RecapStats`'s `Codable` conformance holds on its own — including its optional
        // `bestDay`/`rankMovement` fields staying nil — separately from the container-round-trip
        // test above, which only proves it survives *through* SwiftData's own persistence.
        let stats = RecapStats(goalCompletionRings: ["water": 0.5], timeReclaimedMinutes: 30, streak: 3)
        #expect(stats.bestDay == nil)
        #expect(stats.rankMovement == nil)

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(RecapStats.self, from: data)
        #expect(decoded == stats)
    }

    @Test func nudgeArmRoundTripsThroughJSONEncoderIndependentlyOfSwiftData() throws {
        let arm = NudgeArm(tone: .chill, timingSlot: .afternoon4pm, format: .shieldCopy)
        let data = try JSONEncoder().encode(arm)
        let decoded = try JSONDecoder().decode(NudgeArm.self, from: data)
        #expect(decoded == arm)
    }
}
