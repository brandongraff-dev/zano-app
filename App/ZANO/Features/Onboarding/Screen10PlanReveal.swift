// Screen10PlanReveal.swift
// App / Features / Onboarding
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). See
// `Screen9WakeUp.swift`'s header for the full `Copy.onboarding.*` assumed API this file (and its
// siblings) depend on. `OnboardingFlowState`, `MainGoal`, and `FallOffPattern` are all now verified
// against `OnboardingFlowState.swift` (sibling-owned, read but never edited) rather than guessed —
// see that file's own header table for the full 14-screen map.
//
// docs/spec.md §7.10 "Plan reveal": '"Your Lock-In Plan": locked apps, goals, schedule, starting
// difficulty (deliberately below stated target). Looks bespoke. "Built for you in 2:14."'
//
// Persistence: `OnboardingFlowState.swift`'s own header states the expectation explicitly —
// "Plan Reveal (screen 10) is expected to hand this [`selectedApps`] straight to
// `LockSetManager.createLockSet(name:selection:)` to become the user's default lock set" — and
// `Core/Sources/Core/Monetization/PaywallViewModel.swift` (screen 13, a different task this same
// batch) reads exactly that: `loadBuiltPlanAndLocalProStatus()` fetches the current user's active
// `Goal`s and default `LockSet` to render the paywall's "the plan you built" section, with its own
// doc comment noting it degrades gracefully to an empty section if "Plan Reveal hasn't run yet."
// So this screen is not purely presentational after all — on appear, `persistPlanIfNeeded()` turns
// `flowState`'s Q1/Q2/Q4 answers into real `Goal` rows and a real default `LockSet`, exactly once
// per distinct goal type, via `IntentSupport.activeGoal` (idempotent re-check) and
// `LockSetManager.createLockSet` — both real, on-disk Core APIs. This never blocks "Continue": any
// failure here is swallowed (matching `Screen14FirstWin.swift`'s own "never trap the user on a
// SwiftData write" precedent), and `Screen14FirstWin.swift` re-derives/re-creates whatever's still
// missing defensively when the first win actually needs it, so this screen's persistence is a
// best-effort head start for Paywall, not a hard dependency anything downstream requires.
//
// Known edge case (knownIssues): if a user goes back (`flowState.goBack()`) and changes Q1/Q4,
// returning to this screen adds the newly-implied goal type rather than reconciling/removing the
// old one — acceptable for an onboarding preview screen (CLAUDE.md: don't add abstractions beyond
// what's needed), not silently patched.
//
// Starting difficulty implements docs/spec.md §8 rule 1 verbatim: "Early wins are engineered.
// First 3 days' goals are ~70% of stated capability. The engine raises the bar only after wins."
// `AdaptiveGoalEngine` (Retention module, not owned by this session) is the long-run owner of that
// curve; this screen's 70% starting point is just the one-time onboarding preview of day one.

import SwiftUI
import SwiftData
import FamilyControls
import Core

@MainActor
struct Screen10PlanReveal: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                LockStatusCard(
                    isLocked: true,
                    statusLine: lockedAppsStatusLine,
                    detailLine: Copy.onboarding.planLockedAppsDetailLine
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(planGoals) { goal in
                        GoalRow(
                            title: Copy.onboarding.planGoalTitle(for: goal.type),
                            detail: Copy.onboarding.planGoalStartingDetail(
                                current: goal.startingValue,
                                target: goal.targetValue,
                                unit: goal.unit
                            ),
                            icon: goal.icon,
                            color: Theme.Colors.Ring.color(for: goal.type),
                            status: .pending
                        )
                    }
                }

                scheduleCard

                Text(Copy.onboarding.planBuiltInLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity)

                PrimaryButton(title: Copy.onboarding.planContinueButton) {
                    flowState.advance()
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .task {
            await persistPlanIfNeeded()
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "plan_reveal", "screen_number": 10]
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(Copy.onboarding.planRevealEyebrow)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.accent)
                .textCase(.uppercase)
            Text(Copy.onboarding.planRevealHeadline)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(Copy.onboarding.planScheduleLine)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            if let pattern = flowState.fallOffPattern {
                // `FallOffPattern` is an App-target-only type (`OnboardingFlowState.swift`) — Core
                // cannot declare a `Copy.onboarding.*` function parameterized on it (that file's own
                // doc comment explains why: Core cannot import an App-only type). This resolves the
                // display label on the App side first (`FallOffPattern.displayLabel`, the same
                // narrow Copy-routing exception that file already establishes) and only passes the
                // resulting plain `String` across the module boundary.
                Text(Copy.onboarding.planScheduleFallOffNote(patternLabel: pattern.displayLabel))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var lockedAppsStatusLine: String {
        let selection = flowState.selectedApps
        return Copy.onboarding.planLockedAppsStatusLine(
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    // MARK: - Goal preview rows

    /// One row's worth of the plan preview, derived from `flowState.mainGoal` (Q1) plus, where the
    /// mapped `GoalType` is count-based, `flowState.currentWorkoutsPerWeek`/`targetWorkoutsPerWeek`
    /// (Q4). `.allOfIt` shows every mapped goal type; every other case shows its one match. Uses
    /// only Core's own `GoalType`/`VerificationTier` (never the App-only `MainGoal`) so this same
    /// value can be handed straight to `Goal.init` in `persistPlanIfNeeded()` below.
    private struct PlanGoalPreview: Identifiable {
        let id = UUID()
        let type: GoalType
        let tier: VerificationTier
        let icon: String
        let targetValue: Int
        let unit: String

        /// Spec §8 rule 1: day-one target is ~70% of stated capability, never below what the user
        /// already reported doing (no point "starting" below their own baseline) and never above
        /// the target itself.
        var startingValue: Int {
            let seventyPercent = Int((Double(targetValue) * 0.7).rounded())
            return min(targetValue, max(1, seventyPercent))
        }
    }

    /// Protein has no dedicated onboarding question (Q1-Q6 don't collect a gram target) — 120g/day
    /// is a reasonable, commonly-cited baseline used only as this preview's placeholder target;
    /// the real per-user target is a Fuel-screen/goal-setup concern (docs/spec.md §17 Session 5),
    /// not this onboarding preview. Flagged as an assumption in this task's `decisions`.
    private static let assumedDailyProteinTargetGrams = 120

    private var planGoals: [PlanGoalPreview] {
        let workoutTarget = max(1, flowState.targetWorkoutsPerWeek)
        let focusTarget = FocusSessionPreset.twentyFiveMinutes.minutes

        let workout = PlanGoalPreview(type: .workoutGym, tier: .a, icon: "dumbbell.fill", targetValue: workoutTarget, unit: "workouts")
        let focus = PlanGoalPreview(type: .focusSession, tier: .a, icon: "timer", targetValue: focusTarget, unit: "min")
        let protein = PlanGoalPreview(type: .protein, tier: .b, icon: "fork.knife", targetValue: Self.assumedDailyProteinTargetGrams, unit: "g")

        switch flowState.mainGoal {
        case .gymConsistency: return [workout]
        case .protein: return [protein]
        case .stopDoomscrolling: return [focus]
        case .lockInWorkSchool: return [focus]
        case .allOfIt: return [workout, focus, protein]
        case nil: return [focus]
        }
    }

    // MARK: - Persistence (see file header)

    /// Best-effort: turns `planGoals` into real `Goal` rows (skipping any type that already has an
    /// active goal, via `IntentSupport.activeGoal` — the same lookup `Screen14FirstWin.swift` and
    /// every Focus App Intent already use, CLAUDE.md "never duplicate the same logic in two
    /// places") and `flowState.selectedApps` into a real default `LockSet`, so
    /// `PaywallViewModel.builtPlan` (screen 13) has something to show. Never throws outward, never
    /// blocks "Continue" — see file header.
    private func persistPlanIfNeeded() async {
        do {
            let user = try onboardingResolveOrCreateUser(coachVoice: flowState.coachVoice, in: modelContext)

            for preview in planGoals {
                guard try IntentSupport.activeGoal(ofType: preview.type, for: user.id, in: modelContext) == nil else { continue }
                let goal = Goal(
                    type: preview.type,
                    title: Copy.onboarding.planGoalTitle(for: preview.type),
                    targetValue: Double(preview.targetValue),
                    unit: preview.unit,
                    cadence: "daily",
                    verificationTier: preview.tier,
                    user: user
                )
                modelContext.insert(goal)
            }
            try modelContext.save()

            let selection = flowState.selectedApps
            let hasSelection = !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty
            if hasSelection, try await LockSetManager.shared.defaultLockSet(for: user.id) == nil {
                // `LockSetManager.createLockSet(name:selection:makeDefault:)` resolves the current
                // device's one local `User` row internally (see that file's own doc comment) — it
                // takes no `userID:` parameter. An earlier draft of this call passed one; verified
                // against the real, on-disk `LockSetManager.swift` and corrected.
                _ = try await LockSetManager.shared.createLockSet(
                    name: Copy.onboarding.lockSetName,
                    selection: selection,
                    makeDefault: true
                )
            }
        } catch {
            // Swallowed deliberately — see file header. `Screen14FirstWin.swift` re-derives
            // whatever's still missing when the first win actually needs it.
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen10PlanReveal(flowState: flowState)
    }
    .modelContainer(for: [User.self, Goal.self, LockSet.self], inMemory: true)
}
