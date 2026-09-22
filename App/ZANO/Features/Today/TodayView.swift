// TodayView.swift
// App / ZANO / Features / Today
//
// The Today screen — docs/spec.md §15 ("Screens: Today, Lock, Fuel, Progress, Squad, Settings...")
// and §16 P1 mockup: "Top: streak pill '14 🔥' and lock status card 'Locked · TikTok, Instagram,
// YouTube' with a small padlock. Center: three progress rings labeled Workout, Protein (72/150g),
// Focus (25/50 min). Bottom: a single primary button 'Go to gym · 6 min away'."
//
// Built entirely from Core/UI's design system (Theme + the components named in spec §15's core
// component list: GoalRing, RingCluster, LockStatusCard, StreakPill, PrimaryButton) and reads
// SwiftData directly (this is app code, not an extension — CLAUDE.md's "no network in extensions"
// rule doesn't apply here, and per Core/Sources/Core/Store/SharedDefaults.swift's own doc comment,
// SwiftData — not the App-Group UserDefaults mirror meant for extensions — is the source of truth
// for anything durable). `SharedDefaults.nextScheduledLockAt` is the one exception: there is no
// SwiftData model for "when does the next schedule fire," so that one field is read from the shared
// mirror (`Core/Sources/Core/LockEngine`/DeviceActivity owns writing it).
//
// Engine calls in this file (`LockEngineManager`, `FocusSessionVerifier`, `GymVerifier`) are used
// exactly per this task's SYSTEM CONTRACTS shape. None of those files exist on disk yet in this
// session — they're being built in parallel by other sessions — so none of this can be compiled or
// run here (no Mac/Swift toolchain in this environment either way). See this task's "decisions" /
// "knownIssues" output for the assumptions made where this screen guesses at an unbuilt API.
//
// Copy note: CLAUDE.md requires user-facing strings to live in Core/Sources/Core/Copy, but this
// task's owned-file list is only this file and LockStatusView.swift — adding new Core/Copy files
// isn't in scope here (risk of colliding with another parallel session's file). Structural labels
// (ring titles, button titles) are centralized in the private `Copy` enum below instead, and
// anything with real "coach voice" (streak/goals-remaining phrasing) reuses the already-built
// `CoachVoiceTone` helpers from Core/Sources/Core/Copy/CoachVoice.swift rather than inventing new
// phrasing here. Flagged as a known deviation — recommend a follow-up moves `Copy` below into
// `Core/Sources/Core/Copy/TodayCopy.swift` once that file has a clear owner.

import Foundation
import SwiftUI
import SwiftData
import Core

struct TodayView: View {

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

    // MARK: - Local state

    /// Set locally the moment this screen itself starts a focus session, so the primary button can
    /// reflect "running" immediately without waiting on a round trip. Cleared once a `.complete`/
    /// `.verify`/`.planB` event lands for that goal today (read reactively via `goalEvents`).
    ///
    /// TODO(cross-module, Verification/LiveActivity sessions): this only knows about sessions
    /// *this screen* started. A focus session started from a widget, Siri, or NFC wouldn't be
    /// reflected here until its completion event lands. A shared "is a verification in progress"
    /// signal (e.g. mirrored in `SharedDefaults`, alongside `activeLockSessionID`) would let Today
    /// reflect that across entry points; not part of this task's given contracts, so not guessed.
    @State private var runningFocusGoalID: UUID?
    @State private var trackingGymID: UUID?
    /// Live dwell minutes for `trackingGymID`, polled from `GymVerifier` while tracking is active —
    /// see the `.task(id: trackingGymID)` modifier in `body` below.
    @State private var gymDwellMinutes: Int = 0

    @State private var isPerformingPrimaryAction = false
    @State private var actionError: String?
    @State private var showLockDetail = false
    @State private var showCelebration = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    lockStatusCard
                    ringsSection
                    if let actionError {
                        Text(actionError)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.danger)
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                primaryButtonView
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.sm)
                    .background(.ultraThinMaterial)
            }
            .navigationDestination(isPresented: $showLockDetail) {
                LockStatusView()
            }
            .task(id: trackingGymID) {
                await pollGymDwell()
            }
            .overlay(alignment: .top) {
                if showCelebration {
                    celebrationBanner
                        .padding(.top, Theme.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: isLocked) { oldValue, newValue in
            oldValue == true && newValue == false
        }
        .sensoryFeedback(.impact(weight: .light), trigger: completedGoalCount) { oldValue, newValue in
            newValue > oldValue
        }
        .onChange(of: isLocked) { oldValue, newValue in
            guard oldValue == true, newValue == false, lastUnlockWasEarned else { return }
            withAnimation(Theme.Motion.springCelebration) { showCelebration = true }
            Task {
                try? await Task.sleep(for: .milliseconds(Int(Theme.Motion.unlockCelebrationMaxDuration * 1000)))
                withAnimation(Theme.Motion.springStandard) { showCelebration = false }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Copy.screenTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            StreakPill(
                count: streak?.current ?? 0,
                isFrozen: isStreakFrozenToday,
                accessibilityLabelOverride: CoachVoiceTone.streakClause(voice, streak: streak?.current ?? 0)
            )
        }
    }

    // MARK: - Lock status card

    private var lockStatusCard: some View {
        LockStatusCard(
            isLocked: isLocked,
            statusLine: Copy.lockStatusLine(isLocked: isLocked, goalsRemaining: remainingRequiredGoalCount),
            detailLine: lockDetailLine,
            action: { showLockDetail = true }
        )
    }

    private var lockDetailLine: String? {
        guard activeLockSession != nil else { return nil }
        if let bank = todaysTimeBank, activeLockSession?.mode == .earn, bank.remainingMin > 0 {
            return "\(bank.remainingMin) min banked"
        }
        return CoachVoiceTone.goalsRemainingClause(voice, remaining: remainingRequiredGoalCount)
    }

    // MARK: - Rings

    private var ringsSection: some View {
        RingCluster(items: ringItems, ringSize: .large, layout: .row)
    }

    /// Fixed placeholder ids for the "goal not configured yet" ring state, one per ring slot below.
    /// Without these, the not-configured branch of `ringItem(for:...)` would hand `RingClusterItem`
    /// a fresh `UUID()` on every body re-render (its default), which — since `RingCluster` diffs
    /// its `ForEach` by `id` — would make SwiftUI treat the ring as a brand-new view and reset its
    /// fill animation on every unrelated `@Query` update instead of leaving it stable.
    private enum RingSlotID {
        static let workout = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        static let protein = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        static let focus = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    }

    private var ringItems: [RingClusterItem] {
        [
            ringItem(for: workoutGoal, fallbackID: RingSlotID.workout, title: Copy.ringTitleWorkout, color: Theme.Colors.Ring.workout, icon: "dumbbell.fill"),
            ringItem(for: proteinGoal, fallbackID: RingSlotID.protein, title: Copy.ringTitleProtein, color: Theme.Colors.Ring.protein, icon: "fork.knife"),
            ringItem(for: focusGoal, fallbackID: RingSlotID.focus, title: Copy.ringTitleFocus, color: Theme.Colors.Ring.focus, icon: "timer")
        ]
    }

    private func ringItem(for goal: Goal?, fallbackID: UUID, title: String, color: Color, icon: String) -> RingClusterItem {
        guard let goal else {
            return RingClusterItem(id: fallbackID, title: title, progress: 0, color: Theme.Colors.muted, valueText: Copy.ringNotSet, centerIcon: icon)
        }
        let p = progress(for: goal)
        return RingClusterItem(id: goal.id, title: title, progress: p.fraction, color: color, valueText: p.valueText, centerIcon: icon)
    }

    // MARK: - Celebration

    private var celebrationBanner: some View {
        Text(Copy.celebrationText)
            .font(Theme.Typography.numeralMedium())
            .foregroundStyle(Theme.Colors.background)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.accent, in: Capsule())
    }

    // MARK: - Primary button (contextual — spec §16 P1: "a single primary button")

    /// The one actionable next step Today can offer given current state. Ordered by the tightest
    /// verification loop this screen can directly drive (focus timer, then gym dwell); goals this
    /// screen has no direct action for (e.g. protein/water logging — Fuel screen, not owned here)
    /// fall through to an informational, disabled state rather than guessing at Fuel's API.
    private enum PrimaryAction: Equatable {
        case setupIncomplete
        case beginLock(lockSetID: UUID, requiredGoalIDs: [UUID])
        case startFocus(goalID: UUID, minutes: Int)
        case focusRunning
        case verifyAtGym(gymID: UUID)
        case verifyingAtGym
        case waitingToUnlock
        case openFuel
    }

    private var primaryAction: PrimaryAction {
        guard !activeGoals.isEmpty else { return .setupIncomplete }

        guard let session = activeLockSession else {
            guard let lockSet = defaultLockSet else { return .setupIncomplete }
            return .beginLock(lockSetID: lockSet.id, requiredGoalIDs: activeGoals.map(\.id))
        }

        let requiredIDs = Set(session.requiredGoalIDs)
        let unmet = goals.filter { requiredIDs.contains($0.id) && !isGoalDoneToday($0) }
        guard !unmet.isEmpty else { return .waitingToUnlock }

        if let runningFocusGoalID, unmet.contains(where: { $0.id == runningFocusGoalID }) {
            return .focusRunning
        }
        if let focus = unmet.first(where: { $0.type == .focusSession }) {
            let minutes = Int(todaysPlan(for: focus)?.plannedValue ?? focus.targetValue ?? 25)
            return .startFocus(goalID: focus.id, minutes: max(1, minutes))
        }
        if trackingGymID != nil { return .verifyingAtGym }
        if unmet.contains(where: { $0.type == .workoutGym }), let gym = primaryGym {
            return .verifyAtGym(gymID: gym.id)
        }
        return .openFuel
    }

    @ViewBuilder
    private var primaryButtonView: some View {
        switch primaryAction {
        case .setupIncomplete:
            PrimaryButton(title: Copy.setupIncompleteTitle, systemImage: "gearshape.fill", isEnabled: false, action: {})
        case .beginLock:
            PrimaryButton(
                title: Copy.beginLockTitle,
                systemImage: "lock.fill",
                style: .holdToCommit,
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .startFocus(_, let minutes):
            PrimaryButton(
                title: Copy.startFocusTitle(minutes: minutes),
                systemImage: "timer",
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .focusRunning:
            PrimaryButton(title: Copy.focusRunningTitle, systemImage: "timer", isEnabled: false, action: {})
        case .verifyAtGym:
            PrimaryButton(
                title: Copy.goToGymTitle,
                systemImage: "figure.strengthtraining.traditional",
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .verifyingAtGym:
            PrimaryButton(
                title: Copy.verifyingAtGymTitle(minutes: gymDwellMinutes),
                systemImage: "location.fill",
                isEnabled: false,
                action: {}
            )
        case .waitingToUnlock:
            PrimaryButton(title: Copy.allDoneTitle, systemImage: "checkmark.circle.fill", isEnabled: false, action: {})
        case .openFuel:
            PrimaryButton(title: Copy.openFuelTitle, systemImage: "fork.knife", isEnabled: false, action: {})
        }
    }

    private func performPrimaryAction() {
        switch primaryAction {
        case .beginLock(let lockSetID, let requiredGoalIDs):
            isPerformingPrimaryAction = true
            Task {
                defer { isPerformingPrimaryAction = false }
                do {
                    _ = try await LockEngineManager.shared.startLock(
                        lockSetID: lockSetID,
                        mode: .earn,
                        requiredGoalIDs: requiredGoalIDs,
                        trigger: .manual
                    )
                } catch {
                    actionError = error.localizedDescription
                }
            }

        case .startFocus(let goalID, let minutes):
            isPerformingPrimaryAction = true
            Task {
                defer { isPerformingPrimaryAction = false }
                do {
                    _ = try await FocusSessionVerifier.shared.startSession(goalID: goalID, plannedMinutes: minutes)
                    runningFocusGoalID = goalID
                } catch {
                    actionError = error.localizedDescription
                }
            }

        case .verifyAtGym(let gymID):
            trackingGymID = gymID
            Task { await GymVerifier.shared.beginDwellTracking(gymID: gymID) }

        case .setupIncomplete, .focusRunning, .verifyingAtGym, .waitingToUnlock, .openFuel:
            break
        }
    }

    /// Polls `GymVerifier` for live dwell progress while `trackingGymID` is set, stopping itself
    /// once `isVerified` returns true (the required-minutes threshold — `workoutGoal.targetValue`,
    /// falling back to spec §3's "default 35 min" — has been met) or once tracking is cancelled by
    /// `.task(id:)` restarting with a new/nil id. Clearing `trackingGymID` here (rather than only
    /// waiting on a `GoalEvent` to propagate through `@Query`) lets the primary button react the
    /// moment verification completes instead of lagging a poll interval behind it.
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

    // MARK: - Derived state

    private var voice: CoachVoice { users.first?.coachVoice ?? .hype }
    private var streak: Streak? { streaks.first }
    private var activeGoals: [Goal] { goals.filter(\.active) }
    private var defaultLockSet: LockSet? { lockSets.first(where: \.isDefault) ?? lockSets.first }
    private var primaryGym: Gym? { gyms.first(where: \.confirmed) }

    private var workoutGoal: Goal? {
        activeGoals.first { $0.type == .workoutGym || $0.type == .workoutHomeOutdoor }
    }
    private var proteinGoal: Goal? { activeGoals.first { $0.type == .protein } }
    private var focusGoal: Goal? { activeGoals.first { $0.type == .focusSession } }

    private var activeLockSession: LockSession? { lockSessions.first(where: \.isActive) }
    private var isLocked: Bool { activeLockSession != nil }

    private var remainingRequiredGoalCount: Int {
        guard let session = activeLockSession else { return 0 }
        let requiredIDs = Set(session.requiredGoalIDs)
        return goals.filter { requiredIDs.contains($0.id) && !isGoalDoneToday($0) }.count
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

    private func isGoalDoneToday(_ goal: Goal) -> Bool {
        progress(for: goal).fraction >= 1
    }

    /// Fraction complete + a caller-composed value string for today, per spec §16 P1's ring labels
    /// (e.g. "72/150g", "25/50 min"). A goal with no numeric target (e.g. a dwell-based workout
    /// goal with no `targetValue`/`plannedValue`) is treated as binary: done once a `.complete`,
    /// `.verify`, or `.planB` (spec §8 Plan B days still count as done) event lands today.
    private func progress(for goal: Goal) -> (fraction: Double, valueText: String) {
        let events = todaysEvents(for: goal)
        let hasCompletion = events.contains { [.complete, .verify, .planB].contains($0.kind) }
        let target = todaysPlan(for: goal)?.plannedValue ?? goal.targetValue

        guard let target, target > 0 else {
            return (hasCompletion ? 1 : 0, hasCompletion ? "Done" : "Not yet")
        }

        let loggedSum = events.compactMap(\.value).reduce(0, +)
        let fraction = hasCompletion ? 1 : min(1, loggedSum / target)
        let unit = goal.unit ?? ""
        let valueText = "\(Int(loggedSum.rounded()))/\(Int(target.rounded()))\(unit)"
        return (fraction, valueText)
    }

    // MARK: - Copy

    /// See the file-level header comment for why this is here instead of `Core/Sources/Core/Copy`.
    private enum Copy {
        static let screenTitle = "Today"

        static func lockStatusLine(isLocked: Bool, goalsRemaining: Int) -> String {
            guard isLocked else { return "Unlocked" }
            return goalsRemaining == 1 ? "Locked · 1 goal left" : "Locked · \(goalsRemaining) goals left"
        }

        static let ringTitleWorkout = "Workout"
        static let ringTitleProtein = "Protein"
        static let ringTitleFocus = "Focus"
        static let ringNotSet = "Not set"

        static let setupIncompleteTitle = "Finish setup to start locking"
        static let beginLockTitle = "Hold to start today's lock"
        static func startFocusTitle(minutes: Int) -> String { "Start \(minutes)-min focus session" }
        static let focusRunningTitle = "Focus session running…"
        static let goToGymTitle = "I'm at the gym"
        static func verifyingAtGymTitle(minutes: Int) -> String { "Verifying at the gym… (\(minutes) min so far)" }
        static let allDoneTitle = "All goals done — unlocking…"
        static let openFuelTitle = "Log the rest on Fuel"
        static let celebrationText = "Earned."
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [
            User.self, Goal.self, DailyPlan.self, GoalEvent.self,
            LockSet.self, LockSession.self, Streak.self, TimeBank.self, Gym.self
        ], inMemory: true)
}
