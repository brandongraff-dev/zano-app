// TrialReminderScheduler.swift
// Core / Monetization
//
// docs/spec.md §21 "Free trials, done well" (decision 2026-10-06) and §7 screen 12: the paywall
// promises "we'll remind you 2 days before it ends" and shows a dated timeline. This file keeps
// that promise: when a purchase starts a free trial, it records the trial locally and schedules
// one local notification on the reminder date the paywall showed. It also decides when Today's
// day-5 "what your trial earned you" card is due.
//
// Local-first, like everything else: no server round trip. The trial is recorded at purchase time
// from the package's introductory offer. Restored purchases carry no trial info, so nothing is
// scheduled for them, which errs on the side of not sending a wrong "you'll be charged" message.

import Foundation
import UserNotifications
import os

/// A free trial that started on this device. Pure date logic, so it is unit-tested directly.
public struct TrialSchedule: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let trialDays: Int
    /// The plan's price with its period ("$39.99/yr"), quoted in the reminder and the card.
    public let priceLine: String

    /// Hour of day (local) the reminder fires. The paywall timeline shows dates only, so a
    /// mid-morning time on that date is a reasonable reading, and it never lands at night.
    static let reminderHour = 10
    /// Spec §21: the value card shows from the trial's 5th day.
    static let valueCardDay = 5
    /// Spec §7 screen 12: "we'll remind you 2 days before it ends." `PaywallViewModel`'s copy
    /// reads the same constant, so the promise and the notification agree.
    public static let reminderDaysBefore = 2

    public init(startedAt: Date, trialDays: Int, priceLine: String) {
        self.startedAt = startedAt
        self.trialDays = trialDays
        self.priceLine = priceLine
    }

    /// When the trial converts to paid: `trialDays` after the start, the same arithmetic the
    /// paywall's timeline uses for its "trial ends" date.
    public func endsAt(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: trialDays, to: startedAt) ?? startedAt
    }

    /// The reminder's fire time, on the same calendar day the paywall's reminder node showed
    /// (`trialDays - daysBefore` after the start). `nil` when the trial is too short to have one,
    /// matching the paywall, which drops its reminder node in that case.
    public func reminderDate(
        daysBefore: Int = TrialSchedule.reminderDaysBefore,
        calendar: Calendar = .current
    ) -> Date? {
        guard trialDays > daysBefore,
              let day = calendar.date(byAdding: .day, value: trialDays - daysBefore, to: startedAt)
        else { return nil }
        return calendar.date(bySettingHour: Self.reminderHour, minute: 0, second: 0, of: day)
    }

    /// The start of the trial's 5th day (day 1 is the start day).
    public func valueCardStart(calendar: Calendar = .current) -> Date {
        let firstDay = calendar.startOfDay(for: startedAt)
        return calendar.date(byAdding: .day, value: Self.valueCardDay - 1, to: firstDay) ?? firstDay
    }

    /// Whether Today should show the value card at `now`: from day 5 until the trial ends. Short
    /// trials (3 days) never reach day 5 and skip it.
    public func showsValueCard(at now: Date, calendar: Calendar = .current) -> Bool {
        now >= valueCardStart(calendar: calendar) && now < endsAt(calendar: calendar)
    }
}

/// Records the trial and owns its reminder notification. `@MainActor` like the rest of
/// `Monetization`, since its callers (`PaywallViewModel`, views) are on the main actor.
@MainActor
public final class TrialReminderScheduler {
    public static let shared = TrialReminderScheduler()

    static let reminderNotificationID = "zano.trialReminder"
    private static let scheduleKey = "trial.schedule"
    private static let cardDismissedKey = "trial.valueCardDismissed"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "TrialReminderScheduler")

    /// `internal` so tests can pass an isolated suite; real callers use `.shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The recorded trial, if one started on this device.
    public var currentTrial: TrialSchedule? {
        guard let data = defaults.data(forKey: Self.scheduleKey) else { return nil }
        return try? JSONDecoder().decode(TrialSchedule.self, from: data)
    }

    /// Whether Today should show the day-5 card now (due, and not hidden by the user).
    public func showsValueCard(at now: Date = .now) -> Bool {
        guard !defaults.bool(forKey: Self.cardDismissedKey), let trial = currentTrial else { return false }
        return trial.showsValueCard(at: now)
    }

    public func dismissValueCard() {
        defaults.set(true, forKey: Self.cardDismissedKey)
    }

    /// Call after a purchase that started a free trial.
    public func trialStarted(trialDays: Int, priceLine: String, at startedAt: Date = .now) {
        record(TrialSchedule(startedAt: startedAt, trialDays: trialDays, priceLine: priceLine))
        rescheduleIfNeeded(now: startedAt)
    }

    /// Persists `trial` and resets the card's hidden flag. Split from `trialStarted` so tests can
    /// cover persistence without touching the notification center.
    func record(_ trial: TrialSchedule) {
        if let data = try? JSONEncoder().encode(trial) {
            defaults.set(data, forKey: Self.scheduleKey)
        }
        defaults.set(false, forKey: Self.cardDismissedKey)
    }

    /// (Re)adds the reminder if its date is still ahead. Idempotent (fixed identifier). Called at
    /// purchase, at app launch, and right after the notification permission prompt (which comes
    /// after the paywall in onboarding), so the reminder exists once permission is granted.
    public func rescheduleIfNeeded(now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        guard let trial = currentTrial,
              let fireDate = trial.reminderDate(),
              fireDate > now
        else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.reminderNotificationID])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = Copy.trial.reminderTitle(daysBefore: TrialSchedule.reminderDaysBefore)
        content.body = Copy.trial.reminderBody(
            endDate: trial.endsAt().formatted(.dateTime.month(.abbreviated).day()),
            priceLine: trial.priceLine
        )
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: Self.reminderNotificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        // Completion-handler form, like `ShieldActionExtension`: no non-Sendable request crosses
        // an actor boundary under Swift 6.
        let logger = self.logger
        center.add(request) { error in
            if let error {
                logger.error("Trial reminder not scheduled: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
