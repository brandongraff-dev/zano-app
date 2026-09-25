// TodaySuggestion.swift
// App / ZANO / Features / Today / Suggestions
//
// The one suggestion card slot under Today's hero (docs/design/buildout-plan.md Wave 2F). Retention
// mechanics from docs/spec.md 5.5 (Plan B), 5.6 (Never Miss Twice), 5.16 (locked-out moment), 5.18
// (comeback, travel) and 9.7 (calendar density) each get one card; Today shows at most one, the
// first in `TodaySuggestion.priority` order that the user hasn't dismissed. None show during a
// health pause (spec 24): `TodayView` builds no candidates then.
//
// `TodayView` decides which candidates apply (it holds the queries and live Health numbers) and
// what each action does; the card views only draw. This file holds the value types, the per-day
// dismiss memory, and today's shield-attempt tally.

import Foundation
import Core

/// One candidate for the suggestion slot. Values only, so `TodayView` can compare and animate.
enum TodaySuggestion: Equatable {
    /// Yesterday was missed while a streak was running: the easiest open goal, and freezes left.
    case neverMissTwice(NeverMissTwiceState)
    /// Comeback mode after 5+ days away: offer the 3-day ramp, or show today's day of it.
    case comeback(ComebackState)
    /// A goal at risk late in the day (or already switched): its smaller Plan B version.
    case planB(PlanBState)
    case travel(TravelCardVariant)
    case calendarLightDay(CalendarCardVariant)
    /// Today's blocked-app attempts crossed the locked-out threshold.
    case lockedOut(attempts: Int)

    /// Lower shows first. Auto-detected moments outrank the two "would you like to..." asks
    /// (calendar access, manual travel), which only fill an otherwise empty slot.
    var priority: Int {
        switch self {
        case .neverMissTwice: 0
        case .comeback: 1
        case .planB: 2
        case .travel(let variant): variant == .manual ? 7 : 3
        case .calendarLightDay(let variant): variant == .ask ? 6 : 4
        case .lockedOut: 5
        }
    }

    /// The dismiss memory key. Variants that are different questions get their own key, so
    /// hiding the calendar ask doesn't also hide a packed-day suggestion.
    var dismissKey: String {
        switch self {
        case .neverMissTwice: "neverMissTwice"
        case .comeback: "comeback"
        case .planB(let state): "planB.\(state.goalID.uuidString)"
        case .travel(let variant): "travel.\(variant.rawValue)"
        case .calendarLightDay(let variant): "calendar.\(variant.rawValue)"
        case .lockedOut: "lockedOut"
        }
    }

    /// How many days a dismiss lasts. "Not today" is one day; the two asks stay quiet longer so
    /// they don't nag (spec 8 rule 7, nudge scarcity).
    var dismissDays: Int {
        switch self {
        case .travel(.manual): 7
        case .calendarLightDay(.ask): 14
        default: 1
        }
    }

    /// Analytics name (identifier, not copy).
    var analyticsName: String {
        switch self {
        case .neverMissTwice: "never_miss_twice"
        case .comeback: "comeback"
        case .planB: "plan_b"
        case .travel(let variant): "travel_\(variant.rawValue)"
        case .calendarLightDay(let variant): "calendar_\(variant.rawValue)"
        case .lockedOut: "locked_out"
        }
    }
}

struct NeverMissTwiceState: Equatable {
    /// The easiest open goal, whose row action the card's button runs. `nil`: nothing open.
    let goalID: UUID?
    let goalTitle: String?
    let freezesLeft: Int
}

struct ComebackState: Equatable {
    /// `nil` while the challenge hasn't started (the card offers to start it).
    let day: Int?
    let totalDays: Int
    /// The easiest open goal once the challenge runs. `nil`: today's goals are done.
    let goalID: UUID?
    let goalTitle: String?
}

struct PlanBState: Equatable {
    let goalID: UUID
    let goalTitle: String
    let goalType: GoalType
    /// Today's full target and the Plan B target, in `unit`.
    let full: Int
    let reduced: Int
    let unit: String
    /// The user already switched this goal to Plan B today.
    let isAccepted: Bool
    /// Verified progress toward `reduced` (logged amount, Health, gym dwell).
    let current: Int

    var isMet: Bool { current >= reduced && reduced > 0 }
}

enum TravelCardVariant: String, Equatable {
    /// `TravelMode` detected a new city and has a pending suggestion.
    case suggested
    /// A travel session is running.
    case active
    /// Nothing detected; the user can say "I'm traveling" themselves.
    case manual
}

enum CalendarCardVariant: String, Equatable {
    /// Calendar awareness isn't on yet: ask from the card (never at launch).
    case ask
    /// Access granted and today is packed.
    case packed
}

// MARK: - Dismiss memory (per device, per day)

/// Remembers "Not today" per suggestion key until the start of the day it expires. A per-viewer
/// convenience in the app's own defaults: extensions never read it.
enum TodaySuggestionDismissals {
    private static let key = "today.suggestionDismissals.v1"

    static func isDismissed(_ suggestion: TodaySuggestion, now: Date = .now) -> Bool {
        guard let until = entries()[suggestion.dismissKey] else { return false }
        return now.timeIntervalSince1970 < until
    }

    static func dismiss(_ suggestion: TodaySuggestion, now: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let until = calendar.date(byAdding: .day, value: max(1, suggestion.dismissDays), to: start)
            ?? start.addingTimeInterval(86_400)
        var all = entries().filter { $0.value > now.timeIntervalSince1970 }
        all[suggestion.dismissKey] = until.timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: key)
    }

    private static func entries() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }
}

// MARK: - Today's shield attempts

/// Today's count of shield impressions (each one is the user opening a blocked app). The shield
/// extension only bumps `SharedDefaults.shieldImpressionCount`; whoever opens first (Today or the
/// Lock tab) flushes it here, reports it to analytics once, and adds it to today's tally.
///
/// Approximate by design: impressions counted before a flush are attributed to the day of the
/// flush, and a shield can render more than once per attempt.
@MainActor
enum ShieldAttemptTally {
    private static let dayKey = "today.shieldAttempts.day"
    private static let countKey = "today.shieldAttempts.count"

    /// Flushes pending impressions (one aggregate `shield_impression` event, spec 23) and returns
    /// today's total.
    @discardableResult
    static func absorbPending(now: Date = .now) -> Int {
        let flushed = SharedDefaults.flushShieldImpressionCount()
        if flushed > 0 {
            Analytics.shared.capture(event: "shield_impression", properties: ["count": flushed])
        }
        let today = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let defaults = UserDefaults.standard
        var count = defaults.double(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
        count += flushed
        defaults.set(today, forKey: dayKey)
        defaults.set(count, forKey: countKey)
        return count
    }
}

// MARK: - Async signals

/// What the suggestion slot needs that isn't in `TodayView`'s queries: the retention engines'
/// state, calendar access, today's shield attempts. Loaded by `TodayView.refreshSuggestionSignals`.
struct TodaySuggestionSignals: Equatable {
    /// `false` until the first load, so no card flashes in and out.
    var loaded = false
    /// Comeback challenge day (1-based) while one runs.
    var comebackDay: Int?
    var comebackTotalDays = 3
    var comebackEligible = false
    var travelActive = false
    var travelCity: String?
    var travelPending = false
    /// `.declined` until loaded, so the calendar ask never shows before the real state is known.
    var calendarAccess: CalendarAwareness.AccessState = .declined
    var isPackedDay = false
    var shieldAttemptsToday = 0
    /// Goals switched to Plan B today (`PlanB.isAccepted`).
    var planBAcceptedGoalIDs: Set<UUID> = []
    /// Longest Health workout today, for a gym goal's Plan B. `nil`: Health not connected.
    var healthWorkoutMinutes: Int?
}
