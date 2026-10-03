// Screen10PlanReveal.swift
// App / Features / Onboarding
//
// docs/spec.md §7.10 "Plan reveal": '"Your Lock-In Plan": locked apps, goals, schedule, starting
// difficulty (deliberately below stated target). Looks bespoke. "Built for you in 2:14."' and §16
// P4: "bespoke card: locked apps row with icons, goals list, schedule, difficulty tag 'Starting easy
// on purpose', a hold-to-commit button at the bottom" (since the short flow, the hold is on this step).
//
// Persistence: `OnboardingFlowState.swift`'s own header states the expectation explicitly —
// "Plan Reveal (screen 10) is expected to hand this [`selectedApps`] straight to
// `LockSetManager.createLockSet(name:selection:)` to become the user's default lock set" — and
// `Core/Sources/Core/Monetization/PaywallViewModel.swift` (screen 13) reads exactly that:
// `loadBuiltPlanAndLocalProStatus()` fetches the current user's active `Goal`s and default
// `LockSet` to render the paywall's "the plan you built" section. So on commit (it ran on appear
// before the short flow), `persistPlanIfNeeded()` turns `flowState`'s Q1/Q2/Q4 answers into real `Goal` rows and a real
// default `LockSet`, exactly once per distinct goal type (`IntentSupport.activeGoal` re-check) and
// via `LockSetManager.createLockSet`. This never blocks the commit: any failure is swallowed
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
// Premium pass (2026-09-24, spec §16 P4, "light is earned"): the plan is a proposal, not an earned
// state, so it is achromatic apart from the goals' own ring colors. The reveal is now ONE bespoke
// "Lock-In Plan" card (the screen's `zanoHero`), vertically centred instead of top-pinned over a
// void: locked apps as dimmed icon tiles behind small padlocks, the goals with their ring colors,
// the schedule, a neutral "Starting easy on purpose" tag, and a footer naming the coach the user
// picked. Section labels are sentence case. The build beat's ring and checks are white.
// The schedule line stays "Locks each morning until your goals are done": the app has no default
// lock time yet, so a "Locks at 7:00 AM" line would state something untrue.
//
// Liveliness pass (2026-09-24): the build beat's hero is the living star (`ZanoLivingMark`) instead
// of a white ring: it takes on charge as each of the user's answers checks off, over a ZANO Blue
// bloom that brightens with it, so "building your plan" reads as the star being built. The revealed
// plan carries a small star above its title, charged to where the flow is (5 of 7 since the short flow). The backdrop
// is the scaffold's flow ambient, not a flat `zanoAmbient(.neutral)`.
//
// NFC pass (2026-09-24), superseded by the short flow: the tags question left onboarding, so a
// protein goal row now always says "meal photo or barcode" (`verificationLine(for:)`).
//
// SHORT FLOW (founder decision 2026-10-02): this is step 5 of 7, and it absorbed two old screens.
//   - Q4's workout target: when the plan has a workout goal, its row carries a -/+ stepper (1...7 a
//     week, default 3). The old "current workouts" question is gone; the starting value stays ~70%
//     of the target.
//   - Commitment: the CTA is the hold-to-commit button (`PrimaryButton(style: .holdToCommit)`, a
//     2-second hold with haptics; VoiceOver double-tap commits), exactly what the plan-reveal mockup
//     describes. Completing the hold records `committed_at`, logs `onboarding_committed`, and only
//     THEN persists the plan (Goals + default LockSet), so the workout target the user just set is
//     the one saved. The hard paywall follows directly, as before.
//   - The ZANO tags question moved to Today's Finish setup card, so a protein goal says it verifies
//     by meal photo or barcode here (tags upgrade it once mapped).
//   - No apps picked (Screen Time access refused): the apps row shows dashed slots and a line that
//     apps can be picked from Today; nothing here pretends a lock exists.
//
// IF-THEN PLAN (2026-10-02, research item 2 in docs/design/growth-and-ml-research.md): under the
// schedule, a compact "When will you do it?" picker per timed goal (gym: day chips + a time, which
// follow the workout stepper until the user touches them; focus: a time, every day). Each row plays
// the answer back as an implementation intention ("If it's Mon/Wed/Fri at 6:00 PM, I go to the
// gym."). On commit, before the plan rows are saved as before, it's stored as
// `ImplementationPlan.current` (App Group), which shapes the default lock schedule, times the
// reminder nudge, and gives the slip-risk score its prior. Protein has no picker: it's logged
// through the day, not done at a time.
//
// VISUAL PASS 2 (2026-10-03, "make it more playful"):
//   - The commit is a charging button (`OnboardingChargeButton`): a tall glass capsule that fills
//     blue-to-violet over the 2-second hold, with a bouncing bolt, a growing glow and a burst when
//     it lands. Same label and hold contract, so the UI tests' press-and-hold still works.
//   - Cramped bottom fixed: the "hold for 2 seconds" hint no longer sits in the pinned bar over the
//     scrolling card (on an SE it covered the last rows); it is the last line of the scroll content,
//     the bar holds only the button, and the content has bottom room so the footer clears it.
//   - The star speaks: under the title, the guide bubble says the plan starts easy on purpose (it
//     replaces the separate tag). Section labels are rounded headlines, not small grey eyebrows.
//   - The if-then picker is the fun bit: day chips are chunky squares in the goal's colour, the time
//     sits in a glass capsule, and the sentence plays back as a quote in the goal's colour. The
//     "a plan with a time is easier to keep" caption moved into an (i).
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
    /// The hold completed; guards a double commit while the save and the advance run.
    @State private var isCommitted = false

    // If-then plan answers (see file header).
    @State private var gymDays: Set<Int> = ImplementationPlan.defaultWorkoutDays(perWeek: 3)
    /// Until the user taps a day chip, the gym days follow the workout stepper.
    @State private var gymDaysEdited = false
    @State private var gymTime = Screen10PlanReveal.time(minuteOfDay: ImplementationPlan.defaultWorkoutMinute)
    @State private var focusTime = Screen10PlanReveal.time(minuteOfDay: ImplementationPlan.defaultFocusMinute)

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
            await runBuildBeat()
        }
        .onAppear {
            if !gymDaysEdited {
                gymDays = ImplementationPlan.defaultWorkoutDays(perWeek: flowState.targetWorkoutsPerWeek)
            }
        }
        .onChange(of: flowState.targetWorkoutsPerWeek) { _, perWeek in
            guard !gymDaysEdited else { return }
            gymDays = ImplementationPlan.defaultWorkoutDays(perWeek: perWeek)
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: OnboardingStep.plan.viewedProperties
            )
        }
    }

    // MARK: - Beat 1: building your plan, out of your own answers

    private struct BuildRow: Identifiable {
        let id: Int
        let icon: String
        let text: String
    }

    /// The user's real answers, in the order they gave them (main goal, apps, when it slips). Q3/Q4 are numbers the
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
        // The coach voice is no longer asked (short flow): it stays the default and is shown on the
        // ticket's footer, not here as if the user had answered it.
        return rows
    }

    private var buildProgress: Double {
        let total = buildRows.count
        guard total > 0 else { return 1 }
        return Double(builtRows) / Double(total)
    }

    private static let buildStarHeight: CGFloat = 88
    private static let revealStarHeight: CGFloat = 44

    /// The build beat's star: 0.1 before anything checks off, 0.75 when every answer has.
    private var buildStarCharge: Double {
        0.1 + 0.65 * buildProgress
    }

    /// Where the revealed plan's star sits: the flow's own progress at this screen.
    private var revealStarCharge: Double {
        flowState.progressFraction
    }

    private var buildingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.lg)

            // The star charges as the answers check off: from a glimmer to where the plan will
            // leave it. It eases each step itself; the bloom brightens with it.
            ZanoLivingMark(charge: buildStarCharge, height: Self.buildStarHeight)
                .background {
                    OnboardingKit.StarBloom(diameter: Self.buildStarHeight * 3.2)
                        .opacity(0.25 + 0.75 * buildProgress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: buildProgress)
                }
                .padding(.vertical, Theme.Spacing.sm)
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
                .foregroundStyle(Theme.Colors.interactive)
                .opacity(isBuilt ? 1 : 0)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isBuilt)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Beat 2: the plan

    /// Header and card, centred in the space above the pinned CTA (they used to sit at the top over
    /// an empty half-screen); scrolls instead when large type makes it taller than the screen.
    private var revealedView: some View {
        OnboardingKit.CenteredScroll {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                OnboardingKit.DisplayTitle(text: Copy.onboarding.planRevealHeadline, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                OnboardingGuideStar(
                    line: Copy.onboarding.guidePlanLine,
                    charge: revealStarCharge,
                    starHeight: Self.revealStarHeight
                )
                planCard
                commitHint
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            // Room under the hint so the last line clears the pinned button on small phones.
            .padding(.bottom, Theme.Spacing.xl)
        }
        .onboardingKitActionBar {
            OnboardingChargeButton(
                title: Copy.onboarding.commitHoldButtonLabel,
                isEnabled: !isCommitted
            ) {
                Task { await commit() }
            }
        }
    }

    /// "Hold for 2 seconds. This is you, deciding." The last line of the scroll content (it used to
    /// sit in the pinned bar, over the card). The button's own hint says the same to VoiceOver.
    private var commitHint: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "hand.tap.fill")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.Aurora.violet)
                .accessibilityHidden(true)
            Text(Copy.onboarding.planCommitHint)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The Lock-In Plan: one hero card, three sections and a footer. A hero radius (28) with
    /// 16pt-inset children keeps nested corners concentric (28 - 16 = 12 = `Theme.Radius.small`).
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
            if !plannableGoalTypes.isEmpty {
                groupDivider
                ifThenGroup
                    .planGroupReveal(isVisible: visibleGroups >= 3, reduceMotion: reduceMotion)
            }
            groupDivider
            footer
                .planGroupReveal(isVisible: visibleGroups >= 3, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoHero()
    }

    /// A dashed rule between sections: the card reads as a ticket (a pass you are about to
    /// commit to), not a settings list.
    private var groupDivider: some View {
        PlanTicketRule()
            .stroke(Theme.Colors.hairlineStrong, style: StrokeStyle(lineWidth: Theme.Metrics.edgeWidth, dash: [4, 4]))
            .frame(height: Theme.Metrics.edgeWidth)
            .padding(.horizontal, Theme.Spacing.md)
            .accessibilityHidden(true)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Group 1 — locked apps

    private var appsGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(Copy.onboardingReveal.planTicketAppsLabel)

            appIconRow

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(lockedAppsStatusLine)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(lockedItemCount > 0 ? Copy.onboarding.planLockedAppsDetailLine : Copy.onboarding.planNoAppsLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
    }

    private enum AppTile: Hashable, Identifiable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)

        var id: Self { self }
    }

    private var appTiles: [AppTile] {
        let selection = flowState.selectedApps
        let apps = selection.applicationTokens.map(AppTile.app)
        let categories = selection.categoryTokens.map(AppTile.category)
        return Array((apps + categories).prefix(Self.maxAppIcons))
    }

    /// The picked apps as dimmed icon tiles, each behind a small padlock: "locked" as a picture,
    /// in neutral (nothing is locked yet, and locked is not an error — better-ui ICO-12). With no
    /// selection (Screen Time access refused, or previews/CI) it shows dashed empty slots.
    @ViewBuilder
    private var appIconRow: some View {
        let tiles = appTiles
        let overflow = lockedItemCount - tiles.count
        HStack(spacing: Theme.Spacing.xs) {
            if tiles.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(Theme.Colors.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                }
            } else {
                ForEach(tiles) { tile in
                    lockedTile {
                        // FamilyControls' privacy-preserving label: the app's real icon, rendered by
                        // the system, so the token never leaves the process (CLAUDE.md, spec §24).
                        switch tile {
                        case .app(let token): Label(token).labelStyle(.iconOnly)
                        case .category(let token): Label(token).labelStyle(.iconOnly)
                        }
                    }
                }
                if overflow > 0 {
                    Text(Copy.onboardingReveal.planAppOverflow(overflow))
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                        .background(
                            Theme.Colors.surface2,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func lockedTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        return content()
            .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
            .background(Theme.Colors.surface2, in: shape)
            .clipShape(shape)
            // Dimmed behind the shield: the app is still there, just not yours yet.
            .saturation(0.2)
            .opacity(0.55)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(Theme.Colors.text)
                    .frame(width: Theme.Spacing.lg, height: Theme.Spacing.lg)
                    .background(Theme.Colors.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
                    .offset(x: Theme.Spacing.xxs, y: Theme.Spacing.xxs)
            }
    }

    // MARK: Group 2 — goals

    private var goalsGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel(Copy.onboardingReveal.planTicketGoalsLabel)
            ForEach(planGoals) { goal in
                goalRow(goal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                if let verification = verificationLine(for: goal.type) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: verificationSymbol)
                            .font(Theme.Typography.icon(.xsmall))
                            .accessibilityHidden(true)
                        Text(verification)
                            .font(Theme.Typography.captionEmphasized)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.xxs)
                }
            }
            Spacer(minLength: 0)

            if goal.type == .workoutGym {
                workoutTargetStepper
            }
        }
        .accessibilityElement(children: goal.type == .workoutGym ? .contain : .combine)
    }

    // MARK: Quick target (the old Q4, folded into the plan)

    /// -/+ for the weekly workout target, right on the workout row. Under VoiceOver the pair is one
    /// adjustable element, like a system stepper.
    private var workoutTargetStepper: some View {
        let value = flowState.targetWorkoutsPerWeek
        return HStack(spacing: Theme.Spacing.xs) {
            targetButton(symbol: "minus", label: Copy.onboarding.q4DecrementButtonLabel, isEnabled: value > Self.workoutTargetRange.lowerBound) {
                flowState.targetWorkoutsPerWeek = max(Self.workoutTargetRange.lowerBound, value - 1)
            }
            targetButton(symbol: "plus", label: Copy.onboarding.q4IncrementButtonLabel, isEnabled: value < Self.workoutTargetRange.upperBound) {
                flowState.targetWorkoutsPerWeek = min(Self.workoutTargetRange.upperBound, value + 1)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.onboarding.q4TargetLabel)
        .accessibilityValue(Text(Copy.onboarding.q4WorkoutsPerWeekValue(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                flowState.targetWorkoutsPerWeek = min(Self.workoutTargetRange.upperBound, value + 1)
            case .decrement:
                flowState.targetWorkoutsPerWeek = max(Self.workoutTargetRange.lowerBound, value - 1)
            @unknown default:
                break
            }
        }
    }

    private static let workoutTargetRange = 1...7

    private func targetButton(symbol: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.icon(.small, weight: .bold))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .background(ZanoGlass(Circle()))
                .overlay(Circle().strokeBorder(Theme.Colors.Ring.workout.opacity(0.6), lineWidth: Theme.Metrics.edgeWidth))
        }
        .buttonStyle(.pressable(scale: 0.88))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// How a goal gets verified on day one. Only protein needs a line: tags are set up after
    /// onboarding (Today's Finish setup card), so until then it is a meal photo or a barcode.
    private func verificationLine(for type: GoalType) -> String? {
        type == .protein ? Copy.onboarding.planVerifiedByPhotoOrBarcode : nil
    }

    /// SF Symbol for the verification line: a camera for the photo fallback.
    private let verificationSymbol = "camera.fill"

    // MARK: Group 3 — schedule

    private var scheduleGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(Copy.onboardingReveal.planTicketScheduleLabel)

            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "sunrise.fill", tint: Theme.Colors.text, size: .medium)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.onboarding.planScheduleLine)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pattern = flowState.fallOffPattern {
                        // `FallOffPattern` is an App-target-only type (`OnboardingFlowState.swift`) —
                        // Core cannot declare a `Copy.onboarding.*` function parameterized on it, so
                        // the display label is resolved here and only a plain `String` crosses into
                        // Core (the same narrow Copy-routing exception that file establishes).
                        Text(Copy.onboarding.planScheduleFallOffNote(patternLabel: pattern.displayLabel))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
    }

    // MARK: Group 3b — the if-then plan

    /// Goals that are done at a time (the picker's rows), in plan order.
    private var plannableGoalTypes: [GoalType] {
        planGoals.map(\.type).filter { $0 == .workoutGym || $0 == .focusSession }
    }

    private var ifThenGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xxs) {
                sectionLabel(Copy.ifThenPlan.sectionLabel)
                ZanoInfoButton(
                    Copy.ifThenPlan.sectionDetail,
                    accessibilityLabel: Copy.settings.sectionInfoLabel(Copy.ifThenPlan.sectionLabel)
                )
            }
            ForEach(plannableGoalTypes, id: \.self) { type in
                ifThenRow(type)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
    }

    private func ifThenRow(_ type: GoalType) -> some View {
        let color = Theme.Colors.Ring.color(for: type)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                OnboardingSticker(systemImage: type == .workoutGym ? "dumbbell.fill" : "timer", tint: color, size: 32)
                Text(Copy.ifThenPlan.rowTitle(for: type))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: Theme.Spacing.xs)
                DatePicker(
                    Copy.ifThenPlan.timeLabel,
                    selection: type == .workoutGym ? $gymTime : $focusTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(color)
            }

            if type == .workoutGym {
                PlanDayChips(selection: $gymDays, tint: color, onEdit: { gymDaysEdited = true })
                if gymDays.isEmpty {
                    Text(Copy.ifThenPlan.noDaysHint)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }

            if let line = ifThenSentence(for: type) {
                PlanIfThenQuote(text: line, tint: color)
            }
        }
        .padding(Theme.Spacing.sm)
        .zanoCard(radius: Theme.Radius.small, tint: color)
    }

    /// "If it's Mon/Wed/Fri at 6:00 PM, I go to the gym." `nil` while no day is picked.
    private func ifThenSentence(for type: GoalType) -> String? {
        guard let entry = implementationPlan.entries.first(where: { $0.goalType == type }) else { return nil }
        let symbols = Calendar.current.shortWeekdaySymbols
        let dayNames = PlanDayChips.orderedWeekdays().filter(entry.weekdays.contains).map { symbols[$0 - 1] }
        let time = Self.time(minuteOfDay: entry.minuteOfDay).formatted(date: .omitted, time: .shortened)
        return Copy.ifThenPlan.sentence(for: type, dayNames: dayNames, isEveryDay: entry.isEveryDay, time: time)
    }

    /// The answers as Core's plan. The gym uses the picked days; focus is every day.
    private var implementationPlan: ImplementationPlan {
        let entries = plannableGoalTypes.map { type in
            type == .workoutGym
                ? ImplementationPlan.Entry(goalType: type, weekdays: gymDays, minuteOfDay: Self.minuteOfDay(gymTime))
                : ImplementationPlan.Entry(goalType: type, weekdays: LockSchedule.allWeekdays, minuteOfDay: Self.minuteOfDay(focusTime))
        }
        return ImplementationPlan(entries: entries, slipPatternRaw: flowState.fallOffPattern?.rawValue)
    }

    private static func time(minuteOfDay: Int) -> Date {
        Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The ticket's stub: the coach the user picked, and where the plan came from.
    private var footer: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: OnboardingKit.icon(for: flowState.coachVoice))
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityHidden(true)
            Text(Copy.onboardingReveal.planTicketCoachLine(voiceName: flowState.coachVoice.displayName))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// One row's worth of the plan preview, derived from `flowState.mainGoal` (Q1) plus, for the
    /// workout goal, `flowState.targetWorkoutsPerWeek` (the stepper on this card). `.allOfIt` shows every mapped goal type; every other case shows its one match. Uses
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

    // MARK: - Commit

    /// The hold completed (or VoiceOver activated the button): record the commitment, save the plan,
    /// then move on to the paywall after a beat. A failed save never traps the user here.
    private func commit() async {
        guard !isCommitted else { return }
        isCommitted = true
        flowState.recordCommitment()
        Analytics.shared.capture(
            event: "onboarding_committed",
            properties: [
                "main_goal": flowState.mainGoal?.rawValue ?? "unspecified",
                "has_apps": flowState.hasAppSelection,
                "workout_target": flowState.targetWorkoutsPerWeek,
                "if_then_entries": implementationPlan.entries.count,
            ]
        )
        // The if-then plan first: cheap, App Group only, and read by the lock schedule seeding,
        // the nudges and the slip-risk score from here on.
        let plan = implementationPlan
        ImplementationPlan.current = plan.entries.isEmpty ? nil : plan
        await persistPlanIfNeeded()
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 450))
        flowState.advance()
        // Coming back to this step (Back from the paywall) can commit again with new answers.
        isCommitted = false
    }

    // MARK: - Persistence (see file header)

    /// Best-effort: turns `planGoals` into real `Goal` rows (skipping any type that already has an
    /// active goal, via `IntentSupport.activeGoal` — the same lookup `Screen14FirstWin.swift` and
    /// every Focus App Intent already use, CLAUDE.md "never duplicate the same logic in two
    /// places") and `flowState.selectedApps` into a real default `LockSet`, so
    /// `PaywallViewModel.builtPlan` (the paywall step) has something to show. Never throws outward, never
    /// blocks "Continue" — see file header.
    private func persistPlanIfNeeded() async {
        do {
            let user = try onboardingResolveOrCreateUser(coachVoice: flowState.coachVoice, in: modelContext)

            for preview in planGoals {
                if let existing = try IntentSupport.activeGoal(ofType: preview.type, for: user.id, in: modelContext) {
                    // Back from the paywall and re-committed with a new workout target: keep one row,
                    // with the latest target.
                    if preview.type == .workoutGym {
                        existing.targetValue = Double(preview.targetValue)
                    }
                    continue
                }
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
            if flowState.hasAppSelection, try await LockSetManager.shared.defaultLockSet(for: user.id) == nil {
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

// MARK: - Day chips (if-then plan)

/// Seven day chips in the user's locale order (same look as the lock schedule editor's).
private struct PlanDayChips: View {
    @Binding var selection: Set<Int>
    var tint: Color = Theme.Colors.accent
    var onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let fullSymbols = Calendar.current.weekdaySymbols
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Self.orderedWeekdays(), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                    onEdit()
                } label: {
                    Text(symbols[day - 1])
                        .font(Theme.Typography.headline.weight(.heavy))
                        .foregroundStyle(isOn ? Theme.Colors.background : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.Colors.glassFill))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isOn ? Color.white.opacity(0.45) : Theme.Colors.hairline, lineWidth: 1)
                        }
                        .scaleEffect(isOn && !reduceMotion ? 1.0 : 0.94)
                        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: isOn)
                }
                .buttonStyle(.pressable(scale: 0.88))
                .accessibilityLabel(fullSymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// Weekdays (1 = Sunday) in the user's locale order.
    static func orderedWeekdays() -> [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

// MARK: - If-then quote

/// The plan played back in the user's own words, as a quote in the goal's colour: a coloured bar,
/// a big opening quote mark, and the sentence. Rolls to the new text when days or time change.
private struct PlanIfThenQuote: View {
    let text: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "quote.opening")
                .font(Theme.Typography.icon(.small, weight: .heavy))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: text)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            Capsule().fill(tint).frame(width: 3)
        }
    }
}

// MARK: - Ticket rule

/// A horizontal line through the middle of its frame, for the plan card's dashed section rules.
private struct PlanTicketRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
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
