// Core/Sources/Core/Retention/StreakEngine.swift
//
// docs/spec.md §5.6 Never Miss Twice:
//   "A miss doesn't kill a streak. A second consecutive miss does. The app makes the 'comeback
//   day' feel special: bigger unlock celebration, 'Comeback' badge, shield copy that acknowledges
//   it."
// docs/spec.md §8 Retention Psychology Rules, rule 3 ("Streaks have forgiveness"):
//   "Freezes, Never Miss Twice, Plan B, Comeback mode. A streak should feel protective, not
//   fragile." Rule 9 ("No shame"): "Copy never says 'you failed.' Misses are 'slipped,' always
//   followed by the next smallest step." Rule 11 ("Endowed progress"): "Streak starts at Day 1
//   after onboarding's first win."
// docs/spec.md §9 (Backend AI & ML Systems header): "goal_events is the training table... every
// log, verification, completion, miss, Plan B, and freeze gets a row" — this file logs its own
// streak-level miss/freeze rows there (`goal: nil`, since these are day-level, not per-goal).
// docs/spec.md §13 Data Model: `streaks (user_id, current, best, freezes_left, last_earned_date,
// never_miss_twice_armed)`, `goal_events (..., kind: ... | miss | freeze, ...)`.
// docs/spec.md §21 Monetization & Paywall: "Free: ... 1 streak freeze/week." "Pro: ... 3
// freezes." This task's own brief makes the cadence explicit: 1/week free, 3/week paid.
// docs/spec.md §5.17 Trophy Case & Cosmetics: "Badges for milestones..." — the "Comeback" badge
// this file awards lives in that same `badges` table (`Models/Badge.swift`).
//
// This file implements EXACTLY the public shape from this task's SYSTEM CONTRACTS block:
//
//   final class StreakEngine {
//       static let shared = StreakEngine()
//       func recordEarnedUnlock(on date: Date) async
//       func recordMiss(on date: Date) async
//       func useFreeze(on date: Date) async -> Bool
//       func currentStreak() async -> Int
//   }
//
// so `LockEngineManager`, App Intents, and UI call sites (owned by other agents this same batch)
// can call `StreakEngine.shared.recordEarnedUnlock(on:)` etc. today, before this file exists on
// disk from their point of view, and keep compiling once it lands.
//
// Zero user-facing strings live in this file (CLAUDE.md: "user-facing copy lives in
// Core/Sources/Core/Copy — no hardcoded UI strings elsewhere"). `Logger` calls below are
// developer diagnostics only, mirroring `LockEngineManager`/`FocusSessionVerifier`'s own
// convention of keeping engine logs separate from anything a view would render. This is also
// where spec §8 rule 9 ("No shame... misses are 'slipped'") and §5.18's "no guilt copy" land for
// this feature: this engine has no copy to get wrong, by construction — see this task's
// `knownIssues` for the one real gap that leaves (`ShieldCopy.ShieldContext.recentMiss` still
// hardcoded `false`, since wiring it up needs a `SharedDefaults` mirror this task does not own).

import Foundation
import SwiftData
import os

/// `StreakEngine` is the sole owner of mutating the one `Streak` row per user
/// (`Models/Streak.swift`'s own doc comment) — every field on it, including the weekly freeze
/// bank and the Never Miss Twice flag, is written only from the methods below.
///
/// `@MainActor`, not a bare `final class` with no isolation, or an `actor`: the same reasoning
/// `LockEngineManager`/`FocusSessionVerifier`/`AdaptiveGoalEngine` each document at their own
/// declaration applies verbatim here. Under Swift 6 strict concurrency a plain `final class`
/// singleton needs either `Sendable` conformance (unrealistic for a type owning a `ModelContext`)
/// or isolation to a global actor; every realistic call site (SwiftUI views, App Intents,
/// `LockEngineManager`'s own unlock path) is already `@MainActor` or happy to `await` a hop onto
/// it. A `@MainActor final class` is implicitly `Sendable`, so `.shared` and every method below
/// stay callable from any isolation domain the way CONTRACTS' other call sites assume.
@MainActor
public final class StreakEngine {
    public static let shared = StreakEngine()

    // MARK: - Freeze allowance (spec §21; this task's brief: "1/week free, 3/week paid")

    /// How many streak freezes a plan tier is granted **per week**, flatly reset (not
    /// accumulated/rolled over) at the start of each new week — see
    /// `replenishFreezesIfNewWeek(_:user:asOf:)` for exactly what "start of a new week" means
    /// here and why this task reads "N/week" as a fresh weekly allotment rather than a bankable
    /// balance (spec §21 doesn't say either way; a flat reset is the simpler, more conservative
    /// v1 reading — flagged in this task's `decisions`).
    private static func weeklyFreezeAllowance(for tier: PlanTier) -> Int {
        switch tier {
        case .free: return 1
        case .pro: return 3
        }
    }

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "StreakEngine")

    /// Separate, App-Group-backed `UserDefaults` instance (same suite as `SharedDefaults`, a
    /// different file this task does not own) used **only** to remember the ISO week this engine
    /// last replenished freezes for. `Models/Streak.swift` has no field for that (only
    /// `freezesLeft` itself, no "as of which week" marker), and adding one is out of scope here
    /// (Session 1's model file, not this task's file list) — see `decisions`/`knownIssues`. Keyed
    /// distinctly from every key `Store/SharedDefaults.swift` defines so the two files can never
    /// collide even though they share the same underlying suite.
    private let freezeDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let freezeWeekAnchorKey = "com.zano.app.streakEngine.freezeWeekAnchor"

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container (mirrors `LockEngineManager`/`FocusSessionVerifier`'s own
    /// convention); every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - CONTRACTS: recordEarnedUnlock

    /// Records that the user earned an unlock on `date`'s calendar day — the one thing that
    /// advances `Streak.current` (spec §2 "Unlock... streak"). Never throws (CONTRACTS:
    /// `async`, not `async throws`): a missing local `User` row or a SwiftData save failure is
    /// logged and swallowed rather than propagated, since this signature has nowhere to put an
    /// error and the caller (an unlock path) must never be blocked by streak bookkeeping failing.
    ///
    /// Day-gap rules (spec §5.6, §8 rule 3, §8 rule 11):
    /// - No prior `lastEarnedDate` at all → first-ever earn, streak starts at **Day 1** (rule 11
    ///   "Endowed progress"), not Day 0.
    /// - Gap of 0 days (a second earned unlock the same day, e.g. two lock sets both unlocked) →
    ///   idempotent no-op; the streak already advanced for today.
    /// - Gap of 1 day, or a gap of exactly 2 days while `neverMissTwiceArmed` is `true` (the one
    ///   miss in between was already forgiven by `recordMiss`) → `current += 1`. The second case
    ///   is the actual "comeback day" spec §5.6 describes: this clears the armed flag and awards
    ///   the "Comeback" badge (`awardComebackBadge(userID:on:)` below) — see that method's doc
    ///   comment for why the badge is keyed per-occurrence rather than a single lifetime trophy.
    /// - Any larger, unforgiven gap → the streak restarts at Day 1 (rule 11 again — a fresh start
    ///   is still "Day 1," never "Day 0"). This is the general reset path; `ComebackMode.swift`
    ///   (this same task, this same directory) is what additionally offers a 3-day low-difficulty
    ///   re-entry challenge on top of a reset like this one — the two are intentionally
    ///   independent (`ComebackMode` reads `Streak.lastEarnedDate` itself; it does not call into
    ///   this method to decide anything), so `StreakEngine` staying correct never depends on
    ///   whether `ComebackMode` happens to run.
    /// - A `date` before the currently-recorded `lastEarnedDate` is logged and ignored — this
    ///   method never rewinds state from a stale/out-of-order call.
    ///
    /// "Bigger celebration" (spec §5.6) has no dedicated flag to set in this task's scope (no
    /// `SharedDefaults` mirror exists for it — see `knownIssues`): the intended signal for a
    /// caller/UI layer is the presence of a freshly-inserted `Badge` with key
    /// `"comeback_<yyyy-MM-dd>"` for today, or equivalently that `neverMissTwiceArmed` was `true`
    /// immediately before this call.
    public func recordEarnedUnlock(on date: Date) async {
        guard let user = try? fetchCurrentUser() else {
            logger.error("recordEarnedUnlock: no local User row — cannot record.")
            return
        }
        let day = calendar.startOfDay(for: date)
        let streak = fetchOrCreateStreak(userID: user.id)

        guard let previousEarned = streak.lastEarnedDate.map({ calendar.startOfDay(for: $0) }) else {
            streak.current = 1
            streak.lastEarnedDate = day
            streak.neverMissTwiceArmed = false
            streak.best = max(streak.best, streak.current)
            persistAndMirror(streak)
            return
        }

        let gap = calendar.dateComponents([.day], from: previousEarned, to: day).day ?? 0
        guard gap != 0 else { return } // Same-day repeat earn — nothing changes.
        guard gap > 0 else {
            logger.notice("recordEarnedUnlock: \(date.timeIntervalSince1970, privacy: .public) is before the last recorded earned date; ignoring.")
            return
        }

        // Health pause (spec §24): paused days never widen the gap, so a pause can't break a
        // streak. `HealthPause.swift` owns the pause history.
        let effectiveGap = max(1, gap - HealthPause.pausedDayCount(strictlyBetween: previousEarned, and: day, calendar: calendar))
        let isForgivenComeback = streak.neverMissTwiceArmed && effectiveGap <= 2
        if effectiveGap == 1 || isForgivenComeback {
            streak.current += 1
        } else {
            streak.current = 1
        }

        if streak.neverMissTwiceArmed {
            streak.neverMissTwiceArmed = false
            if isForgivenComeback {
                awardComebackBadge(userID: user.id, on: day)
            }
        }

        streak.lastEarnedDate = day
        streak.best = max(streak.best, streak.current)
        persistAndMirror(streak)
    }

    // MARK: - CONTRACTS: recordMiss

    /// Records that the user missed all their goals on `date`'s calendar day (spec §9.2's
    /// day-level "did the user miss all goals on day D?" label is exactly this call's input).
    ///
    /// Never breaks a streak on the **first** miss — only arms `neverMissTwiceArmed`, leaving
    /// `current` untouched (spec §5.6 "A miss doesn't kill a streak"). A **second consecutive**
    /// miss (this method called again while the flag is already armed) actually breaks it:
    /// `current` resets to `0` and the flag clears (spec §5.6 "A second consecutive miss does").
    /// A miss recorded while `current == 0` (nothing active to protect) still logs the day (for
    /// idempotency/history) but never arms the flag — there is no streak for Never Miss Twice to
    /// protect yet.
    ///
    /// Idempotent per calendar day: a duplicate call for a `date` this engine already logged a
    /// miss for (e.g. a retried nightly slip-prediction job, spec §9.2) is a no-op rather than
    /// incorrectly counting as the *second* miss.
    public func recordMiss(on date: Date) async {
        guard let user = try? fetchCurrentUser() else {
            logger.error("recordMiss: no local User row — cannot record.")
            return
        }
        let day = calendar.startOfDay(for: date)
        // Health pause (spec §24): a paused day is never a miss — no Never Miss Twice arming, no
        // reset, no `.miss` row.
        guard !HealthPause.wasPaused(on: day, calendar: calendar) else { return }
        guard !hasStreakMissEvent(userID: user.id, on: day) else { return }

        let streak = fetchOrCreateStreak(userID: user.id)
        if streak.current > 0 {
            if streak.neverMissTwiceArmed {
                streak.current = 0
                streak.neverMissTwiceArmed = false
            } else {
                streak.neverMissTwiceArmed = true
            }
        }

        insertStreakMissEvent(user: user, on: day)
        persistAndMirror(streak)
    }

    // MARK: - CONTRACTS: useFreeze

    /// Spends one streak freeze to protect `date`'s calendar day (spec §8 rule 3 "Streaks have
    /// forgiveness"). Replenishes the weekly bank first if a new week has started since this
    /// engine last checked (`weeklyFreezeAllowance(for:)`), then — if any freeze remains —
    /// decrements it, covers `date` (advances `lastEarnedDate` to it if it's later than what's
    /// already recorded, without incrementing `current`: a freeze protects the streak, it does
    /// not pretend a goal was actually completed), and clears `neverMissTwiceArmed` (this day is
    /// now covered by the freeze, not by tomorrow's earn).
    ///
    /// - Returns: `true` if the day is now covered (either just now, or already covered by an
    ///   earlier call for the same `date` — idempotent, never double-spends a second freeze for
    ///   one day); `false` if no freeze was available.
    @discardableResult
    public func useFreeze(on date: Date) async -> Bool {
        guard let user = try? fetchCurrentUser() else {
            logger.error("useFreeze: no local User row — cannot use a freeze.")
            return false
        }
        let day = calendar.startOfDay(for: date)
        if hasFreezeEvent(userID: user.id, on: day) {
            return true
        }

        let streak = fetchOrCreateStreak(userID: user.id)
        replenishFreezesIfNewWeek(streak, user: user, asOf: date)
        guard streak.freezesLeft > 0 else { return false }

        streak.freezesLeft -= 1
        streak.neverMissTwiceArmed = false
        let lastEarned = streak.lastEarnedDate.map { calendar.startOfDay(for: $0) }
        if lastEarned == nil || day > lastEarned! {
            streak.lastEarnedDate = day
        }
        streak.best = max(streak.best, streak.current)

        insertFreezeEvent(user: user, on: day)
        persistAndMirror(streak)
        return true
    }

    // MARK: - CONTRACTS: currentStreak

    public func currentStreak() async -> Int {
        guard let user = try? fetchCurrentUser() else { return 0 }
        return fetchStreak(userID: user.id)?.current ?? 0
    }

    // MARK: - Weekly freeze replenishment

    /// Tops `streak.freezesLeft` up to this week's flat allowance the first time this engine sees
    /// a call land in a new ISO week (per `weekIdentifier(for:)`) — a plain reset, not additive:
    /// unused freezes from a prior week do not roll over (see the allowance doc comment above for
    /// why). Never *lowers* `freezesLeft` mid-week — this only ever runs once per week, on the
    /// first `useFreeze` call that lands in it.
    private func replenishFreezesIfNewWeek(_ streak: Streak, user: User, asOf date: Date) {
        let key = weekIdentifier(for: date)
        guard freezeDefaults.string(forKey: Self.freezeWeekAnchorKey) != key else { return }
        streak.freezesLeft = Self.weeklyFreezeAllowance(for: user.planTier)
        freezeDefaults.set(key, forKey: Self.freezeWeekAnchorKey)
    }

    /// `"<year>-W<week>"` using `Calendar.current`'s week-of-year components — stable within one
    /// week, distinct across weeks. Not strictly ISO-8601 (that would pin Monday-start/UTC); "a"
    /// consistent weekly boundary is all this needs. Flagged as a best-effort choice, not exact
    /// spec text, in `decisions`.
    private func weekIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    // MARK: - Comeback badge (spec §5.6, §5.17)

    /// Awards the "Comeback" badge the moment Never Miss Twice's forgiven miss is actually
    /// redeemed by an earned unlock. Keyed **per occurrence** (`"comeback_<yyyy-MM-dd>"`) rather
    /// than one static `"comeback"` key: spec §5.6 frames this as something that happens every
    /// time the user bounces back from a single slip, not a one-time lifetime trophy — and
    /// `Badge`'s remote `unique(user_id, key)` constraint (`Models/Badge.swift`'s doc comment)
    /// means one shared key could only ever be awarded once. A date-stamped key keeps every real
    /// comeback day awardable while staying idempotent against a duplicate call for the *same*
    /// day (checked below). A future Trophy Case UI (spec §5.17) can group every
    /// `"comeback_*"`-keyed badge as the same visual badge type without this engine needing to
    /// know anything about how Trophy Case displays them.
    private func awardComebackBadge(userID: UUID, on day: Date) {
        let key = "comeback_\(Self.dayFormatter.string(from: day))"
        awardBadgeIfNeeded(key: key, userID: userID, earnedAt: day)
    }

    private func awardBadgeIfNeeded(key: String, userID: UUID, earnedAt: Date) {
        var descriptor = FetchDescriptor<Badge>(
            predicate: #Predicate<Badge> { $0.userID == userID && $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        context.insert(Badge(userID: userID, key: key, earnedAt: earnedAt))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - Streak-level GoalEvent markers (spec §13 `goal_events`; `goal: nil` — these are
    // day-level streak events, not tied to one specific goal)

    /// Whether a streak-level `.miss` marker already exists for `day` — the idempotency check
    /// `recordMiss` uses. Filters `kind`/`goal`/`user` in plain Swift after a `Date`-only
    /// `#Predicate` fetch, the same conservative choice `LockEngineManager.isGoalVerified` and
    /// `AdaptiveGoalEngine`'s fetch helpers document: this task has no Mac/Swift toolchain to
    /// compile-verify `#Predicate`'s handling of a custom `Codable` enum (`kind`) or optional-
    /// relationship chaining (`goal == nil`, `user?.id`) on this SDK version.
    private func hasStreakMissEvent(userID: UUID, on day: Date) -> Bool {
        eventExists(userID: userID, on: day) { $0.kind == .miss }
    }

    private func hasFreezeEvent(userID: UUID, on day: Date) -> Bool {
        eventExists(userID: userID, on: day) { $0.kind == .freeze }
    }

    private func eventExists(userID: UUID, on day: Date, matching predicate: (GoalEvent) -> Bool) -> Bool {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= day && $0.ts < nextDay }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains { $0.goal == nil && $0.user?.id == userID && predicate($0) }
    }

    private func insertStreakMissEvent(user: User, on day: Date) {
        context.insert(GoalEvent(
            ts: day,
            kind: .miss,
            source: .manual,
            verified: false,
            meta: .object(["engine": .string("StreakEngine")]),
            user: user,
            goal: nil
        ))
    }

    private func insertFreezeEvent(user: User, on day: Date) {
        context.insert(GoalEvent(
            ts: day,
            kind: .freeze,
            source: .manual,
            verified: true,
            meta: .object(["engine": .string("StreakEngine")]),
            user: user,
            goal: nil
        ))
    }

    // MARK: - SwiftData

    private func fetchStreak(userID: UUID) -> Streak? {
        var descriptor = FetchDescriptor<Streak>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateStreak(userID: UUID) -> Streak {
        if let existing = fetchStreak(userID: userID) { return existing }
        let streak = Streak(userID: userID)
        context.insert(streak)
        return streak
    }

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `LockEngineManager.fetchCurrentUser()` uses.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw StreakEngineError.noSignedInUser
        }
        return user
    }

    /// Saves the context, then mirrors the two fields `Store/SharedDefaults.swift` already
    /// exposes and already documents as "Owned by `StreakEngine`" (`currentStreak`,
    /// `bestStreak`) — calling that file's existing public API, not editing it. Logs and
    /// continues on a save failure rather than throwing (see `recordEarnedUnlock`'s doc comment
    /// on why this file's CONTRACTS methods never throw outward).
    private func persistAndMirror(_ streak: Streak) {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save Streak: \(String(describing: error), privacy: .public)")
        }
        SharedDefaults.currentStreak = streak.current
        SharedDefaults.bestStreak = streak.best
    }
}

/// Errors this file's private `fetchCurrentUser()` throws internally. Never propagated out of any
/// CONTRACTS method (all four are non-throwing) — kept only so that helper has a typed failure to
/// `try?` at each call site, mirroring `LockEngineManager.LockEngineError`'s convention.
enum StreakEngineError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
