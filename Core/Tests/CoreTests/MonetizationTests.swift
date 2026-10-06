// MonetizationTests.swift
// CoreTests
//
// docs/spec.md §21 (decision 2026-10-06): the Family annual plan must never take the individual
// annual plan's place as the highlighted default, plans show in a fixed order, and the free-trial
// reminder and day-5 card land on the dates the paywall promised. Pure logic only: nothing here
// touches RevenueCat or the notification center.

import Foundation
import Testing
@testable import Core

@Suite("Monetization")
struct MonetizationTests {

    private func package(
        _ id: String,
        _ period: SubscriptionPackage.Period,
        family: Bool = false
    ) -> SubscriptionPackage {
        SubscriptionPackage(
            id: id,
            productIdentifier: "zano.\(id)",
            period: period,
            priceString: "$1",
            isFamilyShareable: family
        )
    }

    // MARK: - Plan selection and order

    @MainActor @Test func defaultSelectionSkipsFamilyEvenWhenListedFirst() {
        let packages = [package("family", .annual, family: true), package("monthly", .monthly), package("annual", .annual)]
        #expect(PaywallViewModel.defaultSelection(in: packages) == "annual")
    }

    @MainActor @Test func defaultSelectionFallsBackToFamilyWhenItIsTheOnlyAnnual() {
        let packages = [package("monthly", .monthly), package("family", .annual, family: true)]
        #expect(PaywallViewModel.defaultSelection(in: packages) == "family")
    }

    @MainActor @Test func defaultSelectionFallsBackToFirstWithNoAnnual() {
        #expect(PaywallViewModel.defaultSelection(in: [package("monthly", .monthly)]) == "monthly")
        #expect(PaywallViewModel.defaultSelection(in: []) == nil)
    }

    @MainActor @Test func displayOrderIsIndividualFamilyMonthlyThenRest() {
        let packages = [
            package("lifetime", .lifetime),
            package("monthly", .monthly),
            package("family", .annual, family: true),
            package("weekly", .weekly),
            package("annual", .annual),
        ]
        #expect(PaywallViewModel.displayOrder(packages).map(\.id) == ["annual", "family", "monthly", "lifetime", "weekly"])
    }

    @Test func familyDetailLine() {
        #expect(Copy.paywall.familyDetailLine(trialDays: 7) == "Up to 6 people · 7 days free")
        #expect(Copy.paywall.familyDetailLine(trialDays: nil) == "Up to 6 people")
    }

    // MARK: - Trial dates

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// Oct 6, 2026, 9:30 PM New York.
    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 21, minute: 30))!
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.month, .day, .hour], from: date)
    }

    @Test func sevenDayTrialDates() {
        let trial = TrialSchedule(startedAt: start, trialDays: 7, priceLine: "$39.99/yr")
        // Ends 7 days after the start; reminder 2 days before that, at 10 AM.
        #expect(components(trial.endsAt(calendar: calendar)) == DateComponents(month: 10, day: 13, hour: 21))
        #expect(components(trial.reminderDate(daysBefore: 2, calendar: calendar)!) == DateComponents(month: 10, day: 11, hour: 10))
        // Day 5 starts at midnight on Oct 10, before the reminder.
        #expect(components(trial.valueCardStart(calendar: calendar)) == DateComponents(month: 10, day: 10, hour: 0))
    }

    @Test func valueCardWindow() {
        let trial = TrialSchedule(startedAt: start, trialDays: 7, priceLine: "$39.99/yr")
        let day4 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23))!
        let day5 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 8))!
        let afterEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 22))!
        #expect(!trial.showsValueCard(at: day4, calendar: calendar))
        #expect(trial.showsValueCard(at: day5, calendar: calendar))
        #expect(!trial.showsValueCard(at: afterEnd, calendar: calendar))
    }

    @Test func threeDayTrialHasReminderButNoValueCard() {
        let trial = TrialSchedule(startedAt: start, trialDays: 3, priceLine: "$39.99/yr")
        #expect(components(trial.reminderDate(daysBefore: 2, calendar: calendar)!) == DateComponents(month: 10, day: 7, hour: 10))
        let lastMoment = trial.endsAt(calendar: calendar).addingTimeInterval(-1)
        #expect(!trial.showsValueCard(at: lastMoment, calendar: calendar))
    }

    @Test func trialTooShortForReminder() {
        let trial = TrialSchedule(startedAt: start, trialDays: 2, priceLine: "$39.99/yr")
        #expect(trial.reminderDate(daysBefore: 2, calendar: calendar) == nil)
    }

    // MARK: - Persistence

    @MainActor @Test func recordAndDismiss() {
        let suite = "MonetizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let scheduler = TrialReminderScheduler(defaults: defaults)
        #expect(scheduler.currentTrial == nil)

        let trial = TrialSchedule(startedAt: start, trialDays: 7, priceLine: "$39.99/yr")
        scheduler.record(trial)
        #expect(scheduler.currentTrial == trial)

        // The scheduler uses the device calendar, so pick a moment that is inside days 5-7 in any
        // US or UTC time zone: Oct 11, 6 PM New York.
        let midWindow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18))!
        #expect(scheduler.showsValueCard(at: midWindow))
        scheduler.dismissValueCard()
        #expect(!scheduler.showsValueCard(at: midWindow))
    }
}
