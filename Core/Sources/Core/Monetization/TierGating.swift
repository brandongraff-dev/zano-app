// TierGating.swift
// Core / Monetization
//
// docs/spec.md §21 (decision 2026-09-23): there is NO free tier. Every user is in a trial or a paid
// subscription, and `EntitlementGate` blocks the whole app when neither holds. So feature gating
// collapses to a single question — "is this user entitled?" — instead of the earlier Free/Pro split
// (1 goal, 1 lock set, Pro-only Earn Mode / schedules / adaptive plan).
//
// The functions keep their old names and signatures because call sites exist
// (`LockSetManager.createLockSet` asks `canCreateAnotherLockSet`); they now answer "yes" for anyone
// who is not definitively lapsed (see `EntitlementGate` for why unknown counts as entitled).

import Foundation

public enum TierGating {

    /// Streak freezes granted per week to every subscriber (spec §21 "3 freezes").
    public static let streakFreezesPerWeek = 3

    /// Whether the user may create one more goal. `currentCount` is kept for source compatibility.
    public static func canCreateAnotherGoal(currentCount: Int) async -> Bool {
        await entitled()
    }

    /// Whether the user may create one more lock set. Backs the gate in
    /// `LockSetManager.createLockSet(name:selection:makeDefault:)`.
    public static func canCreateAnotherLockSet(currentCount: Int) async -> Bool {
        await entitled()
    }

    /// Streak freezes per week: the same for every subscriber.
    public static func maxStreakFreezesPerWeek() async -> Int {
        streakFreezesPerWeek
    }

    /// Earn Mode / Time Bank (spec §5.2).
    public static func earnModeAvailable() async -> Bool {
        await entitled()
    }

    /// Scheduled (daily) locks (spec §4 v1).
    public static func scheduledLocksAvailable() async -> Bool {
        await entitled()
    }

    /// The adaptive plan (spec §9.1).
    public static func adaptivePlanAvailable() async -> Bool {
        await entitled()
    }

    private static func entitled() async -> Bool {
        await EntitlementGate.shared.isEntitledNow()
    }
}
