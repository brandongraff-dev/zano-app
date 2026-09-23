// Core/Sources/Core/Retention/FreshStartScheduler.swift
//
// docs/spec.md §8 Retention Psychology Rules, rule 6 ("Fresh-start timing"):
//   "Push challenges on Mondays, the 1st, after holidays, and on the user's birthday."
// This is the well-documented "fresh start effect" (people are more likely to pursue a goal right
// after a temporal landmark) applied to spec §5.9's Seasons & Ranks / challenge-launch pushes
// (`Core/Sources/Core/Retention/SeasonsAndRanks.swift`, a sibling file this task does not own and
// does not edit). This file's job stops at *computing and exposing* the next qualifying date —
// rule 6's own wording is "push challenges... on [dates]," an instruction to whatever launches a
// challenge, not to this file: `nextFreshStart(from:includingToday:)` below is the read API a
// challenge-launch call site (§5.9, out of this task's file list) consults to decide *when*, the
// same "expose a read signal, don't act on it yourself" boundary `CalendarAwareness.isPackedDay(_:)`
// and `TravelMode`'s own header comments already draw for their own signals in this same directory.
// This file therefore sends no push, schedules no notification, and never calls `NudgeSender` —
// unlike `Core/Sources/Core/Social/OnboardingDripScheduler.swift` (this same task's other file),
// whose task description explicitly says "queues... via NudgeSender," this file's description says
// only "exposes it," and rule 6's own subject is "challenges," a feature this task's file list does
// not include.
//
// "After holidays" is read as the calendar day *immediately following* each holiday in
// `USHoliday`'s fixed list, not the holiday itself — spec's own wording ("after holidays," not "on
// holidays") matches the fresh-start-effect research this rule is drawn from: the reset moment is
// the first ordinary day back, not the holiday's own day off. Flagged in `decisions` as this task's
// reading, not exact spec text either way.
//
// "A fixed US-holiday list" (`USHoliday`, below): the 11 official U.S. federal holidays (Office of
// Personnel Management's published list) — 5 fixed-calendar-date and 6 nth-weekday-of-month. There
// is no server-synced or user-editable holiday calendar here; a future session could layer one on
// top of (not instead of) this fixed list without this file's shape changing, the same "seam for a
// future session" pattern `SquadManager`'s `SquadDirectory`/`SquadRingSource` protocols (read for
// this task) already establish for their own "good enough today, real backend later" gaps.
//
// Birthday storage — a real, flagged gap, not silently invented: `Core/Sources/Core/Models/
// User.swift` (Session 1's frozen model, docs/spec.md §13's Data Model table) has no birthday
// column, and `backend/supabase/migrations/0001_init.sql`'s `users` table doesn't either — this
// task's own file list is exactly 2 new files, not `Models/User.swift` or a new migration, so this
// file cannot add one. Storing the user's birthday is instead this file's own small piece of local,
// App-Group-`UserDefaults`-backed state (`setBirthday(month:day:)`/`birthday`) — the same "no
// dedicated model exists yet, and adding one is out of scope here" pattern `NFCTagMapper`'s tag
// mappings and `ComebackMode`'s challenge-start-date already use in this exact codebase, each
// documented the same way at their own declarations. Only *month + day* are stored, never a birth
// year: this file only ever needs "which calendar day does the birthday fall on this year," and
// storing a year it doesn't need would be extra sensitive data collected for nothing (spec §24's
// general minimal-data-collection posture). Flagged in `knownIssues`: this local-only value does
// not sync (no `Core/Sources/Core/Sync` outbox entry — that directory is explicitly out of this
// task's reach this run) and does not survive a reinstall; a future session should migrate it to a
// real `users.birthday` column plus a Sync outbox entry, at which point this file's public
// `birthday`/`setBirthday(month:day:)` shape can stay exactly as-is and just change what backs it.
//
// Relationship to `CalendarAwareness.swift` (this same directory, read for this task, not edited):
// no overlap despite both living in `Retention` and both being about dates. `CalendarAwareness`
// reads live EventKit event density (opt-in, "is today packed with meetings") to suggest lighter
// goals; this file does pure calendar-math over 4 fixed rules (weekday-of-week, day-of-month, a
// static holiday table, a locally-stored birthday) to find the next *fresh-start* day. Neither
// file's calculation depends on the other, and this file never touches EventKit.

import Foundation

// MARK: - US holiday list (see header comment)

/// The 11 official U.S. federal holidays this file knows about. `dayAfterHoliday` occasions (spec
/// §8 rule 6: "after holidays") are keyed by case, not by a bare `Date`, so a caller can say which
/// holiday a fresh-start day follows (e.g. for a "Welcome back — hope the holidays were good"
/// challenge-launch line a future session's `Copy` file might want) without re-deriving it.
public enum USHoliday: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    case newYearsDay = "new_years_day"
    case mlkDay = "mlk_day"
    case presidentsDay = "presidents_day"
    case memorialDay = "memorial_day"
    case juneteenth = "juneteenth"
    case independenceDay = "independence_day"
    case laborDay = "labor_day"
    case columbusDay = "columbus_day"
    case veteransDay = "veterans_day"
    case thanksgiving = "thanksgiving"
    case christmasDay = "christmas_day"

    /// The calendar date this holiday falls on in `year`, in `calendar`. `nil` only if `calendar`
    /// cannot resolve the given components at all (not expected for any real Gregorian calendar).
    public func date(in year: Int, calendar: Calendar) -> Date? {
        switch self {
        case .newYearsDay: fixedDate(year: year, month: 1, day: 1, calendar: calendar)
        case .juneteenth: fixedDate(year: year, month: 6, day: 19, calendar: calendar)
        case .independenceDay: fixedDate(year: year, month: 7, day: 4, calendar: calendar)
        case .veteransDay: fixedDate(year: year, month: 11, day: 11, calendar: calendar)
        case .christmasDay: fixedDate(year: year, month: 12, day: 25, calendar: calendar)
        // "3rd Monday of January."
        case .mlkDay: nthWeekday(3, weekday: mondayWeekday, month: 1, year: year, calendar: calendar)
        // "3rd Monday of February" (Washington's Birthday, commonly observed as "Presidents Day").
        case .presidentsDay: nthWeekday(3, weekday: mondayWeekday, month: 2, year: year, calendar: calendar)
        // "Last Monday of May."
        case .memorialDay: lastWeekday(mondayWeekday, month: 5, year: year, calendar: calendar)
        // "1st Monday of September."
        case .laborDay: nthWeekday(1, weekday: mondayWeekday, month: 9, year: year, calendar: calendar)
        // "2nd Monday of October."
        case .columbusDay: nthWeekday(2, weekday: mondayWeekday, month: 10, year: year, calendar: calendar)
        // "4th Thursday of November."
        case .thanksgiving: nthWeekday(4, weekday: thursdayWeekday, month: 11, year: year, calendar: calendar)
        }
    }
}

// MARK: - Fresh-start occasion

/// Why a given calendar day qualifies as a fresh-start day (spec §8 rule 6). A single day can
/// match more than one rule at once (e.g. a 1st-of-the-month that also happens to be a Monday) —
/// `FreshStartResult.occasions` carries every match, not just the first one found.
public enum FreshStartOccasion: Sendable, Equatable, Hashable, Codable {
    case monday
    case firstOfMonth
    case dayAfterHoliday(USHoliday)
    case birthday
}

/// One computed fresh-start day plus every rule that made it qualify.
public struct FreshStartResult: Sendable, Equatable {
    /// Local midnight of the qualifying day.
    public let date: Date
    /// Always non-empty — `nextFreshStart` never returns a `FreshStartResult` for a day that
    /// matched nothing.
    public let occasions: [FreshStartOccasion]

    public init(date: Date, occasions: [FreshStartOccasion]) {
        self.date = date
        self.occasions = occasions
    }
}

/// A birthday's month + day only — see this file's header comment for why no year is stored.
public struct MonthDay: Sendable, Equatable, Hashable, Codable {
    public let month: Int
    public let day: Int

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }
}

// MARK: - Errors

public enum FreshStartSchedulerError: Error, Sendable, Equatable, LocalizedError {
    case invalidMonth(Int)
    case invalidDay(Int, month: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMonth(let month):
            "\(month) is not a valid month (1-12)."
        case .invalidDay(let day, let month):
            "\(day) is not a valid day for month \(month)."
        }
    }
}

// MARK: - FreshStartScheduler

/// Computes the next fresh-start date (spec §8 rule 6) and stores the one small piece of state
/// this file needs that has nowhere else to live yet: the user's birthday (see header comment).
///
/// `@MainActor`, matching every other engine in this same directory (`CalendarAwareness`,
/// `TravelMode`, `ComebackMode`, `StreakEngine`) for the identical reason each documents at its own
/// declaration: under Swift 6 strict concurrency a plain `final class` singleton needs either
/// `Sendable` conformance or global-actor isolation, and every realistic call site is already
/// `@MainActor` or happy to `await` a hop onto it. Owns no `ModelContext` (nothing here needs
/// SwiftData — see header comment on birthday storage), unlike most of this directory's other
/// engines.
@MainActor
public final class FreshStartScheduler {
    public static let shared = FreshStartScheduler()

    /// Gregorian explicitly, not `Calendar.current` (which can be a non-Gregorian calendar
    /// depending on the user's Region setting) — spec's holiday list and "the 1st"/"Mondays" rules
    /// are Gregorian-calendar concepts, and computing them against e.g. a Buddhist or Hebrew
    /// calendar identifier would silently produce the wrong dates. `.current` time zone only.
    nonisolated public static let defaultCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private let calendar: Calendar

    /// Separate, App-Group-backed `UserDefaults` instance (same suite `Store/SharedDefaults.swift`
    /// uses, a different file this task does not own), keyed distinctly from every key that file/
    /// `StreakEngine`/`ComebackMode`/`CalendarAwareness`/`OnboardingDripScheduler` (this task's
    /// other file) define so none of them can ever collide despite sharing the same suite.
    private let birthdayDefaults: UserDefaults
    private static let birthdayMonthKey = "com.zano.app.freshStartScheduler.birthdayMonth"
    private static let birthdayDayKey = "com.zano.app.freshStartScheduler.birthdayDay"

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an injected calendar/defaults suite; every real call site uses `.shared`.
    init(calendar: Calendar = FreshStartScheduler.defaultCalendar, userDefaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.calendar = calendar
        self.birthdayDefaults = userDefaults
    }

    // MARK: - Birthday storage (see header comment for why this lives here, not on `User`)

    /// The stored birthday, if the user has ever set one. `nil` before `setBirthday(month:day:)`
    /// is ever called, or after `clearBirthday()`.
    public var birthday: MonthDay? {
        let month = birthdayDefaults.integer(forKey: Self.birthdayMonthKey)
        let day = birthdayDefaults.integer(forKey: Self.birthdayDayKey)
        guard month > 0, day > 0 else { return nil }
        return MonthDay(month: month, day: day)
    }

    /// Validates and stores the user's birthday. `day` is checked against the *leap-year* maximum
    /// for `month` (so Feb 29 is accepted) — `occasions(on:)` handles observing a Feb 29 birthday
    /// on Feb 28 in a non-leap year, see `matchesBirthday`.
    public func setBirthday(month: Int, day: Int) throws {
        guard (1...12).contains(month) else {
            throw FreshStartSchedulerError.invalidMonth(month)
        }
        let maxDay = daysInMonth(month, isLeapYear: true)
        guard (1...maxDay).contains(day) else {
            throw FreshStartSchedulerError.invalidDay(day, month: month)
        }
        birthdayDefaults.set(month, forKey: Self.birthdayMonthKey)
        birthdayDefaults.set(day, forKey: Self.birthdayDayKey)
    }

    /// "Not now"/"turn this off" — mirrors `CalendarAwareness.optOut()`'s "no penalty for
    /// declining/reversing" convention (spec §8 rule 9's spirit applies to *any* optional personal
    /// detail this app asks for, not only to missed goals).
    public func clearBirthday() {
        birthdayDefaults.removeObject(forKey: Self.birthdayMonthKey)
        birthdayDefaults.removeObject(forKey: Self.birthdayDayKey)
    }

    // MARK: - Public: instance API (reads the stored birthday; see the static API below for the
    // pure, birthday-as-parameter version everything here actually delegates to)

    /// Every fresh-start rule `date` matches, using the currently stored `birthday`. Empty if
    /// `date` is not a fresh-start day at all.
    public func occasions(on date: Date = .now) -> [FreshStartOccasion] {
        Self.occasions(on: date, birthday: birthday, calendar: calendar)
    }

    public func isFreshStart(_ date: Date = .now) -> Bool {
        !occasions(on: date).isEmpty
    }

    /// The next fresh-start date at or after `date` (spec §8 rule 6) — what a challenge-launch
    /// call site (§5.9, out of this task's scope) consults to decide when to push. See this file's
    /// header comment for why this file stops at exposing the date rather than sending anything.
    ///
    /// - Parameter includingToday: `true` (the default) returns `date`'s own day if it already
    ///   qualifies (e.g. calling this on a Monday morning returns today); `false` always looks
    ///   strictly after `date`'s day, for a caller that already handled today and wants to know
    ///   what's next.
    public func nextFreshStart(from date: Date = .now, includingToday: Bool = true) -> FreshStartResult? {
        Self.nextFreshStart(from: date, includingToday: includingToday, birthday: birthday, calendar: calendar)
    }

    // MARK: - Public: pure static API (no stored state — a caller/test can pass any birthday,
    // matching `CalendarAwareness.isPacked(eventCount:threshold:)`'s established "split the pure
    // calculation out from the I/O-touching shell around it" convention in this same directory)

    /// Every fresh-start rule `date` matches. `nonisolated`, pure, and side-effect-free: touches no
    /// actor-isolated state, so it's trivially unit-testable and callable from any isolation
    /// domain without an `await` hop.
    nonisolated public static func occasions(
        on date: Date,
        birthday: MonthDay?,
        holidays: [USHoliday] = USHoliday.allCases,
        calendar: Calendar = FreshStartScheduler.defaultCalendar
    ) -> [FreshStartOccasion] {
        let day = calendar.startOfDay(for: date)
        var result: [FreshStartOccasion] = []

        if calendar.component(.weekday, from: day) == mondayWeekday {
            result.append(.monday)
        }
        if calendar.component(.day, from: day) == 1 {
            result.append(.firstOfMonth)
        }

        let year = calendar.component(.year, from: day)
        for holiday in holidays {
            // Checks both `year` and `year - 1`: a holiday late enough in December that "the day
            // after" rolls into January of the next year would otherwise be missed when `day`
            // itself falls in that next year. None of `USHoliday`'s current dates are late enough
            // in December to actually cross a year boundary (Christmas Dec 25 + 1 = Dec 26, same
            // year), but checking both is correct-by-construction rather than relying on that
            // staying true if this list ever grows.
            let matchesThisHoliday = [year, year - 1].contains { candidateYear in
                guard let holidayDate = holiday.date(in: candidateYear, calendar: calendar),
                      let dayAfter = calendar.date(byAdding: .day, value: 1, to: holidayDate)
                else { return false }
                return calendar.isDate(dayAfter, inSameDayAs: day)
            }
            if matchesThisHoliday {
                result.append(.dayAfterHoliday(holiday))
            }
        }

        if let birthday, matchesBirthday(day, birthday, calendar: calendar) {
            result.append(.birthday)
        }

        return result
    }

    /// The earliest date at or after (or strictly after, see `includingToday`) `date` that matches
    /// any fresh-start rule. Every rule set here recurs within a year at most (a birthday, in the
    /// worst case), and a Monday alone recurs within 6 days, so `searchLimitDays`'s default is a
    /// generous safety bound against an unexpected `calendar`/`holidays` combination that matches
    /// nothing at all, not a bound this is expected to ever actually hit in practice.
    ///
    /// - Returns: `nil` only if `searchLimitDays` is exhausted without finding a match (should not
    ///   happen with the default `holidays`/`searchLimitDays` — `.monday` alone guarantees a hit
    ///   within a week) or if `calendar` cannot advance a date at all (not expected for any real
    ///   Gregorian calendar).
    nonisolated public static func nextFreshStart(
        from date: Date,
        includingToday: Bool = true,
        birthday: MonthDay?,
        holidays: [USHoliday] = USHoliday.allCases,
        calendar: Calendar = FreshStartScheduler.defaultCalendar,
        searchLimitDays: Int = 400
    ) -> FreshStartResult? {
        var day = calendar.startOfDay(for: date)
        if !includingToday {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }

        for _ in 0..<searchLimitDays {
            let found = occasions(on: day, birthday: birthday, holidays: holidays, calendar: calendar)
            if !found.isEmpty {
                return FreshStartResult(date: day, occasions: found)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}

// MARK: - Private calendar math (file-scope, not actor-isolated — see below)

// Foundation's `.weekday` component: 1 = Sunday ... 7 = Saturday, for the Gregorian calendar
// regardless of `Calendar.firstWeekday` (that property only affects week-of-year/ordering
// computations, not what `.weekday` itself reports).
private let mondayWeekday = 2
private let thursdayWeekday = 5

private func fixedDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
}

/// The `n`th occurrence of `weekday` in `month` of `year` (`n` starting at 1). Uses
/// `DateComponents.weekdayOrdinal`, Foundation's documented mechanism for exactly this — "the 4th
/// Thursday of November" (Thanksgiving) is the textbook example of this API.
private func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: n))
}

/// The *last* occurrence of `weekday` in `month` of `year` (e.g. Memorial Day: the last Monday of
/// May). Deliberately does not use `weekdayOrdinal: -1` for "last" — unlike the positive-`n` case
/// above, this task could not verify from training knowledge alone, with no Mac/current Apple
/// documentation available (CLAUDE.md rule 5), that a negative `weekdayOrdinal` is guaranteed
/// Foundation behavior. This instead walks backward from the month's last calendar day to the
/// nearest matching weekday — correct by construction from `Calendar.range(of:in:for:)` alone, with
/// no dependency on that unverified behavior.
private func lastWeekday(_ weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
    guard
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth),
        var day = calendar.date(from: DateComponents(year: year, month: month, day: range.count))
    else { return nil }

    for _ in 0..<7 {
        if calendar.component(.weekday, from: day) == weekday { return day }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        day = previous
    }
    return nil
}

private func daysInMonth(_ month: Int, isLeapYear: Bool) -> Int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: 31
    case 4, 6, 9, 11: 30
    case 2: isLeapYear ? 29 : 28
    default: 0
    }
}

private func isLeapYear(_ year: Int, calendar: Calendar) -> Bool {
    guard
        let firstOfMarch = calendar.date(from: DateComponents(year: year, month: 3, day: 1)),
        let lastOfFebruary = calendar.date(byAdding: .day, value: -1, to: firstOfMarch)
    else { return false }
    return calendar.component(.day, from: lastOfFebruary) == 29
}

/// `date` (already normalized to local midnight by the caller) matches `birthday`'s month/day.
/// A Feb 29 birthday is observed on Feb 28 in a non-leap year — a documented choice, not the only
/// defensible one (some conventions instead observe it Mar 1), but the more common one.
private func matchesBirthday(_ date: Date, _ birthday: MonthDay, calendar: Calendar) -> Bool {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else { return false }

    if birthday.month == month && birthday.day == day { return true }
    if birthday.month == 2, birthday.day == 29, month == 2, day == 28 {
        return !isLeapYear(year, calendar: calendar)
    }
    return false
}
