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
        openGoalsToday: Int = 0
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
    }

    func delivered(on date: Date) -> Int {
        deliveredByDay[calendar.startOfDay(for: date)] ?? 0
    }
}

/// One nudge the planner decided to schedule.
public struct PlannedNudge: Sendable, Equatable {
    public let kind: NudgeKind
    public let fireDate: Date

    public init(kind: NudgeKind, fireDate: Date) {
        self.kind = kind
        self.fireDate = fireDate
    }
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

    /// `internal` so tests can build an isolated instance; the app uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, sender: NudgeSender? = nil) {
        self.modelContainer = modelContainer
        self.sender = sender ?? .shared
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

        var candidates: [PlannedNudge] = []
        func consider(_ kind: NudgeKind, at fire: Date?) {
            guard let fire, prefs.isEnabled(kind),
                  let placed = placeOutsideQuietHours(kind, at: fire, inputs: inputs),
                  placed > now
            else { return }
            candidates.append(PlannedNudge(kind: kind, fireDate: placed))
        }

        if inputs.dailyGoalCount > 0,
           var morning = clockTime(inputs.morningMinutes, on: today, calendar: calendar) {
            if morning <= now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                morning = clockTime(inputs.morningMinutes, on: tomorrow, calendar: calendar) ?? morning
            }
            consider(.morningPlan, at: morning)
        }

        if let protein = inputs.protein, protein.target > 0, !protein.isComplete {
            let fraction = protein.logged / protein.target
            if fraction >= lastMileMinimumFraction, fraction < 1 {
                consider(.proteinLastMile, at: clockTime(proteinMinutes, on: today, calendar: calendar))
            }
        }

        if inputs.streak > 0, inputs.openGoalsToday > 0 {
            consider(.streakAtRisk, at: clockTime(streakMinutes, on: today, calendar: calendar))
        }

        let recap = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: recapMinutes / 60, minute: recapMinutes % 60, weekday: recapWeekday),
            matchingPolicy: .nextTime
        )
        consider(.weeklyRecap, at: recap)

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

        // 1. Take back everything still pending, rows included, so the counts below are real.
        let pendingIDs: [String] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        let ours = pendingIDs.filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
            sender.cancelScheduled(nudgeIDs: ours.compactMap(Self.nudgeID(fromIdentifier:)), notFiredBy: now)
        }

        // 2. Only schedule what the user will actually see. Permission is asked in onboarding
        //    (Screen12PermissionPriming), never from here.
        let authorized: Bool = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status = settings.authorizationStatus
                continuation.resume(returning: status == .authorized || status == .provisional || status == .ephemeral)
            }
        }
        guard authorized else { return }

        // 3. Plan and schedule.
        guard let snapshot = await makeSnapshot(now: now) else { return }
        let planned = Self.plan(snapshot.inputs)
        for nudge in planned {
            await schedule(nudge, snapshot: snapshot)
        }
        if !planned.isEmpty {
            logger.notice("Scheduled \(planned.count, privacy: .public) nudge(s): \(planned.map(\.kind.rawValue).joined(separator: ","), privacy: .public).")
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

        let copy = Self.copy(for: nudge.kind, snapshot: snapshot)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = [
            Self.kindUserInfoKey: nudge.kind.rawValue,
            Self.deepLinkUserInfoKey: Self.deepLink(for: nudge.kind),
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

    private static func copy(for kind: NudgeKind, snapshot: Snapshot) -> (title: String, body: String) {
        let inputs = snapshot.inputs
        switch kind {
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
            let plannedValue = plans.first { $0.goal?.id == goal.id }?.plannedValue
            let progress = GoalDayProgress(goal: goal, todaysEvents: goalEvents, plannedValue: plannedValue)
            if !progress.isComplete { openGoals += 1 }
            if protein == nil, goal.type == .protein, let target = plannedValue ?? goal.targetValue {
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
            openGoalsToday: openGoals
        )
        return Snapshot(inputs: inputs, tone: tone, dailyGoalTitles: dailyGoals.map(\.title), proteinUnit: proteinUnit)
    }
}
