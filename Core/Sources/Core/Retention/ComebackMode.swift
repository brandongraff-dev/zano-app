// Core/Sources/Core/Retention/ComebackMode.swift
//
// docs/spec.md §5.18 Travel & Comeback Modes:
//   "Comeback mode (after 5+ days inactive): streak restart with a '3-day comeback' mini-
//   challenge at low difficulty; no guilt copy."
// docs/spec.md §8 Retention Psychology Rules, rule 1 ("Early wins are engineered"): "First 3
// days' goals are ~70% of stated capability. The engine raises the bar only after wins." — this
// file applies that same "engineer the first wins" philosophy to *re-entry* after a long gap,
// not just brand-new onboarding. Rule 3 ("Streaks have forgiveness"): "Freezes, Never Miss
// Twice, Plan B, Comeback mode. A streak should feel protective, not fragile." Rule 9 ("No
// shame"): "Copy never says 'you failed.'... always followed by the next smallest step" — this
// file's entire design (a challenge offered at low difficulty, not a scolding) is that rule
// applied to a long absence specifically.
// docs/spec.md §13 Data Model: `daily_plans (..., difficulty_step, plan_b_value, source)` —
// `source` includes `'manual'` precisely for a product-logic override like this one, alongside
// the `'rules'`/`'bandit'` engine outputs `AdaptiveGoalEngine.swift` produces.
//
// Not part of this task's SYSTEM CONTRACTS list (only `LockEngineManager`, `FocusSessionVerifier`,
// `GymVerifier`, `TimeBankEngine`, `StreakEngine`, `AdaptiveGoalEngine`, and the LiveActivity
// attribute structs have a fixed public shape other agents build against) — this file's public
// API is this task's own design choice, kept deliberately small (CLAUDE.md: "don't add
// abstractions... beyond what the current session's scope requires").
//
// Relationship to `StreakEngine.swift` (this same task, this same directory): independent by
// design. `StreakEngine.recordEarnedUnlock` already restarts `Streak.current` at Day 1 on any
// unforgiven gap (see that method's doc comment) — that *is* spec §5.18's "streak restart" half.
// This file adds the other half — the 3-day low-difficulty re-entry challenge — by reading
// `Streak.lastEarnedDate` itself, not by being called from `StreakEngine`. Neither file depends
// on the other being present at runtime for its own half to work correctly.
//
// Relationship to `AdaptiveGoalEngine.swift` (this same task, this same directory): that file's
// own header comment calls it "the sole owner of producing/persisting DailyPlan rows" among the
// modules that existed when it was written. This file still writes `DailyPlan` rows directly
// (via its own `ModelContext`, not `AdaptiveGoalEngine.shared`'s) rather than routing through
// `AdaptiveGoalEngine.dailyPlan(for:on:)`, for a concrete reason: that method is itself
// idempotent — "if a plan already exists for (goal, date), return it unchanged" — and its only
// exposed override hook (`setPlanBValue(_:on:)`, `internal`, used by `PlanB.swift`) only ever
// touches `planBValue`, not `plannedValue`/`difficultyStep`/`source`. There is no public way to
// ask that engine for a *reduced* plan. `daily_plans.source`'s `'manual'` case (spec §13) exists
// exactly for this kind of override, so `startChallengeIfEligible` upserts its own manual-source
// rows directly instead. This is safe under SwiftData — a second, independent `ModelContext` over
// the same `ModelContainer.appGroup` store can fetch and mutate the same row; there is no shared-
// object-identity requirement *across* contexts, only within one context's own fetched instances
// (that's what `AdaptiveGoalEngine`'s `setPlanBValue` doc comment is actually about — `PlanB.swift`
// reusing rows fetched through that engine's *one* `.shared` context, not a general SwiftData
// rule). The one real ordering caveat — flagged in this task's `knownIssues` — is that if
// `AdaptiveGoalEngine`'s own context already has that same row loaded in memory (e.g. a screen
// currently showing it) when this file's separate context saves a change to it, that in-memory
// copy can go stale until it's re-fetched; this task has no Mac/Swift toolchain to verify exactly
// how that plays out on this SwiftData version, the same category of assumption
// `LockEngineManager`'s `#Predicate` caution already flags elsewhere in this codebase.

import Foundation
import SwiftData
import os

/// Detects a 5+ day inactivity gap (spec §5.18) and, on request, sets up the 3-day low-difficulty
/// re-entry mini-challenge — reduced `DailyPlan` targets for the user's active goals across the
/// next 3 calendar days, plus the "Comeback" celebration once the final day completes.
///
/// `@MainActor`, matching every other engine in this codebase (`StreakEngine`,
/// `AdaptiveGoalEngine`, `LockEngineManager`, `FocusSessionVerifier`) for the same reason each of
/// those documents at their own declaration: a plain `final class` singleton needs either
/// `Sendable` conformance (unrealistic for a type owning a `ModelContext`) or global-actor
/// isolation under Swift 6 strict concurrency, and every realistic call site is already
/// `@MainActor` or happy to `await` a hop onto it.
@MainActor
public final class ComebackMode {
    public static let shared = ComebackMode()

    // MARK: - Tunables (spec §5.18)

    /// "after 5+ days inactive."
    public static let inactivityThresholdDays = 5
    /// "a '3-day comeback' mini-challenge."
    public static let totalDays = 3

    /// How much this engine reduces an active/adaptive goal's target for the challenge window,
    /// relative to that goal's stated `targetValue` (not `AdaptiveGoalEngine`'s current adaptive
    /// plan for the day — a returning user gets a fresh, generous floor, not a further reduction
    /// stacked on top of wherever their difficulty happened to be before they left). Spec §5.18
    /// says "low difficulty" without pinning an exact number; this task reads it as deliberately
    /// lower than onboarding's own ~70% early-win floor (spec §8 rule 1) since re-entry after a
    /// long gap needs an even softer landing than a brand-new user's first days. Flagged as this
    /// task's own numeric choice in `decisions`, not exact spec text.
    public static let targetMultiplier = 0.5
    /// An even easier Plan B–style fallback within the challenge itself (spec §5.5's Plan B
    /// pattern applied here too — a comeback day should be *very* hard to miss).
    public static let planBMultiplier = 0.3
    /// Sentinel `DailyPlan.difficultyStep` value written on every row this engine creates. Doubles
    /// as both "how much easier" (a clearly negative step) and a provenance marker:
    /// `fetchChallengeGoalIDs(startingOn:)` below uses it to recognize which `DailyPlan` rows a
    /// given challenge touched, since there's no dedicated "created by ComebackMode" column on
    /// that model (Session 1's file, not this task's to extend).
    public static let difficultyStepMarker = -3

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "ComebackMode")

    /// Separate, App-Group-backed `UserDefaults` instance (same suite `Store/SharedDefaults.swift`
    /// uses, a different file this task does not own) holding the one small piece of state this
    /// engine needs that has nowhere else to live: which calendar day (if any) the current 3-day
    /// challenge started on. There is no `ComebackChallenge`-shaped SwiftData model in
    /// `Core/Sources/Core/Models` to persist this in instead (this task's file list does not
    /// include adding one), so a challenge's day-by-day progress is instead derived live from
    /// this one start date plus `DailyPlan.difficultyStepMarker`-tagged rows, rather than
    /// persisting a separate counter that could drift from them. Keyed distinctly from every key
    /// `StreakEngine.swift`/`Store/SharedDefaults.swift` define so the three can never collide
    /// even though they share the same underlying suite.
    private let comebackDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let challengeStartDateKey = "com.zano.app.comebackMode.challengeStartDate"

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public shape

    /// One in-progress (or, from `startChallengeIfEligible`'s return value, just-started) 3-day
    /// comeback challenge.
    public struct ComebackChallenge: Sendable, Equatable {
        /// Local calendar day the challenge started on.
        public let startDate: Date
        /// 1-indexed: `1` on the day it started, up to `totalDays`.
        public let dayIndex: Int
        public let totalDays: Int
        /// `Goal.id`s this challenge set a reduced `DailyPlan` for.
        public let goalIDs: [UUID]
    }

    /// `true` when the signed-in user's `Streak.lastEarnedDate` is `Self.inactivityThresholdDays`
    /// or more calendar days before `date`, and no challenge is already in progress. A user who
    /// has never earned a single unlock yet (`lastEarnedDate == nil`) is never "eligible" here —
    /// they haven't started yet, which is onboarding's job (spec §7), not a comeback from
    /// anything. Never throws: no local `User`/`Streak` row is treated as "not eligible," not an
    /// error, matching every other read-only method in this codebase's engines.
    public func isEligible(asOf date: Date = .now) async -> Bool {
        guard await activeChallenge(asOf: date) == nil else { return false }
        guard let user = try? fetchCurrentUser(),
              let streak = fetchStreak(userID: user.id),
              let lastEarned = streak.lastEarnedDate
        else { return false }

        let day = calendar.startOfDay(for: date)
        let gap = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: lastEarned), to: day
        ).day ?? 0
        return gap >= Self.inactivityThresholdDays
    }

    /// The currently in-progress challenge as of `date`, or `nil` if none is running. Reads the
    /// persisted start date and derives `dayIndex` live (`date - startDate`, in days, `+1`) rather
    /// than tracking a separate counter — see this file's header comment on why. If the window has
    /// fully elapsed (`dayIndex > totalDays`), this also clears the stale marker so a later
    /// `isEligible` check isn't blocked by a challenge that's actually over.
    public func activeChallenge(asOf date: Date = .now) async -> ComebackChallenge? {
        guard let startDate = comebackDefaults.object(forKey: Self.challengeStartDateKey) as? Date else {
            return nil
        }
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: date)
        let dayIndex = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1

        guard dayIndex >= 1 else { return nil } // `date` is before the challenge started.
        guard dayIndex <= Self.totalDays else {
            clearChallengeMarker()
            return nil
        }

        return ComebackChallenge(
            startDate: start,
            dayIndex: dayIndex,
            totalDays: Self.totalDays,
            goalIDs: fetchChallengeGoalIDs(startingOn: start)
        )
    }

    /// If `isEligible(asOf:)`, starts the 3-day challenge: for each of the signed-in user's
    /// active, adaptive goals (`Goal.active && Goal.adaptive` — a non-adaptive goal has opted out
    /// of any engine moving its bar, spec §9/§11, so this engine leaves those alone the same way
    /// `AdaptiveGoalEngine.dailyPlan(for:on:)` does), upserts a reduced-target `DailyPlan` for
    /// `date`, `date + 1`, and `date + 2`, then persists the challenge's start date so
    /// `activeChallenge`/`recordDayCompleted` can track it. Returns the new challenge (`dayIndex
    /// == 1`), or `nil` if not eligible right now.
    ///
    /// A returning user with zero active/adaptive goals still starts a challenge with an empty
    /// `goalIDs` — there's nothing to reduce, but the streak-restart half of "comeback mode"
    /// (`StreakEngine.recordEarnedUnlock`) still applies the moment they complete *any* goal, and
    /// a later goal added mid-window is not retroactively picked up (this task's v1 scope; flagged
    /// in `knownIssues`).
    @discardableResult
    public func startChallengeIfEligible(on date: Date = .now) async throws -> ComebackChallenge? {
        guard await isEligible(asOf: date) else { return nil }
        let user = try fetchCurrentUser()

        let start = calendar.startOfDay(for: date)
        let goals = fetchActiveAdaptiveGoals(userID: user.id)

        for offset in 0..<Self.totalDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for goal in goals {
                upsertComebackPlan(for: goal, user: user, on: day)
            }
        }
        try context.save()

        comebackDefaults.set(start, forKey: Self.challengeStartDateKey)
        logger.notice(
            "Started 3-day comeback challenge for user \(user.id.uuidString, privacy: .public) starting \(start.timeIntervalSince1970, privacy: .public), \(goals.count, privacy: .public) goal(s)."
        )

        return ComebackChallenge(
            startDate: start,
            dayIndex: 1,
            totalDays: Self.totalDays,
            goalIDs: goals.map(\.id)
        )
    }

    /// Call whenever the user records an earned unlock on `date` (spec §5.18's mini-challenge is
    /// "complete" once its final day is). This is a cross-module integration point:
    ///
    /// TODO(cross-module, App Intents/unlock-path session; not this task's file list): whichever
    /// call site already invokes `StreakEngine.shared.recordEarnedUnlock(on:)` for a real earned
    /// unlock (`LockEngineManager`'s unlock path, an App Intent, ...) should also call
    /// `ComebackMode.shared.recordDayCompleted(on:)` alongside it. Both calls are safe to make
    /// unconditionally on every earned unlock — this one is a no-op whenever there's no active
    /// challenge, or `date` isn't its final day.
    ///
    /// On the final day, this awards the recurring "comeback_challenge_<start date>" badge (same
    /// per-occurrence keying rationale as `StreakEngine.awardComebackBadge` — spec frames this as
    /// something that can happen again after a future lapse, not a single lifetime trophy) and
    /// clears the challenge marker so `isEligible` can consider a fresh gap later.
    public func recordDayCompleted(on date: Date = .now) async {
        guard let challenge = await activeChallenge(asOf: date), challenge.dayIndex == challenge.totalDays,
              let user = try? fetchCurrentUser()
        else { return }

        awardChallengeCompleteBadge(userID: user.id, challengeStart: challenge.startDate)
        clearChallengeMarker()
    }

    // MARK: - DailyPlan overrides (see this file's header comment for why this writes directly)

    private func upsertComebackPlan(for goal: Goal, user: User, on day: Date) {
        let lowTarget = goal.targetValue.map { $0 * Self.targetMultiplier }
        let lowPlanB = goal.targetValue.map { $0 * Self.planBMultiplier }

        if let plan = fetchDailyPlan(goalID: goal.id, day: day) {
            plan.plannedValue = lowTarget
            plan.planBValue = lowPlanB
            plan.difficultyStep = Self.difficultyStepMarker
            plan.source = .manual
        } else {
            context.insert(DailyPlan(
                date: day,
                plannedValue: lowTarget,
                difficultyStep: Self.difficultyStepMarker,
                planBValue: lowPlanB,
                source: .manual,
                user: user,
                goal: goal
            ))
        }
    }

    /// Filters the `goal` relationship in plain Swift after a `Date`-only `#Predicate` fetch — the
    /// same conservative choice `AdaptiveGoalEngine.fetchDailyPlan`/`LockEngineManager.
    /// isGoalVerified` document: no Mac/Swift toolchain in this task to compile-verify
    /// `#Predicate`'s handling of optional-relationship chaining on this SDK version.
    private func fetchDailyPlan(goalID: UUID, day: Date) -> DailyPlan? {
        let descriptor = FetchDescriptor<DailyPlan>(predicate: #Predicate<DailyPlan> { $0.date == day })
        guard let plans = try? context.fetch(descriptor) else { return nil }
        return plans.first { $0.goal?.id == goalID }
    }

    /// `Goal.id`s of every `DailyPlan` dated `start` that carries this engine's
    /// `difficultyStepMarker`. `date`/`difficultyStep` are plain, unambiguous attribute types
    /// (`Date`/`Int`), so (unlike the relationship filter below) those two stay in one
    /// `#Predicate`, matching the "cheap, predicate-safe fields" precedent
    /// `LockEngineManager.isGoalVerified` sets.
    ///
    /// Also requires `source == .manual` (filtered here in plain Swift, not `#Predicate`, per
    /// this file's own caution about enum equality there): `difficultyStepMarker` (`-3`) is a
    /// plausible value for `AdaptiveGoalEngine`'s own rules engine to reach organically after
    /// enough weekly step-downs (nothing bounds how negative a real `difficultyStep` can go, only
    /// the *value* it produces is floored — see that file's `steppedValue`). Requiring
    /// `source == .manual` too — the one thing only this engine (currently) ever sets that value
    /// through — keeps this lookup from ever attributing an unrelated, coincidentally-matching
    /// `.rules` row to this challenge.
    private func fetchChallengeGoalIDs(startingOn start: Date) -> [UUID] {
        let sentinel = Self.difficultyStepMarker
        let descriptor = FetchDescriptor<DailyPlan>(
            predicate: #Predicate<DailyPlan> { $0.date == start && $0.difficultyStep == sentinel }
        )
        guard let plans = try? context.fetch(descriptor) else { return [] }
        return plans.filter { $0.source == .manual }.compactMap { $0.goal?.id }
    }

    private func fetchActiveAdaptiveGoals(userID: UUID) -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { $0.active == true && $0.adaptive == true }
        )
        guard let goals = try? context.fetch(descriptor) else { return [] }
        return goals.filter { $0.user?.id == userID }
    }

    // MARK: - Completion badge (spec §5.6/§5.17's Trophy Case pattern, reused for §5.18)

    private func awardChallengeCompleteBadge(userID: UUID, challengeStart: Date) {
        let key = "comeback_challenge_\(Self.dayFormatter.string(from: challengeStart))"
        var descriptor = FetchDescriptor<Badge>(
            predicate: #Predicate<Badge> { $0.userID == userID && $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        context.insert(Badge(userID: userID, key: key, earnedAt: challengeStart))
        do {
            try context.save()
        } catch {
            logger.error("Failed to save comeback-challenge badge: \(String(describing: error), privacy: .public)")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private func clearChallengeMarker() {
        comebackDefaults.removeObject(forKey: Self.challengeStartDateKey)
    }

    // MARK: - SwiftData

    private func fetchStreak(userID: UUID) -> Streak? {
        var descriptor = FetchDescriptor<Streak>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `LockEngineManager.fetchCurrentUser()`/`StreakEngine.fetchCurrentUser()` use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw ComebackModeError.noSignedInUser
        }
        return user
    }
}

/// Thrown only by this file's private `fetchCurrentUser()`. `isEligible`/`activeChallenge`/
/// `recordDayCompleted` swallow it via `try?` (never throw outward, matching every read-only
/// method in this codebase's engines); `startChallengeIfEligible` is the one method that does
/// propagate it, since a caller explicitly asking to *start* something needs to know why it
/// couldn't.
enum ComebackModeError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
