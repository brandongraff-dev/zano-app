// TodayView.swift
// App / ZANO / Features / Today
//
// The Today screen — docs/spec.md §15/§16 P1. Premium UI + UX pass 2026-09-24
// (docs/design/premium-ui-plan.md). What the screen is, and why:
//
// - The hero is the vault (`LockVaultCard`): the lock state as one huge condensed number ("2 goals
//   to unlock"), the locked apps themselves dimmed behind a lock (on device), and one bar segment
//   per required goal that fills in that goal's color. Tapping it opens Lock.
// - The screen's light follows the state (`zanoAmbient`): cool and dim while locked, warming as
//   required goals complete, accent only once everything is earned ("light is earned").
// - Goals are rows with their one action in place (`GoalActionList`): "+25g" protein and "+250ml"
//   water log with one tap (App Intents, same path as widgets/NFC), focus starts from its row, a gym
//   workout starts dwell tracking from its row. The old layout made the day's most frequent action
//   cost a tab switch ("Log the rest on Fuel") and showed only the goals gating the lock.
// - Grouping answers "what do I still owe?": "To unlock" (required, open first) then "Also today".
//   Nothing locked: one "Today's goals" group.
// - The bottom bar only carries what a row can't: starting today's lock, finishing setup, and the
//   live status of a running focus session or gym check-in. No duplicate CTA for a row's action.
// - Begin-lock is a plain tap (holds are for commitment and the 60-second emergency unlock).
// - Red means emergency only: a running lock is cool navy/grey, never `danger`.
// - A quick-log shows a 5-second undo toast (longer under VoiceOver). Goals that verify on their own
//   say so in their row; honor-system goals get a "Log" with one confirmation; a gym goal with no
//   saved gym says "Set up your gym" and goes to Settings.
//
// Every animation is gated on Reduce Motion; the ambient light and washes drop under Reduce
// Transparency. User-facing strings live in `Copy.today` (`Core/Sources/Core/Copy/TodayCopy.swift`);
// `beginLockStandardTitle` and `lockStatusLine` are matched by the UI tests.

import Foundation
import SwiftUI
import SwiftData
import DeviceActivity
import FamilyControls
import Core

struct TodayView: View {

    // MARK: - Injected navigation

    /// Switches the tab shell to Fuel. Kept for the shell's call site; Today logs protein and water
    /// in place now, so it's no longer the fallback action.
    private let onOpenFuel: (() -> Void)?

    /// Opens whichever surface finishes setup (goals, lock set). While `nil`, an incomplete setup
    /// shows no bottom action — the hero already says "Finish setup to start locking".
    private let onFinishSetup: (() -> Void)?

    /// Opens gym setup (the shell switches to Settings, where the gym row lives). While `nil`, a gym
    /// goal with no saved gym shows a read-only status instead of an action.
    private let onOpenGymSetup: (() -> Void)?

    init(
        onOpenFuel: (() -> Void)? = nil,
        onFinishSetup: (() -> Void)? = nil,
        onOpenGymSetup: (() -> Void)? = nil
    ) {
        self.onOpenFuel = onOpenFuel
        self.onFinishSetup = onFinishSetup
        self.onOpenGymSetup = onOpenGymSetup
        _screenTimeStatus = State(initialValue: AuthorizationCenter.shared.authorizationStatus)
    }

    // MARK: - Data

    @Query private var users: [User]
    @Query private var goals: [Goal]
    @Query private var goalEvents: [GoalEvent]
    @Query private var dailyPlans: [DailyPlan]
    @Query private var lockSessions: [LockSession]
    @Query private var lockSets: [LockSet]
    @Query private var streaks: [Streak]
    @Query private var timeBanks: [TimeBank]
    @Query private var gyms: [Gym]

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    // MARK: - Local state

    /// Screen Time authorization, kept in state (the `AuthorizationCenter` value isn't observed by
    /// SwiftUI) and refreshed after a request and whenever the scene becomes active.
    @State private var screenTimeStatus: AuthorizationStatus
    /// The undo toast after a quick-log. Cleared after `undoDuration` or on undo.
    @State private var pendingUndo: QuickLogUndo?
    /// An honor-system goal waiting on its one confirmation before it's logged.
    @State private var confirmingLogGoal: Goal?

    /// Set the moment this screen starts a focus session, so its row and the status bar reflect
    /// "running" without waiting on a round trip. Cleared once a completion lands (read via
    /// `goalEvents`).
    ///
    /// TODO(cross-module, Verification/LiveActivity sessions): only knows about sessions *this
    /// screen* started; a session started from a widget, Siri, or NFC shows once it completes.
    @State private var runningFocusGoalID: UUID?
    @State private var trackingGymID: UUID?
    /// Live dwell minutes for `trackingGymID`, polled from `GymVerifier`.
    @State private var gymDwellMinutes: Int = 0

    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var showLockDetail = false
    /// The first-day checklist's "Choose apps to lock" step pushes the same `LockSetupView` the
    /// Settings "Lock sets" row opens.
    @State private var showLockSetup = false
    /// Drives `UnlockCelebrationView` (spec §16 P3). Set only for an *earned* unlock.
    ///
    /// Known gap (flagged, not built here): spec §8 rule 4's "1 in ~6 unlocks" variable-reward
    /// badge has no gating logic yet, so this always presents with `badge: nil`.
    @State private var showUnlockCelebration = false
    /// Today vs. "Ghost You" (spec §5.4). `nil` until the first load completes.
    @State private var ghostComparison: GhostMode.GhostComparison?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    heroCard
                    if showsFirstDayChecklist {
                        firstDayChecklist
                    }
                    goalSections
                    screenTimeSection
                    if let ghostComparison {
                        ghostRow(ghostComparison)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .zanoAmbient(reduceTransparency ? .neutral : ambientState)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: ambientState)
            // Today draws its own header; no empty navigation-bar band above it.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationDestination(isPresented: $showLockDetail) {
                // Pushed from Today, "Go to Today" is just the way back.
                LockStatusView(onGoToToday: { showLockDetail = false })
            }
            .navigationDestination(isPresented: $showLockSetup) {
                LockSetupView()
            }
            .task(id: trackingGymID) {
                await pollGymDwell()
            }
            .task(id: completedGoalCount) {
                ghostComparison = await GhostMode.shared.ghostComparison(for: .now)
            }
            .task {
                // spec §23: "every screen view... (count only, on device → aggregate)".
                Analytics.shared.capture(event: "screen_viewed", properties: ["screen": "today"])
            }
            .task(id: pendingUndo?.id) {
                guard let undo = pendingUndo else { return }
                try? await Task.sleep(for: .seconds(voiceOverEnabled ? 10 : 5))
                guard !Task.isCancelled, pendingUndo?.id == undo.id else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) { pendingUndo = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshScreenTimeStatus() }
            }
            .confirmationDialog(
                confirmingLogGoal.map { Copy.today.logGoalConfirmTitle(goal: $0.title) } ?? "",
                isPresented: Binding(
                    get: { confirmingLogGoal != nil },
                    set: { if !$0 { confirmingLogGoal = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmingLogGoal
            ) { goal in
                Button(Copy.today.logGoalConfirmAction) { logHonorGoal(goal) }
            } message: { _ in
                Text(Copy.today.logGoalConfirmMessage)
            }
            .task(id: defaultLockSet?.appTokensBlob) {
                // Lets the screen-time report (ZANOReport) mark locked apps even when no lock runs.
                if let blob = defaultLockSet?.appTokensBlob { SharedDefaults.lockedSelectionData = blob }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: isLocked) { oldValue, newValue in
            oldValue == true && newValue == false
        }
        .sensoryFeedback(.success, trigger: completedGoalCount) { oldValue, newValue in
            newValue > oldValue
        }
        .onChange(of: isLocked) { oldValue, newValue in
            guard oldValue == true, newValue == false else { return }
            // spec §23: "every... unlock kind" — every ended session, earned or not.
            if let kind = mostRecentlyEndedSession?.unlockKind {
                Analytics.shared.capture(
                    event: "unlock_completed",
                    properties: ["kind": kind.rawValue, "screen": "today"]
                )
            }
            guard lastUnlockWasEarned else { return }
            showUnlockCelebration = true
        }
        .fullScreenCover(isPresented: $showUnlockCelebration) {
            UnlockCelebrationView(
                goalName: unlockCelebrationGoalName,
                timeBankRemainingMinutes: todaysTimeBank?.remainingMin ?? 0,
                timeBankTotalMinutes: todaysTimeBank?.earnedMin ?? 0
            )
        }
    }

    // MARK: - Header

    /// The wordmark and the date on the left, the streak on the right (the Opal-style top bar the
    /// founder picked as reference; the tab bar already says "Today").
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            ZanoWordmark(height: 11)
            Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            StreakPill(
                count: streak?.current ?? 0,
                isFrozen: isStreakFrozenToday,
                accessibilityLabelOverride: CoachVoiceTone.streakClause(voice, streak: streak?.current ?? 0)
            )
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Hero (the vault)

    /// What the hero says. Derived from the same facts the actions read, so they can't disagree.
    private enum HeroState: Equatable {
        /// Nothing to lock yet (no goals, or no lock set).
        case setup
        /// A lock is running and `remaining` of its `total` required goals are still open.
        case locked(remaining: Int, total: Int)
        /// A lock is running and every required goal is done; the engine is about to release it.
        case unlocking
        /// No lock running. `done` of the user's `total` active goals are done today.
        case unlocked(done: Int, total: Int)
    }

    private var heroState: HeroState {
        if isLocked {
            let remaining = remainingRequiredGoalCount
            guard remaining > 0 else { return .unlocking }
            return .locked(remaining: remaining, total: max(requiredGoals.count, remaining))
        }
        if activeGoals.isEmpty || defaultLockSet == nil { return .setup }
        return .unlocked(done: completedGoalCount, total: activeGoals.count)
    }

    /// Every goal for the day is done (or the lock is about to release): the one bright state.
    private var heroIsEarned: Bool {
        switch heroState {
        case .unlocking: true
        case .unlocked(let done, let total): total > 0 && done >= total
        case .setup, .locked: false
        }
    }

    /// The screen's light, from the same state: cold while locked, warming with each required goal.
    private var ambientState: ZanoAmbientState {
        if heroIsEarned { return .earned }
        switch heroState {
        case .locked(let remaining, let total):
            let done = Double(total - remaining)
            return done > 0 ? .progress(done / Double(max(total, 1))) : .locked
        case .unlocked(let done, let total):
            return total > 0 && done > 0 ? .progress(Double(done) / Double(total)) : .neutral
        case .setup, .unlocking:
            return .neutral
        }
    }

    private var heroCard: some View {
        Button {
            Analytics.shared.capture(event: "today_lock_status_tapped")
            showLockDetail = true
        } label: {
            vault
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                // One announcement for the whole card.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroAccessibilityLabel)
        }
        .buttonStyle(.pressable)
    }

    /// The hero is an object, not a card (Opal's gem): the living ZANO star, charged by today's time
    /// off the phone, floating in a halo whose light follows the lock state. Under it the one big
    /// number, a segment per goal, and the lock status. Tapping it opens Lock.
    private var vault: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [heroHalo.opacity(reduceTransparency ? 0 : 0.42), heroHalo.opacity(0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 175
                        )
                    )
                    // Capped at 350 but never wider than the screen (an SE is 320 wide).
                    .frame(maxWidth: 350, maxHeight: 350)
                    .aspectRatio(1, contentMode: .fit)
                heroStar
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.heroStageHeight)

            heroNumber

            if !heroSegments.isEmpty {
                VaultSegmentBar(segments: heroSegments)
                    .frame(width: 160)
                    .padding(.vertical, Theme.Spacing.xxs)
            }

            ZanoStatusCapsule(dotColor: heroStatusColor, text: heroStatusLine, showsChevron: true)

            if let chip = bankChipText {
                Text(chip)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Colors.accentWash, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.Spacing.sm)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: heroState)
    }

    @ViewBuilder
    private var heroNumber: some View {
        switch heroState {
        case .setup:
            VStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.today.setupIncompleteTitle)
                    .font(Theme.Typography.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.today.heroSetupSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .multilineTextAlignment(.center)
        case .unlocking:
            Text(Copy.today.allDoneTitle)
                .font(Theme.Typography.titleLarge)
                .foregroundStyle(Theme.Colors.accent)
                .multilineTextAlignment(.center)
        case .locked(let remaining, _):
            centredNumeral(Copy.today.heroGoalsToUnlockLine(count: remaining), earned: false, changeKey: remaining)
        case .unlocked(let done, let total):
            centredNumeral(Copy.today.heroFractionDone(done: done, total: total), earned: heroIsEarned, changeKey: done)
        }
    }

    /// "2" at poster size with its words under it, centred.
    private func centredNumeral(_ line: String, earned: Bool, changeKey: Int) -> some View {
        VStack(spacing: 0) {
            NumeralText(line, size: .hero, color: earned ? Theme.Colors.accent : Theme.Colors.text, remainder: .hidden)
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: changeKey)
            Text(NumeralText.remainder(of: line))
                .font(.system(.title3, weight: .bold).width(.condensed))
                .foregroundStyle(Theme.Colors.text)
            if case .locked = heroState,
               let names = Copy.today.heroRemainingGoals(openFirst(requiredGoals).filter { !isGoalDoneToday($0) }.map(\.title)) {
                Text(names)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// The star's charge is screen time, which only the `ZANOReport` extension can read (spec §27),
    /// so on a device the star is that extension's view. It can't take taps, so the card's button
    /// still gets them. Screenshots use demo data; without access the star is uncharged.
    @ViewBuilder
    private var heroStar: some View {
        if ScreenshotMode.screen != nil {
            ScreenTimeChargeView(summary: DemoData.screenTime, height: Self.heroMarkHeight)
        } else if screenTimeStatus == .approved {
            DeviceActivityReport(.zanoMark, filter: Self.todayFilter)
                .frame(height: Self.heroStageHeight)
                .allowsHitTesting(false)
        } else {
            ScreenTimeChargeView(height: Self.heroMarkHeight)
        }
    }

    /// The hero's stage (halo + star) and the star itself. One pair of constants for the screenshot,
    /// no-access and on-device (report extension) paths, so all three lay out the same.
    private static let heroStageHeight: CGFloat = 330
    private static let heroMarkHeight: CGFloat = 124

    private func refreshScreenTimeStatus() {
        screenTimeStatus = AuthorizationCenter.shared.authorizationStatus
    }

    private var heroSegments: [VaultSegment] {
        switch heroState {
        case .setup: []
        case .locked, .unlocking: segments(for: requiredGoals)
        case .unlocked: segments(for: activeGoals)
        }
    }

    /// Cold steel while locked, the accent once earned, a faint neutral otherwise.
    private var heroHalo: Color {
        if heroIsEarned { return Theme.Colors.accent }
        switch heroState {
        case .locked: return Theme.Colors.lockedAmbient
        default: return Theme.Colors.textSecondary.opacity(0.4)
        }
    }

    /// Red is reserved for emergency: a running lock is a quiet grey dot on the navy halo.
    private var heroStatusColor: Color {
        switch heroState {
        case .locked: Theme.Colors.textSecondary
        case .unlocking, .unlocked: Theme.Colors.accent
        case .setup: Theme.Colors.muted
        }
    }

    /// "Locked · Social · since 7:00 AM", "Unlocked", "Setup".
    private var heroStatusLine: String {
        switch heroState {
        case .locked:
            let base = Copy.today.heroLockedEyebrow(lockSetName: activeLockSet?.name)
            guard let session = activeLockSession else { return base }
            return base + " · " + Copy.today.heroLockedSince(session.startedAt.formatted(date: .omitted, time: .shortened))
        case .unlocking: return Copy.today.heroUnlockingEyebrow
        case .unlocked: return Copy.today.lockStatusLine(isLocked: false, goalsRemaining: 0)
        case .setup: return Copy.today.heroSetupEyebrow
        }
    }

    private func segments(for pool: [Goal]) -> [VaultSegment] {
        sortedByPriority(pool).map {
            VaultSegment(id: $0.id, color: Theme.Colors.Ring.color(for: $0.type), isDone: isGoalDoneToday($0), progress: dayProgress(for: $0).fraction)
        }
    }

    /// Earn Mode's banked minutes, shown as a chip beside the segments while locked.
    private var bankChipText: String? {
        guard activeLockSession?.mode == .earn, let bank = todaysTimeBank, bank.remainingMin > 0 else { return nil }
        return Copy.today.heroTimeBankChip(minutes: bank.remainingMin)
    }

    /// The spoken version of the whole card. The locked and unlocked variants start with
    /// `Copy.today.lockStatusLine(...)`, which the UI tests match.
    private var heroAccessibilityLabel: String {
        switch heroState {
        case .setup:
            return Copy.today.setupIncompleteTitle
        case .unlocking:
            return Copy.today.allDoneTitle
        case .locked(let remaining, _):
            let parts: [String?] = [
                Copy.today.lockStatusLine(isLocked: true, goalsRemaining: remaining),
                CoachVoiceTone.goalsRemainingClause(voice, remaining: remaining),
                bankChipText
            ]
            return parts.compactMap { $0 }.joined(separator: ". ")
        case .unlocked(let done, let total):
            return [
                Copy.today.lockStatusLine(isLocked: false, goalsRemaining: 0),
                Copy.today.heroFractionDoneSpoken(done: done, total: total)
            ].joined(separator: ". ")
        }
    }

    // MARK: - First day (what's left before the first lock)

    /// Shown while setup is incomplete, and on the first day until a lock has ever started: the
    /// hero says what's missing, this says how to get there, one tappable step at a time. Gone for
    /// good once any `LockSession` exists (a lock that ran, even one that ended).
    private var showsFirstDayChecklist: Bool {
        if case .setup = heroState { return true }
        return !isLocked && lockSessions.isEmpty
    }

    private struct FirstDayStep: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let isDone: Bool
        /// `nil` when nothing in the app can take this step from here yet (no goal picker exists
        /// outside onboarding unless the shell supplies `onFinishSetup`).
        let action: (() -> Void)?
    }

    private var firstDaySteps: [FirstDayStep] {
        let goalsDone = !activeGoals.isEmpty
        let appsDone = defaultLockSet != nil
        let lockDone = !lockSessions.isEmpty
        let lockAction: (() -> Void)?
        if case .beginLock(let lockSetID, let requiredGoalIDs) = barState {
            lockAction = { beginLock(lockSetID: lockSetID, requiredGoalIDs: requiredGoalIDs) }
        } else {
            lockAction = nil
        }
        return [
            FirstDayStep(
                id: 1,
                title: Copy.today.firstDayStepGoalsTitle,
                detail: Copy.today.firstDayStepGoalsDetail,
                isDone: goalsDone,
                action: goalsDone ? nil : onFinishSetup
            ),
            FirstDayStep(
                id: 2,
                title: Copy.today.firstDayStepAppsTitle,
                detail: Copy.today.firstDayStepAppsDetail,
                isDone: appsDone,
                action: {
                    Analytics.shared.capture(event: "today_first_day_step_tapped", properties: ["step": "apps"])
                    showLockSetup = true
                }
            ),
            FirstDayStep(
                id: 3,
                title: Copy.today.firstDayStepLockTitle,
                detail: goalsDone && appsDone ? Copy.today.firstDayStepLockDetail : Copy.today.firstDayStepLockWaiting,
                isDone: lockDone,
                action: lockDone || isPerformingAction ? nil : lockAction
            )
        ]
    }

    private var firstDayChecklist: some View {
        let steps = firstDaySteps
        let doneCount = steps.filter(\.isDone).count
        let currentID = steps.first(where: { !$0.isDone })?.id
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.today.firstDayTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.Spacing.sm)
                Text(Copy.today.firstDayProgress(done: doneCount, total: steps.count))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .monospacedDigit()
            }
            .padding(.leading, Theme.Spacing.xxs)

            VStack(spacing: 0) {
                ForEach(steps) { step in
                    FirstDayStepRow(
                        index: step.id,
                        total: steps.count,
                        title: step.title,
                        detail: step.detail,
                        isDone: step.isDone,
                        isCurrent: step.id == currentID,
                        isLast: step.id == steps.last?.id,
                        action: step.action
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.md)
            .zanoCard()
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: doneCount)
    }

    // MARK: - Goals (rows with their action in place)

    private static func priority(of type: GoalType) -> Int {
        switch type {
        case .workoutGym, .workoutHomeOutdoor: 0
        case .protein: 1
        case .focusSession: 2
        case .water: 3
        default: 4
        }
    }

    private func sortedByPriority(_ pool: [Goal]) -> [Goal] {
        pool.sorted {
            (Self.priority(of: $0.type), $0.createdAt) < (Self.priority(of: $1.type), $1.createdAt)
        }
    }

    /// Open goals first, done ones after, each in spec order.
    private func openFirst(_ pool: [Goal]) -> [Goal] {
        let sorted = sortedByPriority(pool)
        return sorted.filter { !isGoalDoneToday($0) } + sorted.filter { isGoalDoneToday($0) }
    }

    @ViewBuilder
    private var goalSections: some View {
        if isLocked {
            let requiredIDs = Set(requiredGoals.map(\.id))
            let others = activeGoals.filter { !requiredIDs.contains($0.id) }
            if !requiredGoals.isEmpty {
                goalSection(Copy.today.sectionToUnlock, goals: openFirst(requiredGoals), required: true)
            }
            if !others.isEmpty {
                goalSection(Copy.today.sectionAlsoToday, goals: openFirst(others), required: false)
            }
        } else if !activeGoals.isEmpty {
            goalSection(Copy.today.sectionTodaysGoals, goals: openFirst(activeGoals), required: false)
        }
    }

    private func goalSection(_ title: String, goals: [Goal], required: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .padding(.leading, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            GoalActionList(
                items: goals.map { actionItem(for: $0, required: required) },
                isBusy: isPerformingAction
            ) { item in
                perform(rowAction: item)
            }
        }
    }

    /// Quick-log amounts: the most common single serving, matching Fuel's middle chips.
    private static let proteinQuickAddGrams = 25
    private static let waterQuickAddMilliliters = 250

    private func actionItem(for goal: Goal, required: Bool) -> GoalActionItem {
        let p = dayProgress(for: goal)
        let title = goal.title
        let primary: String
        var secondary: String?
        if let target = p.target {
            primary = p.isComplete
                ? Copy.today.statusDone
                : Copy.today.goalProgressLine(current: p.current ?? 0, target: target, unit: p.unit)
            if !p.isComplete {
                secondary = Copy.today.goalRemainingLine(remaining: max(0, target - (p.current ?? 0)), unit: p.unit)
            }
        } else {
            primary = p.isComplete ? Copy.today.statusDone : Copy.today.ringNotYet
        }

        return GoalActionItem(
            id: goal.id,
            title: title,
            icon: goalIconName(for: goal.type),
            color: Theme.Colors.Ring.color(for: goal.type),
            progress: p.fraction,
            primaryLine: primary,
            secondaryLine: secondary,
            isRequired: required,
            trailing: trailing(for: goal, progress: p)
        )
    }

    private func trailing(for goal: Goal, progress p: GoalDayProgress) -> GoalActionItem.Trailing {
        if p.isComplete { return .done }
        switch goal.type {
        case .protein:
            let grams = Self.proteinQuickAddGrams
            return .quickAdd(
                label: Copy.today.quickAddAmount(grams, unit: "g"),
                accessibilityLabel: Copy.today.quickAddAccessibility(grams, unit: "g", goal: goal.title)
            )
        case .water:
            let ml = Self.waterQuickAddMilliliters
            return .quickAdd(
                label: Copy.today.quickAddAmount(ml, unit: "ml"),
                accessibilityLabel: Copy.today.quickAddAccessibility(ml, unit: "ml", goal: goal.title)
            )
        case .focusSession:
            return runningFocusGoalID == goal.id
                ? .status(Copy.today.statusRunning, isLive: true)
                : .start(label: Copy.today.actionStart)
        case .workoutGym:
            if trackingGymID != nil { return .status(Copy.today.statusDwell(minutes: gymDwellMinutes), isLive: true) }
            if primaryGym != nil { return .start(label: Copy.today.actionGo) }
            return onOpenGymSetup == nil
                ? .status(Copy.today.statusVerifiesAtGym, isLive: false)
                : .start(label: Copy.today.actionSetUpGym)
        case .workoutHomeOutdoor, .steps, .sleepOnTime, .sunriseAlarm:
            // HealthKit, the step counter, the bedtime gate and the alarm verify these on their own.
            return .status(Copy.today.statusVerifiesAutomatically, isLive: false)
        case .creatine, .custom, .coldShowerSauna, .reading, .stretchMobility, .mealPrep:
            return .start(label: Copy.today.actionLog)
        }
    }

    private func perform(rowAction item: GoalActionItem) {
        guard let goal = goals.first(where: { $0.id == item.id }) else { return }
        actionError = nil
        switch goal.type {
        case .protein:
            log(goalType: .protein, amount: Double(Self.proteinQuickAddGrams))
        case .water:
            log(goalType: .water, amount: Double(Self.waterQuickAddMilliliters))
        case .focusSession:
            let minutes = Int(todaysPlan(for: goal)?.plannedValue ?? goal.targetValue ?? 25)
            startFocus(goalID: goal.id, minutes: max(1, minutes))
        case .workoutGym:
            guard let gym = primaryGym else {
                Analytics.shared.capture(event: "today_set_up_gym_tapped")
                onOpenGymSetup?()
                return
            }
            Analytics.shared.capture(event: "today_verify_at_gym_tapped")
            trackingGymID = gym.id
            Task { await GymVerifier.shared.beginDwellTracking(gymID: gym.id) }
        case .creatine:
            // One tap, like the Control Center control that calls the same intent.
            logCreatine()
        case .custom, .coldShowerSauna, .reading, .stretchMobility, .mealPrep:
            // Honor-system goals: one confirmation is the friction before the log.
            confirmingLogGoal = goal
        case .workoutHomeOutdoor, .steps, .sleepOnTime, .sunriseAlarm:
            break
        }
    }

    private func logCreatine() {
        Analytics.shared.capture(event: "today_log_creatine_tapped")
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                _ = try await LogCreatineIntent(source: .manual).perform()
            } catch {
                showError(Copy.today.logFailedTitle)
            }
        }
    }

    /// `LogCustomGoalIntent` records a verified completion for the goal (spec's Tier C: honesty
    /// with friction; the confirmation dialog is the friction).
    private func logHonorGoal(_ goal: Goal) {
        confirmingLogGoal = nil
        Analytics.shared.capture(event: "today_log_honor_goal_tapped", properties: ["goal_type": goal.type.rawValue])
        isPerformingAction = true
        let entity = GoalEntity(id: goal.id, title: goal.title)
        Task {
            defer { isPerformingAction = false }
            do {
                _ = try await LogCustomGoalIntent(goal: entity).perform()
            } catch {
                showError(Copy.today.logFailedTitle)
            }
        }
    }

    /// Shows `message` in the bottom bar and announces it to VoiceOver (an error line that appears
    /// silently is missed by anyone not looking at the bottom of the screen).
    private func showError(_ message: String) {
        actionError = message
        AccessibilityNotification.Announcement(message).post()
    }

    /// Logs through the same App Intents the widgets, Siri and NFC tags use (CLAUDE.md: every user
    /// action is an intent), so Today never grows a second logging path.
    private func log(goalType: GoalType, amount: Double) {
        Analytics.shared.capture(
            event: "today_quick_log_tapped",
            properties: ["goal_type": goalType.rawValue, "amount": amount]
        )
        isPerformingAction = true
        let startedAt = Date.now
        Task {
            defer { isPerformingAction = false }
            do {
                switch goalType {
                case .protein:
                    var intent = LogProteinIntent()
                    intent.grams = amount
                    intent.source = .manual
                    _ = try await intent.perform()
                case .water:
                    var intent = LogWaterIntent()
                    intent.milliliters = Int(amount)
                    intent.source = .manual
                    _ = try await intent.perform()
                default:
                    return
                }
                offerUndo(goalType: goalType, amount: amount, since: startedAt)
            } catch {
                showError(Copy.today.logFailedTitle)
            }
        }
    }

    /// Finds the event the intent just wrote (it saves through its own context on the same store)
    /// and offers to remove it. No toast if it can't be found: an undo that can't undo is worse.
    private func offerUndo(goalType: GoalType, amount: Double, since startedAt: Date) {
        guard let goal = activeGoals.first(where: { $0.type == goalType }) else { return }
        let goalID = goal.id
        let descriptor = FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.ts >= startedAt })
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        guard let event = recent
            .filter({ $0.goal?.id == goalID && $0.value == amount && $0.source == .manual })
            .max(by: { $0.ts < $1.ts })
        else { return }
        let unit = goalType == .water ? "ml" : "g"
        let message = Copy.today.quickLogConfirmation(Int(amount), unit: unit, goal: goal.title)
        withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
            pendingUndo = QuickLogUndo(eventID: event.id, message: message)
        }
        AccessibilityNotification.Announcement(message).post()
    }

    private func undo(_ undo: QuickLogUndo) {
        let eventID = undo.eventID
        withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) { pendingUndo = nil }
        Analytics.shared.capture(event: "today_quick_log_undone")
        do {
            let descriptor = FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.id == eventID })
            for event in try modelContext.fetch(descriptor) {
                modelContext.delete(event)
            }
            try modelContext.save()
            AccessibilityNotification.Announcement(Copy.today.undoDone).post()
        } catch {
            showError(Copy.today.undoFailed)
        }
    }

    private func startFocus(goalID: UUID, minutes: Int) {
        Analytics.shared.capture(event: "today_start_focus_tapped", properties: ["planned_minutes": minutes])
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                _ = try await FocusSessionVerifier.shared.startSession(goalID: goalID, plannedMinutes: minutes)
                runningFocusGoalID = goalID
            } catch {
                showError(Copy.today.focusStartFailed)
            }
        }
    }

    // MARK: - Screen time (the Opal reference's lower half; data only exists in ZANOReport)

    private var screenTimeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(Copy.screenTime.sectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .padding(.leading, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            screenTimeContent
        }
        .padding(.top, Theme.Spacing.sm)
    }

    /// The real numbers are drawn by the `ZANOReport` extension (spec §27: the app itself can never
    /// read them), sized to the summary view's height. CI screenshots have no Screen Time data, so
    /// they draw the same view from demo numbers. Without authorization, one card that asks.
    @ViewBuilder
    private var screenTimeContent: some View {
        if ScreenshotMode.screen != nil {
            ScreenTimeSummaryView(summary: DemoData.screenTime)
        } else if screenTimeStatus == .approved {
            DeviceActivityReport(.zanoToday, filter: Self.todayFilter)
                .frame(height: 660)
        } else {
            screenTimeAccessCard
        }
    }

    private static var todayFilter: DeviceActivityFilter {
        let day = Calendar.current.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: Calendar.current.startOfDay(for: .now), duration: 86_400)
        return DeviceActivityFilter(segment: .hourly(during: day))
    }

    /// Before Screen Time access: the same star, uncharged, beside what granting access buys.
    private var screenTimeAccessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZanoLivingMark(charge: 0, height: 34)
                    .padding(.top, Theme.Spacing.xxs)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.screenTime.accessTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.screenTime.accessDetail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PrimaryButton(title: Copy.screenTime.accessButton, style: .secondary) {
                Task {
                    try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    refreshScreenTimeStatus()
                }
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    // MARK: - Ghost Mode (one quiet line — the third most important thing here)

    private func ghostTint(_ c: GhostMode.GhostComparison) -> Color {
        // Same standing rules `GhostProgressBanner` uses: accent ahead, muted tied/none, warning
        // (never danger — spec §8 rule 9) when behind.
        guard c.hasGhostWeek else { return Theme.Colors.muted }
        if c.isAheadOfGhost { return Theme.Colors.accent }
        if c.isTiedWithGhost { return Theme.Colors.muted }
        return Theme.Colors.warning
    }

    private func ghostRow(_ c: GhostMode.GhostComparison) -> some View {
        let tint = ghostTint(c)
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flag.checkered")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(tint)
                .frame(width: Theme.Spacing.lg)
            Text(c.headline)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.xs)
            if c.hasGhostWeek {
                HStack(spacing: Theme.Spacing.sm) {
                    ghostScore(icon: "person.fill", value: c.currentCompletedCount, tint: Theme.Colors.text)
                    ghostScore(icon: "person", value: c.ghostCompletedCount, tint: Theme.Colors.muted)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xxs)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: c)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Copy.today.ghostModeTitle). \(c.headline)"))
    }

    private func ghostScore(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: icon)
                .font(Theme.Typography.icon(.xsmall))
            Text("\(value)")
                .font(Theme.Typography.numeralSmall())
                .contentTransition(.numericText(value: Double(value)))
        }
        .foregroundStyle(tint)
    }

    // MARK: - Bottom bar (only what a row can't do)

    private enum BarState: Equatable {
        case none
        case finishSetup
        case beginLock(lockSetID: UUID, requiredGoalIDs: [UUID])
        case focusRunning
        case verifyingAtGym
    }

    private var barState: BarState {
        guard !activeGoals.isEmpty else { return onFinishSetup == nil ? .none : .finishSetup }
        guard isLocked else {
            guard let lockSet = defaultLockSet else { return onFinishSetup == nil ? .none : .finishSetup }
            return .beginLock(lockSetID: lockSet.id, requiredGoalIDs: activeGoals.map(\.id))
        }
        if let runningFocusGoalID, requiredGoals.contains(where: { $0.id == runningFocusGoalID && !isGoalDoneToday($0) }) {
            return .focusRunning
        }
        if trackingGymID != nil { return .verifyingAtGym }
        return .none
    }

    @ViewBuilder
    private var bottomBar: some View {
        if barState != .none || actionError != nil || pendingUndo != nil {
            StickyActionBar(extendsToBottomEdge: false) {
                VStack(spacing: Theme.Spacing.xs) {
                    if let pendingUndo {
                        UndoToast(message: pendingUndo.message) { undo(pendingUndo) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let actionError {
                        Text(actionError)
                            .font(Theme.Typography.caption)
                            // `warning`, not `danger`: red is reserved for emergency.
                            .foregroundStyle(Theme.Colors.warning)
                            .multilineTextAlignment(.center)
                    }
                    barControl
                }
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: barState)
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: pendingUndo)
            }
        }
    }

    @ViewBuilder
    private var barControl: some View {
        switch barState {
        case .none:
            EmptyView()
        case .finishSetup:
            if let onFinishSetup {
                PrimaryButton(title: Copy.today.finishSetupTitle, systemImage: "arrow.right", action: onFinishSetup)
            }
        case .beginLock(let lockSetID, let requiredGoalIDs):
            PrimaryButton(
                title: Copy.today.beginLockStandardTitle,
                systemImage: "lock.fill",
                isEnabled: !isPerformingAction
            ) {
                beginLock(lockSetID: lockSetID, requiredGoalIDs: requiredGoalIDs)
            }
        case .focusRunning:
            TodayStatusRow(icon: "timer", title: Copy.today.focusRunningTitle, isLive: true)
        case .verifyingAtGym:
            TodayStatusRow(
                icon: "location.fill",
                title: Copy.today.verifyingAtGymTitle(minutes: gymDwellMinutes),
                isLive: true
            )
        }
    }

    private func beginLock(lockSetID: UUID, requiredGoalIDs: [UUID]) {
        actionError = nil
        Analytics.shared.capture(
            event: "today_begin_lock_tapped",
            properties: ["required_goal_count": requiredGoalIDs.count]
        )
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                _ = try await LockEngineManager.shared.startLock(
                    lockSetID: lockSetID,
                    mode: .earn,
                    requiredGoalIDs: requiredGoalIDs,
                    trigger: .manual
                )
            } catch {
                showError(Copy.today.lockStartFailed)
            }
        }
    }

    /// Polls `GymVerifier` for live dwell progress while `trackingGymID` is set, stopping once
    /// `isVerified` (the required minutes — `workoutGoal.targetValue`, falling back to spec §3's
    /// "default 35 min") or once `.task(id:)` restarts with a new/nil id.
    private func pollGymDwell() async {
        guard let gymID = trackingGymID else { return }
        let requiredMinutes = Int(workoutGoal?.targetValue ?? 35)
        while !Task.isCancelled, trackingGymID == gymID {
            gymDwellMinutes = await GymVerifier.shared.currentDwellMinutes(gymID: gymID)
            if await GymVerifier.shared.isVerified(gymID: gymID, requiredMinutes: requiredMinutes) {
                trackingGymID = nil
                return
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    // MARK: - Celebration

    /// The single required goal's title when the lock only required one, otherwise a generic
    /// fallback — naming one of several would misrepresent what happened.
    private var unlockCelebrationGoalName: String {
        guard let session = mostRecentlyEndedSession else { return Copy.today.unlockCelebrationFallbackGoalName }
        let requiredIDs = Set(session.requiredGoalIDs)
        let required = goals.filter { requiredIDs.contains($0.id) }
        guard required.count == 1, let only = required.first else {
            return Copy.today.unlockCelebrationFallbackGoalName
        }
        return only.title
    }

    // MARK: - Derived state

    private var voice: CoachVoice { users.first?.coachVoice ?? .hype }
    private var streak: Streak? { streaks.first }
    private var activeGoals: [Goal] { goals.filter(\.active) }
    private var defaultLockSet: LockSet? { lockSets.first(where: \.isDefault) ?? lockSets.first }
    private var primaryGym: Gym? { gyms.first(where: \.confirmed) }

    private var workoutGoal: Goal? {
        activeGoals.first { $0.type == .workoutGym || $0.type == .workoutHomeOutdoor }
    }

    private var activeLockSession: LockSession? { lockSessions.first(where: \.isActive) }
    private var isLocked: Bool { activeLockSession != nil }

    /// The lock set the running session is shielding (falls back to the default). Only its `name`
    /// and the on-device token blob are ever used — FamilyControls tokens never leave the device.
    private var activeLockSet: LockSet? {
        if let id = activeLockSession?.lockSetID, let match = lockSets.first(where: { $0.id == id }) {
            return match
        }
        return defaultLockSet
    }

    private var requiredGoals: [Goal] {
        guard let session = activeLockSession else { return [] }
        let requiredIDs = Set(session.requiredGoalIDs)
        return goals.filter { requiredIDs.contains($0.id) }
    }

    private var remainingRequiredGoalCount: Int {
        requiredGoals.filter { !isGoalDoneToday($0) }.count
    }

    private var completedGoalCount: Int {
        activeGoals.filter(isGoalDoneToday).count
    }

    private var mostRecentlyEndedSession: LockSession? {
        lockSessions
            .filter { $0.endedAt != nil }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
    }
    private var lastUnlockWasEarned: Bool { mostRecentlyEndedSession?.unlockKind == .earned }

    private var todaysTimeBank: TimeBank? {
        timeBanks.first { Calendar.current.isDateInToday($0.date) }
    }

    private var isStreakFrozenToday: Bool {
        goalEvents.contains { $0.kind == .freeze && Calendar.current.isDateInToday($0.ts) }
    }

    // MARK: - Per-goal progress

    private func todaysPlan(for goal: Goal) -> DailyPlan? {
        dailyPlans.first { $0.goal?.id == goal.id && Calendar.current.isDateInToday($0.date) }
    }

    private func todaysEvents(for goal: Goal) -> [GoalEvent] {
        goalEvents.filter { $0.goal?.id == goal.id && Calendar.current.isDateInToday($0.ts) }
    }

    private func dayProgress(for goal: Goal) -> GoalDayProgress {
        GoalDayProgress(
            goal: goal,
            todaysEvents: todaysEvents(for: goal),
            plannedValue: todaysPlan(for: goal)?.plannedValue
        )
    }

    private func isGoalDoneToday(_ goal: Goal) -> Bool {
        dayProgress(for: goal).isComplete
    }
}

// MARK: - Shared pieces (internal: `LockStatusView.swift` reuses these)

/// SF Symbol for a goal type. Symbol names are identifiers, not copy. Names beyond the four Today
/// already used (`dumbbell.fill`, `timer`, `fork.knife`) are from memory of the SF Symbols catalog
/// and unverified in this environment; a wrong name renders blank rather than crashing.
func goalIconName(for type: GoalType) -> String {
    switch type {
    case .workoutGym: "dumbbell.fill"
    case .workoutHomeOutdoor: "figure.run"
    case .focusSession: "timer"
    case .protein: "fork.knife"
    case .water: "drop.fill"
    case .steps: "figure.walk"
    case .creatine: "pills.fill"
    case .sunriseAlarm: "sunrise.fill"
    case .sleepOnTime: "moon.zzz.fill"
    case .reading: "book.fill"
    case .mealPrep: "refrigerator.fill"
    case .stretchMobility: "figure.flexibility"
    case .coldShowerSauna: "snowflake"
    case .custom: "star.fill"
    }
}

// `GoalDayProgress` (shared by Today and Lock) lives in Core: `Core/Sources/Core/LockEngine/
// GoalDayProgress.swift`, so the UI and `GoalCompletionCoordinator` use one rule.

/// One capsule per required goal (capped at 8; beyond that, proportionally), filled for done. The
/// unfilled segments are `Theme.Colors.track` (1.6 : 1 on a card) so a fresh day's bar is visible,
/// not a floating accent fragment. Decorative — the numeral and the card's spoken label carry the
/// information.
struct SegmentedProgress: View {
    let total: Int
    let done: Int
    let filled: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxSegments = 8
    /// No `Theme.Metrics` home for a segment height; named here rather than inlined.
    private static let segmentHeight: CGFloat = 6

    private var segmentCount: Int { max(1, min(total, Self.maxSegments)) }

    private var filledCount: Int {
        guard total > 0 else { return 0 }
        let clamped = min(max(done, 0), total)
        return total <= Self.maxSegments ? clamped : (clamped * Self.maxSegments) / total
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < filledCount ? filled : Theme.Colors.track)
                    .frame(height: Self.segmentHeight)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: filledCount)
        .accessibilityHidden(true)
    }
}

// MARK: - Private pieces

/// One step of the first-day checklist: a numbered disc (a blue check once done, a blue ring on
/// the step that's next), the step and one line of why, a chevron when it can be tapped. The disc
/// column is joined by a thin rail so the three read as one path, not three unrelated rows.
private struct FirstDayStepRow: View {
    let index: Int
    let total: Int
    let title: String
    let detail: String
    let isDone: Bool
    let isCurrent: Bool
    let isLast: Bool
    let action: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 28

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) { spokenContent }
                .buttonStyle(.pressable)
        } else {
            spokenContent
        }
    }

    /// One announcement per step (the Button, when there is one, adds its own trait and action).
    private var spokenContent: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.today.firstDayStepAccessibility(index: index, total: total, title: title, isDone: isDone))
            .accessibilityHint(detail)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(spacing: 0) {
                disc
                if !isLast {
                    Rectangle()
                        .fill(isDone ? Theme.Colors.accentDim : Theme.Colors.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, Theme.Spacing.xxs)
                }
            }
            .frame(width: discSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isDone ? Theme.Colors.muted : Theme.Colors.text)
                    .strikethrough(isDone, color: Theme.Colors.muted)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
            .padding(.bottom, isLast ? Theme.Spacing.xs : Theme.Spacing.md)

            Spacer(minLength: Theme.Spacing.xs)

            if action != nil, !isDone {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(isCurrent ? Theme.Colors.accent : Theme.Colors.muted)
                    .padding(.top, 6)
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var disc: some View {
        if isDone {
            Image(systemName: "checkmark")
                .font(Theme.Typography.icon(.small, weight: .bold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: discSize, height: discSize)
                .background(Theme.Colors.accent, in: Circle())
        } else {
            Text("\(index)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(isCurrent ? Theme.Colors.accent : Theme.Colors.muted)
                .frame(width: discSize, height: discSize)
                .background(isCurrent ? Theme.Colors.accentWash : Color.clear, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        isCurrent ? Theme.Colors.accent : Theme.Colors.hairlineStrong,
                        lineWidth: isCurrent ? 1.5 : Theme.Metrics.edgeWidth
                    )
                )
        }
    }
}

/// A non-interactive state row for bottom-bar states that used to be a dead, half-opacity accent
/// button. Same height and shape as `PrimaryButton` (a capsule, `primaryButtonHeight`) so the bar
/// doesn't jump when it swaps.
private struct TodayStatusRow: View {
    let icon: String
    let title: String
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.accent)
                // Indefinite pulse only while live, never under Reduce Motion.
                .symbolEffect(.pulse, isActive: isLive && !reduceMotion)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryButtonHeight, alignment: .leading)
        .background(Theme.Colors.surface2, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The pending undo for the last quick-log.
private struct QuickLogUndo: Identifiable, Equatable {
    let id = UUID()
    let eventID: UUID
    let message: String
}

#Preview {
    TodayView()
        .modelContainer(for: [
            User.self, Goal.self, DailyPlan.self, GoalEvent.self,
            LockSet.self, LockSession.self, Streak.self, TimeBank.self, Gym.self
        ], inMemory: true)
}
