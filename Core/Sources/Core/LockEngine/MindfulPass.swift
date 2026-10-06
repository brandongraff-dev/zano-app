// Core/Sources/Core/LockEngine/MindfulPass.swift
//
// docs/spec.md §5.23 (Mindful Pass): a short, escalating pause before a shielded app can be
// opened for a brief pass, with a daily cap. Pure computation only — like `PartialUnlockTiers`, it
// never touches `ManagedSettingsStore`, `DeviceActivityCenter`, or SwiftData, so the policy is
// testable without FamilyControls. Lifting the shield and re-applying it after the pass is wiring
// that needs a device (spec §27) and lives elsewhere.
//
// A pass is NOT a goal: it never counts toward verification, the Time Bank, or the streak, and it
// never replaces Emergency Unlock (spec §24).

import Foundation

/// Tunables for a lock set's Mindful Pass. Defaults match spec §5.23.
public struct MindfulPassPolicy: Sendable, Equatable {
    /// Passes allowed per calendar day before the normal shield returns.
    public var dailyPassCap: Int
    /// Pause length for the first pass of the day.
    public var basePauseSeconds: Int
    /// Added to the pause for each pass already used today.
    public var pauseStepSeconds: Int
    /// Upper bound on the pause so it never becomes a punishment.
    public var maxPauseSeconds: Int
    /// How long a granted pass lasts. 15 min is DeviceActivity's minimum interval (spec §27).
    public var passMinutes: Int

    public init(
        dailyPassCap: Int = 5,
        basePauseSeconds: Int = 10,
        pauseStepSeconds: Int = 5,
        maxPauseSeconds: Int = 45,
        passMinutes: Int = 15
    ) {
        self.dailyPassCap = dailyPassCap
        self.basePauseSeconds = basePauseSeconds
        self.pauseStepSeconds = pauseStepSeconds
        self.maxPauseSeconds = maxPauseSeconds
        self.passMinutes = passMinutes
    }
}

/// What the pause screen should do for the next pass request.
public enum MindfulPassDecision: Sendable, Equatable {
    /// Show a `pauseSeconds` pause, then lift the shield for `passMinutes`.
    case granted(pauseSeconds: Int, passMinutes: Int, passesLeftAfter: Int)
    /// The daily cap is spent; keep the normal shield (goals / emergency still available).
    case capReached
}

public enum MindfulPass {

    /// Decides the next pass given how many were already granted today.
    public static func evaluate(
        policy: MindfulPassPolicy = MindfulPassPolicy(),
        grantsToday: Int
    ) -> MindfulPassDecision {
        let used = max(0, grantsToday)
        guard used < policy.dailyPassCap else { return .capReached }

        let pause = min(policy.maxPauseSeconds, policy.basePauseSeconds + used * policy.pauseStepSeconds)
        return .granted(
            pauseSeconds: pause,
            passMinutes: policy.passMinutes,
            passesLeftAfter: policy.dailyPassCap - used - 1
        )
    }

    /// Number of grant timestamps that fall on the same calendar day as `now`.
    public static func grantsToday(
        in grants: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        grants.filter { calendar.isDate($0, inSameDayAs: now) }.count
    }

    /// Keeps only today's grants so the stored list can't grow without bound.
    public static func prunedToToday(
        _ grants: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        grants.filter { calendar.isDate($0, inSameDayAs: now) }
    }
}
