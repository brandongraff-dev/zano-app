// SubscriptionGate.swift
// Core / Monetization
//
// The paywall's grace period (audit M2, founder decision 2026-10-02). The onboarding paywall is hard
// (spec §21), but when it can't sell anything — offline first launch, a build with no RevenueCat
// key, a store or dashboard error — a hard wall is a dead end, and a Release build must never be
// stuck there. Instead the paywall offers "Continue for now": the user gets into the app for
// `initialGraceDays`, and the paywall comes back once the grace has run out and the app can
// actually reach the store.
//
// How it ends:
//   * The user starts the trial or restores (from the paywall, or from the "Finish starting your
//     trial" banner) -> `clearGrace()`; `EntitlementGate` also clears it whenever RevenueCat says
//     the user is entitled.
//   * The grace runs out and RevenueCat answers "not entitled" -> `EntitlementGate` blocks with the
//     lapsed paywall (after releasing any active lock, as it always does).
//   * The grace runs out but the store still can't be reached -> `EntitlementGate` fails open, as
//     it always has; nobody is locked out by a network problem.
//   * If the store fails again while the paywall is up after an expired grace, "Continue for now"
//     grants `retryGraceDays` more. It is only offered when plans can't load, i.e. when there is
//     nothing the user could buy, so it is not a way around paying.
//
// State lives in the App Group defaults (start and end dates only). Read-only for everything but
// the paywall and `EntitlementGate`. Surfaces that show the soft banner read
// `hasPendingTrialStart` / `isInGracePeriod` / `graceDaysLeft`.

import Foundation

public enum SubscriptionGate {
    /// The first grace: long enough to get through a weekend offline, short enough that the trial
    /// is still the obvious next step.
    public static let initialGraceDays = 3
    /// Each later grace, offered only while plans still can't load.
    public static let retryGraceDays = 1

    static let startedAtKey = "zano.subscriptionGate.graceStartedAt.v1"
    static let endsAtKey = "zano.subscriptionGate.graceEndsAt.v1"

    // MARK: - Reads

    /// When the first grace started; `nil` if the user never needed one (or started the trial).
    public static func graceStartedAt(defaults: UserDefaults = SharedDefaults.store) -> Date? {
        defaults.object(forKey: startedAtKey) as? Date
    }

    /// When the current grace ends; `nil` without one.
    public static func graceEndsAt(defaults: UserDefaults = SharedDefaults.store) -> Date? {
        defaults.object(forKey: endsAtKey) as? Date
    }

    /// The user is inside a grace period right now.
    public static func isInGracePeriod(now: Date = .now, defaults: UserDefaults = SharedDefaults.store) -> Bool {
        guard let end = graceEndsAt(defaults: defaults) else { return false }
        return end > now
    }

    /// Whole days left, rounded up (2.1 days left reads "3"); 0 outside a grace.
    public static func graceDaysLeft(now: Date = .now, defaults: UserDefaults = SharedDefaults.store) -> Int {
        guard let end = graceEndsAt(defaults: defaults), end > now else { return 0 }
        return Int((end.timeIntervalSince(now) / 86_400).rounded(.up))
    }

    /// The user got into the app on a grace and hasn't started the trial yet. Drives the soft
    /// "Finish starting your trial" banner. Stays true after the grace ends until the trial starts,
    /// so the banner doesn't vanish on a build that can't reach the store at all.
    public static func hasPendingTrialStart(defaults: UserDefaults = SharedDefaults.store) -> Bool {
        graceStartedAt(defaults: defaults) != nil
    }

    /// A grace was granted and has run out.
    public static func hasGraceExpired(now: Date = .now, defaults: UserDefaults = SharedDefaults.store) -> Bool {
        guard let end = graceEndsAt(defaults: defaults) else { return false }
        return end <= now
    }

    // MARK: - Writes (paywall and EntitlementGate only)

    /// Grants a grace and returns when it ends. The first one lasts `initialGraceDays`; asking again
    /// while one is running changes nothing; asking after it ran out grants `retryGraceDays`.
    @discardableResult
    public static func startGrace(now: Date = .now, defaults: UserDefaults = SharedDefaults.store) -> Date {
        if let end = graceEndsAt(defaults: defaults), end > now {
            return end
        }
        let isFirst = graceStartedAt(defaults: defaults) == nil
        let days = isFirst ? initialGraceDays : retryGraceDays
        let end = now.addingTimeInterval(TimeInterval(days) * 86_400)
        if isFirst {
            defaults.set(now, forKey: startedAtKey)
        }
        defaults.set(end, forKey: endsAtKey)
        return end
    }

    /// The trial started (or a purchase was restored): the grace and its banner are done.
    public static func clearGrace(defaults: UserDefaults = SharedDefaults.store) {
        defaults.removeObject(forKey: startedAtKey)
        defaults.removeObject(forKey: endsAtKey)
    }
}
