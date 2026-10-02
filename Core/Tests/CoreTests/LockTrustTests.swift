// Core/Tests/CoreTests/LockTrustTests.swift
//
// The lock trust pass (2026-10-02): Time Bank borrowing on any lock (docs/spec.md §5.2 Time Bank,
// §24 "never trap users"), the spend/borrow window's open and end rules, the Screen Time self-check
// decision, and the hero's blocking line.
//
// Like GoalCompletionTests.swift and LockEngineTests.swift, nothing here touches
// `ManagedSettingsStore`, `DeviceActivityCenter` or `AuthorizationCenter`: the borrow flow runs on
// the real `TimeBankEngine` (in-memory store) with the lock engine injected as closures, and the
// window/health/summary rules are pure functions. Dates are a fixed reference day, never `.now`
// (so `TimeBankEngine` never mirrors to the Earn Meter, which only follows *today*).

import Foundation
import FamilyControls
import SwiftData
import Testing
@testable import Core

@MainActor
private enum TrustFixture {
    static let referenceDay = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)
    )!

    static func engineWithUser() throws -> TimeBankEngine {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(User())
        try context.save()
        return TimeBankEngine(modelContainer: container)
    }
}

// MARK: - Borrow amounts

@Suite("TimeBankBorrow — amounts on offer")
struct TimeBankBorrowAmountTests {
    @Test("an empty bank offers nothing")
    func emptyBankOffersNothing() {
        #expect(TimeBankBorrow.choices(remaining: 0).isEmpty)
        #expect(TimeBankBorrow.choices(remaining: -3).isEmpty)
    }

    @Test("chips appear only when the bank covers them")
    func chipsFitTheBank() {
        #expect(TimeBankBorrow.choices(remaining: 5) == [5])
        #expect(TimeBankBorrow.choices(remaining: 12) == [5, 10])
        #expect(TimeBankBorrow.choices(remaining: 90) == [5, 10, 15])
    }

    @Test("less than 5 minutes left offers exactly what's left")
    func smallBankOffersTheRest() {
        #expect(TimeBankBorrow.choices(remaining: 3) == [3])
    }

    @Test("a borrow is 1 to 15 minutes")
    func validAmounts() {
        #expect(!TimeBankBorrow.isValidAmount(0))
        #expect(TimeBankBorrow.isValidAmount(1))
        #expect(TimeBankBorrow.isValidAmount(15))
        #expect(!TimeBankBorrow.isValidAmount(16))
    }
}

// MARK: - Borrow flow

@Suite("TimeBankEngine.borrowToUnlock — rules")
@MainActor
struct TimeBankBorrowFlowTests {
    private let day = TrustFixture.referenceDay

    @Test("works on a full-mode lock: deducts the minutes and opens a window")
    func fullModeBorrowDeducts() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 30, for: day)
        var opened: [Int] = []
        let until = day.addingTimeInterval(10 * 60)

        let result = try await engine.borrowToUnlock(
            minutes: 10,
            now: day,
            activeLockMode: { .full },
            openWindow: { minutes, _ in opened.append(minutes); return until }
        )

        #expect(result == .unlocked(until: until))
        #expect(opened == [10])
        #expect(await engine.remainingMinutes(for: day) == 20)
    }

    @Test("works on an Earn Mode lock too")
    func earnModeBorrowDeducts() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 5, for: day)
        let result = try await engine.borrowToUnlock(
            minutes: 5,
            now: day,
            activeLockMode: { .earn },
            openWindow: { _, now in now.addingTimeInterval(300) }
        )
        #expect(result == .unlocked(until: day.addingTimeInterval(300)))
        #expect(await engine.remainingMinutes(for: day) == 0)
    }

    @Test("not enough minutes: nothing is deducted and no window opens")
    func insufficientMinutes() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 3, for: day)
        var opened = false
        let result = try await engine.borrowToUnlock(
            minutes: 5,
            now: day,
            activeLockMode: { .full },
            openWindow: { _, now in opened = true; return now }
        )
        #expect(result == .insufficientMinutes(remaining: 3))
        #expect(!opened)
        #expect(await engine.remainingMinutes(for: day) == 3)
    }

    @Test("an empty bank reports zero remaining")
    func emptyBank() async throws {
        let engine = try TrustFixture.engineWithUser()
        let result = try await engine.borrowToUnlock(
            minutes: 5,
            now: day,
            activeLockMode: { .full },
            openWindow: { _, now in now }
        )
        #expect(result == .insufficientMinutes(remaining: 0))
    }

    @Test("no running lock: nothing is deducted")
    func noLock() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 30, for: day)
        let result = try await engine.borrowToUnlock(
            minutes: 5,
            now: day,
            activeLockMode: { nil },
            openWindow: { _, now in now }
        )
        #expect(result == .noActiveLock)
        #expect(await engine.remainingMinutes(for: day) == 30)
    }

    @Test("amounts outside 1...15 throw and deduct nothing")
    func invalidAmountsThrow() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 60, for: day)
        for minutes in [0, -5, 16, 30] {
            do {
                _ = try await engine.borrowToUnlock(
                    minutes: minutes,
                    now: day,
                    activeLockMode: { .full },
                    openWindow: { _, now in now }
                )
                Issue.record("Expected .invalidMinutes(\(minutes))")
            } catch TimeBankEngineError.invalidMinutes(let rejected) {
                #expect(rejected == minutes)
            } catch {
                Issue.record("Expected .invalidMinutes(\(minutes)), got \(error)")
            }
        }
        #expect(await engine.remainingMinutes(for: day) == 60)
    }

    @Test("if the window can't open, the minutes are refunded")
    func failedWindowRefunds() async throws {
        let engine = try TrustFixture.engineWithUser()
        try await engine.deposit(minutes: 20, for: day)
        do {
            _ = try await engine.borrowToUnlock(
                minutes: 10,
                now: day,
                activeLockMode: { .full },
                openWindow: { _, _ in throw LockEngineError.noActiveLock }
            )
            Issue.record("Expected the window error to be rethrown")
        } catch LockEngineError.noActiveLock {
            // expected
        } catch {
            Issue.record("Expected LockEngineError.noActiveLock, got \(error)")
        }
        #expect(await engine.remainingMinutes(for: day) == 20)
    }
}

// MARK: - Spend/borrow window

@Suite("SpendWindow — open, extend, and re-lock at the end")
struct SpendWindowRuleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = UUID()

    @Test("a fresh window runs from now for the minutes paid")
    func freshWindow() {
        let window = SpendWindow.opening(existing: nil, sessionID: session, minutes: 5, now: now)
        #expect(window.sessionID == session)
        #expect(window.startedAt == now)
        #expect(window.endsAt == now.addingTimeInterval(300))
    }

    @Test("borrowing again during an open window extends it from its end")
    func extendsOpenWindow() {
        let first = SpendWindow.opening(existing: nil, sessionID: session, minutes: 5, now: now)
        let later = now.addingTimeInterval(120)
        let second = SpendWindow.opening(existing: first, sessionID: session, minutes: 10, now: later)
        #expect(second.startedAt == now)
        #expect(second.endsAt == now.addingTimeInterval(15 * 60))
    }

    @Test("an expired window or another lock's window never carries over")
    func staleWindowsStartFresh() {
        let expired = SpendWindow(sessionID: session, startedAt: now.addingTimeInterval(-900), endsAt: now.addingTimeInterval(-60))
        let renewed = SpendWindow.opening(existing: expired, sessionID: session, minutes: 5, now: now)
        #expect(renewed.startedAt == now)
        #expect(renewed.endsAt == now.addingTimeInterval(300))

        let other = SpendWindow(sessionID: UUID(), startedAt: now, endsAt: now.addingTimeInterval(600))
        let mine = SpendWindow.opening(existing: other, sessionID: session, minutes: 5, now: now)
        #expect(mine.endsAt == now.addingTimeInterval(300))
    }

    @Test("before the end the window stays open")
    func stillOpenBeforeEnd() {
        let window = SpendWindow(sessionID: session, startedAt: now, endsAt: now.addingTimeInterval(600))
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: session, hasIntendedShield: true, now: now) == .stillOpen)
    }

    @Test("at the end, a still-running lock (any mode) gets its shield back")
    func reshieldsAtEnd() {
        let window = SpendWindow(sessionID: session, startedAt: now, endsAt: now.addingTimeInterval(300))
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: session, hasIntendedShield: true, now: now.addingTimeInterval(300)) == .reshield)
        // DeviceActivity callbacks can be a little early.
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: session, hasIntendedShield: true, now: now.addingTimeInterval(240)) == .reshield)
    }

    @Test("a lock that already ended is never re-shielded")
    func endedLockOnlyClears() {
        let window = SpendWindow(sessionID: session, startedAt: now, endsAt: now.addingTimeInterval(300))
        let end = now.addingTimeInterval(400)
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: nil, hasIntendedShield: true, now: end) == .clearOnly)
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: UUID(), hasIntendedShield: true, now: end) == .clearOnly)
        #expect(SpendWindow.endOutcome(window: window, activeSessionID: session, hasIntendedShield: false, now: end) == .clearOnly)
    }
}

// MARK: - Screen Time self-check

@Suite("LockHealthCheck.evaluate")
struct LockHealthCheckTests {
    @Test("nothing running or scheduled is always fine")
    func idleIsOK() {
        #expect(LockHealthCheck.evaluate(isLockActive: false, hasEnabledSchedule: false, isAuthorized: false, isInSpendWindow: false, expectsShield: false, shieldPresent: nil) == .ok)
    }

    @Test("access off with a running or scheduled lock is flagged")
    func accessOff() {
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: false, isAuthorized: false, isInSpendWindow: false, expectsShield: true, shieldPresent: false) == .screenTimeAccessOff)
        #expect(LockHealthCheck.evaluate(isLockActive: false, hasEnabledSchedule: true, isAuthorized: false, isInSpendWindow: false, expectsShield: false, shieldPresent: nil) == .screenTimeAccessOff)
    }

    @Test("an empty shield on a running lock is flagged, but not during a Time Bank window")
    func shieldMissing() {
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: false, isAuthorized: true, isInSpendWindow: false, expectsShield: true, shieldPresent: false) == .shieldMissing)
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: false, isAuthorized: true, isInSpendWindow: true, expectsShield: true, shieldPresent: false) == .ok)
    }

    @Test("an unknown read or nothing intended never raises a false alarm")
    func noFalseAlarms() {
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: false, isAuthorized: true, isInSpendWindow: false, expectsShield: true, shieldPresent: nil) == .ok)
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: false, isAuthorized: true, isInSpendWindow: false, expectsShield: false, shieldPresent: false) == .ok)
        #expect(LockHealthCheck.evaluate(isLockActive: true, hasEnabledSchedule: true, isAuthorized: true, isInSpendWindow: false, expectsShield: true, shieldPresent: true) == .ok)
    }
}

// MARK: - Blocking line

@Suite("LockBlockingSummary + blocking line copy")
struct LockBlockingSummaryTests {
    private let session = UUID()
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12))!
    }

    @Test("counts what's blocked, never the tokens themselves")
    func countsOnly() {
        #expect(Copy.lockStatus.blockingWhat(apps: 12, categories: 0, websites: 0) == "12 apps")
        #expect(Copy.lockStatus.blockingWhat(apps: 5, categories: 2, websites: 0) == "2 categories + 5 apps")
        #expect(Copy.lockStatus.blockingWhat(apps: 1, categories: 1, websites: 1) == "1 category + 1 app + 1 website")
        #expect(Copy.lockStatus.blockingWhat(apps: nil, categories: nil, websites: nil) == "your apps")
    }

    @Test("a goal lock ends when the goals are done")
    func goalLockLine() {
        let summary = LockBlockingSummary(appCount: 12, categoryCount: 0, webDomainCount: 0, ending: .whenGoalsDone, openUntil: nil)
        #expect(Copy.lockStatus.blockingLine(summary) == "Blocking 12 apps · ends when your goals are done")
    }

    @Test("resolve picks the schedule's fixed end, else goals, else 'until you end it'")
    func endings() {
        let timed = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 2, scheduleEndMinuteOfDay: 21 * 60, spendWindow: nil, now: noon, calendar: calendar)
        #expect(timed.ending == .at(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 21))!))
        #expect(timed.appCount == nil)

        let goals = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 2, scheduleEndMinuteOfDay: nil, spendWindow: nil, now: noon, calendar: calendar)
        #expect(goals.ending == .whenGoalsDone)

        let manual = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 0, scheduleEndMinuteOfDay: nil, spendWindow: nil, now: noon, calendar: calendar)
        #expect(manual.ending == .whenEnded)

        // A schedule end already passed today falls back to the goals.
        let past = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 1, scheduleEndMinuteOfDay: 9 * 60, spendWindow: nil, now: noon, calendar: calendar)
        #expect(past.ending == .whenGoalsDone)
    }

    @Test("an empty selection counts zero and reads as 'your apps'")
    func emptySelection() {
        let summary = LockBlockingSummary.resolve(selection: FamilyActivitySelection(), sessionID: session, requiredGoalCount: 1, scheduleEndMinuteOfDay: nil, spendWindow: nil, now: noon, calendar: calendar)
        #expect(summary.appCount == 0)
        #expect(Copy.lockStatus.blockingLine(summary) == "Blocking your apps · ends when your goals are done")
    }

    @Test("only this lock's open window turns the line into 'Apps open until …'")
    func openWindowLine() {
        let open = SpendWindow(sessionID: session, startedAt: noon, endsAt: noon.addingTimeInterval(600))
        let summary = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 1, scheduleEndMinuteOfDay: nil, spendWindow: open, now: noon, calendar: calendar)
        #expect(summary.openUntil == open.endsAt)
        let line = Copy.lockStatus.blockingLine(summary)
        #expect(line.hasPrefix("Apps open until "))
        #expect(line.hasSuffix(" · locks again after"))

        let other = SpendWindow(sessionID: UUID(), startedAt: noon, endsAt: noon.addingTimeInterval(600))
        let mine = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 1, scheduleEndMinuteOfDay: nil, spendWindow: other, now: noon, calendar: calendar)
        #expect(mine.openUntil == nil)

        let expired = SpendWindow(sessionID: session, startedAt: noon, endsAt: noon.addingTimeInterval(-1))
        let closed = LockBlockingSummary.resolve(selection: nil, sessionID: session, requiredGoalCount: 1, scheduleEndMinuteOfDay: nil, spendWindow: expired, now: noon, calendar: calendar)
        #expect(closed.openUntil == nil)
    }
}
