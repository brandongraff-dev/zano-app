// Core/Tests/CoreTests/SocialTests.swift
//
// Owns test coverage for `Core/Sources/Core/Social/{NudgeSender,DuelManager,ReferralManager}.swift`
// per docs/spec.md:
//   - §8 Retention Psychology Rules, rule 7: "Nudge scarcity. Max 2 proactive pushes/day. A nudge
//     must change what the user does tonight or it doesn't send." — this is a hard product rule,
//     not a nice-to-have, so `NudgeSenderTests` below leads with it and covers it from several
//     angles (exact boundary, suppression past the boundary, the closure never firing when
//     suppressed, the per-calendar-day reset, and the constant itself).
//   - §9.3 Nudge Optimizer: "Reward: goal completed within 3 hours of nudge... Respect the 2/day
//     cap." — `NudgeSenderTests` also covers `closeExpiredAttributionWindows`'s scoring/idempotency.
//   - §5.7 Squads & Duels (the Duel half): "7-day head-to-head, points per verified goal" —
//     `DuelManagerTests` covers `recomputeLocalPoints`/`applyVerifiedGoalEvent`'s point tally,
//     including that only `.complete`/`.planB` *verified* `GoalEvent`s inside the duel's date
//     window ever score (CLAUDE.md's additive-goals rule: a duel point is only ever a real,
//     verified completion, never anything restrictive), plus the create/respond/refresh lifecycle.
//   - §4 v2 Feature Spec: "Referral: invite a friend → both get a streak freeze" — `ReferralManagerTests`
//     covers that `redeem(code:)` round-trips both sides' grant flags and credits *this* device's
//     own `Streak.freezesLeft` locally, per `ReferralManager`'s own header comment on why the
//     referrer's half is necessarily a server-side concern this device can only report on.
//
// Conventions followed (see each source file's header comment for the fuller reasoning this
// mirrors): actor-owned/`@MainActor`-owned `ModelContext`s, `Sendable` snapshot structs, and the
// `internal` (not `private`) `init(modelContainer:...)` seam every one of these types exposes
// specifically so `CoreTests` can construct an isolated instance against an in-memory
// `ModelContainer` instead of the real `.appGroup` singleton.
//
// Every fixture here builds its own fresh, isolated, in-memory `ModelContainer` (via
// `ModelContainer.makeAppGroupContainer(inMemory: true)` — the exact same schema
// `ModelContainer.appGroup` uses, just never touching disk or a real App Group) so tests never
// share state with each other or with `.shared` singletons.
//
// knownIssues (flagged here rather than silently "fixed" by guessing at intent, since there is no
// Mac/compiler in this environment to confirm any of the below against a real build):
//   - `DuelManager.recomputeLocalPoints(duelID:)` degrades to a silent no-op (unchanged snapshot)
//     when there is no local `User` row at all, rather than throwing `DuelManagerError
//     .noSignedInUser` the way `NudgeSender.send`/`ReferralManager.myReferralCode` throw their own
//     `.noSignedInUser` case for the same precondition (`fetchCurrentUser()` does throw here too —
//     the only call site just swallows it with `try?`). `recomputeLocalPointsIsANoOpWhenThereIsNoLocalUserAtAll`
//     below asserts the *current* behavior rather than the arguably-more-consistent alternative;
//     worth a follow-up to align the three managers' behavior deliberately rather than by omission.
//   - `ReferralManager.myReferralCode()`'s best-effort backend registration runs on an unstructured
//     `Task` (`registerWithBackendBestEffort`), so it cannot be asserted deterministically from a
//     synchronous test without an arbitrary delay/poll. Deliberately not tested here to avoid a
//     flaky test; `redeem(code:)`'s backend call, by contrast, is awaited inline and *is* fully
//     covered.
//   - None of this file has been run through a Swift compiler (no Mac available in this
//     environment — see CLAUDE.md's "Current environment status"). Every API name, signature, and
//     access-control/isolation attribute referenced below was cross-checked directly against the
//     current source of `NudgeSender.swift`/`DuelManager.swift`/`ReferralManager.swift`/their
//     `Models` and against `SquadManager.swift`'s identical conventions, but the usual "first CI
//     run on a Mac" pass (`swift test --package-path Core`) still needs to happen before this is
//     trusted the way spec's `Scaffolded — Unverified` status implies.

import Testing
import SwiftData
import Foundation
@testable import Core

// MARK: - Shared test fixtures

/// A fresh, private, in-memory store using the exact same schema `ModelContainer.appGroup` does
/// (`ModelContainer.appGroupModelTypes`), so relationships (e.g. `GoalEvent.user`) resolve exactly
/// like the real App Group store without ever touching disk or a real App Group container (this
/// sandboxed test process has neither).
private func makeTestContainer() throws -> ModelContainer {
    try ModelContainer.makeAppGroupContainer(inMemory: true)
}

/// Inserts a single local `User` row and returns its id. Every manager under test here documents
/// "this device's local store holds exactly one `User` row" as its `fetchCurrentUser()` precondition
/// (see `Models/User.swift`'s doc comment) — this fixture is how tests set that up deliberately,
/// one call per test, never more than one per container.
@discardableResult
private func insertUser(in container: ModelContainer, id: UUID = UUID()) throws -> UUID {
    let context = ModelContext(container)
    context.insert(User(id: id))
    try context.save()
    return id
}

/// Inserts a `GoalEvent` attributed to `userID`, for exercising point-tally / attribution logic
/// directly — without going through the full Verification/Intents pipeline that would normally
/// produce one (out of scope for this file; those modules are owned elsewhere and, per this run's
/// forbidden-paths list, off-limits to touch).
private func insertGoalEvent(
    in container: ModelContainer,
    userID: UUID,
    kind: GoalEventKind,
    ts: Date,
    verified: Bool = true,
    source: GoalEventSource = .manual
) throws {
    let context = ModelContext(container)
    var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userID })
    descriptor.fetchLimit = 1
    guard let user = try context.fetch(descriptor).first else {
        Issue.record("test setup: no local User row with id \(userID) to attach a GoalEvent to")
        return
    }
    let event = GoalEvent(ts: ts, kind: kind, source: source, verified: verified, user: user)
    context.insert(event)
    try context.save()
}

/// Reads back one `Nudge`'s `actedWithin3h` directly. `NudgeSender`'s public API only ever returns
/// a `NudgeSendOutcome` (id + delivered), never the raw row, so attribution scoring — the one part
/// of a `Nudge` this file doesn't otherwise observe — can only be checked this way.
private func fetchActedWithin3h(in container: ModelContainer, nudgeID: UUID) throws -> Bool? {
    let context = ModelContext(container)
    var descriptor = FetchDescriptor<Nudge>(predicate: #Predicate { $0.id == nudgeID })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.actedWithin3h
}

/// Reads back a user's `Streak.freezesLeft` directly — the one observable, durable effect of a
/// granted streak freeze (`ReferralManager` exposes no getter for it itself; `StreakEngine`, which
/// would, is out of scope/forbidden for this run).
private func fetchFreezesLeft(in container: ModelContainer, userID: UUID) throws -> Int? {
    let context = ModelContext(container)
    var descriptor = FetchDescriptor<Streak>(predicate: #Predicate { $0.userID == userID })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.freezesLeft
}

/// Reads back a user's `referredBy` directly, to confirm `redeem(code:)` actually recorded who
/// referred them, not just that it returned a result.
private func fetchReferredBy(in container: ModelContainer, userID: UUID) throws -> UUID? {
    let context = ModelContext(container)
    var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userID })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.referredBy
}

/// A minimal, deterministic nudge arm for tests that don't care which tone/slot/format was picked
/// — only whether the cap/attribution logic around it behaved correctly.
private func sampleArm(_ tone: NudgeTone = .hype) -> NudgeArm {
    NudgeArm(tone: tone, timingSlot: .evening, format: .push)
}

// MARK: - NudgeSenderTests — spec §8 rule 7 (2/day cap) and §9.3 (attribution)

@Suite("NudgeSender — 2/day cap (spec §8 rule 7) and attribution (§9.3)")
@MainActor
struct NudgeSenderTests {

    /// Builds a `NudgeSender` against a fresh in-memory container with exactly one local user —
    /// every test's starting point unless it's specifically testing the no-signed-in-user path.
    private func makeSender() throws -> (sender: NudgeSender, container: ModelContainer, userID: UUID) {
        let container = try makeTestContainer()
        let userID = try insertUser(in: container)
        return (NudgeSender(modelContainer: container), container, userID)
    }

    // MARK: The hard rule (§8 rule 7)

    @Test("delivers the first two nudges of a day, suppresses the third")
    func dailyCapAllowsExactlyTwoDeliveriesThenSuppresses() async throws {
        let (sender, _, _) = try makeSender()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try await sender.send(arm: sampleArm(.hype), on: day)
        let second = try await sender.send(arm: sampleArm(.toughLove), on: day.addingTimeInterval(60))
        let third = try await sender.send(arm: sampleArm(.chill), on: day.addingTimeInterval(120))

        #expect(first.delivered)
        #expect(second.delivered)
        #expect(
            !third.delivered,
            "spec §8 rule 7: \"Max 2 proactive pushes/day\" — a 3rd nudge the same calendar day " +
            "must be suppressed, not delivered"
        )
        // Every attempt still writes a distinct row — spec §9.3's bandit needs to see suppressed
        // attempts, not just delivered ones (see NudgeSendOutcome's doc comment).
        #expect(Set([first.nudgeID, second.nudgeID, third.nudgeID]).count == 3)
    }

    @Test("suppresses every nudge past the 2nd, no matter how many are attempted in one day")
    func capHoldsRegardlessOfAttemptCount() async throws {
        let (sender, _, _) = try makeSender()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        var delivered: [Bool] = []
        for i in 0..<5 {
            let outcome = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(TimeInterval(i) * 60))
            delivered.append(outcome.delivered)
        }

        #expect(delivered == [true, true, false, false, false])
    }

    @Test("a suppressed nudge never invokes deliver, but a delivered one always does")
    func suppressedNudgeNeverInvokesDeliverButStillPersists() async throws {
        let (sender, _, _) = try makeSender()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        var deliverInvocations = 0

        _ = try await sender.send(arm: sampleArm(), on: day, deliver: { _ in deliverInvocations += 1 })
        _ = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(60), deliver: { _ in deliverInvocations += 1 })
        let third = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(120), deliver: { _ in deliverInvocations += 1 })

        #expect(deliverInvocations == 2, "deliver must run exactly once per actually-delivered nudge, never for a suppressed one")
        #expect(!third.delivered)
    }

    @Test("remainingToday counts down from dailyCap as nudges are delivered")
    func remainingTodayCountsDownFromTheCap() async throws {
        let (sender, _, _) = try makeSender()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(await sender.remainingToday(on: day) == NudgeSender.dailyCap)
        _ = try await sender.send(arm: sampleArm(), on: day)
        #expect(await sender.remainingToday(on: day) == NudgeSender.dailyCap - 1)
        _ = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(60))
        #expect(await sender.remainingToday(on: day) == 0)
    }

    @Test("the cap is per local calendar day, not a rolling 24h window")
    func dailyCapResetsOnANewCalendarDay() async throws {
        let (sender, _, _) = try makeSender()
        let calendar = Calendar.current
        let day1 = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = try #require(calendar.date(byAdding: .day, value: 1, to: day1))

        _ = try await sender.send(arm: sampleArm(), on: day1)
        _ = try await sender.send(arm: sampleArm(), on: day1.addingTimeInterval(3600))
        let stillCappedSameDay = try await sender.send(arm: sampleArm(), on: day1.addingTimeInterval(7200))
        #expect(!stillCappedSameDay.delivered)

        let nextDayOutcome = try await sender.send(arm: sampleArm(), on: day2)
        #expect(
            nextDayOutcome.delivered,
            "the 2/day cap is evaluated per local calendar day, so a nudge on the following day " +
            "must not be suppressed by yesterday's count"
        )
    }

    @Test("dailyCap is exactly 2 — spec §8 rule 7 is a hard product rule, not a tunable")
    func dailyCapConstantMatchesSpecRule() {
        #expect(NudgeSender.dailyCap == 2)
    }

    // MARK: Preconditions

    @Test("send throws noSignedInUser when there is no local User row")
    func sendThrowsWithNoSignedInUser() async throws {
        let container = try makeTestContainer()
        let sender = NudgeSender(modelContainer: container)

        do {
            _ = try await sender.send(arm: sampleArm())
            Issue.record("expected NudgeSenderError.noSignedInUser to be thrown")
        } catch let error as NudgeSenderError {
            #expect(error == .noSignedInUser)
        }
    }

    @Test("remainingToday degrades to 0, not a crash, with no signed-in user")
    func remainingTodayIsZeroWithNoUser() async throws {
        let container = try makeTestContainer()
        let sender = NudgeSender(modelContainer: container)

        #expect(await sender.remainingToday() == 0)
    }

    // MARK: Attribution (§9.3's bandit reward signal)

    @Test("closeExpiredAttributionWindows scores true/false correctly and is idempotent")
    func attributionWindowScoresActedTrueOrFalseAndIsIdempotent() async throws {
        let (sender, container, userID) = try makeSender()
        let nudgeTime = Date(timeIntervalSince1970: 1_700_000_000)

        let acted = try await sender.send(arm: sampleArm(.hype), on: nudgeTime)
        #expect(acted.delivered)
        let notActed = try await sender.send(arm: sampleArm(.chill), on: nudgeTime.addingTimeInterval(6 * 3600))
        #expect(notActed.delivered)

        // Inside `acted`'s 3h window (1h after it) — should score true.
        try insertGoalEvent(in: container, userID: userID, kind: .complete, ts: nudgeTime.addingTimeInterval(3600))
        // Well outside `notActed`'s 3h window (its nudge fired 6h in; this is 10h in) — should
        // score false for `notActed`, and must not retroactively "count" for `acted` either.
        try insertGoalEvent(in: container, userID: userID, kind: .complete, ts: nudgeTime.addingTimeInterval(10 * 3600))

        let closeAt = nudgeTime.addingTimeInterval(6 * 3600 + NudgeSender.attributionWindow + 1)
        let scoredCount = try await sender.closeExpiredAttributionWindows(asOf: closeAt)
        #expect(scoredCount == 2)

        #expect(try fetchActedWithin3h(in: container, nudgeID: acted.nudgeID) == true)
        #expect(try fetchActedWithin3h(in: container, nudgeID: notActed.nudgeID) == false)

        // Idempotent: a second pass over the same "now" rescoring already-closed windows does
        // nothing (this is what makes it safe to call from a periodic background task).
        let rescored = try await sender.closeExpiredAttributionWindows(asOf: closeAt)
        #expect(rescored == 0)
    }

    @Test("closeExpiredAttributionWindows leaves a still-open window untouched")
    func attributionLeavesUnexpiredWindowsAlone() async throws {
        let (sender, container, _) = try makeSender()
        let nudgeTime = Date(timeIntervalSince1970: 1_700_000_000)
        let outcome = try await sender.send(arm: sampleArm(), on: nudgeTime)

        let tooSoon = nudgeTime.addingTimeInterval(NudgeSender.attributionWindow - 1)
        let scored = try await sender.closeExpiredAttributionWindows(asOf: tooSoon)

        #expect(scored == 0)
        #expect(try fetchActedWithin3h(in: container, nudgeID: outcome.nudgeID) == nil)
    }

    @Test("a suppressed (never-delivered) nudge is never picked up for attribution scoring")
    func suppressedNudgesAreNeverScored() async throws {
        let (sender, container, _) = try makeSender()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await sender.send(arm: sampleArm(), on: day)
        _ = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(60))
        let suppressed = try await sender.send(arm: sampleArm(), on: day.addingTimeInterval(120))
        #expect(!suppressed.delivered)

        let scored = try await sender.closeExpiredAttributionWindows(
            asOf: day.addingTimeInterval(NudgeSender.attributionWindow + 1000)
        )

        // Only the 2 delivered nudges are eligible; the suppressed one's `delivered == false`
        // excludes it from `closeExpiredAttributionWindows`'s own predicate.
        #expect(scored == 2)
        #expect(try fetchActedWithin3h(in: container, nudgeID: suppressed.nudgeID) == nil)
    }
}

// MARK: - DuelManagerTests — spec §5.7 (points per verified goal)

@Suite("DuelManager — 7-day lifecycle and point tally per verified goal (spec §5.7)")
struct DuelManagerTests {

    // MARK: Create / respond lifecycle

    @Test("createDuel starts pending with zero points on both sides")
    func createDuelStartsPendingWithZeroPoints() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)

        let snapshot = try await manager.createDuel(challengerID: a, opponentID: b)

        #expect(snapshot.status == .pending)
        #expect(snapshot.aPoints == 0)
        #expect(snapshot.bPoints == 0)
        #expect(snapshot.aUser == a)
        #expect(snapshot.bUser == b)
        #expect(snapshot.winner == nil)

        let calendar = Calendar.current
        let expectedStart = calendar.startOfDay(for: snapshot.startDate)
        let expectedEnd = try #require(calendar.date(byAdding: .day, value: DuelManager.durationDays, to: expectedStart))
        #expect(snapshot.endDate == expectedEnd, "spec §5.7: \"7-day head-to-head\"")
    }

    @Test("createDuel rejects dueling yourself")
    func createDuelRejectsDuelingYourself() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let manager = DuelManager(modelContainer: container)

        do {
            _ = try await manager.createDuel(challengerID: a, opponentID: a)
            Issue.record("expected DuelManagerError.cannotDuelSelf")
        } catch let error as DuelManagerError {
            guard case .cannotDuelSelf = error else {
                Issue.record("expected cannotDuelSelf, got \(error)")
                return
            }
        }
    }

    @Test("respond(accept: true) transitions a pending duel to active")
    func respondAcceptTransitionsToActive() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(challengerID: a, opponentID: b)

        let updated = try await manager.respond(duelID: duel.id, userID: b, accept: true)
        #expect(updated.status == .active)
    }

    @Test("respond(accept: false) transitions a pending duel to declined")
    func respondDeclineSetsStatusDeclined() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(challengerID: a, opponentID: b)

        let updated = try await manager.respond(duelID: duel.id, userID: b, accept: false)
        #expect(updated.status == .declined)
    }

    @Test("respond rejects a caller who isn't one of the two participants")
    func respondRejectsANonParticipant() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let stranger = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(challengerID: a, opponentID: b)

        do {
            _ = try await manager.respond(duelID: duel.id, userID: stranger, accept: true)
            Issue.record("expected DuelManagerError.notAParticipant")
        } catch let error as DuelManagerError {
            guard case .notAParticipant(let duelID, let userID) = error else {
                Issue.record("expected notAParticipant, got \(error)")
                return
            }
            #expect(duelID == duel.id)
            #expect(userID == stranger)
        }
    }

    @Test("respond rejects a duel that isn't currently pending")
    func respondRejectsATransitionFromANonPendingStatus() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(challengerID: a, opponentID: b)
        _ = try await manager.respond(duelID: duel.id, userID: a, accept: true)

        do {
            _ = try await manager.respond(duelID: duel.id, userID: b, accept: true)
            Issue.record("expected DuelManagerError.invalidStatusTransition")
        } catch let error as DuelManagerError {
            guard case .invalidStatusTransition(let from, let to) = error else {
                Issue.record("expected invalidStatusTransition, got \(error)")
                return
            }
            #expect(from == .active)
            #expect(to == .active)
        }
    }

    @Test("operations on an unknown duel id throw duelNotFound")
    func operationsOnAnUnknownDuelIDThrowDuelNotFound() async throws {
        let container = try makeTestContainer()
        let manager = DuelManager(modelContainer: container)
        let bogusID = UUID()

        do {
            _ = try await manager.respond(duelID: bogusID, userID: UUID(), accept: true)
            Issue.record("expected DuelManagerError.duelNotFound")
        } catch let error as DuelManagerError {
            guard case .duelNotFound(let id) = error else {
                Issue.record("expected duelNotFound, got \(error)")
                return
            }
            #expect(id == bogusID)
        }
    }

    // MARK: Point tally — "points per verified goal" (the core of this suite)

    @Test("recomputeLocalPoints counts exactly one point per verified .complete/.planB event in the duel window")
    func recomputeLocalPointsCountsOneVerifiedCompleteOrPlanBGoalPerEvent() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID() // opponent: remote-only, never has a local User row (local-first design)
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(
            challengerID: a,
            opponentID: b,
            startDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await manager.respond(duelID: duel.id, userID: b, accept: true)
        let start = duel.startDate

        // The two genuine scoring events.
        try insertGoalEvent(in: container, userID: a, kind: .complete, ts: start.addingTimeInterval(3600))
        try insertGoalEvent(in: container, userID: a, kind: .planB, ts: start.addingTimeInterval(7200))
        // Must NOT score: same kind but unverified.
        try insertGoalEvent(in: container, userID: a, kind: .complete, ts: start.addingTimeInterval(10800), verified: false)
        // Must NOT score: before the duel's window even opened.
        try insertGoalEvent(in: container, userID: a, kind: .complete, ts: start.addingTimeInterval(-3600))

        let updated = try await manager.recomputeLocalPoints(duelID: duel.id)

        #expect(
            updated.aPoints == 2,
            "only verified .complete/.planB events inside [startDate, now] score — CLAUDE.md's " +
            "additive-goals rule means a duel point is only ever a real, verified completion"
        )
        #expect(updated.bPoints == 0, "this device can only ever compute its own signed-in user's side locally")
    }

    @Test(
        "non-scoring GoalEvent kinds never add a duel point, even when verified and in-window",
        arguments: [GoalEventKind.log, .verify, .miss, .freeze]
    )
    func nonScoringGoalEventKindsNeverAddADuelPoint(kind: GoalEventKind) async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(
            challengerID: a,
            opponentID: b,
            startDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await manager.respond(duelID: duel.id, userID: b, accept: true)

        try insertGoalEvent(in: container, userID: a, kind: kind, ts: duel.startDate.addingTimeInterval(3600))

        let result = try await manager.recomputeLocalPoints(duelID: duel.id)
        #expect(result.aPoints == 0)
    }

    @Test("recomputeLocalPoints is a no-op before the duel has been accepted")
    func recomputeLocalPointsIsANoOpBeforeTheDuelIsAccepted() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let duel = try await manager.createDuel(
            challengerID: a,
            opponentID: b,
            startDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try insertGoalEvent(in: container, userID: a, kind: .complete, ts: duel.startDate.addingTimeInterval(3600))

        let result = try await manager.recomputeLocalPoints(duelID: duel.id)

        #expect(result.status == .pending)
        #expect(result.aPoints == 0)
    }

    @Test("recomputeLocalPoints is a no-op when the signed-in user isn't a participant")
    func recomputeLocalPointsIsANoOpWhenTheSignedInUserIsntAParticipant() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container) // a local user, unrelated to the duel below
        let manager = DuelManager(modelContainer: container)

        let strangerA = UUID()
        let strangerB = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(container)
        let duel = Duel(
            aUser: strangerA,
            bUser: strangerB,
            startDate: start,
            endDate: start.addingTimeInterval(7 * 86_400),
            status: .active
        )
        context.insert(duel)
        try context.save()
        let duelID = duel.id

        let result = try await manager.recomputeLocalPoints(duelID: duelID)

        #expect(result.aPoints == 0)
        #expect(result.bPoints == 0)
    }

    @Test("recomputeLocalPoints is a (documented, current-behavior) silent no-op with no local user at all")
    func recomputeLocalPointsIsANoOpWhenThereIsNoLocalUserAtAll() async throws {
        // See this file's header knownIssues note: fetchCurrentUser() does throw
        // .noSignedInUser internally, but recomputeLocalPoints swallows it with `try?` rather than
        // propagating it — unlike NudgeSender.send/ReferralManager.myReferralCode, which surface
        // the same precondition as a thrown error. This test documents that as it exists today.
        let container = try makeTestContainer()
        let manager = DuelManager(modelContainer: container)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(container)
        let duel = Duel(
            aUser: UUID(),
            bUser: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(7 * 86_400),
            status: .active
        )
        context.insert(duel)
        try context.save()
        let duelID = duel.id

        let result = try await manager.recomputeLocalPoints(duelID: duelID)

        #expect(result.aPoints == 0)
        #expect(result.bPoints == 0)
    }

    // MARK: Live-increment hook

    @Test("applyVerifiedGoalEvent increments the correct side of every applicable active duel")
    func applyVerifiedGoalEventIncrementsTheCorrectSideOfEveryApplicableActiveDuel() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let c = UUID()
        let manager = DuelManager(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let duel1 = try await manager.createDuel(challengerID: a, opponentID: b, startDate: start) // a is aUser
        _ = try await manager.respond(duelID: duel1.id, userID: b, accept: true)
        let duel2 = try await manager.createDuel(challengerID: c, opponentID: a, startDate: start) // a is bUser
        _ = try await manager.respond(duelID: duel2.id, userID: c, accept: true)

        await manager.applyVerifiedGoalEvent(userID: a, verifiedAt: start.addingTimeInterval(3600))

        let updated1 = try await manager.duel(id: duel1.id)
        let updated2 = try await manager.duel(id: duel2.id)
        #expect(updated1?.aPoints == 1)
        #expect(updated2?.bPoints == 1)
    }

    @Test("applyVerifiedGoalEvent ignores a date outside the duel's [startDate, endDate) window")
    func applyVerifiedGoalEventIgnoresDatesOutsideTheDuelWindow() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let duel = try await manager.createDuel(challengerID: a, opponentID: b, startDate: start)
        _ = try await manager.respond(duelID: duel.id, userID: b, accept: true)

        await manager.applyVerifiedGoalEvent(userID: a, verifiedAt: start.addingTimeInterval(-1))

        let after = try await manager.duel(id: duel.id)
        #expect(after?.aPoints == 0)
    }

    @Test("applyVerifiedGoalEvent is a no-op when the user has no active duels")
    func applyVerifiedGoalEventIsANoOpWithNoActiveDuels() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let manager = DuelManager(modelContainer: container)

        // Should not throw or crash even with zero duels on record.
        await manager.applyVerifiedGoalEvent(userID: a)

        let duels = try await manager.activeDuels(involving: a)
        #expect(duels.isEmpty)
    }

    // MARK: Lifecycle expiry

    @Test("refreshStatuses completes only expired active duels, leaving pending/future ones alone")
    func refreshStatusesCompletesExpiredActiveDuelsOnly() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let manager = DuelManager(modelContainer: container)
        let past = Date(timeIntervalSince1970: 1_700_000_000)

        let expiredDuel = try await manager.createDuel(challengerID: a, opponentID: b, startDate: past)
        _ = try await manager.respond(duelID: expiredDuel.id, userID: b, accept: true)

        let freshDuel = try await manager.createDuel(challengerID: a, opponentID: b, startDate: .now)
        _ = try await manager.respond(duelID: freshDuel.id, userID: b, accept: true)

        let pendingDuel = try await manager.createDuel(challengerID: a, opponentID: b, startDate: past)
        // left .pending — never responded to.

        let completed = try await manager.refreshStatuses(asOf: .now)

        #expect(completed.map(\.id).contains(expiredDuel.id))
        #expect(!completed.map(\.id).contains(freshDuel.id))
        #expect(!completed.map(\.id).contains(pendingDuel.id))

        let expiredAfter = try await manager.duel(id: expiredDuel.id)
        let pendingAfter = try await manager.duel(id: pendingDuel.id)
        #expect(expiredAfter?.status == .complete)
        #expect(
            pendingAfter?.status == .pending,
            "refreshStatuses only ever transitions .active duels; a still-pending invite must not silently become .complete"
        )
    }

    // MARK: Introspection

    @Test("activeDuels(involving:) returns only this user's currently-active duels")
    func activeDuelsFiltersByStatusAndParticipant() async throws {
        let container = try makeTestContainer()
        let a = try insertUser(in: container)
        let b = UUID()
        let c = UUID()
        let manager = DuelManager(modelContainer: container)

        let active = try await manager.createDuel(challengerID: a, opponentID: b)
        _ = try await manager.respond(duelID: active.id, userID: b, accept: true)

        let pending = try await manager.createDuel(challengerID: a, opponentID: c)
        // left pending

        let declined = try await manager.createDuel(challengerID: a, opponentID: b)
        _ = try await manager.respond(duelID: declined.id, userID: b, accept: false)

        let unrelated = try await manager.createDuel(challengerID: b, opponentID: c)

        let results = try await manager.activeDuels(involving: a)

        #expect(results.map(\.id) == [active.id])
        #expect(!results.map(\.id).contains(pending.id))
        #expect(!results.map(\.id).contains(declined.id))
        #expect(!results.map(\.id).contains(unrelated.id))
    }

    // MARK: DuelSnapshot.winner — pure logic, no I/O

    @Test("winner is nil until complete and nil on an exact tie, otherwise the higher side")
    func winnerIsNilUntilCompleteAndNilOnATie() {
        let a = UUID()
        let b = UUID()
        let now = Date()

        let stillActive = DuelSnapshot(id: UUID(), aUser: a, bUser: b, startDate: now, endDate: now, aPoints: 5, bPoints: 1, status: .active)
        #expect(stillActive.winner == nil)

        let tie = DuelSnapshot(id: UUID(), aUser: a, bUser: b, startDate: now, endDate: now, aPoints: 3, bPoints: 3, status: .complete)
        #expect(tie.winner == nil)

        let bWins = DuelSnapshot(id: UUID(), aUser: a, bUser: b, startDate: now, endDate: now, aPoints: 3, bPoints: 5, status: .complete)
        #expect(bWins.winner == b)

        let aWins = DuelSnapshot(id: UUID(), aUser: a, bUser: b, startDate: now, endDate: now, aPoints: 7, bPoints: 2, status: .complete)
        #expect(aWins.winner == a)
    }
}

// MARK: - ReferralManagerTests — spec §4 v2 (both sides get a streak freeze)

@Suite("ReferralManager — code redemption grants a streak freeze to both sides (spec §4 v2)")
@MainActor
struct ReferralManagerTests {

    /// A `ReferralBackend` test double. Configurable to hand back a fixed `ReferralRedemptionResult`
    /// (or nothing, to exercise `redeem`'s error path when the network/server hasn't answered with
    /// a usable result) and counts calls so tests can assert a rejected-before-the-network case
    /// really never reached the backend.
    private actor FakeReferralBackend: ReferralBackend {
        private(set) var registeredCodes: [String: UUID] = [:]
        private(set) var redeemCallCount = 0
        private let redemptionResult: ReferralRedemptionResult?

        init(redemptionResult: ReferralRedemptionResult? = nil) {
            self.redemptionResult = redemptionResult
        }

        func register(code: String, forUserID: UUID) async throws {
            registeredCodes[code] = forUserID
        }

        func redeem(code: String, refereeUserID: UUID) async throws -> ReferralRedemptionResult {
            redeemCallCount += 1
            guard let redemptionResult else {
                struct NoResultConfigured: Error {}
                throw NoResultConfigured()
            }
            return redemptionResult
        }
    }

    // MARK: Code generation

    @Test("myReferralCode generates a non-empty code and is idempotent across repeated calls")
    func myReferralCodeGeneratesAndPersistsAStableCode() throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let manager = ReferralManager(modelContainer: container)

        let first = try manager.myReferralCode()
        let second = try manager.myReferralCode()

        #expect(!first.isEmpty)
        #expect(first == second, "a user's referral code must be stable once generated, not regenerated on every call")
    }

    @Test("myReferralCode throws noSignedInUser with no local User row")
    func myReferralCodeThrowsWithNoSignedInUser() throws {
        let container = try makeTestContainer()
        let manager = ReferralManager(modelContainer: container)

        do {
            _ = try manager.myReferralCode()
            Issue.record("expected ReferralManagerError.noSignedInUser")
        } catch let error as ReferralManagerError {
            #expect(error == .noSignedInUser)
        }
    }

    // MARK: Redemption — the core of this suite

    @Test("redeem grants a streak freeze to both sides when the backend confirms both")
    func redeemGrantsAStreakFreezeToBothSidesWhenBackendConfirmsBoth() async throws {
        let container = try makeTestContainer()
        let userID = try insertUser(in: container)
        let referrerID = UUID()
        let backend = FakeReferralBackend(redemptionResult: ReferralRedemptionResult(
            referrerUserID: referrerID,
            refereeFreezeGranted: true,
            referrerFreezeGranted: true
        ))
        let manager = ReferralManager(modelContainer: container, backend: backend)

        let result = try await manager.redeem(code: ReferralManager.generateCode())

        #expect(result.referrerUserID == referrerID)
        #expect(result.refereeFreezeGranted)
        #expect(
            result.referrerFreezeGranted,
            "spec §4 v2: \"invite a friend → both get a streak freeze\" — the referrer's grant " +
            "flag must round-trip even though this device applies its own half locally and the " +
            "referrer's half is credited server-side (see ReferralManager's header comment)"
        )

        // This device's own (the referee's) half must actually be credited locally — not just
        // reported as granted in the result.
        let freezesLeft = try fetchFreezesLeft(in: container, userID: userID)
        #expect(
            freezesLeft == 2,
            "Streak.init defaults freezesLeft to 1; redeeming a valid code that grants the " +
            "referee a freeze should credit exactly one more"
        )
        #expect(try fetchReferredBy(in: container, userID: userID) == referrerID)
    }

    @Test("redeem does not grant a local freeze when the backend declines the referee's side")
    func redeemDoesNotGrantALocalFreezeWhenBackendDeclinesTheRefereeSide() async throws {
        let container = try makeTestContainer()
        let userID = try insertUser(in: container)
        let referrerID = UUID()
        let backend = FakeReferralBackend(redemptionResult: ReferralRedemptionResult(
            referrerUserID: referrerID,
            refereeFreezeGranted: false,
            referrerFreezeGranted: true
        ))
        let manager = ReferralManager(modelContainer: container, backend: backend)

        _ = try await manager.redeem(code: ReferralManager.generateCode())

        #expect(
            try fetchFreezesLeft(in: container, userID: userID) == nil,
            "no Streak row should be created at all when the backend reports the referee's grant as false"
        )
    }

    @Test("redeem rejects a malformed code before ever touching the backend")
    func redeemRejectsAMalformedCodeBeforeTouchingTheNetwork() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let backend = FakeReferralBackend()
        let manager = ReferralManager(modelContainer: container, backend: backend)

        do {
            _ = try await manager.redeem(code: "TOO-SHORT")
            Issue.record("expected ReferralManagerError.invalidCodeFormat")
        } catch let error as ReferralManagerError {
            guard case .invalidCodeFormat = error else {
                Issue.record("expected invalidCodeFormat, got \(error)")
                return
            }
        }

        #expect(await backend.redeemCallCount == 0, "an unparseable code must be rejected client-side, per this file's own header comment")
    }

    @Test("redeem rejects redeeming your own code")
    func redeemRejectsRedeemingYourOwnCode() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let backend = FakeReferralBackend()
        let manager = ReferralManager(modelContainer: container, backend: backend)
        let ownCode = try manager.myReferralCode()

        do {
            _ = try await manager.redeem(code: ownCode)
            Issue.record("expected ReferralManagerError.cannotRedeemOwnCode")
        } catch let error as ReferralManagerError {
            #expect(error == .cannotRedeemOwnCode)
        }
    }

    @Test("redeem rejects a second redemption by the same user")
    func redeemRejectsASecondRedemptionByTheSameUser() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let referrerID = UUID()
        let backend = FakeReferralBackend(redemptionResult: ReferralRedemptionResult(
            referrerUserID: referrerID,
            refereeFreezeGranted: true,
            referrerFreezeGranted: true
        ))
        let manager = ReferralManager(modelContainer: container, backend: backend)

        _ = try await manager.redeem(code: ReferralManager.generateCode())

        do {
            _ = try await manager.redeem(code: ReferralManager.generateCode())
            Issue.record("expected ReferralManagerError.alreadyRedeemed")
        } catch let error as ReferralManagerError {
            #expect(error == .alreadyRedeemed, "users.referred_by is a single FK (spec §13) — only one redemption, ever")
        }
    }

    @Test("redeem throws backendUnavailable when no ReferralBackend has been configured yet")
    func redeemThrowsWhenNoBackendIsConfiguredYet() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let manager = ReferralManager(modelContainer: container) // no backend passed

        do {
            _ = try await manager.redeem(code: ReferralManager.generateCode())
            Issue.record("expected ReferralManagerError.backendUnavailable")
        } catch let error as ReferralManagerError {
            #expect(error == .backendUnavailable)
        }
    }

    @Test("setBackend wires in a backend after construction, matching SyncEngine.setBackend's contract")
    func setBackendWiresInABackendAfterConstruction() async throws {
        let container = try makeTestContainer()
        try insertUser(in: container)
        let manager = ReferralManager(modelContainer: container)
        let referrerID = UUID()

        manager.setBackend(FakeReferralBackend(redemptionResult: ReferralRedemptionResult(
            referrerUserID: referrerID,
            refereeFreezeGranted: true,
            referrerFreezeGranted: true
        )))

        let result = try await manager.redeem(code: ReferralManager.generateCode())
        #expect(result.referrerUserID == referrerID)
    }
}
