// Core/Sources/Core/Social/NudgeScheduler.swift
//
// docs/spec.md §8 rule 7 ("Nudge scarcity. Max 2 proactive pushes/day. A nudge must change what
// the user does tonight or it doesn't send.") and §9.3 (Nudge Optimizer: timing slots morning /
// pre-gym / 4 PM / evening, "Respect the 2/day cap"). §9.6 puts the weekly recap job at Sunday
// 6 PM, so the recap nudge goes out an hour later, once the card exists.
//
// `NudgeSender` owns the cap, the preferences and the `Nudge` rows; nothing scheduled the four
// `NudgeKind`s. This file does, as local notifications only (local-first, no networking, no
// background tasks). Call `reschedule()` on every app foreground and after every goal event:
// each call removes this file's own pending requests (identifier prefix `zano.nudge.`) and plans
// the next ones from current state, so a goal finished at 6 PM takes tonight's nudge with it.
//
// The decision is `plan(_:)`, a pure function of plain values so it can be tested without
// `UNUserNotificationCenter`. Rules as implemented:
//   - morningPlan: next morning occurrence at `morningMinutes` (8:00, or 15 min after the Sunrise
//     Alarm wake time when the user has an active Sunrise Alarm goal and the alarm is on). Only
//     when there is at least one daily goal. Body lists the goals.
//   - proteinLastMile: today 18:30, only when a protein goal is open with at least 40% logged
//     (close enough to finish tonight). Body says how much is left ("40g to go").
//   - streakAtRisk: today 20:00, only when the streak is above 0 and a daily goal is still open.
//   - weeklyRecap: next Sunday 19:00.
//   - Quiet hours: morningPlan and weeklyRecap move to the end of quiet hours (morningPlan is
//     dropped if that lands after noon or on another day); proteinLastMile and streakAtRisk are
//     about tonight, so they're dropped instead of moved to tomorrow.
//   - Nudges off, the kind switched off, or a health pause active now: nothing is scheduled.
//   - Cap: per calendar day, at most `NudgeSender.dailyCap` minus what's already delivered or
//     scheduled that day. When there are more candidates than room: streakAtRisk >
//     proteinLastMile > morningPlan > weeklyRecap.
//   - A time already passed today is skipped (morningPlan and weeklyRecap roll to the next one).
//
// Bookkeeping: each scheduled nudge is written through `NudgeSender.recordScheduled` (see the
// comment there) and the row's id is part of the notification identifier, so cancelling a pending
// notification also deletes its row. "Daily goals" are active goals whose cadence doesn't say
// "week" (a weekly meal prep can't be open "today").
//
// Tapping a nudge opens the app through `userInfo["deepLink"]`, the key `ZANONotificationDelegate`
// already routes. Links: `zano://today`, `zano://goals`, `zano://fuel`, `zano://progress`.
//
// SMART TIMING (2026-10-02; research items 2, 4 and 10 in docs/design/growth-and-ml-research.md):
//   - Timing bandit. morningPlan, proteinLastMile and streakAtRisk each have a few candidate times
//     ("arms"); which one fires is chosen by Thompson sampling over a Beta(α, β) per arm
//     (`NudgeTimingBandit`, persisted in the App Group). Reward = the user completed a verified
//     goal within the 3-hour attribution window (`NudgeSender.scoreExpiredAttributionWindows`).
//     The draw is seeded per (install, day, kind), so rescheduling ten times a day keeps the same
//     choice instead of jittering. The default time of each kind (the old fixed time) starts with
//     a small prior edge; weights forget slowly (×0.97 per update) because nudge effects decay
//     over weeks (HeartSteps). The weekly recap stays fixed at Sunday 19:00.
//   - If-then plan (`ImplementationPlan`). On a planned day, "45 minutes before the planned time"
//     is an extra arm with a strong prior. It belongs to morningPlan when it falls before noon,
//     otherwise to streakAtRisk, and uses the plan's own reminder copy. It needs no streak.
//   - Slip risk (`SlipRisk`). The usual streak-at-risk times only qualify when today's score is
//     at least `SlipRisk.streakNudgeThreshold`; a low-risk evening gets no streak nudge.
//   - Weekly recap. `WeeklyRecapBuilder.buildIfDue()` runs at the start of every pass, and the
//     Sunday nudge is skipped when the week has no data (an empty recap is worse than none).
//   - A kind that already fired today is not planned again today (`firedKindsToday`).
// Everything else above (2/day cap, quiet hours, health pause, priorities) is unchanged. Without
// a bandit, plan or risk in the inputs, `plan(_:)` behaves exactly as before.
//
// Each pass also closes expired attribution windows first and feeds them to the bandit, so that
// happens on every foreground with no extra call site.

import Foundation
import SwiftData
import UserNotifications
import os

// MARK: - Planning inputs and output

/// Everything `NudgeScheduler.plan(_:)` decides from, as plain values.
public struct NudgeScheduleInputs: Sendable, Equatable {
    /// Today's protein goal.
    public struct Protein: Sendable, Equatable {
        public var logged: Double
        public var target: Double
        public var isComplete: Bool

        public init(logged: Double, target: Double, isComplete: Bool = false) {
            self.logged = logged
            self.target = target
            self.isComplete = isComplete
        }

        /// Rounded up, never negative.
        public var amountToGo: Int { max(0, Int((target - logged).rounded(.up))) }
    }

    public var now: Date
    public var calendar: Calendar
    public var preferences: NudgePreferences
    /// A health pause is active right now.
    public var healthPaused: Bool
    /// Nudges already delivered or scheduled, keyed by `calendar.startOfDay`. Missing days count 0.
    public var deliveredByDay: [Date: Int]
    /// Minutes after midnight for the morning plan.
    public var morningMinutes: Int
    /// How many daily goals the morning plan would list.
    public var dailyGoalCount: Int
    /// `nil` when there is no protein goal (or it has no target).
    public var protein: Protein?
    public var streak: Int
    /// Daily goals not yet complete today.
    public var openGoalsToday: Int
    /// Today's slip-risk score (`SlipRisk`). `nil` = no risk gate (the old behaviour).
    public var slipRisk: Double?
    /// Earliest if-then-plan minute per planned day, keyed by `calendar.startOfDay` (today and
    /// tomorrow are enough). Missing day = nothing planned.
    public var plannedMinutesByDay: [Date: Int]
    /// The timing bandit. `nil` = each kind fires at its fixed default time (the old behaviour).
    public var bandit: NudgeTimingBandit?
    /// Per-install salt for the bandit's per-day draws.
    public var banditSeed: UInt64
    /// Kinds that already fired today (so a later arm doesn't send the same kind twice).
    public var firedKindsToday: Set<NudgeKind>
    /// Whether the week the next Sunday recap covers has any data; no data, no recap nudge.
    public var recapWeekHasData: Bool

    public init(
        now: Date,
        calendar: Calendar = .current,
        preferences: NudgePreferences = NudgePreferences(),
        healthPaused: Bool = false,
        deliveredByDay: [Date: Int] = [:],
        morningMinutes: Int = NudgeScheduler.defaultMorningMinutes,
        dailyGoalCount: Int = 0,
        protein: Protein? = nil,
        streak: Int = 0,
        openGoalsToday: Int = 0,
        slipRisk: Double? = nil,
        plannedMinutesByDay: [Date: Int] = [:],
        bandit: NudgeTimingBandit? = nil,
        banditSeed: UInt64 = 0,
        firedKindsToday: Set<NudgeKind> = [],
        recapWeekHasData: Bool = true
    ) {
        self.now = now
        self.calendar = calendar
        self.preferences = preferences
        self.healthPaused = healthPaused
        self.deliveredByDay = deliveredByDay
        self.morningMinutes = morningMinutes
        self.dailyGoalCount = dailyGoalCount
        self.protein = protein
        self.streak = streak
        self.openGoalsToday = openGoalsToday
        self.slipRisk = slipRisk
        self.plannedMinutesByDay = plannedMinutesByDay
        self.bandit = bandit
        self.banditSeed = banditSeed
        self.firedKindsToday = firedKindsToday
        self.recapWeekHasData = recapWeekHasData
    }

    func delivered(on date: Date) -> Int {
        deliveredByDay[calendar.startOfDay(for: date)] ?? 0
    }
}

/// One nudge the planner decided to schedule.
public struct PlannedNudge: Sendable, Equatable {
    public let kind: NudgeKind
    public let fireDate: Date
    /// The timing arm that produced it (`NudgeTimeArm.id`); `nil` for the weekly recap.
    public let armID: String?

    public init(kind: NudgeKind, fireDate: Date, armID: String? = nil) {
        self.kind = kind
        self.fireDate = fireDate
        self.armID = armID
    }

    /// The if-then plan reminder rather than a regular nudge of `kind`.
    public var isPlanReminder: Bool { armID == NudgeTimeArm.beforePlan.id }
}

// MARK: - NudgeScheduler

/// `@MainActor`, like `NudgeSender` and `OnboardingDripScheduler`, which it calls into.
@MainActor
public final class NudgeScheduler {
    public static let shared = NudgeScheduler()

    // Times, in minutes after local midnight.
    public nonisolated static let defaultMorningMinutes = 8 * 60
    nonisolated static let latestMorningMinutes = 12 * 60
    nonisolated static let sunriseMorningOffsetMinutes = 15
    nonisolated static let proteinMinutes = 18 * 60 + 30
    nonisolated static let streakMinutes = 20 * 60
    nonisolated static let recapMinutes = 19 * 60
    /// Gregorian weekday numbering: 1 is Sunday.
    nonisolated static let recapWeekday = 1
    /// "Last mile": at least this share of the protein target is logged.
    nonisolated static let lastMileMinimumFraction = 0.4

    /// Highest priority first; used when a day has more candidates than the cap allows.
    nonisolated static let priority: [NudgeKind] = [.streakAtRisk, .proteinLastMile, .morningPlan, .weeklyRecap]

    /// Every pending request this file owns starts with this. Full form:
    /// `zano.nudge.<kind raw value>.<Nudge row UUID>`.
    nonisolated public static let identifierPrefix = "zano.nudge."
    /// `userInfo` key holding the `NudgeKind` raw value.
    nonisolated public static let kindUserInfoKey = "zano.nudge"
    /// The key `ZANONotificationDelegate` routes taps by (`NotificationRouting.deepLinkUserInfoKey`).
    nonisolated static let deepLinkUserInfoKey = "deepLink"

    private let modelContainer: ModelContainer
    private let sender: NudgeSender
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "NudgeScheduler")

    /// Overlapping calls (a foreground and a goal event together) run one after another instead
    /// of interleaving their remove/add steps.
    private var isRescheduling = false
    private var needsAnotherPass = false

    /// Builds the weekly recap before each pass (see header).
    private let recapBuilder: WeeklyRecapBuilder

    /// `internal` so tests can build an isolated instance; the app uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, sender: NudgeSender? = nil) {
        self.modelContainer = modelContainer
        self.sender = sender ?? .shared
        self.recapBuilder = WeeklyRecapBuilder(modelContainer: modelContainer)
    }

    // MARK: - Public

    /// Replaces this file's pending nudges with a fresh plan. Cheap; never throws.
    public func reschedule(now: Date = .now) async {
        if isRescheduling {
            needsAnotherPass = true
            return
        }
        isRescheduling = true
        defer { isRescheduling = false }

        var passNow = now
        repeat {
            needsAnotherPass = false
            await reschedulePass(now: passNow)
            passNow = .now
        } while needsAnotherPass
    }

    // MARK: - Planning (pure)

    /// Which nudges to schedule, sorted by fire date. See this file's header for the rules.
    public nonisolated static func plan(_ inputs: NudgeScheduleInputs) -> [PlannedNudge] {
        let prefs = inputs.preferences
        guard !inputs.healthPaused, prefs.enabled else { return [] }
        let now = inputs.now
        let calendar = inputs.calendar
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)

        var candidates: [PlannedNudge] = []
        func add(_ nudge: PlannedNudge?) {
            if let nudge { candidates.append(nudge) }
        }
        func notFiredToday(_ kind: NudgeKind) -> Bool {
            !inputs.firedKindsToday.contains(kind)
        }

        if inputs.dailyGoalCount > 0, prefs.isEnabled(.morningPlan) {
            var morning: PlannedNudge?
            if notFiredToday(.morningPlan) {
                morning = choose(.morningPlan, on: today, inputs: inputs)
            }
            if morning == nil, let tomorrow {
                morning = choose(.morningPlan, on: tomorrow, inputs: inputs)
            }
            add(morning)
        }

        if let protein = inputs.protein, protein.target > 0, !protein.isComplete,
           prefs.isEnabled(.proteinLastMile), notFiredToday(.proteinLastMile) {
            let fraction = protein.logged / protein.target
            if fraction >= lastMileMinimumFraction, fraction < 1 {
                add(choose(.proteinLastMile, on: today, inputs: inputs))
            }
        }

        if inputs.openGoalsToday > 0, prefs.isEnabled(.streakAtRisk), notFiredToday(.streakAtRisk) {
            add(choose(.streakAtRisk, on: today, inputs: inputs))
        }

        if inputs.recapWeekHasData, prefs.isEnabled(.weeklyRecap),
           let recap = calendar.nextDate(
               after: now,
               matching: DateComponents(hour: recapMinutes / 60, minute: recapMinutes % 60, weekday: recapWeekday),
               matchingPolicy: .nextTime
           ),
           let placed = placeOutsideQuietHours(.weeklyRecap, at: recap, inputs: inputs),
           placed > now {
            add(PlannedNudge(kind: .weeklyRecap, fireDate: placed))
        }

        // The cap, highest priority first.
        let ranked = candidates.sorted { rank($0.kind) < rank($1.kind) }
        var usedByDay: [Date: Int] = [:]
        var kept: [PlannedNudge] = []
        for candidate in ranked {
            let day = calendar.startOfDay(for: candidate.fireDate)
            let used = usedByDay[day, default: 0]
            guard inputs.delivered(on: day) + used < NudgeSender.dailyCap else { continue }
            usedByDay[day] = used + 1
            kept.append(candidate)
        }
        return kept.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Arms

    /// How long before a planned time the plan reminder fires.
    public nonisolated static let planReminderLeadMinutes = 45

    /// Candidate times per kind when the bandit is on. The first is the old fixed time.
    nonisolated static func fixedArms(for kind: NudgeKind) -> [Int] {
        switch kind {
        case .morningPlan: [defaultMorningMinutes, 7 * 60 + 30, 9 * 60]
        case .proteinLastMile: [proteinMinutes, 17 * 60, 19 * 60 + 30]
        case .streakAtRisk: [streakMinutes, 18 * 60, 19 * 60]
        case .weeklyRecap: [recapMinutes]
        }
    }

    /// The old fixed time for `kind` (also the arm with a small prior edge).
    nonisolated static func defaultMinutes(for kind: NudgeKind, inputs: NudgeScheduleInputs) -> Int {
        kind == .morningPlan ? inputs.morningMinutes : fixedArms(for: kind)[0]
    }

    /// The arms available for `kind` on `day`, each with where it would actually fire (after quiet
    /// hours), keeping only those still in the future.
    nonisolated static func availableArms(
        _ kind: NudgeKind,
        on day: Date,
        inputs: NudgeScheduleInputs
    ) -> [(arm: NudgeTimeArm, fire: Date)] {
        let calendar = inputs.calendar
        var arms: [NudgeTimeArm] = []

        // Fixed times.
        let sunriseOverride = kind == .morningPlan && inputs.morningMinutes != defaultMorningMinutes
        let fixedAllowed: Bool
        switch kind {
        case .streakAtRisk:
            fixedAllowed = inputs.streak > 0 && (inputs.slipRisk.map { $0 >= SlipRisk.streakNudgeThreshold } ?? true)
        case .morningPlan, .proteinLastMile, .weeklyRecap:
            fixedAllowed = true
        }
        if fixedAllowed {
            if inputs.bandit == nil || sunriseOverride {
                arms.append(.fixed(minutes: defaultMinutes(for: kind, inputs: inputs)))
            } else {
                arms += fixedArms(for: kind).map { .fixed(minutes: $0) }
            }
        }

        // The if-then plan reminder: before noon it's a morning nudge, after it an evening one.
        var planFire: Date?
        if !sunriseOverride, let planned = inputs.plannedMinutesByDay[calendar.startOfDay(for: day)] {
            let reminder = planned - planReminderLeadMinutes
            let owner: NudgeKind = reminder < latestMorningMinutes ? .morningPlan : .streakAtRisk
            if reminder >= 0, owner == kind, let fire = clockTime(reminder, on: day, calendar: calendar),
               !inputs.preferences.isQuiet(at: fire, calendar: calendar) {
                arms.append(.beforePlan)
                planFire = fire
            }
        }

        return arms.compactMap { arm in
            let fire: Date?
            switch arm {
            case .beforePlan:
                fire = planFire
            case .fixed(let minutes):
                fire = clockTime(minutes, on: day, calendar: calendar)
                    .flatMap { placeOutsideQuietHours(kind, at: $0, inputs: inputs) }
            }
            guard let fire, fire > inputs.now else { return nil }
            return (arm, fire)
        }
    }

    /// Picks one arm for `kind` on `day`: Thompson sampling when there's a bandit (seeded per
    /// install, day and kind), otherwise the plan reminder if available, else the default time.
    nonisolated static func choose(_ kind: NudgeKind, on day: Date, inputs: NudgeScheduleInputs) -> PlannedNudge? {
        let available = availableArms(kind, on: day, inputs: inputs)
        guard !available.isEmpty else { return nil }

        let picked: (arm: NudgeTimeArm, fire: Date)?
        if let bandit = inputs.bandit {
            var rng = SeededGenerator(seed: drawSeed(inputs.banditSeed, day: day, kind: kind, calendar: inputs.calendar))
            let chosen = bandit.choose(kind: kind, among: available.map { $0.arm }, using: &rng)
            picked = available.first { $0.arm == chosen }
        } else {
            picked = available.first { $0.arm == .beforePlan } ?? available.first
        }
        guard let picked else { return nil }
        return PlannedNudge(kind: kind, fireDate: picked.fire, armID: picked.arm.id)
    }

    /// Stable per (install, local day, kind).
    nonisolated static func drawSeed(_ seed: UInt64, day: Date, kind: NudgeKind, calendar: Calendar) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let dayNumber = UInt64(max(0, (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)))
        let kindIndex = UInt64(NudgeKind.allCases.firstIndex(of: kind) ?? 0)
        return seed ^ (dayNumber &* 0x9E37_79B9_7F4A_7C15) ^ (kindIndex &* 0xBF58_476D_1CE4_E5B9)
    }

    private nonisolated static func rank(_ kind: NudgeKind) -> Int {
        priority.firstIndex(of: kind) ?? priority.count
    }

    private nonisolated static func clockTime(_ minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// `fire` itself when it's outside quiet hours; otherwise the end of quiet hours for kinds that
    /// can wait, or `nil` for kinds about tonight.
    private nonisolated static func placeOutsideQuietHours(
        _ kind: NudgeKind,
        at fire: Date,
        inputs: NudgeScheduleInputs
    ) -> Date? {
        let prefs = inputs.preferences
        let calendar = inputs.calendar
        guard prefs.isQuiet(at: fire, calendar: calendar) else { return fire }

        switch kind {
        case .proteinLastMile, .streakAtRisk:
            return nil
        case .morningPlan, .weeklyRecap:
            let endMinutes = prefs.quietEndMinutes
            guard var shifted = clockTime(endMinutes, on: fire, calendar: calendar) else { return nil }
            if shifted <= fire {
                guard let next = calendar.date(byAdding: .day, value: 1, to: shifted) else { return nil }
                shifted = next
            }
            guard !prefs.isQuiet(at: shifted, calendar: calendar) else { return nil }
            if kind == .morningPlan {
                guard calendar.isDate(shifted, inSameDayAs: fire), endMinutes < latestMorningMinutes else { return nil }
            }
            return shifted
        }
    }

    // MARK: - One pass

    private func reschedulePass(now: Date) async {
        let center = UNUserNotificationCenter.current()

        // 0. Learn and refresh, whether or not notifications are allowed: score nudges whose
        //    3-hour window has closed and feed the bandit, refresh the slip-risk signals, and
        //    write the weekly recap if it's due (so Progress is never empty on Sunday night).
        await learnFromClosedWindows(now: now)
        SlipRisk.refreshSignals(modelContainer: modelContainer, now: now, calendar: calendar)
        recapBuilder.buildIfDue(now: now)

        // 1. Take back everything still pending, rows included, so the counts below are real.
        // Via a nonisolated helper: a callback written here would be main-actor isolated and trap
        // when the center calls it off the main queue.
        let pendingIDs = await NotificationCenterQueries.pendingIdentifiers()
        let ours = pendingIDs.filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
            let ids = ours.compactMap(Self.nudgeID(fromIdentifier:))
            sender.cancelScheduled(nudgeIDs: ids, notFiredBy: now)
            var ledger = NudgeTimingLedger.current
            ledger.cancel(ids, notFiredBy: now)
            NudgeTimingLedger.current = ledger
        }

        // 2. Only schedule what the user will actually see. Permission is asked in onboarding
        //    (the first-win step, on Start), never from here.
        let authorized = await NotificationCenterQueries.canPostNotifications()
        guard authorized else { return }

        // 3. Plan and schedule.
        guard let snapshot = await makeSnapshot(now: now) else { return }
        let planned = Self.plan(snapshot.inputs)
        for nudge in planned {
            await schedule(nudge, snapshot: snapshot)
        }
        if !planned.isEmpty {
            let summary = planned.map { $0.kind.rawValue + "@" + ($0.armID ?? "fixed") }.joined(separator: ",")
            logger.notice("Scheduled \(planned.count, privacy: .public) nudge(s): \(summary, privacy: .public).")
        }
    }

    /// Closes expired attribution windows and turns each outcome into a bandit reward.
    private func learnFromClosedWindows(now: Date) async {
        let outcomes: [NudgeSender.AttributionOutcome]
        do {
            outcomes = try await sender.scoreExpiredAttributionWindows(asOf: now)
        } catch {
            logger.error("Attribution scoring failed: \(String(describing: error), privacy: .public)")
            return
        }
        var ledger = NudgeTimingLedger.current
        var bandit = NudgeTimingBandit.current
        var learned = 0
        for outcome in outcomes {
            guard let entry = ledger.markScored(outcome.nudgeID) else { continue }
            bandit.record(kind: entry.kind, armID: entry.armID, acted: outcome.acted)
            learned += 1
        }
        ledger.prune(now: now, calendar: calendar)
        NudgeTimingLedger.current = ledger
        if learned > 0 {
            NudgeTimingBandit.current = bandit
            logger.notice("Bandit learned from \(learned, privacy: .public) nudge outcome(s).")
        }
    }

    private func schedule(_ nudge: PlannedNudge, snapshot: Snapshot) async {
        let arm = NudgeArm(tone: snapshot.tone, timingSlot: Self.timingSlot(at: nudge.fireDate), format: .push)
        let nudgeID: UUID
        do {
            nudgeID = try sender.recordScheduled(arm: arm, fireDate: nudge.fireDate)
        } catch {
            logger.error("Could not record \(nudge.kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        let copy = Self.copy(for: nudge, snapshot: snapshot, calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = [
            Self.kindUserInfoKey: nudge.kind.rawValue,
            Self.deepLinkUserInfoKey: nudge.isPlanReminder ? Self.planReminderDeepLink : Self.deepLink(for: nudge.kind),
        ]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        nonisolated(unsafe) let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)\(nudge.kind.rawValue).\(nudgeID.uuidString)",
            content: content,
            trigger: trigger
        )
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
            if let armID = nudge.armID {
                var ledger = NudgeTimingLedger.current
                ledger.record(nudgeID: nudgeID, kind: nudge.kind, armID: armID, fireDate: nudge.fireDate)
                NudgeTimingLedger.current = ledger
            }
        } catch {
            sender.cancelScheduled(nudgeIDs: [nudgeID], notFiredBy: .now)
            logger.error("Could not schedule \(nudge.kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Rendering helpers

    nonisolated static func nudgeID(fromIdentifier identifier: String) -> UUID? {
        guard let last = identifier.split(separator: ".").last else { return nil }
        return UUID(uuidString: String(last))
    }

    /// Existing `AppRouter` links only. Protein and recap would fit `zano://fuel` and
    /// `zano://progress` better; neither exists yet, so they open Today.
    nonisolated static func deepLink(for kind: NudgeKind) -> String {
        switch kind {
        case .streakAtRisk: "zano://goals"
        case .morningPlan: "zano://today"
        case .proteinLastMile: "zano://fuel"
        case .weeklyRecap: "zano://progress"
        }
    }

    /// Plan reminders open Today, where the goal's own controls live.
    nonisolated static let planReminderDeepLink = "zano://today"

    private static func copy(for nudge: PlannedNudge, snapshot: Snapshot, calendar: Calendar) -> (title: String, body: String) {
        let inputs = snapshot.inputs
        if nudge.isPlanReminder, let entry = snapshot.plan?.entries(on: nudge.fireDate, calendar: calendar).first,
           let planned = clockTime(entry.minuteOfDay, on: nudge.fireDate, calendar: calendar) {
            let minutesBefore = max(1, Int(planned.timeIntervalSince(nudge.fireDate) / 60))
            return Copy.ifThenPlan.reminder(
                tone: snapshot.tone,
                goalType: entry.goalType,
                time: planned.formatted(date: .omitted, time: .shortened),
                minutesBefore: minutesBefore
            )
        }
        switch nudge.kind {
        case .morningPlan:
            return Copy.nudges.morningPlan(tone: snapshot.tone, goalTitles: snapshot.dailyGoalTitles)
        case .proteinLastMile:
            return Copy.nudges.proteinLastMile(
                tone: snapshot.tone,
                amountToGo: inputs.protein?.amountToGo ?? 0,
                unit: snapshot.proteinUnit
            )
        case .streakAtRisk:
            return Copy.nudges.streakAtRisk(tone: snapshot.tone, streak: inputs.streak, goalsOpen: inputs.openGoalsToday)
        case .weeklyRecap:
            return Copy.nudges.weeklyRecap(tone: snapshot.tone)
        }
    }

    /// Same hour buckets as `OnboardingDripScheduler.timingSlot(at:)` (private there).
    nonisolated static func timingSlot(at date: Date) -> NudgeTimingSlot {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .morning
        case 11..<16: .preGymWindow
        case 16..<18: .afternoon4pm
        default: .evening
        }
    }

    // MARK: - Reading state

    private struct Snapshot {
        let inputs: NudgeScheduleInputs
        let tone: NudgeTone
        let dailyGoalTitles: [String]
        let proteinUnit: String
        let plan: ImplementationPlan?
    }

    private func makeSnapshot(now: Date) async -> Snapshot? {
        let context = ModelContext(modelContainer)
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        guard let user = try? context.fetch(userDescriptor).first else { return nil }
        let userID = user.id
        let tone = NudgeTone(rawValue: user.coachVoice.rawValue) ?? .hype

        // Enum and relationship filters stay in Swift (SwiftData predicate crash on enums).
        let activeGoals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active == true }))) ?? []
        let dailyGoals = activeGoals
            .filter { $0.user?.id == userID }
            .filter { !($0.cadence?.lowercased().contains("week") ?? false) }
            .sorted { $0.createdAt < $1.createdAt }

        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= start && $0.ts < end }
        ))) ?? []
        let plans = (try? context.fetch(FetchDescriptor<DailyPlan>(
            predicate: #Predicate<DailyPlan> { $0.date >= start && $0.date < end }
        ))) ?? []

        var openGoals = 0
        var protein: NudgeScheduleInputs.Protein?
        var proteinUnit = "g"
        for goal in dailyGoals {
            let goalEvents = events.filter { $0.goal?.id == goal.id }
            let plan = plans.first { $0.goal?.id == goal.id }
            let plannedValue = plan?.plannedValue
            // A goal switched to Plan B today counts against its smaller target.
            let planBValue = PlanB.acceptedTarget(for: plan, goalID: goal.id, on: now)
            let progress = GoalDayProgress(goal: goal, todaysEvents: goalEvents, plannedValue: plannedValue, planBValue: planBValue)
            if !progress.isComplete { openGoals += 1 }
            if protein == nil, goal.type == .protein, let target = planBValue ?? plannedValue ?? goal.targetValue {
                protein = NudgeScheduleInputs.Protein(logged: progress.loggedAmount, target: target, isComplete: progress.isComplete)
                if let unit = goal.unit, !unit.isEmpty { proteinUnit = unit }
            }
        }

        var morningMinutes = Self.defaultMorningMinutes
        if dailyGoals.contains(where: { $0.type == .sunriseAlarm }) {
            let settings = await SunriseAlarmManager.shared.currentSettings()
            if settings.enabled {
                let wake = calendar.dateComponents([.hour, .minute], from: settings.wakeTime)
                let minutes = (wake.hour ?? 8) * 60 + (wake.minute ?? 0) + Self.sunriseMorningOffsetMinutes
                if minutes < Self.latestMorningMinutes { morningMinutes = minutes }
            }
        }

        // If-then plan: earliest planned minute today and tomorrow.
        let plan = ImplementationPlan.current
        var plannedMinutes: [Date: Int] = [:]
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let minute = plan?.earliestMinute(on: day, calendar: calendar) else { continue }
            plannedMinutes[day] = minute
        }

        // No recap nudge for a week with nothing in it.
        let nextRecap = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: Self.recapMinutes / 60, minute: Self.recapMinutes % 60, weekday: Self.recapWeekday),
            matchingPolicy: .nextTime
        )
        let recapWeekHasData = nextRecap.map { recapBuilder.hasData(weekContaining: $0, now: now) } ?? false

        // The planner looks at most 7 days ahead (the next Sunday recap).
        var deliveredByDay: [Date: Int] = [:]
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            deliveredByDay[day] = sender.deliveredCount(on: day)
        }

        let inputs = NudgeScheduleInputs(
            now: now,
            calendar: calendar,
            preferences: NudgePreferences.current,
            healthPaused: HealthPause.isActive(at: now),
            deliveredByDay: deliveredByDay,
            morningMinutes: morningMinutes,
            dailyGoalCount: dailyGoals.count,
            protein: protein,
            streak: SharedDefaults.currentStreak,
            openGoalsToday: openGoals,
            slipRisk: SlipRisk.score(for: now, calendar: calendar),
            plannedMinutesByDay: plannedMinutes,
            bandit: NudgeTimingBandit.current,
            banditSeed: NudgeTimingBandit.installSeed,
            firedKindsToday: NudgeTimingLedger.current.firedKinds(on: now, now: now, calendar: calendar),
            recapWeekHasData: recapWeekHasData
        )
        return Snapshot(
            inputs: inputs,
            tone: tone,
            dailyGoalTitles: dailyGoals.map(\.title),
            proteinUnit: proteinUnit,
            plan: plan
        )
    }
}

// MARK: - Timing bandit (research item 10)

/// One candidate time for a nudge kind.
public enum NudgeTimeArm: Hashable, Sendable {
    /// A fixed clock time, minutes after midnight.
    case fixed(minutes: Int)
    /// `NudgeScheduler.planReminderLeadMinutes` before the if-then plan's time on a planned day.
    case beforePlan

    /// Stable key for persistence: "t1200" or "plan".
    public var id: String {
        switch self {
        case .fixed(let minutes): "t\(minutes)"
        case .beforePlan: "plan"
        }
    }
}

/// Beta(α, β) belief that an arm's nudge is followed by a goal within the attribution window.
public struct BetaArm: Codable, Sendable, Equatable {
    public var alpha: Double
    public var beta: Double

    public init(alpha: Double, beta: Double) {
        self.alpha = alpha
        self.beta = beta
    }

    public var mean: Double { alpha / (alpha + beta) }
}

/// Thompson sampling over each nudge kind's time arms. Small, pure and `Codable`; the app keeps
/// one in the App Group (`current`).
public struct NudgeTimingBandit: Codable, Sendable, Equatable {
    /// Posteriors keyed "<kind raw value>|<arm id>". Missing = the prior.
    public var arms: [String: BetaArm]

    public init(arms: [String: BetaArm] = [:]) {
        self.arms = arms
    }

    /// Old evidence is multiplied by this on every update of the same arm, so the bandit keeps
    /// adapting as a nudge's effect wears off (HeartSteps saw it decay over weeks).
    public static let forgetting = 0.97

    /// Uninformed arms start at Beta(1, 1). The kind's old default time gets a small edge so a new
    /// user sees the familiar time most often until there's evidence; the plan reminder a strong
    /// one, because the user chose that time themselves.
    public static func prior(kind: NudgeKind, armID: String) -> BetaArm {
        if armID == NudgeTimeArm.beforePlan.id { return BetaArm(alpha: 3, beta: 1) }
        if armID == NudgeTimeArm.fixed(minutes: NudgeScheduler.fixedArms(for: kind)[0]).id {
            return BetaArm(alpha: 2, beta: 1)
        }
        return BetaArm(alpha: 1, beta: 1)
    }

    static func key(_ kind: NudgeKind, _ armID: String) -> String { "\(kind.rawValue)|\(armID)" }

    public func posterior(kind: NudgeKind, armID: String) -> BetaArm {
        arms[Self.key(kind, armID)] ?? Self.prior(kind: kind, armID: armID)
    }

    /// Adds one outcome: reward 1 when the user acted within the window, else 0. Evidence above
    /// the prior decays by `forgetting` first.
    public mutating func record(kind: NudgeKind, armID: String, acted: Bool) {
        let prior = Self.prior(kind: kind, armID: armID)
        let current = posterior(kind: kind, armID: armID)
        let alpha = prior.alpha + (current.alpha - prior.alpha) * Self.forgetting + (acted ? 1 : 0)
        let beta = prior.beta + (current.beta - prior.beta) * Self.forgetting + (acted ? 0 : 1)
        arms[Self.key(kind, armID)] = BetaArm(alpha: alpha, beta: beta)
    }

    /// Draws θ ~ Beta(α, β) for each candidate and returns the arm with the highest draw.
    public func choose<G: RandomNumberGenerator>(kind: NudgeKind, among candidates: [NudgeTimeArm], using rng: inout G) -> NudgeTimeArm? {
        var best: (arm: NudgeTimeArm, draw: Double)?
        for arm in candidates {
            let belief = posterior(kind: kind, armID: arm.id)
            let draw = BetaSampler.sample(alpha: belief.alpha, beta: belief.beta, using: &rng)
            if best == nil || draw > best!.draw { best = (arm, draw) }
        }
        return best?.arm
    }

    // MARK: Persistence (App Group)

    private static let key = "zano.nudgeBandit.v1"
    private static let seedKey = "zano.nudgeBandit.seed.v1"

    public static var current: NudgeTimingBandit {
        get {
            guard let data = SharedDefaults.store.data(forKey: key),
                  let value = try? JSONDecoder().decode(NudgeTimingBandit.self, from: data) else { return NudgeTimingBandit() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedDefaults.store.set(data, forKey: key) }
        }
    }

    /// A random per-install salt, created on first use, so two users' daily draws differ.
    public static var installSeed: UInt64 {
        if let stored = SharedDefaults.store.string(forKey: seedKey), let value = UInt64(stored) { return value }
        let value = UInt64.random(in: 1...UInt64.max)
        SharedDefaults.store.set(String(value), forKey: seedKey)
        return value
    }
}

/// Which arm each scheduled nudge came from, so its outcome can be credited when its attribution
/// window closes (`Nudge` rows don't store the kind or the arm). Also answers "did this kind
/// already fire today?". Entries are dropped 2 days after they fire.
public struct NudgeTimingLedger: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var kind: NudgeKind
        public var armID: String
        public var fireDate: Date
        public var scored: Bool
    }

    /// Keyed by `Nudge.id.uuidString`.
    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public mutating func record(nudgeID: UUID, kind: NudgeKind, armID: String, fireDate: Date) {
        entries[nudgeID.uuidString] = Entry(kind: kind, armID: armID, fireDate: fireDate, scored: false)
    }

    /// Forgets nudges that were cancelled before they fired.
    public mutating func cancel(_ nudgeIDs: [UUID], notFiredBy now: Date) {
        for id in nudgeIDs {
            if let entry = entries[id.uuidString], entry.fireDate > now { entries[id.uuidString] = nil }
        }
    }

    /// Marks a nudge scored and returns its entry, or `nil` if unknown or already scored.
    public mutating func markScored(_ nudgeID: UUID) -> Entry? {
        guard var entry = entries[nudgeID.uuidString], !entry.scored else { return nil }
        entry.scored = true
        entries[nudgeID.uuidString] = entry
        return entry
    }

    /// Kinds with a nudge that has already fired on `date`'s day.
    public func firedKinds(on date: Date, now: Date, calendar: Calendar) -> Set<NudgeKind> {
        Set(entries.values.filter { $0.fireDate <= now && calendar.isDate($0.fireDate, inSameDayAs: date) }.map(\.kind))
    }

    public mutating func prune(now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) else { return }
        entries = entries.filter { $0.value.fireDate >= cutoff }
    }

    private static let key = "zano.nudgeBandit.ledger.v1"

    public static var current: NudgeTimingLedger {
        get {
            guard let data = SharedDefaults.store.data(forKey: key),
                  let value = try? JSONDecoder().decode(NudgeTimingLedger.self, from: data) else { return NudgeTimingLedger() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedDefaults.store.set(data, forKey: key) }
        }
    }
}

// MARK: - Seeded randomness

/// SplitMix64: tiny, fast, and reproducible from a seed (tests and per-day draws).
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Beta draws via two Gamma draws (Marsaglia–Tsang), no dependencies.
enum BetaSampler {
    static func sample<G: RandomNumberGenerator>(alpha: Double, beta: Double, using rng: inout G) -> Double {
        let x = gamma(shape: max(alpha, 1e-3), using: &rng)
        let y = gamma(shape: max(beta, 1e-3), using: &rng)
        let total = x + y
        return total > 0 ? x / total : 0.5
    }

    /// Uniform in (0, 1), never exactly 0 (it goes through `log`).
    static func uniform<G: RandomNumberGenerator>(using rng: inout G) -> Double {
        (Double(rng.next() >> 11) + 0.5) / 9_007_199_254_740_992
    }

    static func normal<G: RandomNumberGenerator>(using rng: inout G) -> Double {
        let u1 = uniform(using: &rng)
        let u2 = uniform(using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    static func gamma<G: RandomNumberGenerator>(shape: Double, using rng: inout G) -> Double {
        if shape < 1 {
            // Boost: Gamma(a) = Gamma(a + 1) · U^(1/a).
            return gamma(shape: shape + 1, using: &rng) * pow(uniform(using: &rng), 1 / shape)
        }
        let d = shape - 1.0 / 3.0
        let c = 1 / (9 * d).squareRoot()
        while true {
            var x: Double
            var v: Double
            repeat {
                x = normal(using: &rng)
                v = 1 + c * x
            } while v <= 0
            v = v * v * v
            let u = uniform(using: &rng)
            if log(u) < 0.5 * x * x + d - d * v + d * log(v) { return d * v }
        }
    }
}
