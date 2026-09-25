// Core/Sources/Core/LockEngine/TimeBankEngine.swift
//
// Earn Mode's per-day ledger (docs/spec.md §5.2 "★ Earn Rate ('Screen Time Exchange Rate')"):
// every verified goal deposits minutes into a Time Bank; a shielded app spends minutes out of it;
// whatever's unused expires at midnight — "no hoarding" is a product rule, not just UI copy. Exact
// §5.2 values this file encodes (`TimeBankEarnRates`): "A gym session = 90 min of social apps; a
// focus block = 30 min; hitting protein = 30 min." Also docs/spec.md §11 Architecture ("LockEngine
// (shields, schedules, unlock rules, Time Bank)") and §13 Data Model
// (`time_bank (id, user_id, date, earned_min, spent_min)`).
//
// Implements the exact public shape from this task's SYSTEM CONTRACTS block:
//
//   final class TimeBankEngine {
//       static let shared = TimeBankEngine()
//       func deposit(minutes: Int, for date: Date) async throws
//       func spend(minutes: Int, for date: Date) async throws -> Bool
//       func remainingMinutes(for date: Date) async -> Int
//   }
//
// so any App Intent / UI / other engine can call `TimeBankEngine.shared.deposit(...)` today,
// before this file exists on disk from their point of view, and keep compiling once it lands.
//
// This file is the sole owner of mutating `Models/TimeBank.swift` rows — nothing else in this
// codebase should insert/update a `TimeBank` directly (mirrors `LockEngineManager` being the sole
// owner of `LockSession`, `LockSetManager` of `LockSet`; see those files, same folder).
//
// "No hoarding" / "expires at midnight" is enforced structurally, not by a cron-style expiry
// step: `TimeBank` is one row per `(userID, date)` (see `Models/TimeBank.swift`'s doc comment),
// and every method below only ever reads/writes the single row for the exact `date` it's given —
// nothing here ever sums or copies a balance across days. Once local midnight passes, "today" is
// simply a different `date` with its own fresh (zeroed) row; yesterday's leftover `remainingMin`
// is never consulted again by anything in this file.

import Foundation
import SwiftData
import os

// MARK: - Earn rates (spec §5.2 exact values)

/// The exact Earn Mode deposit amounts docs/spec.md §5.2 gives by name. Only these three
/// `GoalType`s have a spec-defined rate as of this writing — every other goal type intentionally
/// has no entry here rather than a guessed number; extending this table for other goal types
/// (water, steps, creatine, ...) is a product decision for whichever session grows §5.2's table,
/// not something to invent locally in this task.
public enum TimeBankEarnRates {
    /// docs/spec.md §5.2: "A gym session = 90 min of social apps."
    public static let gymSessionMinutes = 90
    /// docs/spec.md §5.2: "a focus block = 30 min."
    public static let focusBlockMinutes = 30
    /// docs/spec.md §5.2: "hitting protein = 30 min."
    public static let proteinMinutes = 30

    /// The Earn Mode minutes a verified `goalType` deposits, or `nil` if spec §5.2 hasn't defined
    /// an exact value for it yet. Callers should treat `nil` as "don't deposit anything for this
    /// goal type in Earn Mode" — a real spec gap, not a silent zero.
    public static func minutes(for goalType: GoalType) -> Int? {
        switch goalType {
        case .workoutGym: gymSessionMinutes
        case .focusSession: focusBlockMinutes
        case .protein: proteinMinutes
        default: nil
        }
    }
}

// MARK: - Spend result

/// Outcome of `TimeBankEngine.spendToUnlock(minutes:)`.
public enum SpendToUnlockResult: Sendable, Equatable {
    /// Minutes debited; the shield is lifted until this time.
    case unlocked(until: Date)
    /// Not enough minutes in today's bank; nothing was debited.
    case insufficientMinutes(remaining: Int)
    /// No Earn Mode lock is running (none at all, or a full-mode lock).
    case noActiveEarnLock
}

// MARK: - Errors

/// Errors `TimeBankEngine` throws itself, as opposed to errors bubbled up from SwiftData.
public enum TimeBankEngineError: Error, Sendable, LocalizedError {
    /// `deposit`/`spend` was called with a value that can never mean anything (`<= 0`).
    case invalidMinutes(Int)
    /// No local `User` row exists yet to attribute this Time Bank row to.
    case noSignedInUser

    public var errorDescription: String? {
        switch self {
        case .invalidMinutes(let minutes):
            "TimeBankEngine minutes must be greater than zero (got \(minutes))."
        case .noSignedInUser:
            "No local User row exists yet."
        }
    }
}

// MARK: - TimeBankEngine

/// The sole owner of creating and mutating `TimeBank` rows.
///
/// `@MainActor`, matching `LockEngineManager`/`LockSetManager` in this same folder: a plain
/// `final class` with `static let shared` needs either `Sendable` conformance (unrealistic for a
/// class that owns a `ModelContext`) or global-actor isolation to satisfy Swift 6 strict
/// concurrency, and every realistic caller (SwiftUI views, App Intents, `LockEngineManager`
/// itself deciding whether to lift a shield) is already on the main actor. `await`ing these
/// methods reads identically from any isolation domain either way, so this choice is invisible at
/// CONTRACTS' call sites.
@MainActor
public final class TimeBankEngine {
    public static let shared = TimeBankEngine()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "TimeBankEngine")

    /// - Parameter modelContainer: Defaults to the shared App Group container (spec §11).
    ///   Overridable for unit tests (an in-memory container).
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
    }

    // MARK: - Deposit / spend / remaining (CONTRACTS)

    /// Deposits `minutes` into `date`'s Time Bank row for the current user, creating that day's
    /// row on first use. Only ever affects the single row for `date` — see the file header's
    /// "no hoarding" note — so depositing for a past/future `date` never touches today's balance.
    ///
    /// - Throws: `TimeBankEngineError.invalidMinutes` (`minutes <= 0`), `.noSignedInUser`, or
    ///   whatever `ModelContext.save()` throws.
    public func deposit(minutes: Int, for date: Date) async throws {
        guard minutes > 0 else { throw TimeBankEngineError.invalidMinutes(minutes) }
        let user = try fetchCurrentUser()
        let bank = try fetchOrCreateTimeBank(userID: user.id, date: date)
        bank.earnedMin += minutes
        try context.save()
        await mirrorIfToday(bank, for: date)
        logger.notice("TimeBank deposit: +\(minutes, privacy: .public) min, remaining=\(bank.remainingMin, privacy: .public).")
    }

    /// Attempts to spend `minutes` from `date`'s Time Bank row. Atomic against that row's current
    /// balance: either the full amount is available and gets deducted, or nothing is deducted —
    /// spending 20 of a requested 30 would leave a caller's shield-lifting logic in an
    /// inconsistent state, so this is deliberately all-or-nothing.
    ///
    /// - Returns: `true` if `minutes` were available and spent; `false` if the balance was
    ///   insufficient.
    /// - Throws: `TimeBankEngineError.invalidMinutes` (`minutes <= 0`), `.noSignedInUser`, or
    ///   whatever `ModelContext.save()` throws.
    public func spend(minutes: Int, for date: Date) async throws -> Bool {
        guard minutes > 0 else { throw TimeBankEngineError.invalidMinutes(minutes) }
        let user = try fetchCurrentUser()
        let bank = try fetchOrCreateTimeBank(userID: user.id, date: date)
        guard bank.remainingMin >= minutes else { return false }
        bank.spentMin += minutes
        try context.save()
        await mirrorIfToday(bank, for: date)
        logger.notice("TimeBank spend: -\(minutes, privacy: .public) min, remaining=\(bank.remainingMin, privacy: .public).")
        return true
    }

    /// `date`'s remaining Time Bank minutes (`max(0, earnedMin - spentMin)`, `TimeBank.
    /// remainingMin`) for the current user; `0` if that day has no row yet (nothing earned) or no
    /// `User` exists locally.
    ///
    /// Never throws — this is read constantly by widget/Live-Activity/shield copy and must never
    /// crash a caller over a missing row, mirroring `LockEngineManager.
    /// evaluateUnlockEligibility`'s "never throw, degrade to the safe/empty answer" convention.
    public func remainingMinutes(for date: Date) async -> Int {
        guard let user = try? fetchCurrentUser() else { return 0 }
        guard let bank = try? fetchTimeBank(userID: user.id, date: date) else { return 0 }
        return bank.remainingMin
    }

    // MARK: - Spending to unlock (spec §5.2 "a shielded app spends minutes out of it")

    /// Spends `minutes` from today's bank and lifts the active Earn Mode lock's shield for that
    /// long (`LockEngineManager.beginSpendWindow`; see its doc for the re-shield mechanism and
    /// DeviceActivity limits). Spending during an open window extends it. Only Earn Mode locks can
    /// be bought out — a full lock is a hard block until goals are done (emergency unlock is
    /// separate and always available). Minutes still expire at midnight: a window only covers the
    /// minutes paid for.
    public func spendToUnlock(minutes: Int, now: Date = .now) async throws -> SpendToUnlockResult {
        guard minutes > 0 else { throw TimeBankEngineError.invalidMinutes(minutes) }
        guard LockEngineManager.shared.activeEarnSessionID() != nil else { return .noActiveEarnLock }
        guard try await spend(minutes: minutes, for: now) else {
            return .insufficientMinutes(remaining: await remainingMinutes(for: now))
        }
        do {
            let until = try LockEngineManager.shared.beginSpendWindow(minutes: minutes, now: now)
            return .unlocked(until: until)
        } catch {
            await refund(minutes: minutes, for: now)
            throw error
        }
    }

    // MARK: - Goal-type convenience (spec §5.2 exact values)

    /// Deposits the spec §5.2 Earn Mode amount for a verified `goalType` (see
    /// `TimeBankEarnRates`), if one is defined for it.
    ///
    /// Not part of the fixed CONTRACTS shape — purely additive, so a goal-completion call site
    /// (LockEngine/Verification integration point: wherever a `GoalEvent.kind == .complete` gets
    /// written while the active lock is in `.earn` mode — not this file's job to wire that up)
    /// doesn't have to duplicate `TimeBankEarnRates`'s lookup at every call site.
    ///
    /// - Returns: `true` if `goalType` has a defined rate and the deposit succeeded; `false` if
    ///   spec §5.2 doesn't define a rate for this goal type yet — nothing was deposited (see
    ///   `TimeBankEarnRates.minutes(for:)`'s doc comment on why that's not silently treated as 0).
    @discardableResult
    public func depositEarnedMinutes(forVerifiedGoalType goalType: GoalType, on date: Date = .now) async throws -> Bool {
        guard let minutes = TimeBankEarnRates.minutes(for: goalType) else { return false }
        try await deposit(minutes: minutes, for: date)
        return true
    }

    // MARK: - Private

    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw TimeBankEngineError.noSignedInUser
        }
        return user
    }

    /// Finds `date`'s local-calendar-day `TimeBank` row for `userID` by date range rather than by
    /// `TimeBank.dayKey` directly: `dayKey`'s derivation (`makeDayKey`) is `private` to
    /// `Models/TimeBank.swift` (owned by another session), so this file can't recompute the same
    /// string to query by it. A `[startOfDay, nextStartOfDay)` range on `date` is equivalent for
    /// lookup purposes and needs no knowledge of that private algorithm.
    private func fetchTimeBank(userID: UUID, date: Date) throws -> TimeBank? {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        var descriptor = FetchDescriptor<TimeBank>(
            predicate: #Predicate<TimeBank> { $0.userID == userID && $0.date >= start && $0.date < end }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Finds (or creates and inserts, unsaved) `date`'s `TimeBank` row for `userID`. The caller
    /// is responsible for `context.save()` after mutating whatever this returns.
    ///
    /// Known limitation (flagged for the orchestrator rather than solved here, per CLAUDE.md
    /// "don't add abstractions beyond what the session's scope requires"): the App Group store is
    /// shared across six processes (main app + 5 extensions, spec §11/§27). Two processes racing
    /// this method for the same `(userID, date)` at the same instant could both insert a row and
    /// trip `TimeBank`'s unique `dayKey` constraint on `save()`. Earn Mode deposits/spends are
    /// user-initiated and rare enough per second that this is a theoretical edge case, not an
    /// observed one — worth a retry-on-conflict pass once there's a device to reproduce it on.
    private func fetchOrCreateTimeBank(userID: UUID, date: Date) throws -> TimeBank {
        if let existing = try fetchTimeBank(userID: userID, date: date) {
            return existing
        }
        let normalized = Calendar.current.startOfDay(for: date)
        let bank = TimeBank(userID: userID, date: normalized)
        context.insert(bank)
        return bank
    }

    /// Mirrors this Time Bank row to `SharedDefaults.earnedMinutesRemainingToday` only when
    /// `date` is today (local calendar day) — that key is specifically "today's" balance for
    /// widgets/Dynamic Island (spec §5.11 Dynamic Island Earn Meter) to render without a SwiftData
    /// fetch; mirroring a backfilled past/future date's balance there would show the wrong number.
    private func mirrorIfToday(_ bank: TimeBank, for date: Date) async {
        guard Calendar.current.isDateInToday(date) else { return }
        SharedDefaults.earnedMinutesRemainingToday = bank.remainingMin
        // Spec §5.11: the Dynamic Island's draining bar follows every bank change.
        await EarnMeterActivityManager.shared.refreshFromTimeBank(earnedMinutesRemaining: bank.remainingMin)
    }

    /// Gives back minutes a spend took when the unlock it paid for couldn't start.
    private func refund(minutes: Int, for date: Date) async {
        guard let user = try? fetchCurrentUser(),
              let bank = try? fetchTimeBank(userID: user.id, date: date) else { return }
        bank.spentMin = max(0, bank.spentMin - minutes)
        try? context.save()
        await mirrorIfToday(bank, for: date)
    }
}
