// Core/Sources/Core/Social/NudgeSender.swift
//
// docs/spec.md §9.3 Nudge Optimizer ("Arms: tone (4) × timing slot (morning / pre-gym window /
// 4 PM / evening) × format (push / widget copy / shield copy). Reward: goal completed within 3
// hours of nudge. Per-user bandit with population prior. Respect the 2/day cap.") and §8
// Retention Psychology Rules, rule 7 ("Nudge scarcity. Max 2 proactive pushes/day. A nudge must
// change what the user does tonight or it doesn't send.").
//
// Scope (this task's owned slice of §9.3): enforce the 2/day cap client-side, and close the loop
// by recording `delivered` / `acted_within_3h` on `Nudge` (Core/Sources/Core/Models/Nudge.swift —
// owned by Session 1; reused verbatim here, including its `NudgeArm`/`NudgeTone`/
// `NudgeTimingSlot`/`NudgeFormat` types, never redeclared). This file does NOT own:
//   - *Which* arm to pick. §9.3's per-user contextual bandit is the ML service (§9.9, session
//     `feat/ml`, the `/nudge` endpoint) — this file's job starts once a caller (that model, or a
//     v1 population-prior rule, whichever lands first) has already chosen tone × timing slot ×
//     format and asks "send this now (subject to the cap)."
//   - *Rendering* the chosen `NudgeFormat` — a push notification (`UNUserNotificationCenter` +
//     Core/Sources/Core/Copy for the actual copy text), or writing widget/shield-visible state
//     (`SharedDefaults` + the Shield/Widget extensions). None of those modules belong to this
//     task. `send(arm:on:deliver:)`'s `deliver` closure is the seam: a no-op by default (so this
//     file's cap/record/attribution behavior is complete and real without it), and the actual
//     rendering is a narrow, explicitly-scoped cross-module integration point for whichever
//     session wires up push/widget/shield delivery.

import Foundation
import SwiftData
import os

// MARK: - Errors

/// Errors `NudgeSender` throws itself, as opposed to errors bubbled up from SwiftData. Kept as
/// plain, developer-facing diagnostics (mirroring `LockEngineError`'s documented convention) —
/// not routed through `Core/Sources/Core/Copy`, since nothing here is copy meant to be shown
/// verbatim to the user.
public enum NudgeSenderError: Error, Sendable, Equatable, LocalizedError {
    /// No local `User` row exists yet to attribute this nudge to.
    case noSignedInUser

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser:
            "No local User row exists yet."
        }
    }
}

// MARK: - Kinds and preferences (Settings → Nudges)

/// What a nudge is *about* — the user-facing categories Settings lets them switch off. Orthogonal
/// to `NudgeArm` (tone × timing × format), which is how it's said, not what it's for.
public enum NudgeKind: String, CaseIterable, Identifiable, Sendable {
    /// The morning "here's today's plan" nudge.
    case morningPlan = "morning_plan"
    /// The 8 PM protein "last mile" nudge when within 20 g (spec, Wave 2 list).
    case proteinLastMile = "protein_last_mile"
    /// Streak at risk tonight (spec §5.6, §9.2 slip prediction).
    case streakAtRisk = "streak_at_risk"
    /// The weekly recap (spec §5.12).
    case weeklyRecap = "weekly_recap"

    public var id: String { rawValue }
}

/// Why a nudge didn't go out. The 2/day cap is one reason among several now; all are normal
/// outcomes, not errors.
public enum NudgeSuppressionReason: String, Sendable, Equatable {
    /// spec §8 rule 7: already 2 delivered today.
    case dailyCap
    /// A health pause is active (spec §24) — no proactive nudges at all.
    case healthPause
    /// The user switched nudges off.
    case nudgesOff
    /// The user switched this `NudgeKind` off.
    case kindOff
    /// Inside the user's quiet hours.
    case quietHours
}

/// A snapshot of the user's nudge settings, read from `SharedDefaults`.
public struct NudgePreferences: Sendable, Equatable {
    public var enabled: Bool
    public var quietHoursEnabled: Bool
    /// Minutes after local midnight.
    public var quietStartMinutes: Int
    /// Minutes after local midnight.
    public var quietEndMinutes: Int
    public var disabledKinds: Set<NudgeKind>

    public init(
        enabled: Bool = true,
        quietHoursEnabled: Bool = false,
        quietStartMinutes: Int = 22 * 60,
        quietEndMinutes: Int = 7 * 60,
        disabledKinds: Set<NudgeKind> = []
    ) {
        self.enabled = enabled
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartMinutes = quietStartMinutes
        self.quietEndMinutes = quietEndMinutes
        self.disabledKinds = disabledKinds
    }

    /// The saved preferences.
    public static var current: NudgePreferences {
        get {
            NudgePreferences(
                enabled: SharedDefaults.nudgesEnabled,
                quietHoursEnabled: SharedDefaults.nudgeQuietHoursEnabled,
                quietStartMinutes: SharedDefaults.nudgeQuietStartMinutes,
                quietEndMinutes: SharedDefaults.nudgeQuietEndMinutes,
                disabledKinds: Set(SharedDefaults.nudgeDisabledKinds.compactMap(NudgeKind.init(rawValue:)))
            )
        }
        set {
            SharedDefaults.nudgesEnabled = newValue.enabled
            SharedDefaults.nudgeQuietHoursEnabled = newValue.quietHoursEnabled
            SharedDefaults.nudgeQuietStartMinutes = newValue.quietStartMinutes
            SharedDefaults.nudgeQuietEndMinutes = newValue.quietEndMinutes
            SharedDefaults.nudgeDisabledKinds = Set(newValue.disabledKinds.map(\.rawValue))
        }
    }

    public func isEnabled(_ kind: NudgeKind) -> Bool { !disabledKinds.contains(kind) }

    /// Whether `date` falls in quiet hours. Handles windows that wrap past midnight (22:00–07:00).
    /// Start is inclusive, end exclusive; equal start and end means no quiet window.
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled, quietStartMinutes != quietEndMinutes else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if quietStartMinutes < quietEndMinutes {
            return minutes >= quietStartMinutes && minutes < quietEndMinutes
        }
        return minutes >= quietStartMinutes || minutes < quietEndMinutes
    }

    /// The first reason (other than the daily cap) a nudge of `kind` can't go out at `date`, or
    /// `nil` if it may. A health pause beats everything.
    public func suppressionReason(for kind: NudgeKind?, at date: Date, calendar: Calendar = .current) -> NudgeSuppressionReason? {
        if HealthPause.isActive(at: date) { return .healthPause }
        if !enabled { return .nudgesOff }
        if let kind, !isEnabled(kind) { return .kindOff }
        if isQuiet(at: date, calendar: calendar) { return .quietHours }
        return nil
    }
}

// MARK: - Result

/// What actually happened when `send(arm:on:deliver:)` was called. Suppression by the daily cap
/// is a normal, frequently-expected outcome (spec §8 rule 7) — not an error — so it's represented
/// here rather than thrown; `Nudge.delivered`'s doc comment is explicit that a row gets written
/// either way ("true once the push/widget/shield copy actually reached the user, as opposed to
/// being selected but suppressed"), which is exactly what keeps this a useful training signal for
/// §9.3's bandit later (it needs to see how often an arm was picked but capped out, not just how
/// often it was actually delivered).
public struct NudgeSendOutcome: Sendable, Equatable {
    /// The `Nudge.id` of the row this call wrote — always written, delivered or not.
    public let nudgeID: UUID
    /// `true` if this call's `deliver` closure ran (i.e. the nudge actually reached the user);
    /// `false` if it was suppressed (see ``suppressedBy``).
    public let delivered: Bool
    /// Why it was suppressed; `nil` when delivered.
    public let suppressedBy: NudgeSuppressionReason?

    init(nudgeID: UUID, delivered: Bool, suppressedBy: NudgeSuppressionReason? = nil) {
        self.nudgeID = nudgeID
        self.delivered = delivered
        self.suppressedBy = suppressedBy
    }
}

// MARK: - NudgeSender

/// `@MainActor`, not a plain `actor`: matches this codebase's established choice for every other
/// `Core` engine that owns a `ModelContext` against the shared App Group store
/// (`LockEngineManager`, `FocusSessionVerifier`) — see those files' doc comments for the same
/// reasoning. A `@MainActor final class` is implicitly usable across actor boundaries through its
/// `async` members, the same way `static let shared` and every call site elsewhere in `Core`
/// already assumes.
@MainActor
public final class NudgeSender {
    public static let shared = NudgeSender()

    /// docs/spec.md §8 rule 7: "Max 2 proactive pushes/day."
    public static let dailyCap = 2

    /// docs/spec.md §9.3: "Reward: goal completed within 3 hours of nudge."
    public static let attributionWindow: TimeInterval = 3 * 60 * 60

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "NudgeSender")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(
        modelContainer: ModelContainer = .appGroup,
        preferences: @escaping @Sendable () -> NudgePreferences = { NudgePreferences.current }
    ) {
        self.modelContainer = modelContainer
        self.preferences = preferences
    }

    /// Where the user's nudge settings come from — `SharedDefaults` in the app, a fixed value in
    /// tests.
    private let preferences: @Sendable () -> NudgePreferences

    // MARK: - Send (cap enforcement + delivery record)

    /// Attempts to send a nudge for the already-chosen `arm`. Always writes a `Nudge` row (spec
    /// §9.3's bandit needs to see suppressed attempts, not just delivered ones — see
    /// `NudgeSendOutcome`'s doc comment); only actually invokes `deliver` — and only counts toward
    /// the cap — when today's delivered count for the local user is still under
    /// ``dailyCap``.
    ///
    /// - Parameters:
    ///   - arm: The tone × timing slot × format combination already selected by the caller (the
    ///     bandit/`/nudge` endpoint, or a simpler v1 rule) — this file does not choose one itself.
    ///   - date: When this nudge is being sent; defaults to now. Also the day the 2/day cap is
    ///     evaluated against (local calendar day).
    ///   - deliver: Runs only when the nudge is not suppressed — the actual push/widget/shield
    ///     rendering for `arm.format` (see this file's header comment for why that's not
    ///     implemented here). Defaults to a no-op so calling this without a `deliver` closure
    ///     still does the complete, real cap-enforcement + persistence work this task owns.
    /// - Returns: ``NudgeSendOutcome`` — always has a `nudgeID` (a row was written either way).
    /// - Throws: ``NudgeSenderError/noSignedInUser``, or whatever `ModelContext.save()` throws.
    @discardableResult
    public func send(
        arm: NudgeArm,
        on date: Date = .now,
        deliver: (NudgeArm) async -> Void = { _ in }
    ) async throws -> NudgeSendOutcome {
        try await send(kind: nil, arm: arm, on: date, deliver: deliver)
    }

    /// Same as ``send(arm:on:deliver:)``, and also honours the user's per-kind switch in Settings
    /// → Nudges. Every product nudge should come through here with its ``NudgeKind``. Order of
    /// checks: health pause (spec §24), nudges off, this kind off, quiet hours, then the 2/day cap
    /// (spec §8 rule 7). A row is written whichever way it goes.
    @discardableResult
    public func send(
        kind: NudgeKind?,
        arm: NudgeArm,
        on date: Date = .now,
        deliver: (NudgeArm) async -> Void = { _ in }
    ) async throws -> NudgeSendOutcome {
        let user = try fetchCurrentUser()
        let deliveredToday = try deliveredCount(for: user.id, on: date)
        let reason: NudgeSuppressionReason? = preferences().suppressionReason(for: kind, at: date, calendar: calendar)
            ?? (deliveredToday < Self.dailyCap ? nil : .dailyCap)
        let willDeliver = reason == nil

        let nudge = Nudge(userID: user.id, ts: date, arm: arm, delivered: willDeliver)
        context.insert(nudge)
        try context.save()

        if willDeliver {
            await deliver(arm)
            logger.notice(
                "Delivered nudge \(nudge.id.uuidString, privacy: .public) (arm: tone=\(arm.tone.rawValue, privacy: .public) timing=\(arm.timingSlot.rawValue, privacy: .public) format=\(arm.format.rawValue, privacy: .public))."
            )
        } else {
            logger.notice(
                "Suppressed nudge \(nudge.id.uuidString, privacy: .public) — \(reason?.rawValue ?? "unknown", privacy: .public) (\(deliveredToday, privacy: .public)/\(Self.dailyCap, privacy: .public) already delivered today)."
            )
        }

        return NudgeSendOutcome(nudgeID: nudge.id, delivered: willDeliver, suppressedBy: reason)
    }

    /// How many more nudges can be delivered to the local user today before ``dailyCap`` is hit.
    /// Cheap, non-throwing check for a caller (e.g. a scheduler deciding whether it's even worth
    /// asking the bandit for an arm) that doesn't need `send`'s full error handling — returns `0`
    /// rather than throwing if there's no signed-in user or the fetch fails.
    public func remainingToday(on date: Date = .now) async -> Int {
        guard preferences().suppressionReason(for: nil, at: date, calendar: calendar) == nil else { return 0 }
        guard let user = try? fetchCurrentUser(),
              let deliveredToday = try? deliveredCount(for: user.id, on: date)
        else { return 0 }
        return max(0, Self.dailyCap - deliveredToday)
    }

    // MARK: - Attribution (reward signal for §9.3's bandit)

    /// Closes the 3-hour attribution window (spec §9.3) for every delivered nudge that's old
    /// enough and hasn't been scored yet: sets `Nudge.actedWithin3h` to whether the user had a
    /// verified goal completion in the 3 hours following it. Idempotent — a nudge whose window is
    /// already closed (`actedWithin3h != nil`) is left untouched — so this is safe to call
    /// repeatedly from a periodic background task (e.g. on launch, or a `BGAppRefreshTask`).
    ///
    /// - Returns: how many `Nudge` rows were scored by this call.
    @discardableResult
    public func closeExpiredAttributionWindows(asOf now: Date = .now) async throws -> Int {
        let cutoff = now.addingTimeInterval(-Self.attributionWindow)
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate<Nudge> {
                $0.delivered == true && $0.actedWithin3h == nil && $0.ts <= cutoff
            }
        )
        let pending = try context.fetch(descriptor)
        guard !pending.isEmpty else { return 0 }

        for nudge in pending {
            let windowEnd = nudge.ts.addingTimeInterval(Self.attributionWindow)
            nudge.actedWithin3h = try hasVerifiedGoalCompletion(userID: nudge.userID, from: nudge.ts, to: windowEnd)
        }
        try context.save()
        return pending.count
    }

    // MARK: - SwiftData

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw NudgeSenderError.noSignedInUser
        }
        return user
    }

    /// Number of `Nudge` rows already **delivered** to `userID` on `date`'s local calendar day —
    /// the exact quantity spec §8 rule 7's "2/day cap" caps. `Nudge.userID` is a plain `UUID`
    /// property (not a `@Relationship`, unlike `GoalEvent.user`), so the owner check can live
    /// directly in the `#Predicate` here.
    private func deliveredCount(for userID: UUID, on date: Date) throws -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }
        let descriptor = FetchDescriptor<Nudge>(
            predicate: #Predicate<Nudge> {
                $0.userID == userID && $0.delivered == true && $0.ts >= startOfDay && $0.ts < startOfNextDay
            }
        )
        return try context.fetchCount(descriptor)
    }

    /// Best-effort proxy for spec §9.3's reward ("*the targeted goal* completed within 3 hours of
    /// the nudge"): `Nudge` (Models/Nudge.swift, owned by Session 1) carries no `goalID` — only
    /// `userID`/`ts`/`arm`/`delivered`/`actedWithin3h` — so there is no way from this model alone
    /// to know which single goal a given nudge was actually about. This checks for *any* verified
    /// goal completion (`GoalEvent.kind` of `.complete` or `.planB`, `verified == true`) by the
    /// same user in the window instead, which is a real, usable-today reward signal but a coarser
    /// one than the spec describes. Flagged in this task's `knownIssues`; the precise fix (adding
    /// `Nudge.goalID: UUID?`) is Session 1's model to extend, not this file's to guess at.
    ///
    /// Filters the relationship (`event.user?.id`) in plain Swift after fetching by the
    /// `#Predicate`-safe fields only (`verified`, `ts`), mirroring `LockEngineManager.
    /// isGoalVerified(goalID:coveringDayOf:)`'s documented reasoning for the same tradeoff.
    private func hasVerifiedGoalCompletion(userID: UUID, from: Date, to: Date) throws -> Bool {
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= from && $0.ts <= to }
        )
        let events = try context.fetch(descriptor)
        return events.contains { event in
            event.user?.id == userID && (event.kind == .complete || event.kind == .planB)
        }
    }
}
