// TrialReminder.swift
// Core / Monetization
//
// The promise on the paywall's timeline — "we'll remind you 2 days before it ends" (spec §7, §21) —
// made real (audit M3, growth research #1 and #5, 2026-10-02).
//
//   * The paywall shows a "Remind me before my trial ends" toggle, ON by default (`isEnabled`).
//     Turning it on asks for notification permission right there, if it was never asked.
//   * When a trial starts, `recordTrialStarted` stores the trial window — RevenueCat's
//     `expirationDate` when the store gave one, otherwise start + trial length — and schedules one
//     local notification `PaywallViewModel.trialReminderDaysBefore` days before the end.
//   * Every `EntitlementGate.refresh()` (launch and each foreground) calls `refresh`, which follows
//     the store's real end date, drops the reminder once the user has converted or the trial is
//     gone, and re-composes the body with the latest "What your trial earned you" numbers
//     (`TrialSummary`), since a scheduled notification's text can't change on its own.
//   * `isInFinalWindow` tells the app when to show the in-app card (`TrialEarnedCard`).
//
// Window dates live in the App Group defaults; the notification is the system's.

import Foundation

@MainActor
public enum TrialReminder {
    public static let notificationIdentifier = "zano.trialReminder"
    /// Where a tap on the reminder lands: Today, where the trial card is.
    public static let deepLink = "zano://today"

    static let enabledKey = "zano.trialReminder.enabled.v1"
    static let startedAtKey = "zano.trialReminder.trialStartedAt.v1"
    static let endsAtKey = "zano.trialReminder.trialEndsAt.v1"

    /// Overridable for tests.
    static var defaults: UserDefaults = SharedDefaults.store
    /// Overridable for tests: whether to touch the real notification center.
    static var schedulesNotifications = true

    public static var daysBefore: Int { PaywallViewModel.trialReminderDaysBefore }

    // MARK: - The toggle

    /// The paywall toggle. Defaults to ON.
    public static var isEnabled: Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Flips the toggle. ON asks for notification permission if it was never asked (the paywall
    /// moment, where the user has a concrete reason to say yes) and schedules the reminder if a
    /// trial is already running; OFF cancels it. Returns the permission status afterwards.
    @discardableResult
    public static func setEnabled(_ enabled: Bool, now: Date = .now) async -> NotificationPermission.Status {
        defaults.set(enabled, forKey: enabledKey)
        guard schedulesNotifications else { return .denied }
        guard enabled else {
            cancelNotification()
            return await NotificationPermission.status()
        }
        let status = await NotificationPermission.requestIfUndetermined()
        await reschedule(now: now)
        return status
    }

    // MARK: - The trial window

    public static var trialStartedAt: Date? { defaults.object(forKey: startedAtKey) as? Date }
    public static var trialEndsAt: Date? { defaults.object(forKey: endsAtKey) as? Date }

    /// When the reminder fires for a trial ending at `endsAt`.
    public static func reminderDate(endsAt: Date) -> Date {
        endsAt.addingTimeInterval(-TimeInterval(daysBefore) * 86_400)
    }

    /// From the reminder moment until the trial ends: show "What your trial earned you".
    public static func isInFinalWindow(now: Date = .now) -> Bool {
        guard let end = trialEndsAt else { return false }
        return now >= reminderDate(endsAt: end) && now < end
    }

    /// The trial's numbers so far (`TrialSummary`). Empty without a recorded trial.
    public static func summary(now: Date = .now) -> TrialSummary {
        guard let start = trialStartedAt else { return .empty }
        return TrialSummary.current(since: start, now: now)
    }

    /// A trial just started on a plan with `trialDays` free days. Prefers the store's own end date.
    /// Asks for permission if the toggle is on and it was never asked, then schedules.
    public static func recordTrialStarted(trialDays: Int, entitlement: ProEntitlementInfo?, now: Date = .now) async {
        let end: Date
        if let entitlement, entitlement.isTrial, let expiration = entitlement.expirationDate, expiration > now {
            end = expiration
        } else {
            end = now.addingTimeInterval(TimeInterval(max(trialDays, 0)) * 86_400)
        }
        guard end > now else { return }
        defaults.set(now, forKey: startedAtKey)
        defaults.set(end, forKey: endsAtKey)
        if isEnabled, schedulesNotifications {
            await NotificationPermission.requestIfUndetermined()
        }
        await reschedule(now: now)
    }

    /// Follows the store's view of the trial and re-composes the pending reminder. `entitlement` is
    /// `RevenueCatManager.lastProEntitlement`; `nil` (offline, no key) keeps the local window.
    public static func refresh(entitlement: ProEntitlementInfo?, now: Date = .now) async {
        if let entitlement {
            if entitlement.isTrial, entitlement.isActive, let expiration = entitlement.expirationDate {
                if trialEndsAt != expiration {
                    if trialStartedAt == nil {
                        // The trial started somewhere this device didn't record (restore, reinstall).
                        defaults.set(expiration.addingTimeInterval(-7 * 86_400), forKey: startedAtKey)
                    }
                    defaults.set(expiration, forKey: endsAtKey)
                }
            } else if trialEndsAt != nil {
                // Converted to paid, or the trial is over: nothing left to remind about.
                clearTrial()
                return
            }
        }
        await reschedule(now: now)
    }

    /// Forgets the trial window and its reminder.
    public static func clearTrial() {
        defaults.removeObject(forKey: startedAtKey)
        defaults.removeObject(forKey: endsAtKey)
        cancelNotification()
    }

    // MARK: - Scheduling

    /// The reminder's title and body for a trial ending `endsAt`, with `summary`'s numbers.
    public static func content(summary: TrialSummary, endsAt: Date) -> (title: String, body: String) {
        let date = endsAt.formatted(date: .abbreviated, time: .omitted)
        return (
            Copy.trialSummary.reminderTitle(daysBefore: daysBefore),
            Copy.trialSummary.reminderBody(summary: summary, chargeDate: date)
        )
    }

    private static func reschedule(now: Date) async {
        guard isEnabled, let end = trialEndsAt else {
            cancelNotification()
            return
        }
        let fireAt = reminderDate(endsAt: end)
        guard fireAt > now else { return }
        guard schedulesNotifications else { return }
        let text = content(summary: summary(now: now), endsAt: end)
        await NotificationPermission.scheduleOneShot(
            identifier: notificationIdentifier,
            title: text.title,
            body: text.body,
            at: fireAt,
            deepLink: deepLink,
            buddyPose: .idle,
            now: now
        )
    }

    private static func cancelNotification() {
        guard schedulesNotifications else { return }
        NotificationPermission.cancel(identifiers: [notificationIdentifier])
    }
}
