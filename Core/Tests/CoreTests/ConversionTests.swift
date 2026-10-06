// Core/Tests/CoreTests/ConversionTests.swift
//
// Tests the conversion pass (2026-10-02): the paywall grace period (Monetization/SubscriptionGate),
// the trial window and reminder date (Monetization/TrialReminder), "What your trial earned you"
// (Monetization/TrialSummary + Copy.trialSummary) and the rating-ask rules (Retention/RatingPrompt).
// No notification center and no RevenueCat: everything here is pure or runs on throwaway defaults.

import Foundation
import SwiftData
import Testing
@testable import Core

/// Serialized: the TrialReminder tests swap its static defaults suite.
@Suite(.serialized)
@MainActor
struct ConversionTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private static func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private static let day: TimeInterval = 86_400

    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "zano.tests.conversion.\(UUID().uuidString)"))
    }

    // MARK: - SubscriptionGate (grace period)

    @Test func noGraceByDefault() throws {
        let defaults = try freshDefaults()
        #expect(!SubscriptionGate.isInGracePeriod(now: Self.date(1), defaults: defaults))
        #expect(SubscriptionGate.graceDaysLeft(now: Self.date(1), defaults: defaults) == 0)
        #expect(!SubscriptionGate.hasPendingTrialStart(defaults: defaults))
        #expect(!SubscriptionGate.hasGraceExpired(now: Self.date(1), defaults: defaults))
    }

    @Test func firstGraceLastsThreeDays() throws {
        let defaults = try freshDefaults()
        let start = Self.date(1)
        let end = SubscriptionGate.startGrace(now: start, defaults: defaults)
        #expect(end == start.addingTimeInterval(3 * Self.day))
        #expect(SubscriptionGate.isInGracePeriod(now: start.addingTimeInterval(2.9 * Self.day), defaults: defaults))
        #expect(SubscriptionGate.graceDaysLeft(now: start, defaults: defaults) == 3)
        #expect(SubscriptionGate.graceDaysLeft(now: start.addingTimeInterval(1.5 * Self.day), defaults: defaults) == 2)
        #expect(SubscriptionGate.hasPendingTrialStart(defaults: defaults))
        #expect(!SubscriptionGate.isInGracePeriod(now: end, defaults: defaults))
        #expect(SubscriptionGate.hasGraceExpired(now: end, defaults: defaults))
    }

    @Test func askingAgainDuringGraceChangesNothing() throws {
        let defaults = try freshDefaults()
        let end = SubscriptionGate.startGrace(now: Self.date(1), defaults: defaults)
        #expect(SubscriptionGate.startGrace(now: Self.date(2), defaults: defaults) == end)
    }

    @Test func graceAfterExpiryIsOneDay() throws {
        let defaults = try freshDefaults()
        SubscriptionGate.startGrace(now: Self.date(1), defaults: defaults)
        let later = Self.date(10)
        let end = SubscriptionGate.startGrace(now: later, defaults: defaults)
        #expect(end == later.addingTimeInterval(Self.day))
        // The original start is kept (the banner keys off it).
        #expect(SubscriptionGate.graceStartedAt(defaults: defaults) == Self.date(1))
    }

    @Test func clearingGraceEndsTheBanner() throws {
        let defaults = try freshDefaults()
        SubscriptionGate.startGrace(now: Self.date(1), defaults: defaults)
        SubscriptionGate.clearGrace(defaults: defaults)
        #expect(!SubscriptionGate.hasPendingTrialStart(defaults: defaults))
        #expect(!SubscriptionGate.isInGracePeriod(now: Self.date(1), defaults: defaults))
    }

    // MARK: - TrialSummary

    @Test func trialSummaryCountsOnlyTheWindow() {
        let since = Self.date(1, 0)
        let now = Self.date(6, 0)
        let snapshot = MilestoneSnapshot(
            currentStreak: 3,
            lockIntervals: [
                // Before the trial: ignored.
                DateInterval(start: Self.date(0, 8), end: Self.date(0, 12)),
                // Straddles the start: only the 2 hours inside count.
                DateInterval(start: Self.date(0, 22), end: Self.date(1, 2)),
                // Inside: 3 hours, overlapping 1 hour with the next.
                DateInterval(start: Self.date(2, 8), end: Self.date(2, 11)),
                DateInterval(start: Self.date(2, 10), end: Self.date(2, 12)),
            ],
            earnedUnlockDates: [Self.date(0, 12), Self.date(2), Self.date(3), Self.date(4), Self.date(4, 18)],
            gymCompletionDates: [Self.date(2, 9), Self.date(2, 18), Self.date(4)]
        )
        let summary = TrialSummary.make(snapshot: snapshot, since: since, now: now, calendar: Self.calendar)
        #expect(summary.earnedUnlocks == 4)
        #expect(summary.gymVisits == 2)
        #expect(summary.hoursLockedIn == 6)
        #expect(summary.bestStreak == 3)
        #expect(summary.hasWins)
    }

    @Test func emptyTrialHasNoWins() {
        let summary = TrialSummary.make(snapshot: MilestoneSnapshot(), since: Self.date(1), now: Self.date(5), calendar: Self.calendar)
        #expect(summary == .empty)
        #expect(!summary.hasWins)
    }

    @Test func reminderBodyNamesNumbersAndBillingDate() {
        let summary = TrialSummary(earnedUnlocks: 3, gymVisits: 1, hoursLockedIn: 9, bestStreak: 3)
        let body = Copy.trialSummary.reminderBody(summary: summary, chargeDate: "Oct 8")
        #expect(body.contains("3 earned unlocks"))
        #expect(body.contains("1 gym visit"))
        #expect(body.contains("9 h locked in"))
        #expect(body.contains("best streak 3 days"))
        #expect(body.contains("Oct 8"))
        #expect(body.contains("Cancel anytime"))
    }

    @Test func reminderBodyWithoutWinsOffersTheSmallestStep() {
        let body = Copy.trialSummary.reminderBody(summary: .empty, chargeDate: "Oct 8")
        #expect(!body.contains("0"))
        #expect(body.contains("smallest goal"))
        #expect(body.contains("Oct 8"))
    }

    // MARK: - TrialReminder

    @Test func trialWindowUsesStoreExpirationWhenTrial() async throws {
        TrialReminder.defaults = try freshDefaults()
        TrialReminder.schedulesNotifications = false
        defer {
            TrialReminder.defaults = SharedDefaults.store
            TrialReminder.schedulesNotifications = true
        }
        let now = Self.date(1)
        let storeEnd = now.addingTimeInterval(7 * Self.day + 3600)
        await TrialReminder.recordTrialStarted(
            trialDays: 7,
            entitlement: ProEntitlementInfo(isActive: true, isTrial: true, expirationDate: storeEnd, willRenew: true),
            now: now
        )
        #expect(TrialReminder.trialEndsAt == storeEnd)
        #expect(TrialReminder.reminderDate(endsAt: storeEnd) == storeEnd.addingTimeInterval(-2 * Self.day))
        #expect(!TrialReminder.isInFinalWindow(now: now))
        #expect(TrialReminder.isInFinalWindow(now: storeEnd.addingTimeInterval(-Self.day)))
        #expect(!TrialReminder.isInFinalWindow(now: storeEnd))
    }

    @Test func trialWindowFallsBackToTrialLength() async throws {
        TrialReminder.defaults = try freshDefaults()
        TrialReminder.schedulesNotifications = false
        defer {
            TrialReminder.defaults = SharedDefaults.store
            TrialReminder.schedulesNotifications = true
        }
        let now = Self.date(1)
        await TrialReminder.recordTrialStarted(trialDays: 7, entitlement: nil, now: now)
        #expect(TrialReminder.trialEndsAt == now.addingTimeInterval(7 * Self.day))
        #expect(TrialReminder.trialStartedAt == now)
        #expect(TrialReminder.isEnabled) // ON by default
    }

    @Test func convertingToPaidClearsTheTrial() async throws {
        TrialReminder.defaults = try freshDefaults()
        TrialReminder.schedulesNotifications = false
        defer {
            TrialReminder.defaults = SharedDefaults.store
            TrialReminder.schedulesNotifications = true
        }
        await TrialReminder.recordTrialStarted(trialDays: 7, entitlement: nil, now: Self.date(1))
        await TrialReminder.refresh(
            entitlement: ProEntitlementInfo(isActive: true, isTrial: false, expirationDate: Self.date(30), willRenew: true),
            now: Self.date(9)
        )
        #expect(TrialReminder.trialEndsAt == nil)
        #expect(!TrialReminder.isInFinalWindow(now: Self.date(7)))
    }

    // MARK: - RatingPrompt

    private func earnedInputs(_ change: (inout RatingPromptInputs) -> Void = { _ in }) -> RatingPromptInputs {
        var inputs = RatingPromptInputs(earnedUnlockCount: 3, lastUnlockKind: .earned)
        change(&inputs)
        return inputs
    }

    @Test func asksAfterThirdEarnedUnlock() {
        #expect(RatingPrompt.decide(earnedInputs(), now: Self.date(10)) == .thirdEarnedUnlock)
        #expect(RatingPrompt.decide(earnedInputs { $0.earnedUnlockCount = 2 }, now: Self.date(10)) == nil)
    }

    @Test func asksAfterFirstGymUnlockAndSevenDayStreak() {
        let gym = earnedInputs { $0.earnedUnlockCount = 1; $0.gymVerifiedCount = 1 }
        #expect(RatingPrompt.decide(gym, now: Self.date(10)) == .firstGymUnlock)
        let streak = earnedInputs { $0.earnedUnlockCount = 1; $0.currentStreak = 7 }
        #expect(RatingPrompt.decide(streak, now: Self.date(10)) == .sevenDayStreak)
    }

    @Test func eachTriggerOnlyOnce() {
        let used = earnedInputs { $0.usedTriggers = [.thirdEarnedUnlock] }
        #expect(RatingPrompt.decide(used, now: Self.date(10)) == nil)
    }

    @Test func neverAfterABadMoment() {
        let now = Self.date(10)
        #expect(RatingPrompt.decide(earnedInputs { $0.lastUnlockKind = .emergency }, now: now) == nil)
        #expect(RatingPrompt.decide(earnedInputs { $0.lastUnlockKind = nil }, now: now) == nil)
        #expect(RatingPrompt.decide(earnedInputs { $0.isSlipped = true }, now: now) == nil)
        #expect(RatingPrompt.decide(earnedInputs { $0.lastEmergencyUnlockAt = now.addingTimeInterval(-3600) }, now: now) == nil)
        #expect(RatingPrompt.decide(earnedInputs { $0.lastPaywallViewAt = now.addingTimeInterval(-3600) }, now: now) == nil)
        // A day later the emergency unlock no longer blocks it.
        #expect(RatingPrompt.decide(earnedInputs { $0.lastEmergencyUnlockAt = now.addingTimeInterval(-25 * 3600) }, now: now) == .thirdEarnedUnlock)
    }

    @Test func rateLimits() {
        let now = Self.date(30)
        let recent = earnedInputs { $0.askDates = [now.addingTimeInterval(-13 * Self.day)] }
        #expect(RatingPrompt.decide(recent, now: now) == nil)
        let gapOK = earnedInputs { $0.askDates = [now.addingTimeInterval(-15 * Self.day)] }
        #expect(RatingPrompt.decide(gapOK, now: now) == .thirdEarnedUnlock)
        let capped = earnedInputs {
            $0.askDates = [100, 60, 30].map { now.addingTimeInterval(-Double($0) * Self.day) }
        }
        #expect(RatingPrompt.decide(capped, now: now) == nil)
        let oldAsks = earnedInputs {
            $0.askDates = [400, 380, 370].map { now.addingTimeInterval(-Double($0) * Self.day) }
        }
        #expect(RatingPrompt.decide(oldAsks, now: now) == .thirdEarnedUnlock)
    }

    @Test func storeBackedPromptReadsSessionsAndLedger() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        for offset in 0..<3 {
            let end = Self.date(5 + offset)
            context.insert(LockSession(userID: user.id, startedAt: end.addingTimeInterval(-3600), endedAt: end, mode: .earn, unlockKind: .earned))
        }
        try context.save()
        let prompt = RatingPrompt(modelContainer: container, defaults: try freshDefaults())
        let now = Self.date(8)
        #expect(prompt.triggerIfDue(now: now) == .thirdEarnedUnlock)
        prompt.recordAsked(.thirdEarnedUnlock, now: now)
        #expect(prompt.triggerIfDue(now: now) == nil)

        // A paywall view blocks the next day's ask.
        let other = RatingPrompt(modelContainer: container, defaults: try freshDefaults())
        other.recordPaywallViewed(now: now.addingTimeInterval(-60))
        #expect(other.triggerIfDue(now: now) == nil)
    }
}
