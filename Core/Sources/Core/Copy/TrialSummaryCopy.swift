// TrialSummaryCopy.swift
// Core / Copy
//
// `Copy.trialSummary` — "What your trial earned you" (growth research #5, 2026-10-02): the
// reminder notification two days before the first charge and the in-app card
// (`App/ZANO/Features/Paywall/TrialEarnedCard.swift`). Honest by construction (spec §21): the charge
// date is always stated, cancelling is always mentioned, no countdowns, no guilt. With no wins yet
// the copy offers the smallest next step instead of zeros.
//
// Also the Finish setup "Turn on notifications" item (audit N2), as an extension of
// `Copy.onboarding` next to the other Finish setup items.

extension Copy {
    public enum trialSummary {
        // MARK: Notification

        public static func reminderTitle(daysBefore: Int) -> String {
            daysBefore == 1 ? "Your free trial ends tomorrow" : "Your free trial ends in \(daysBefore) days"
        }

        public static func reminderBody(summary: TrialSummary, chargeDate: String) -> String {
            let billing = "Billing starts \(chargeDate). Cancel anytime in Settings."
            guard summary.hasWins else {
                return "No wins yet? Start with your smallest goal today. \(billing)"
            }
            return "So far: \(statsLine(summary)). \(billing)"
        }

        /// "3 earned unlocks, 2 gym visits, 9 h locked in, best streak 3 days", leaving out zeros.
        public static func statsLine(_ summary: TrialSummary) -> String {
            var parts: [String] = []
            if summary.earnedUnlocks > 0 {
                parts.append(summary.earnedUnlocks == 1 ? "1 earned unlock" : "\(summary.earnedUnlocks) earned unlocks")
            }
            if summary.gymVisits > 0 {
                parts.append(summary.gymVisits == 1 ? "1 gym visit" : "\(summary.gymVisits) gym visits")
            }
            if summary.hoursLockedIn > 0 {
                parts.append("\(summary.hoursLockedIn) h locked in")
            }
            if summary.bestStreak > 1 {
                parts.append("best streak \(summary.bestStreak) days")
            }
            return parts.joined(separator: ", ")
        }

        // MARK: Card

        public static let cardEyebrow = "Your trial so far"
        public static let cardTitle = "What your trial earned you"
        public static let earnedUnlocksLabel = "Earned unlocks"
        public static let gymVisitsLabel = "Gym visits"
        public static let hoursLockedInLabel = "Hours locked in"
        public static let bestStreakLabel = "Best streak"
        public static func bestStreakValue(_ days: Int) -> String {
            days == 1 ? "1 day" : "\(days) days"
        }
        public static let noWinsTitle = "No wins yet, and that's okay"
        public static let noWinsDetail = "Start with your smallest goal today. One verified win is enough to feel how it works."
        public static func chargeLine(date: String) -> String {
            "Billing starts \(date). Cancel anytime in Settings > [your name] > Subscriptions."
        }
        public static let dismissLabel = "Hide"
        public static let dismissSpoken = "Hide trial summary"
    }
}

extension Copy.onboarding {
    // MARK: - Today "Finish setup": notifications (audit N2)

    public static let finishSetupNotificationsTitle = "Turn on notifications"
    public static let finishSetupNotificationsDetail = "Shield buttons, your trial reminder and at most 2 nudges a day."
    /// While notifications are off in the Settings app: the row opens it.
    public static let finishSetupNotificationsDeniedDetail = "They're off for ZANO. Tap to open Settings."
}
