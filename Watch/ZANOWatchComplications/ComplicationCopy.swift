// ComplicationCopy.swift
// Watch/ZANOWatchComplications
//
// User-facing strings for the watch complications. Same arrangement as the watch app's
// `WatchCopy.swift`: Core (and so `Core/Sources/Core/Copy`) can't be linked on watchOS, so the
// strings live in the target, shaped as `Copy.<area>` so call sites read like the phone's. This
// target can't reuse `WatchCopy.swift` itself: that file references the generated buddy types,
// which this extension deliberately doesn't compile (see `ComplicationSnapshot.swift`).
// Voice-neutral on purpose: complications are too small for the coach voices.

enum Copy {}

extension Copy {
    enum watchComplication {
        static let displayName = "Streak"
        static let description = "Your streak and today's goals at a glance."

        /// "12-day streak". Zero reads as an invitation, not a failure.
        static func streak(_ days: Int) -> String {
            switch days {
            case ...0: "Start a streak"
            case 1: "1-day streak"
            default: "\(days)-day streak"
            }
        }

        /// The curved label in a watch-face corner: short.
        static func streakCorner(_ days: Int) -> String {
            days == 1 ? "1 day" : "\(max(0, days)) days"
        }

        static let today = "Today"
        static func buddyLevel(_ level: Int) -> String { "Buddy Lv \(level)" }

        static let notSynced = "Open ZANO on iPhone"
        static let notSyncedInline = "ZANO"
        static let noStreakNumber = "–"

        static func accessibility(streak days: Int, todayPercent: Int) -> String {
            "\(streak(days)), today \(todayPercent) percent done"
        }
    }
}
