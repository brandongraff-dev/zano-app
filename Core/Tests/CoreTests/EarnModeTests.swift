// Core/Tests/CoreTests/EarnModeTests.swift
//
// Tests Core/Sources/Core/LockEngine/TimeBankEngine.swift — Earn Mode's per-day ledger
// (docs/spec.md §5.2 "★ Earn Rate ('Screen Time Exchange Rate')"). Read in full before writing
// this, along with docs/spec.md §5.2 and §13's `time_bank` table shape.
//
// Covers exactly what this task named: deposit/spend/remaining math, and midnight expiry ("no
// hoarding") — proven structurally here the same way TimeBankEngine's own header documents it:
// by depositing into one calendar day and asserting an *adjacent* day's row starts fresh at zero,
// never by simulating a clock or a cron-style expiry step (there isn't one; see
// TimeBankEngine.swift's header comment).
//
// Every test builds its own isolated in-memory ModelContainer (via
// `ModelContainer.makeAppGroupContainer(inMemory: true)`, exactly the override
// `TimeBankEngine.init(modelContainer:)` documents itself as existing for) and its own
// `TimeBankEngine` instance — never `TimeBankEngine.shared` — so tests can run in any order or in
// parallel with zero shared state between them.
//
// All dates are built from a fixed reference `DateComponents`, never `Date()`/`.now`, so day-
// boundary math is deterministic regardless of when the suite happens to run. Deliberately left on
// `Calendar.current` (not pinned to UTC the way VerificationTests.swift's fixtures are): every day
// boundary under test here is computed with `Calendar.current` inside TimeBankEngine.swift itself
// (`fetchTimeBank`/`fetchOrCreateTimeBank`), so matching that same calendar in the test is what
// keeps the test meaningful — pinning the test to UTC while the engine uses the device's local
// calendar would just be testing two different calendars against each other.

import Foundation
import SwiftData
import Testing
@testable import Core

// MARK: - Shared fixtures

@MainActor
private enum EarnModeFixture {
    /// A fixed reference instant, far from any DST transition, used as "day 0" for every test
    /// below. Never `Date()`/`.now` — see file header.
    static let referenceDay = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)
    )!

    /// `referenceDay` plus `offset` calendar days, still at noon local time.
    static func day(_ offset: Int = 0) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    /// A fresh, isolated in-memory store — never the real App Group / `.appGroup` singleton.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer.makeAppGroupContainer(inMemory: true)
    }

    /// Inserts and saves a single `User` row into `container` via a scratch `ModelContext`, then
    /// hands back a `TimeBankEngine` built on that same container — mirroring how every other
    /// engine in this folder (`LockEngineManager`, `LockSetManager`, `StreakEngine`) expects
    /// exactly one local `User` row to exist before any of their CONTRACTS methods will do
    /// anything besides throw/return the graceful-empty answer.
    static func makeEngineWithSignedInUser() throws -> TimeBankEngine {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(User())
        try context.save()
        return TimeBankEngine(modelContainer: container)
    }
}

// MARK: - §5.2 exact rate values ("A gym session = 90 min... a focus block = 30 min... protein = 30 min")

@Suite("TimeBankEarnRates — spec §5.2 exact values")
struct TimeBankEarnRatesTests {
    @Test("gym session deposits exactly 90 minutes")
    func gymRateIs90() {
        #expect(TimeBankEarnRates.gymSessionMinutes == 90)
    }

    @Test("focus block deposits exactly 30 minutes")
    func focusRateIs30() {
        #expect(TimeBankEarnRates.focusBlockMinutes == 30)
    }

    @Test("protein deposits exactly 30 minutes")
    func proteinRateIs30() {
        #expect(TimeBankEarnRates.proteinMinutes == 30)
    }

    @Test("minutes(for:) looks the three defined goal types up by their exact spec §5.2 rate")
    func lookupReturnsExactRatesForDefinedGoalTypes() {
        #expect(TimeBankEarnRates.minutes(for: .workoutGym) == 90)
        #expect(TimeBankEarnRates.minutes(for: .focusSession) == 30)
        #expect(TimeBankEarnRates.minutes(for: .protein) == 30)
    }

    @Test("minutes(for:) is nil — not a guessed zero — for every goal type §5.2 doesn't define a rate for")
    func lookupReturnsNilRatherThanZeroForUndefinedGoalTypes() {
        for type in GoalType.allCases where ![.workoutGym, .focusSession, .protein].contains(type) {
            #expect(TimeBankEarnRates.minutes(for: type) == nil, "\(type) should have no defined Earn Mode rate yet")
        }
    }
}

// MARK: - Deposit

@Suite("TimeBankEngine.deposit")
@MainActor
struct TimeBankEngineDepositTests {
    @Test("a single deposit is reflected in that day's remaining minutes")
    func depositIsReflectedInRemaining() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        try await engine.deposit(minutes: 90, for: EarnModeFixture.day())
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 90)
    }

    @Test("multiple deposits on the same day accumulate (spec §5.2's gym + focus + protein stacking)")
    func depositsAccumulateAcrossCalls() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: TimeBankEarnRates.gymSessionMinutes, for: today)
        try await engine.deposit(minutes: TimeBankEarnRates.focusBlockMinutes, for: today)
        try await engine.deposit(minutes: TimeBankEarnRates.proteinMinutes, for: today)
        #expect(await engine.remainingMinutes(for: today) == 150) // 90 + 30 + 30
    }

    @Test("depositing at different times of the same calendar day shares one ledger")
    func depositAndReadShareOneLedgerRegardlessOfTimeOfDay() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let morning = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: EarnModeFixture.day())!
        let night = Calendar.current.date(bySettingHour: 23, minute: 45, second: 0, of: EarnModeFixture.day())!
        try await engine.deposit(minutes: 90, for: morning)
        #expect(await engine.remainingMinutes(for: night) == 90)
    }

    @Test("deposit(minutes: 0) throws .invalidMinutes and deposits nothing")
    func depositRejectsZeroMinutes() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        do {
            try await engine.deposit(minutes: 0, for: EarnModeFixture.day())
            Issue.record("Expected TimeBankEngineError.invalidMinutes to be thrown")
        } catch TimeBankEngineError.invalidMinutes(let minutes) {
            #expect(minutes == 0)
        } catch {
            Issue.record("Expected .invalidMinutes(0), got \(error)")
        }
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 0)
    }

    @Test("deposit(minutes: negative) throws .invalidMinutes and deposits nothing")
    func depositRejectsNegativeMinutes() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        do {
            try await engine.deposit(minutes: -15, for: EarnModeFixture.day())
            Issue.record("Expected TimeBankEngineError.invalidMinutes to be thrown")
        } catch TimeBankEngineError.invalidMinutes(let minutes) {
            #expect(minutes == -15)
        } catch {
            Issue.record("Expected .invalidMinutes(-15), got \(error)")
        }
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 0)
    }

    @Test("deposit throws .noSignedInUser when no local User row exists")
    func depositThrowsWithNoSignedInUser() async throws {
        let container = try EarnModeFixture.makeContainer() // deliberately no User inserted
        let engine = TimeBankEngine(modelContainer: container)
        do {
            try await engine.deposit(minutes: 90, for: EarnModeFixture.day())
            Issue.record("Expected TimeBankEngineError.noSignedInUser to be thrown")
        } catch TimeBankEngineError.noSignedInUser {
            // expected
        } catch {
            Issue.record("Expected .noSignedInUser, got \(error)")
        }
    }
}

// MARK: - Spend

@Suite("TimeBankEngine.spend")
@MainActor
struct TimeBankEngineSpendTests {
    @Test("spending less than the balance succeeds and decrements remaining by exactly that amount")
    func spendSucceedsAndDecrementsRemaining() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 90, for: today)
        let didSpend = try await engine.spend(minutes: 30, for: today)
        #expect(didSpend == true)
        #expect(await engine.remainingMinutes(for: today) == 60)
    }

    @Test("spending exactly the remaining balance succeeds and drains it to zero")
    func spendingExactBalanceDrainsToZero() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 30, for: today)
        let didSpend = try await engine.spend(minutes: 30, for: today)
        #expect(didSpend == true)
        #expect(await engine.remainingMinutes(for: today) == 0)
    }

    @Test("spending more than the balance fails atomically — nothing is deducted")
    func spendFailsAtomicallyWhenBalanceInsufficient() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 30, for: today)
        let didSpend = try await engine.spend(minutes: 31, for: today)
        #expect(didSpend == false)
        // All-or-nothing: a rejected 31-minute spend must not partially deduct 30 of it.
        #expect(await engine.remainingMinutes(for: today) == 30)
    }

    @Test("spending from an empty bank fails without creating a negative balance")
    func spendingFromEmptyBankFails() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let didSpend = try await engine.spend(minutes: 1, for: EarnModeFixture.day())
        #expect(didSpend == false)
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 0)
    }

    @Test("repeated partial spends draw down the same balance correctly")
    func repeatedPartialSpendsDrawDownBalance() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 90, for: today) // gym
        #expect(try await engine.spend(minutes: 20, for: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 70)
        #expect(try await engine.spend(minutes: 50, for: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 20)
        #expect(try await engine.spend(minutes: 21, for: today) == false) // one over what's left
        #expect(await engine.remainingMinutes(for: today) == 20)
        #expect(try await engine.spend(minutes: 20, for: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 0)
    }

    @Test("spend(minutes: 0) throws .invalidMinutes")
    func spendRejectsZeroMinutes() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 90, for: today)
        do {
            _ = try await engine.spend(minutes: 0, for: today)
            Issue.record("Expected TimeBankEngineError.invalidMinutes to be thrown")
        } catch TimeBankEngineError.invalidMinutes(let minutes) {
            #expect(minutes == 0)
        } catch {
            Issue.record("Expected .invalidMinutes(0), got \(error)")
        }
        #expect(await engine.remainingMinutes(for: today) == 90) // untouched
    }

    @Test("spend(minutes: negative) throws .invalidMinutes and deducts nothing")
    func spendRejectsNegativeMinutes() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        try await engine.deposit(minutes: 90, for: today)
        do {
            _ = try await engine.spend(minutes: -10, for: today)
            Issue.record("Expected TimeBankEngineError.invalidMinutes to be thrown")
        } catch TimeBankEngineError.invalidMinutes(let minutes) {
            #expect(minutes == -10)
        } catch {
            Issue.record("Expected .invalidMinutes(-10), got \(error)")
        }
        #expect(await engine.remainingMinutes(for: today) == 90) // untouched
    }
}

// MARK: - Midnight expiry ("no hoarding" — spec §5.2)

@Suite("TimeBankEngine midnight expiry — \"no hoarding\" (spec §5.2)")
@MainActor
struct TimeBankEngineMidnightExpiryTests {
    @Test("an unused balance does not carry over into the next calendar day")
    func unusedBalanceDoesNotCarryOverPastMidnight() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        try await engine.deposit(minutes: 90, for: EarnModeFixture.day(0))
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(0)) == 90)
        // Tomorrow is a fresh row that was never deposited into — nothing hoarded from today.
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(1)) == 0)
    }

    @Test("a spend dated after midnight cannot draw on the previous day's leftover balance")
    func spendAfterMidnightCannotDrawOnPreviousDaysBalance() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        try await engine.deposit(minutes: 90, for: EarnModeFixture.day(0))
        let didSpend = try await engine.spend(minutes: 1, for: EarnModeFixture.day(1))
        #expect(didSpend == false)
        // Yesterday's balance is untouched by the failed cross-day spend attempt.
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(0)) == 90)
    }

    @Test("each calendar day is an entirely independent ledger, not just a running total")
    func eachCalendarDayIsAnIndependentLedger() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        try await engine.deposit(minutes: 90, for: EarnModeFixture.day(0))
        try await engine.deposit(minutes: 45, for: EarnModeFixture.day(1))
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(0)) == 90)
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(1)) == 45)
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(2)) == 0)
    }

    @Test("spending down to zero today still leaves tomorrow's fresh row untouched")
    func drainingTodayDoesNotAffectTomorrow() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        try await engine.deposit(minutes: 30, for: EarnModeFixture.day(0))
        #expect(try await engine.spend(minutes: 30, for: EarnModeFixture.day(0)) == true)
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(0)) == 0)
        try await engine.deposit(minutes: 30, for: EarnModeFixture.day(1))
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day(1)) == 30)
    }
}

// MARK: - remainingMinutes graceful defaults (never throws — read by widget/shield copy)

@Suite("TimeBankEngine.remainingMinutes graceful defaults")
@MainActor
struct TimeBankEngineRemainingMinutesTests {
    @Test("remainingMinutes is 0 for a day nothing was ever deposited into")
    func remainingIsZeroForUntouchedDay() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 0)
    }

    @Test("remainingMinutes is 0, never a thrown error, when no local User row exists")
    func remainingIsZeroWithNoSignedInUser() async throws {
        let container = try EarnModeFixture.makeContainer() // no User inserted
        let engine = TimeBankEngine(modelContainer: container)
        #expect(await engine.remainingMinutes(for: EarnModeFixture.day()) == 0)
    }
}

// MARK: - depositEarnedMinutes(forVerifiedGoalType:) convenience

@Suite("TimeBankEngine.depositEarnedMinutes(forVerifiedGoalType:)")
@MainActor
struct TimeBankEngineDepositEarnedMinutesTests {
    @Test("deposits the exact spec §5.2 rate for each of the three defined goal types")
    func depositsExactSpecRatesForDefinedGoalTypes() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()

        #expect(try await engine.depositEarnedMinutes(forVerifiedGoalType: .workoutGym, on: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 90)

        #expect(try await engine.depositEarnedMinutes(forVerifiedGoalType: .focusSession, on: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 120)

        #expect(try await engine.depositEarnedMinutes(forVerifiedGoalType: .protein, on: today) == true)
        #expect(await engine.remainingMinutes(for: today) == 150)
    }

    @Test("is a no-op — not a silent zero deposit — for goal types §5.2 doesn't define a rate for")
    func noOpForGoalTypesWithNoDefinedRate() async throws {
        let engine = try EarnModeFixture.makeEngineWithSignedInUser()
        let today = EarnModeFixture.day()
        let deposited = try await engine.depositEarnedMinutes(forVerifiedGoalType: .steps, on: today)
        #expect(deposited == false)
        #expect(await engine.remainingMinutes(for: today) == 0)
    }
}

// MARK: - TimeBank model invariant (docs/spec.md §5.2/§13; Models/TimeBank.swift)

@Suite("TimeBank.remainingMin invariant")
@MainActor
struct TimeBankRemainingMinInvariantTests {
    @Test("remainingMin is clamped at zero and never goes negative even if spentMin exceeds earnedMin")
    func remainingMinNeverGoesNegative() {
        let bank = TimeBank(userID: UUID(), date: EarnModeFixture.day(), earnedMin: 10, spentMin: 999)
        #expect(bank.remainingMin == 0)
    }

    @Test("remainingMin is the straightforward difference when spentMin is within earnedMin")
    func remainingMinIsEarnedMinusSpentWhenPositive() {
        let bank = TimeBank(userID: UUID(), date: EarnModeFixture.day(), earnedMin: 90, spentMin: 30)
        #expect(bank.remainingMin == 60)
    }
}
