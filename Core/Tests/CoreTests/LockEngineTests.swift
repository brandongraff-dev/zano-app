// Core/Tests/CoreTests/LockEngineTests.swift
//
// Tests two pieces of Core/Sources/Core/LockEngine, both read in full before writing this file:
//
//   - PartialUnlockTiers.swift: pure tier-computation over a completed-goal count (docs/spec.md
//     §2, §4). No SwiftData, no ManagedSettings/FamilyControls side effects — the file's own
//     header says so explicitly ("Pure computation only... it never calls store.shield... itself")
//     — so every test below is a plain, deterministic value test.
//   - EmergencyUnlock.swift: the 60-second hold `@Observable` state machine (spec §4, §14, §24).
//
// EmergencyUnlock's scope note (read this before extending these tests):
//
//   `completeHold()` — reached only once a hold's `progress` reaches `1.0` at the full 60-second
//   `holdDuration` — calls through to `LockEngineManager.shared.emergencyUnlock(sessionID:)`,
//   which ends by calling a real `ManagedSettingsStore(named: .zanoLock).clearAllSettings()`
//   (`removeShield()` in LockEngineManager.swift). Whether that FamilyControls API call throws,
//   no-ops, or traps when invoked from a plain SwiftPM test bundle with no Family Controls
//   entitlement and no granted authorization is not something this environment can verify (no
//   Mac/device/compiler — flagged in this task's knownIssues). VerificationTests.swift (this same
//   folder, a different concurrent task) draws the identical line for the same reason around
//   `GymVerifier`'s live-CLMonitor-backed `GymDwellState`, excluding it rather than risking an
//   unverified framework call inside a test binary. This file follows that same precedent: no test
//   here ever lets a hold's `progress` reach `1.0` / `completeHold()` run, so `LockEngineManager`,
//   `ManagedSettingsStore`, and `AuthorizationCenter` are never touched. Every reachable, purely
//   local piece of the state machine below `.completing` — begin/cancel/idempotency/penalty
//   toggling/progress-and-countdown tracking — is exercised for real, including real elapsed wall
//   time via `Task.sleep`. Verifying the `.completing → .unlocked`/`.failed` transition itself
//   needs a Mac with the Family Controls (Development) capability — see docs/setup/mac-setup.md —
//   and is left for that session.
//
// `useStreakFreezeInstead()` does reach a real singleton (`StreakEngine.shared`), but that file is
// pure SwiftData + UserDefaults with no FamilyControls/ManagedSettings surface at all, so it's safe
// to exercise here. Its test below deliberately asserts the *documented invariant*
// (`appliesStreakPenalty == !spent`) rather than a specific true/false value for `spent`, since
// `StreakEngine.shared`'s backing store is a process-wide singleton this file doesn't fully
// control the contents of (see that test's comment).

import Foundation
import FamilyControls
import Testing
@testable import Core

// MARK: - PartialUnlockTiers — docs/spec.md §2's "2 of 3 unlocks messaging, all 3 unlocks TikTok"

@Suite("PartialUnlockTiers — spec §2/§4 partial-unlock ladder")
@MainActor
struct PartialUnlockTiersTests {

    // MARK: Fixtures

    /// A `LockSet` with an (optionally) saved, empty `FamilyActivitySelection` — enough to
    /// exercise `remainingLockedSelection`'s nil-vs-present branch without needing any real,
    /// user-picked `ApplicationToken`s (those only ever come from a live `FamilyActivityPicker`
    /// and can't be synthesized in a unit test — see this suite's knownIssues note).
    private func makeLockSet(hasSavedSelection: Bool = true) throws -> LockSet {
        let blob = hasSavedSelection ? try JSONEncoder().encode(FamilyActivitySelection()) : nil
        return LockSet(userID: UUID(), name: "Distractions", appTokensBlob: blob)
    }

    /// Spec §2's literal example, built the way a "partial unlock" settings toggle would build it:
    /// one tier one goal short of the total ("Messaging"), one tier at the full total ("TikTok").
    private func makeSpecExampleLadder() throws -> [PartialUnlockTier] {
        try PartialUnlockTiers.twoTierLadder(
            totalRequiredGoals: 3,
            partialTierName: "Messaging",
            partialSelection: FamilyActivitySelection(),
            fullTierName: "TikTok",
            fullSelection: FamilyActivitySelection()
        )
    }

    // MARK: twoTierLadder shape

    @Test("twoTierLadder puts the partial tier one goal short of the total and the full tier at the total")
    func specExampleLadderHasCorrectThresholds() throws {
        let tiers = try makeSpecExampleLadder()
        #expect(tiers.count == 2)
        let messaging = try #require(tiers.first { $0.name == "Messaging" })
        let tikTok = try #require(tiers.first { $0.name == "TikTok" })
        #expect(messaging.requiredCompletedGoalCount == 2) // 3 - 1
        #expect(tikTok.requiredCompletedGoalCount == 3)
    }

    @Test("totalRequiredGoals: 1 puts the partial tier's threshold at 0, not -1")
    func oneRequiredGoalClampsPartialThresholdToZero() throws {
        let tiers = try PartialUnlockTiers.twoTierLadder(
            totalRequiredGoals: 1,
            partialTierName: "Messaging",
            partialSelection: FamilyActivitySelection(),
            fullTierName: "TikTok",
            fullSelection: FamilyActivitySelection()
        )
        #expect(tiers.first { $0.name == "Messaging" }?.requiredCompletedGoalCount == 0)
        #expect(tiers.first { $0.name == "TikTok" }?.requiredCompletedGoalCount == 1)
    }

    @Test("totalRequiredGoals: 0 never produces a negative threshold")
    func zeroRequiredGoalsNeverGoesNegative() throws {
        let tiers = try PartialUnlockTiers.twoTierLadder(
            totalRequiredGoals: 0,
            partialTierName: "Messaging",
            partialSelection: FamilyActivitySelection(),
            fullTierName: "TikTok",
            fullSelection: FamilyActivitySelection()
        )
        #expect(tiers.allSatisfy { $0.requiredCompletedGoalCount == 0 })
    }

    // MARK: spec §2's example, walked goal-by-goal

    @Test("0 of 3 completed goals unlocks nothing")
    func zeroOfThreeUnlocksNothing() throws {
        let tiers = try makeSpecExampleLadder()
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: tiers, completedGoalIDs: []
        )
        #expect(evaluation.unlockedTiers.isEmpty)
        #expect(evaluation.lockedTiers.map(\.name) == ["Messaging", "TikTok"])
        #expect(evaluation.highestUnlockedTier == nil)
    }

    @Test("1 of 3 completed goals still unlocks nothing (messaging needs 2)")
    func oneOfThreeStillUnlocksNothing() throws {
        let tiers = try makeSpecExampleLadder()
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: tiers, completedGoalIDs: [UUID()]
        )
        #expect(evaluation.unlockedTiers.isEmpty)
        #expect(evaluation.highestUnlockedTier == nil)
    }

    @Test("2 of 3 completed goals unlocks messaging only — spec §2's exact example")
    func twoOfThreeUnlocksMessagingOnly() throws {
        let tiers = try makeSpecExampleLadder()
        let completed: Set<UUID> = [UUID(), UUID()]
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: tiers, completedGoalIDs: completed
        )
        #expect(evaluation.unlockedTiers.map(\.name) == ["Messaging"])
        #expect(evaluation.lockedTiers.map(\.name) == ["TikTok"])
        #expect(evaluation.highestUnlockedTier?.name == "Messaging")
    }

    @Test("all 3 of 3 completed goals unlocks both messaging and TikTok — spec §2's exact example")
    func allThreeUnlocksMessagingAndTikTok() throws {
        let tiers = try makeSpecExampleLadder()
        let completed: Set<UUID> = [UUID(), UUID(), UUID()]
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: tiers, completedGoalIDs: completed
        )
        #expect(evaluation.unlockedTiers.map(\.name) == ["Messaging", "TikTok"])
        #expect(evaluation.lockedTiers.isEmpty)
        #expect(evaluation.highestUnlockedTier?.name == "TikTok")
    }

    @Test("completing more goals than required still keeps every tier unlocked")
    func moreThanRequiredStillUnlocksEverything() throws {
        let tiers = try makeSpecExampleLadder()
        let completed: Set<UUID> = [UUID(), UUID(), UUID(), UUID()]
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: tiers, completedGoalIDs: completed
        )
        #expect(evaluation.unlockedTiers.count == 2)
        #expect(evaluation.highestUnlockedTier?.name == "TikTok")
    }

    @Test("the threshold is purely a count — which specific goal ids are done never matters")
    func thresholdIsACountNotSpecificGoalIdentities() throws {
        let tiers = try makeSpecExampleLadder()
        let lockSet = try makeLockSet()
        let a = PartialUnlockTiers.evaluate(lockSet: lockSet, tiers: tiers, completedGoalIDs: [UUID(), UUID()])
        let b = PartialUnlockTiers.evaluate(lockSet: lockSet, tiers: tiers, completedGoalIDs: [UUID(), UUID()])
        #expect(a.unlockedTiers.map(\.name) == b.unlockedTiers.map(\.name))
    }

    // MARK: General N-tier ladder + ordering

    @Test("evaluate sorts declared-out-of-order tiers loosest-threshold-first")
    func evaluateSortsTiersLoosestFirstRegardlessOfDeclarationOrder() throws {
        let games = try PartialUnlockTier(name: "Games", requiredCompletedGoalCount: 3, selection: FamilyActivitySelection())
        let messaging = try PartialUnlockTier(name: "Messaging", requiredCompletedGoalCount: 1, selection: FamilyActivitySelection())
        let social = try PartialUnlockTier(name: "Social", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())

        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(),
            tiers: [games, messaging, social], // declared out of order on purpose
            completedGoalIDs: [UUID(), UUID()] // 2 completed
        )
        #expect(evaluation.unlockedTiers.map(\.name) == ["Messaging", "Social"])
        #expect(evaluation.lockedTiers.map(\.name) == ["Games"])
        #expect(evaluation.highestUnlockedTier?.name == "Social")
    }

    @Test("two tiers sharing the same threshold unlock together, the instant that count is reached")
    func tiersSharingTheSameThresholdUnlockTogether() throws {
        let messaging = try PartialUnlockTier(name: "Messaging", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())
        let social = try PartialUnlockTier(name: "Social", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())
        let lockSet = try makeLockSet()

        let belowThreshold = PartialUnlockTiers.evaluate(
            lockSet: lockSet, tiers: [messaging, social], completedGoalIDs: [UUID()]
        )
        #expect(belowThreshold.unlockedTiers.isEmpty)

        let atThreshold = PartialUnlockTiers.evaluate(
            lockSet: lockSet, tiers: [messaging, social], completedGoalIDs: [UUID(), UUID()]
        )
        #expect(Set(atThreshold.unlockedTiers.map(\.name)) == ["Messaging", "Social"])
        #expect(atThreshold.lockedTiers.isEmpty)
    }

    @Test("an empty tier list means everything stays locked, no matter how many goals are done")
    func emptyTierListMeansEverythingStaysLocked() throws {
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(), tiers: [], completedGoalIDs: [UUID(), UUID(), UUID()]
        )
        #expect(evaluation.unlockedTiers.isEmpty)
        #expect(evaluation.lockedTiers.isEmpty)
        #expect(evaluation.highestUnlockedTier == nil)
    }

    // MARK: remainingLockedSelection

    @Test("remainingLockedSelection is nil when the LockSet has no saved app selection at all")
    func remainingLockedSelectionIsNilWithNoSavedSelection() throws {
        let tiers = try makeSpecExampleLadder()
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(hasSavedSelection: false), tiers: tiers, completedGoalIDs: []
        )
        #expect(evaluation.remainingLockedSelection == nil)
    }

    @Test("remainingLockedSelection is present (not nil) when the LockSet has a saved selection")
    func remainingLockedSelectionIsPresentWithASavedSelection() throws {
        let tiers = try makeSpecExampleLadder()
        let evaluation = PartialUnlockTiers.evaluate(
            lockSet: try makeLockSet(hasSavedSelection: true), tiers: tiers, completedGoalIDs: []
        )
        #expect(evaluation.remainingLockedSelection != nil)
    }

    // MARK: PartialUnlockTier construction

    @Test("a negative requiredCompletedGoalCount clamps to 0 rather than going negative")
    func negativeThresholdClampsToZero() throws {
        let tier = try PartialUnlockTier(name: "Everything", requiredCompletedGoalCount: -5, selection: FamilyActivitySelection())
        #expect(tier.requiredCompletedGoalCount == 0)
    }

    @Test("selection round-trips through selectionBlob's JSON encoding")
    func selectionRoundTripsThroughSelectionBlob() throws {
        let tier = try PartialUnlockTier(name: "Messaging", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())
        #expect(tier.selection != nil)
    }
}

// MARK: - EmergencyUnlock — 60-second hold state machine (spec §4, §14, §24)

@Suite("EmergencyUnlock — 60-second hold state machine (spec §4, §14, §24)")
@MainActor
struct EmergencyUnlockStateMachineTests {

    // MARK: Initial state

    @Test("starts idle, at full duration, with the streak penalty on by default")
    func initialStateIsIdleAtFullDurationWithPenaltyOn() {
        let unlock = EmergencyUnlock(sessionID: UUID())
        #expect(unlock.phase == .idle)
        #expect(unlock.progress == 0)
        #expect(unlock.secondsRemaining == 60)
        #expect(unlock.appliesStreakPenalty == true)
        #expect(unlock.lastError == nil)
    }

    @Test("can be constructed with the streak penalty pre-disabled")
    func canConstructWithPenaltyDisabled() {
        let unlock = EmergencyUnlock(sessionID: UUID(), appliesStreakPenalty: false)
        #expect(unlock.appliesStreakPenalty == false)
    }

    @Test("holdDuration is a fixed, non-configurable 60 seconds (spec §4/§14)")
    func holdDurationIsFixedAt60Seconds() {
        #expect(EmergencyUnlock.holdDuration == 60)
    }

    // MARK: beginHold / cancelHold

    @Test("beginHold() transitions idle → holding")
    func beginHoldTransitionsIdleToHolding() {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        #expect(unlock.phase == .holding)
        unlock.cancelHold() // stop the background tick loop before the test ends
    }

    @Test("cancelHold() while idle is a no-op")
    func cancelHoldIsNoOpWhileIdle() {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.cancelHold()
        #expect(unlock.phase == .idle)
        #expect(unlock.progress == 0)
    }

    @Test("cancelHold() during a hold returns to idle and resets progress/countdown")
    func cancelHoldDuringHoldResetsProgressAndCountdown() async throws {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 150_000_000) // let a few ticks land
        #expect(unlock.progress > 0)

        unlock.cancelHold()
        #expect(unlock.phase == .idle)
        #expect(unlock.progress == 0)
        #expect(unlock.secondsRemaining == 60)
    }

    @Test("releasing a hold early is never a penalty by itself (never punish attempting to leave)")
    func releasingEarlyDoesNotTouchTheStreakPenaltyChoice() async throws {
        let unlock = EmergencyUnlock(sessionID: UUID())
        #expect(unlock.appliesStreakPenalty == true)
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 100_000_000)
        unlock.cancelHold()
        #expect(unlock.appliesStreakPenalty == true) // unchanged by cancelling
    }

    @Test("a cancelled hold can be restarted from idle")
    func canRestartAfterCancelling() async throws {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 100_000_000)
        unlock.cancelHold()
        #expect(unlock.phase == .idle)

        unlock.beginHold()
        #expect(unlock.phase == .holding)
        unlock.cancelHold()
    }

    @Test("beginHold() is idempotent while already holding — it does not restart the in-flight hold")
    func beginHoldIsIdempotentWhileAlreadyHolding() async throws {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 200_000_000)
        let progressBeforeSecondCall = unlock.progress
        #expect(progressBeforeSecondCall > 0)

        unlock.beginHold() // guard: phase == .holding, not .idle/.failed — must no-op
        #expect(unlock.phase == .holding)

        try await Task.sleep(nanoseconds: 100_000_000)
        // The original hold kept running (progress kept climbing) rather than being reset by
        // the second beginHold() call.
        #expect(unlock.progress >= progressBeforeSecondCall)

        unlock.cancelHold()
    }

    // MARK: progress / secondsRemaining tracking (real elapsed time, well short of completion)

    @Test("progress and secondsRemaining track real elapsed time during a hold")
    func progressAndSecondsRemainingTrackElapsedTime() async throws {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 300_000_000) // ~0.3s into a 60s hold

        // Generous bounds (not a tight equality) so this stays robust against CI scheduler
        // jitter while still proving the tick loop is live and roughly on-pace.
        #expect(unlock.progress > 0)
        #expect(unlock.progress < 0.5)
        #expect(unlock.secondsRemaining >= 30)
        #expect(unlock.secondsRemaining <= 60)

        unlock.cancelHold()
    }

    // MARK: setAppliesStreakPenalty guard

    @Test("setAppliesStreakPenalty toggles freely while idle or holding")
    func setAppliesStreakPenaltyTogglesWhileIdleOrHolding() {
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.setAppliesStreakPenalty(false)
        #expect(unlock.appliesStreakPenalty == false)

        unlock.beginHold()
        unlock.setAppliesStreakPenalty(true)
        #expect(unlock.appliesStreakPenalty == true)
        unlock.cancelHold()
    }

    @Test("the idle/holding guard isn't sticky — setAppliesStreakPenalty still works after a cancel")
    func setAppliesStreakPenaltyStillWorksAfterACancel() async throws {
        // Sanity check that the idle/holding guard isn't accidentally sticky across a
        // cancel → restart cycle.
        let unlock = EmergencyUnlock(sessionID: UUID())
        unlock.beginHold()
        try await Task.sleep(nanoseconds: 50_000_000)
        unlock.cancelHold()
        unlock.setAppliesStreakPenalty(false)
        #expect(unlock.appliesStreakPenalty == false)
    }

    // MARK: useStreakFreezeInstead (StreakEngine.shared — pure SwiftData, no FamilyControls)

    @Test("useStreakFreezeInstead keeps appliesStreakPenalty consistent with whether a freeze was actually spent")
    func useStreakFreezeInsteadKeepsPenaltyConsistentWithWhetherAFreezeWasSpent() async {
        // StreakEngine.shared is a process-wide singleton this file doesn't fully control the
        // contents of (see this file's header), so this deliberately asserts the *documented*
        // invariant from EmergencyUnlock.swift's own doc comment — "if a freeze was spent
        // (`true`), appliesStreakPenalty is now off" — rather than a specific true/false value
        // for whether a freeze happened to be available.
        let unlock = EmergencyUnlock(sessionID: UUID())
        #expect(unlock.appliesStreakPenalty == true)
        let spent = await unlock.useStreakFreezeInstead()
        #expect(unlock.appliesStreakPenalty == !spent)
    }
}
