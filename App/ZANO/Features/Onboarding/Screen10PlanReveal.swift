// Screen10PlanReveal.swift
// App / Features / Onboarding
//
// docs/spec.md §7.10 "Plan reveal": '"Your Lock-In Plan": locked apps, goals, schedule, starting
// difficulty (deliberately below stated target). Looks bespoke. "Built for you in 2:14."' and §16
// P4: "bespoke card: locked apps row with icons, goals list, schedule, difficulty tag 'Starting easy
// on purpose', a hold-to-commit button at the bottom" (the hold lives on screen 11).
//
// Persistence: `OnboardingFlowState.swift`'s own header states the expectation explicitly —
// "Plan Reveal (screen 10) is expected to hand this [`selectedApps`] straight to
// `LockSetManager.createLockSet(name:selection:)` to become the user's default lock set" — and
// `Core/Sources/Core/Monetization/PaywallViewModel.swift` (screen 13) reads exactly that:
// `loadBuiltPlanAndLocalProStatus()` fetches the current user's active `Goal`s and default
// `LockSet` to render the paywall's "the plan you built" section. So on appear,
// `persistPlanIfNeeded()` turns `flowState`'s Q1/Q2/Q4 answers into real `Goal` rows and a real
// default `LockSet`, exactly once per distinct goal type (`IntentSupport.activeGoal` re-check) and
// via `LockSetManager.createLockSet`. This never blocks "Continue": any failure is swallowed
// (matching `Screen14FirstWin.swift`'s own "never trap the user on a SwiftData write" precedent),
// and `Screen14FirstWin.swift` re-derives whatever's still missing when the first win needs it.
// (Unchanged by the design pass.)
//
// Known edge case: if a user goes back and changes Q1/Q4, returning here adds the newly-implied goal
// type rather than reconciling/removing the old one — acceptable for an onboarding preview screen.
//
// Starting difficulty implements docs/spec.md §8 rule 1: "First 3 days' goals are ~70% of stated
// capability."
//
// Design pass (composition-audit offender 4, better-layout 1.8/2.2/7.4, better-ui ICO-12/DEP-06/
// MOT-07/MOT-08, competitive-research §3.5): the "reveal" was a `LockStatusCard` (a danger-red
// padlock, before anything is locked) plus one sibling card per goal, each with an empty to-do
// circle, plus a text card and a full-width button, with no app icons and no staging. Now:
//   1. A 2-3s "building your plan" beat that lists the user's OWN answers as they resolve (goal,
//      apps, when they slip, coach voice). That is real personalization, so it is honest. Tap
//      skips it; Reduce Motion skips it entirely.
//   2. The reveal is ONE composite plan card in three groups (apps, goals, schedule) separated by
//      hairlines rather than five sibling cards, with a hero radius so its 16pt-inset children sit
//      at a concentric 12.
//   3. The locked-apps row shows the picked apps' real icons via FamilyControls' privacy-preserving
//      `Label(token)` (capped at four: the framework is known to stall when many token labels
//      render at once), then "+N".
//   4. Goal rows carry their goal color and glyph in an outline ring, no status glyph (a plan is
//      not a checklist), and the "Starting easy on purpose" tag from spec P4.
//   5. The lock is shown neutrally: this is a proposed plan, not a lock.
//   6. "Built for you in 2:14." is no longer shown: it was a constant, so every user was told they
//      built their plan in exactly 2:14 (writing-findings, HIGH). The build beat replaces it.
//
// Unverified without a device: that `Label(_:)` over an `ApplicationToken` renders (it needs the
// Family Controls entitlement) and that `.labelStyle(.iconOnly)` is honored by it.

import SwiftUI
import SwiftData
import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import Core

@MainActor
struct Screen10PlanReveal: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case building
        case revealed
    }

    @State private var phase: Phase = .building
    /// How many "your answers" rows the build beat has checked off.
    @State private var builtRows = 0
    /// How many of the plan card's three groups are visible (staggered in after the build beat).
    @State private var revealedGroups = 0

    private static let groupCount = 3
    /// Token labels stall when many render at once (Apple forums, FB12332927), so cap the row.
    private static let maxAppIcons = 4

    /// Reduce Motion skips the beat and the stagger with no flash of the un-revealed state.
    private var visiblePhase: Phase {
        reduceMotion ? .revealed : phase
    }

    private var visibleGroups: Int {
        reduceMotion ? Self.groupCount : revealedGroups
    }

    var body: some View {
        ZStack {
            OnboardingKit.Glow(tint: Theme.Colors.accent, opacity: 0.08)

            switch visiblePhase {
            case .building:
                buildingView
                    .transition(.opacity)
            case .revealed:
                revealedView
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: visiblePhase)
        .task {
            await persistPlanIfNeeded()
        }
        .task {
            await runBuildBeat()
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "plan_reveal", "screen_number": 10]
            )
        }
    }

    // MARK: - Beat 1: building your plan, out of your own answers

    private struct BuildRow: Identifiable {
        let id: Int
        let icon: String
        let text: String
    }

    /// The user's real answers, in the order they gave them (Q1, Q2, Q5, Q6). Q3/Q4 are numbers the
    /// plan card itself shows; Q5's label is the App-target-only `FallOffPattern.displayLabel`.
    private var buildRows: [BuildRow] {
        var rows: [BuildRow] = []
        if let goal = flowState.mainGoal {
            rows.append(BuildRow(id: rows.count, icon: "scope", text: goal.displayLabel))
        }
        if lockedItemCount > 0 {
            rows.append(BuildRow(id: rows.count, icon: "lock.fill", text: lockedAppsStatusLine))
        }
        if let pattern = flowState.fallOffPattern {
            rows.append(BuildRow(id: rows.count, icon: "calendar", text: pattern.displayLabel))
        }
        rows.append(
            BuildRow(
                id: rows.count,
                icon: OnboardingKit.icon(for: flowState.coachVoice),
                text: flowState.coachVoice.displayName
            )
        )
        return rows
    }

    private var buildProgress: Double {
        let total = buildRows.count
        guard total > 0 else { return 1 }
        return Double(builtRows) / Double(total)
    }

    private var buildingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.lg)

            GoalRing(
                progress: buildProgress,
                color: Theme.Colors.accent,
                size: .medium,
                center: .icon(systemName: "sparkles")
            )
            .accessibilityHidden(true)

            Text(Copy.onboardingReveal.planBuildingTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(buildRows) { row in
                    buildRow(row)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            revealNow()
        }
        .sensoryFeedback(.selection, trigger: builtRows)
    }

    private func buildRow(_ row: BuildRow) -> some View {
        let isBuilt = row.id < builtRows
        return HStack(spacing: Theme.Spacing.sm) {
            IconBadge(
                systemName: row.icon,
                tint: isBuilt ? Theme.Colors.text : Theme.Colors.muted,
                size: .small
            )

            Text(row.text)
                .font(Theme.Typography.headline)
                .foregroundStyle(isBuilt ? Theme.Colors.text : Theme.Colors.muted)
                .lineLimit(2)

            Spacer(minLength: Theme.Spacing.xs)

            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.icon(.large))
                .foregroundStyle(Theme.Colors.accent)
                .opacity(isBuilt ? 1 : 0)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isBuilt)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Beat 2: the plan

    private var revealedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                planCard
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.onboarding.planContinueButton) {
                flowState.advance()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            OnboardingKit.Eyebrow(text: Copy.onboarding.planRevealEyebrow)
            OnboardingKit.DisplayTitle(text: Copy.onboarding.planRevealHeadline, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One composite card, three groups. A hero radius (28) with 16pt-inset children keeps the
    /// nested corners concentric (28 - 16 = 12 = `Theme.Radius.small`).
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            appsGroup
                .planGroupReveal(isVisible: visibleGroups >= 1, reduceMotion: reduceMotion)
            groupDivider
            goalsGroup
                .planGroupReveal(isVisible: visibleGroups >= 2, reduceMotion: reduceMotion)
            groupDivider
            scheduleGroup
                .planGroupReveal(isVisible: visibleGroups >= 3, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.large)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: Theme.Metrics.edgeWidth)
    }

    // MARK: Group 1 — locked apps

    private var appsGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                // Neutral, not danger-red: this is a proposed plan, nothing is locked yet
                // (better-ui ICO-12, "locked is not an error").
                IconBadge(systemName: "lock.fill", tint: Theme.Colors.text, size: .medium)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(lockedAppsStatusLine)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.onboarding.planLockedAppsDetailLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            appIconRow
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var appIconRow: some View {
        let tokens = Array(flowState.selectedApps.applicationTokens.prefix(Self.maxAppIcons))
        let overflow = lockedItemCount - tokens.count
        if !tokens.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(tokens, id: \.self) { token in
                    // FamilyControls' privacy-preserving label: the app's real icon, rendered by the
                    // system, so the token never leaves the process (CLAUDE.md, spec §24).
                    Label(token)
                        .labelStyle(.iconOnly)
                        .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                        .background(
                            Theme.Colors.surface2,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        )
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                        .background(
                            Theme.Colors.surface2,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        )
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Group 2 — goals

    private var goalsGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(planGoals) { goal in
                goalRow(goal)
            }
            easyStartTag
        }
        .padding(Theme.Spacing.md)
    }

    private func goalRow(_ goal: PlanGoalPreview) -> some View {
        let color = Theme.Colors.Ring.color(for: goal.type)
        return HStack(spacing: Theme.Spacing.sm) {
            // An empty ring in the goal's own color: it says "this is the ring you'll fill", and
            // carries the goal's glyph so identity never rests on hue alone. It is the real
            // `GoalRing` at 0%, so this plan row and the Today ring it becomes are one object.
            GoalRing(
                progress: 0,
                color: color,
                size: .custom(Theme.Metrics.iconBadgeMedium),
                center: .icon(systemName: goal.icon)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.onboarding.planGoalTitle(for: goal.type))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(
                    Copy.onboarding.planGoalStartingDetail(
                        current: goal.startingValue,
                        target: goal.targetValue,
                        unit: goal.unit
                    )
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Spec §16 P4's "Starting easy on purpose" tag — the day-one targets really are ~70% of stated.
    private var easyStartTag: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(Theme.Typography.icon(.xsmall))
            Text(Copy.onboardingReveal.planEasyStartTag)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.accentWash, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Group 3 — schedule

    private var scheduleGroup: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "clock.fill", tint: Theme.Colors.text, size: .medium)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.onboarding.planScheduleLine)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let pattern = flowState.fallOffPattern {
                    // `FallOffPattern` is an App-target-only type (`OnboardingFlowState.swift`) — Core
                    // cannot declare a `Copy.onboarding.*` function parameterized on it. This resolves
                    // the display label on the App side first (`FallOffPattern.displayLabel`, the same
                    // narrow Copy-routing exception that file already establishes) and only passes the
                    // resulting plain `String` across the module boundary.
                    Text(Copy.onboarding.planScheduleFallOffNote(patternLabel: pattern.displayLabel))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Locked-apps summary

    private var lockedItemCount: Int {
        let selection = flowState.selectedApps
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    private var lockedAppsStatusLine: String {
        let selection = flowState.selectedApps
        return Copy.onboarding.planLockedAppsStatusLine(
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    // MARK: - Build beat driver

    private func runBuildBeat() async {
        guard !reduceMotion else { return }

        for index in 0..<buildRows.count {
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled, phase == .building else { return }
            withAnimation(Theme.Motion.springStandard) { builtRows = index + 1 }
        }

        // A short hold on the finished checklist so the last answer is actually read.
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled, phase == .building else { return }
        await reveal()
    }

    /// Tap-to-skip (and the natural end of the beat): jump to the plan.
    private func revealNow() {
        guard phase == .building else { return }
        Task { await reveal() }
    }

    private func reveal() async {
        guard phase == .building else { return }
        withAnimation(Theme.Motion.springStandard) { phase = .revealed }
        for group in 1...Self.groupCount {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.springStandard) { revealedGroups = group }
        }
    }

    // MARK: - Goal preview rows

    /// One row's worth of the plan preview, derived from `flowState.mainGoal` (Q1) plus, where the
    /// mapped `GoalType` is count-based, `flowState.currentWorkoutsPerWeek`/`targetWorkoutsPerWeek`
    /// (Q4). `.allOfIt` shows every mapped goal type; every other case shows its one match. Uses
    /// only Core's own `GoalType`/`VerificationTier` (never the App-only `MainGoal`) so this same
    /// value can be handed straight to `Goal.init` in `persistPlanIfNeeded()` below.
    private struct PlanGoalPreview: Identifiable {
        /// Stable across body re-evaluations (a fresh `UUID()` per evaluation, as this had before,
        /// would recreate every row — and restart its animations — on each state change).
        var id: String { type.rawValue }
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
    /// not this onboarding preview.
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
                // takes no `userID:` parameter.
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

// MARK: - Group reveal

private extension View {
    /// Fades and rises one plan-card group in. Reduce Motion passes `true` from the first frame.
    func planGroupReveal(isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : Theme.Spacing.xs)
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isVisible)
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen10PlanReveal(flowState: flowState)
    }
    .modelContainer(for: [User.self, Goal.self, LockSet.self], inMemory: true)
}
