// TierGating.swift
// Core / Monetization
//
// docs/spec.md §21 (Monetization & Paywall), tier table verbatim:
//   "Free: 1 goal, 1 lock set, manual/NFC lock, basic widget, 1 streak freeze/week.
//    Pro: unlimited goals & lock sets, schedules, adaptive plan, Earn Mode, protein photo AI,
//    recaps, squads/duels, 3 freezes, cosmetics."
// Feature-level cross-references for the flags below: §4 v1 ("Lock via: manual button, NFC tag,
// daily schedule" — §21 puts only manual/NFC on Free, so the daily *schedule* trigger is the Pro
// "schedules" line), §5.2 (Earn Mode / Time Bank), §9.1 (Adaptive Goal Engine — "adaptive plan"),
// §5.6 / §8 rule 3 (streak freezes: 1/week Free, 3/week Pro).
//
// `TierGating` is the one place that turns that tier table into concrete yes/no and count answers
// a call site can check before letting a Free user do something Pro-gated. It is pure decision
// logic: no SwiftData, no UI, no `Copy` entries. What a call site *does* with a `false` — show the
// paywall, throw a typed error, disable a control — and whatever `Copy`-owned string it shows the
// user when it does, belongs to that call site, not here (same split `AlwaysAllowedCheck` and
// `CosmeticsStore.CosmeticPurchaseOutcome` already use: a plain decision, no UI opinions).
//
// === Source of truth for "is this user Pro?" ===
//
// Every gate below that actually depends on tier reads `RevenueCatManager.shared.
// isProSubscriber()` (`Monetization/RevenueCatManager.swift`) — this task's brief is explicit
// about that, and it matches what `PaywallViewModel`/`CosmeticsStore` each document for their own
// cheap local `User.planTier` mirror: that mirror is "deliberately not a substitute for
// `RevenueCatManager.isProSubscriber()`'s network-backed truth anywhere a real entitlement gate is
// being enforced." This file is that real entitlement gate.
//
// `isProSubscriber()` is `async` (it can hit RevenueCat's cached/network `customerInfo()`), so
// every method here is `async` and callers must `await`. It never throws: an unconfigured SDK, a
// missing entitlement, or a network failure all degrade to `false` (Free) — see its own doc
// comment. Consequence worth knowing: RevenueCat is not linked yet (`docs/dependencies.md`,
// "Session 6"), so today `isProSubscriber()` is always `false` and *every* user is gated as Free
// until it is added and `configure(apiKey:)` runs.
//
// === One optimization, deliberately behavior-preserving ===
//
// The two count-based gates (`canCreateAnotherGoal`, `canCreateAnotherLockSet`) return `true`
// immediately when `currentCount` is still under the Free cap, without consulting RevenueCat at
// all: the answer cannot depend on tier in that case (Free and Pro both get at least that many),
// and skipping the entitlement read keeps a brand-new user's very first goal / lock set creation
// instant and offline (CLAUDE.md: "Unlock must be instant and offline"; onboarding creates both
// before any purchase can have happened). Results are identical to reading the tier first.
//
// Enforcement wiring in this file's task: `LockSetManager.createLockSet(name:selection:
// makeDefault:)` is the one concrete call site (it throws
// `LockSetManagerError.freeTierLockSetLimitReached`). Every other §21 call site — goal creation,
// scheduled locks, Earn Mode, the adaptive plan — lives in files this task does not own and is
// listed as follow-up integration in this task's knownIssues rather than edited from here.

import Foundation

/// Free-vs-Pro limits and feature availability (docs/spec.md §21). Stateless: nothing here caches
/// Pro status, so every call sees the current entitlement.
public enum TierGating {

    // MARK: - Limits (spec §21)

    /// Free tier goal cap ("1 goal"). Pro is unlimited.
    public static let freeGoalLimit = 1
    /// Free tier lock set cap ("1 lock set"). Pro is unlimited.
    public static let freeLockSetLimit = 1
    /// Streak freezes per week on Free ("1 streak freeze/week"). Matches
    /// `StreakEngine`'s own private weekly allowance (1 free / 3 pro, same spec line), which reads
    /// the local `User.planTier` instead of this file — see that file's `weeklyFreezeAllowance`.
    public static let freeStreakFreezesPerWeek = 1
    /// Streak freezes per week on Pro ("3 freezes").
    public static let proStreakFreezesPerWeek = 3

    // MARK: - Count-based gates

    /// Whether the user may create one more goal.
    ///
    /// - Parameter currentCount: How many goals the user already has, *before* the new one. The
    ///   caller supplies it (there is no goal-creation manager to count for us — goals are
    ///   inserted straight into a `ModelContext` by their call sites).
    /// - Returns: `true` if `currentCount` is under the Free cap (any tier), otherwise whether the
    ///   user is Pro (unlimited).
    public static func canCreateAnotherGoal(currentCount: Int) async -> Bool {
        if currentCount < freeGoalLimit { return true }
        return await isPro()
    }

    /// Whether the user may create one more lock set. Backs the gate in
    /// `LockSetManager.createLockSet(name:selection:makeDefault:)`.
    ///
    /// - Parameter currentCount: How many lock sets the user already has, *before* the new one.
    /// - Returns: `true` if `currentCount` is under the Free cap (any tier), otherwise whether the
    ///   user is Pro (unlimited).
    public static func canCreateAnotherLockSet(currentCount: Int) async -> Bool {
        if currentCount < freeLockSetLimit { return true }
        return await isPro()
    }

    // MARK: - Streak freezes

    /// Streak freezes granted per week to this user's tier: 1 on Free, 3 on Pro (spec §21).
    public static func maxStreakFreezesPerWeek() async -> Int {
        let pro = await isPro()
        return pro ? proStreakFreezesPerWeek : freeStreakFreezesPerWeek
    }

    // MARK: - Pro-only feature flags

    /// Earn Mode / Time Bank (spec §5.2, §21) — Pro only. Free stays on the plain
    /// goal-gated lock.
    public static func earnModeAvailable() async -> Bool {
        await isPro()
    }

    /// Scheduled (daily) locks (spec §4 v1, §21 "schedules") — Pro only. Free is manual/NFC lock.
    public static func scheduledLocksAvailable() async -> Bool {
        await isPro()
    }

    /// The adaptive plan (spec §9.1 Adaptive Goal Engine, §21 "adaptive plan") — Pro only.
    public static func adaptivePlanAvailable() async -> Bool {
        await isPro()
    }

    // MARK: - Private

    /// The single read of Pro status — every tier-dependent gate above funnels through here.
    private static func isPro() async -> Bool {
        await RevenueCatManager.shared.isProSubscriber()
    }
}
