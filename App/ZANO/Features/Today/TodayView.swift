// TodayView.swift
// App / ZANO / Features / Today
//
// The Today screen — docs/spec.md §15 ("Screens: Today, Lock, Fuel, Progress, Squad, Settings...")
// and §16 P1 mockup: "Top: streak pill '14 🔥' and lock status card 'Locked · TikTok, Instagram,
// YouTube' with a small padlock. Center: three progress rings labeled Workout, Protein (72/150g),
// Focus (25/50 min). Bottom: a single primary button 'Go to gym · 6 min away'."
//
// Design pass (2026-09-23; docs/design/composition-audit.md offender #1, better-layout H1/H6,
// better-ui BRK-05/MOT-04/DEP-01…06, typography-color T3/C10, competitive-research 3.1/3.10/3.12,
// 2026-ios-trends §2.3/§3.3). What the screen is now, and why, in one place:
//
// - ONE hero. The lock state is a single large card whose whole job is one number, set in the
//   design system's hero numeral tier (`NumeralText(.hero)`, 72 pt heavy rounded): "2 goals left"
//   while locked, "3/4 done" while not. Everything else on the page is deliberately quieter than it
//   (hero numeral 72 pt vs ring values ~26 pt vs captions 13 pt), so the eye lands once. The card
//   carries the state in its surface, not just its label: a danger-tinted top-leading wash while a
//   lock runs (`danger` is the spec's locked colour; only the small badge and the wash use it, the
//   numeral stays `text` so a routine locked day reads calm), accent + the static "earned" glow when
//   every goal is done. The screen backdrop takes a faint accent wash in the same earned state.
// - The ring row fits. `RingCluster(.row)` is equal columns (three 88 pt rings, 312 pt, in a 343 pt
//   minimum column) — it used to be a 500 pt scroller that clipped the third ring on every iPhone.
//   The value is inside each ring, the goal's glyph is beside its title, tracks are the ring's own
//   hue, and an unconfigured slot is a dashed ring with a plus.
// - The rings are the goals that gate the lock. While locked they are the session's required goals
//   (open ones first), not three hard-coded types, so "2 goals left" can never coexist with no
//   visible goal (better-layout H6). Overflow past three is a "+N more" link to the Lock screen.
// - No dead CTA. Statuses (focus running, verifying at the gym, all done) are a status row or
//   nothing, never a 50 %-opacity accent button. "Open Fuel" and "Finish setup" are real buttons
//   once the tab shell injects `onOpenFuel` / `onFinishSetup` (`ContentView`/`AppRouter` belong to
//   another workflow this run); until then they degrade to a status row / nothing.
// - Begin-lock is a plain tap. The 2 s hold is the app's commitment/emergency gesture; spending it on
//   a daily routine action dilutes it (spec only requires hold-to-commit for onboarding step 11).
// - The bottom bar is a `StickyActionBar` gradient fade, not `.ultraThinMaterial`, so it never
//   stacks a second translucent slab over the iOS 26 floating tab bar.
// - Built on Core/UI, not local stand-ins: `zanoCard` (top-lit edge, tint wash, earned glow),
//   `IconBadge`, `NumeralText`, `GoalRing`/`RingCluster`, `zanoBackdrop`, `StickyActionBar`,
//   `PressableStyle`, `PrimaryButton`. The only private pieces left are the ghost row, the
//   segmented progress and the status row, none of which Core has.
//
// Every animation here is gated on `@Environment(\.accessibilityReduceMotion)` (nil animation or a
// plain fade), and the wash/glow are dropped under Reduce Transparency; the Core components used
// here carry their own Reduce Motion gates.
//
// Reads SwiftData directly (this is app code, not an extension — CLAUDE.md's "no network in
// extensions" rule doesn't apply here, and per Core/Sources/Core/Store/SharedDefaults.swift's own
// doc comment, SwiftData — not the App-Group UserDefaults mirror meant for extensions — is the
// source of truth for anything durable).
//
// Engine calls in this file (`LockEngineManager`, `FocusSessionVerifier`, `GymVerifier`) are used
// exactly per this task's SYSTEM CONTRACTS shape. Nothing here has been compiled or rendered (no
// Mac/Swift toolchain in this environment).
//
// Copy note: user-facing strings go through `Copy.today.*` (`Core/Sources/Core/Copy/TodayCopy.swift`).
// The strings this pass added (`hero*`, `progressValue`, `moreGoalsLink`, `beginLockStandardTitle`, ...)
// briefly lived in an `extension Copy.today` at the bottom of this file; the review pass moved them
// into `TodayCopy.swift` verbatim, so call sites are unchanged. `Copy.today.beginLockStandardTitle`
// is load-bearing: the UI tests find the begin-lock button by that exact text. Coach-voice
// phrasing reuses `CoachVoiceTone`.

import Foundation
import SwiftUI
import SwiftData
import Core

struct TodayView: View {

    // MARK: - Injected navigation

    /// Switches the tab shell to Fuel. `ContentView` / `AppRouter` are owned by a concurrent
    /// workflow this run, so Today can't route there itself; the shell should pass its own
    /// tab-switch closure. While `nil`, the "log the rest on Fuel" state renders as a status row
    /// instead of a button that does nothing.
    private let onOpenFuel: (() -> Void)?

    /// Opens whichever surface finishes setup (goals, lock set). Same story as `onOpenFuel`: the
    /// shell owns navigation. While `nil`, an incomplete setup shows no bottom action — the hero
    /// already says "Finish setup to start locking" — rather than a button that does nothing.
    private let onFinishSetup: (() -> Void)?

    init(onOpenFuel: (() -> Void)? = nil, onFinishSetup: (() -> Void)? = nil) {
        self.onOpenFuel = onOpenFuel
        self.onFinishSetup = onFinishSetup
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
    /// Drives `UnlockCelebrationView`'s `.fullScreenCover` below (docs/spec.md §16 P3). Set only
    /// for an *earned* unlock (`lastUnlockWasEarned`) by the `onChange(of: isLocked)` handler —
    /// manual/emergency/schedule-end unlocks never get the celebration moment.
    ///
    /// Known gap (flagged, not built here): spec §8 rule 4's "1 in ~6 unlocks" variable-reward
    /// surprise (`UnlockCelebrationBadge`) has no gating logic anywhere in the codebase yet, so
    /// this always presents with `badge: nil`. Wiring the odds belongs to whichever session owns
    /// that reward logic (not this screen's own presentation hook).
    @State private var showUnlockCelebration = false
    /// Today vs. "Ghost You" (docs/spec.md §5.4), loaded/refreshed by the `.task(id:
    /// completedGoalCount)` below. `nil` until the first load completes, which keeps the ghost row
    /// off screen for that one frame instead of handing it a fabricated empty comparison.
    @State private var ghostComparison: GhostMode.GhostComparison?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    heroCard
                    ringsSection
                    if let ghostComparison {
                        ghostRow(ghostComparison)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            // The screen fits on a tall phone; don't rubber-band content that has nowhere to go.
            .scrollBounceBehavior(.basedOnSize)
            // The canvas, with a faint accent wash from the top edge in the earned state only
            // (`accent` = earned/unlock). Static, and dropped under Reduce Transparency.
            .zanoBackdrop(glow: reduceTransparency ? nil : backdropGlow, intensity: 0.10)
            // Today draws its own header. Without this a `NavigationStack` with no title leaves an
            // empty navigation-bar band above it (composition-audit #1 "Minor"). Pushed screens
            // (`LockStatusView`) set their own bar and are unaffected.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationDestination(isPresented: $showLockDetail) {
                LockStatusView()
            }
            .task(id: trackingGymID) {
                await pollGymDwell()
            }
            .task(id: completedGoalCount) {
                // Refetches whenever today's completed-goal count changes, which is the only
                // input that can move `currentCompletedCount` for *today* (docs/spec.md §5.4);
                // also covers the initial load since `.task(id:)` runs immediately for the
                // current id.
                ghostComparison = await GhostMode.shared.ghostComparison(for: .now)
            }
            .task {
                // docs/spec.md §23: "every screen view... (count only, on device → aggregate)".
                Analytics.shared.capture(event: "screen_viewed", properties: ["screen": "today"])
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
            guard oldValue == true, newValue == false else { return }
            // docs/spec.md §23: "every... unlock kind". Every lock-session end this screen
            // observes, not only earned ones — manual/emergency/schedule-end unlocks are still an
            // "unlock kind" worth counting even though only an earned one gets the celebration
            // moment below.
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

    /// Date eyebrow over the title, streak pill trailing. The eyebrow is locale-formatted date
    /// data (not copy), so it needs no `Copy` entry. The title is one step quieter than the
    /// sibling tabs' large titles on purpose: the hero numeral below is the loudest thing here.
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.muted)
                Text(Copy.today.screenTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: Theme.Spacing.sm)
            StreakPill(
                count: streak?.current ?? 0,
                isFrozen: isStreakFrozenToday,
                accessibilityLabelOverride: CoachVoiceTone.streakClause(voice, streak: streak?.current ?? 0)
            )
        }
    }

    // MARK: - Hero (the lock state, as one number)

    /// What the hero says. Derived from the same facts the primary action reads, so the two can't
    /// disagree about what state the app is in.
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

    /// The earned state: every goal for the day is done (or the lock is about to release). The one
    /// place the card glows and the backdrop washes — the glow is the reward, so it stays rare.
    private var heroIsEarned: Bool {
        switch heroState {
        case .unlocking: true
        case .unlocked(let done, let total): total > 0 && done >= total
        case .setup, .locked: false
        }
    }

    private var heroCard: some View {
        Button {
            Analytics.shared.capture(event: "today_lock_status_tapped")
            showLockDetail = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroTopRow
                heroBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .zanoCard(
                radius: Theme.Radius.large,
                tint: reduceTransparency ? nil : heroTint,
                active: heroIsEarned && !reduceTransparency
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            // One announcement for the whole card instead of a swipe through badge, eyebrow,
            // numeral and unit as four disconnected stops.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
        }
        // Padding and background live inside the label, so the whole card is the hit target and
        // the whole card presses.
        .buttonStyle(.pressable)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: heroState)
    }

    private var heroTopRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: heroBadgeSymbol, tint: heroBadgeTint, size: .small)
            Text(heroEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    @ViewBuilder
    private var heroBody: some View {
        switch heroState {
        case .setup:
            Text(Copy.today.setupIncompleteTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)

        case .locked(let remaining, let total):
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroNumeral(
                    Copy.today.heroGoalsLeftLine(count: remaining),
                    color: Theme.Colors.text,
                    changeKey: remaining
                )
                HStack(spacing: Theme.Spacing.sm) {
                    SegmentedProgress(total: total, done: total - remaining, filled: Theme.Colors.accent)
                    if let chip = bankChipText {
                        bankChip(chip)
                    }
                }
            }

        case .unlocking:
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "checkmark", tint: Theme.Colors.accent, size: .medium)
                Text(Copy.today.allDoneTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .unlocked(let done, let total):
            let allDone = total > 0 && done >= total
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroNumeral(
                    Copy.today.heroFractionDone(done: done, total: total),
                    color: allDone ? Theme.Colors.accent : Theme.Colors.text,
                    changeKey: done
                )
                SegmentedProgress(total: total, done: done, filled: Theme.Colors.accent)
            }
        }
    }

    /// The one giant number. `NumeralText` splits the caller-composed line into a big numeral and a
    /// quiet unit on a shared baseline ("2" over "goals left"; "3" over "/4 done") and rolls the
    /// digits with `.numericText` when the count changes (a no-op under Reduce Motion, where the
    /// ambient animation is nil and `NumeralText` swaps to an identity transition).
    private func heroNumeral(_ line: String, color: Color, changeKey: Int) -> some View {
        NumeralText(line, size: .hero, color: color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: changeKey)
    }

    /// Earn Mode's banked minutes, beside the progress segments while locked. Earned minutes are
    /// the accent's job, so this is accent-on-wash (11.2 : 1).
    private func bankChip(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.accent)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.Colors.accentWash, in: Capsule())
            .fixedSize()
    }

    private var heroEyebrow: String {
        switch heroState {
        case .setup: Copy.today.heroSetupEyebrow
        case .locked: Copy.today.heroLockedEyebrow(lockSetName: activeLockSet?.name)
        case .unlocking: Copy.today.heroUnlockingEyebrow
        case .unlocked: Copy.today.lockStatusLine(isLocked: false, goalsRemaining: 0)
        }
    }

    private var heroBadgeSymbol: String {
        switch heroState {
        case .setup: "gearshape.fill"
        case .locked: "lock.fill"
        case .unlocking: "checkmark"
        case .unlocked: "lock.open.fill"
        }
    }

    /// Locked keeps the spec's `danger` (§15 "Danger/locked") but only as a badge tint and a faint
    /// wash — the numeral itself stays `text`, so a routine locked day reads as calm, not alarming.
    /// `accent` is reserved for earned/unlocked states.
    private var heroBadgeTint: Color {
        switch heroState {
        case .setup: Theme.Colors.muted
        case .locked: Theme.Colors.danger
        case .unlocking, .unlocked: Theme.Colors.accent
        }
    }

    private var heroTint: Color? {
        switch heroState {
        case .setup: nil
        default: heroBadgeTint
        }
    }

    private var backdropGlow: Color? {
        heroIsEarned ? Theme.Colors.accent : nil
    }

    /// Earn Mode's banked minutes, shown as a chip beside the progress segments while locked.
    private var bankChipText: String? {
        guard activeLockSession?.mode == .earn, let bank = todaysTimeBank, bank.remainingMin > 0 else { return nil }
        return Copy.today.heroTimeBankChip(minutes: bank.remainingMin)
    }

    /// The spoken version of the whole card. Keeps the coach-voice clause the old card carried in
    /// its detail line (it is no longer drawn, because it repeated the numeral). The locked and
    /// unlocked variants start with `Copy.today.lockStatusLine(...)`, which the UI tests match.
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

    // MARK: - Rings

    private static let maxRings = 3

    /// The three ring slots the spec names (§16 P1). Used to keep those goals first and to draw a
    /// "Not set" placeholder for a slot the user hasn't configured while nothing is locked.
    private enum CanonicalSlot: CaseIterable {
        case workout, protein, focus

        /// Fixed placeholder ids for the "goal not configured yet" ring state, one per slot.
        /// Without these, the placeholder would get a fresh `UUID()` on every body re-render,
        /// which — since `ForEach` diffs by `id` — would make SwiftUI treat the ring as a brand-new
        /// view and reset its fill animation on every unrelated `@Query` update.
        var placeholderID: UUID {
            switch self {
            case .workout: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            case .protein: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            case .focus: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            }
        }

        var title: String {
            switch self {
            case .workout: Copy.today.ringTitleWorkout
            case .protein: Copy.today.ringTitleProtein
            case .focus: Copy.today.ringTitleFocus
            }
        }

        var icon: String {
            switch self {
            case .workout: "dumbbell.fill"
            case .protein: "fork.knife"
            case .focus: "timer"
            }
        }

        init?(type: GoalType) {
            switch type {
            case .workoutGym, .workoutHomeOutdoor: self = .workout
            case .protein: self = .protein
            case .focusSession: self = .focus
            default: return nil
            }
        }
    }

    private static func ringPriority(of type: GoalType) -> Int {
        switch type {
        case .workoutGym, .workoutHomeOutdoor: 0
        case .protein: 1
        case .focusSession: 2
        case .water: 3
        default: 4
        }
    }

    /// Goals worth a ring, best first. While locked this is the lock's own required goals with the
    /// open ones ahead of the done ones; otherwise the user's active goals in spec order.
    private var orderedRingGoals: [Goal] {
        let pool = isLocked ? requiredGoals : activeGoals
        let byPriority = pool.sorted {
            (Self.ringPriority(of: $0.type), $0.createdAt) < (Self.ringPriority(of: $1.type), $1.createdAt)
        }
        guard isLocked else { return byPriority }
        return byPriority.filter { !isGoalDoneToday($0) } + byPriority.filter { isGoalDoneToday($0) }
    }

    private var overflowGoalCount: Int {
        max(0, orderedRingGoals.count - Self.maxRings)
    }

    private var ringItems: [RingClusterItem] {
        let shown = Array(orderedRingGoals.prefix(Self.maxRings))
        var items = shown.map(ringItem(for:))
        // Placeholders only while nothing is locked: a lock's rings should be exactly its goals.
        if !isLocked, items.count < Self.maxRings {
            let covered = Set(shown.compactMap { CanonicalSlot(type: $0.type) })
            for slot in CanonicalSlot.allCases where items.count < Self.maxRings && !covered.contains(slot) {
                items.append(placeholderItem(for: slot))
            }
        }
        return items
    }

    /// A numeric goal becomes "72/150g" (the cluster puts "72" in the ring over "/150g"); a binary
    /// one becomes "Done" / "Not yet" under its title with its glyph (or a check) in the ring.
    private func ringItem(for goal: Goal) -> RingClusterItem {
        let p = dayProgress(for: goal)
        let valueText: String
        if let target = p.target {
            valueText = Copy.today.progressValue(current: p.current ?? 0, target: target, unit: p.unit)
        } else {
            valueText = p.isComplete ? Copy.today.ringDone : Copy.today.ringNotYet
        }
        let icon = (p.target == nil && p.isComplete) ? "checkmark" : goalIconName(for: goal.type)
        return RingClusterItem(
            id: goal.id,
            title: CanonicalSlot(type: goal.type)?.title ?? goal.title,
            progress: p.fraction,
            color: Theme.Colors.Ring.color(for: goal.type),
            valueText: valueText,
            centerIcon: icon
        )
    }

    private func placeholderItem(for slot: CanonicalSlot) -> RingClusterItem {
        RingClusterItem(
            id: slot.placeholderID,
            title: slot.title,
            progress: 0,
            color: Theme.Colors.muted,
            valueText: Copy.today.ringNotSet,
            centerIcon: slot.icon,
            isPlaceholder: true
        )
    }

    @ViewBuilder
    private var ringsSection: some View {
        let items = ringItems
        if !items.isEmpty {
            VStack(spacing: Theme.Spacing.xs) {
                // Equal columns, not a scroller: 3 x 88 pt rings need 312 pt and the narrowest
                // content column on a supported iPhone is 343 pt. `.medium` is the *maximum*; the
                // cluster shrinks rings further rather than overflow.
                RingCluster(items: items, ringSize: .medium, layout: .row)
                if overflowGoalCount > 0 {
                    moreGoalsButton
                }
            }
        }
    }

    private var moreGoalsButton: some View {
        Button {
            Analytics.shared.capture(event: "today_more_goals_tapped")
            showLockDetail = true
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.today.moreGoalsLink(count: overflowGoalCount))
                    .font(Theme.Typography.captionEmphasized)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.xsmall))
            }
            .foregroundStyle(Theme.Colors.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Ghost Mode (one quiet line, not a card — it is the third most important thing here)

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
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Rectangle()
                .fill(Theme.Colors.hairline)
                .frame(height: Theme.Metrics.edgeWidth)
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "flag.checkered")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(tint)
                    .frame(width: Theme.Spacing.lg)
                Text(c.headline)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
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
        }
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

    // MARK: - Bottom bar (contextual — spec §16 P1: "a single primary button")

    private var hasPrimaryControl: Bool {
        switch primaryAction {
        case .setupIncomplete: onFinishSetup != nil
        case .waitingToUnlock: false
        default: true
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if hasPrimaryControl || actionError != nil {
            StickyActionBar {
                VStack(spacing: Theme.Spacing.xs) {
                    if let actionError {
                        Text(actionError)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.danger)
                            .multilineTextAlignment(.center)
                    }
                    if hasPrimaryControl {
                        primaryControl
                    }
                }
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: primaryAction)
            }
        }
    }

    /// The one actionable next step Today can offer given current state. Ordered by the tightest
    /// verification loop this screen can directly drive (focus timer, then gym dwell); goals this
    /// screen has no direct action for (e.g. protein/water logging — Fuel screen, not owned here)
    /// fall through to `openFuel`, which needs `onOpenFuel` to be a real button.
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

    /// Actionable states are `PrimaryButton`s; states that are really *status* are a status row.
    /// `.waitingToUnlock` renders nothing here — the hero already says so — and `.setupIncomplete`
    /// is a button only once the shell has injected `onFinishSetup`.
    @ViewBuilder
    private var primaryControl: some View {
        switch primaryAction {
        case .setupIncomplete:
            if let onFinishSetup {
                PrimaryButton(title: Copy.today.finishSetupTitle, systemImage: "arrow.right", action: onFinishSetup)
            }
        case .waitingToUnlock:
            EmptyView()
        case .beginLock:
            PrimaryButton(
                title: Copy.today.beginLockStandardTitle,
                systemImage: "lock.fill",
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .startFocus(_, let minutes):
            PrimaryButton(
                title: Copy.today.startFocusTitle(minutes: minutes),
                systemImage: "timer",
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .focusRunning:
            TodayStatusRow(icon: "timer", title: Copy.today.focusRunningTitle, isLive: true)
        case .verifyAtGym:
            PrimaryButton(
                title: Copy.today.goToGymTitle,
                systemImage: "figure.strengthtraining.traditional",
                isEnabled: !isPerformingPrimaryAction,
                action: performPrimaryAction
            )
        case .verifyingAtGym:
            TodayStatusRow(
                icon: "location.fill",
                title: Copy.today.verifyingAtGymTitle(minutes: gymDwellMinutes),
                isLive: true
            )
        case .openFuel:
            if let onOpenFuel {
                PrimaryButton(title: Copy.today.openFuelTitle, systemImage: "fork.knife", action: onOpenFuel)
            } else {
                TodayStatusRow(icon: "fork.knife", title: Copy.today.openFuelTitle, isLive: false)
            }
        }
    }

    private func performPrimaryAction() {
        actionError = nil
        switch primaryAction {
        case .beginLock(let lockSetID, let requiredGoalIDs):
            Analytics.shared.capture(
                event: "today_begin_lock_tapped",
                properties: ["required_goal_count": requiredGoalIDs.count]
            )
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
            Analytics.shared.capture(
                event: "today_start_focus_tapped",
                properties: ["planned_minutes": minutes]
            )
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
            Analytics.shared.capture(event: "today_verify_at_gym_tapped")
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

    // MARK: - Celebration

    /// `UnlockCelebrationView.goalName` for the just-ended session (spec §16 P3): the single
    /// required goal's own `Goal.title` when the lock only required one, otherwise a generic
    /// fallback — this screen has no single "the goal that verified" when a lock required several
    /// (e.g. workout + protein + focus all feeding the same unlock), and guessing which one to
    /// name would misrepresent what actually happened.
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

    /// The lock set the running session is shielding (falls back to the default when the session
    /// was ad hoc or its set was deleted). Only its `name` is ever shown — FamilyControls tokens
    /// never leave the device layer.
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

/// A goal's progress for today, shared by Today and Lock. A goal with no numeric target (e.g. a
/// dwell-based workout with no `targetValue`/`plannedValue`) is binary: done once a `.complete`,
/// `.verify`, or `.planB` (spec §8 Plan B days still count as done) event lands today.
struct GoalDayProgress {
    /// `0...1`.
    let fraction: Double
    /// Logged amount so far (numeric goals only). Never shown below the target once the goal is
    /// complete, so a ring can't read "0 of 35 min" while full.
    let current: Int?
    /// Target amount (numeric goals only).
    let target: Int?
    let unit: String

    var isComplete: Bool { fraction >= 1 }
    var hasStarted: Bool { fraction > 0 }

    init(goal: Goal, todaysEvents events: [GoalEvent], plannedValue: Double?) {
        let hasCompletion = events.contains { [.complete, .verify, .planB].contains($0.kind) }

        guard let targetValue = plannedValue ?? goal.targetValue, targetValue > 0 else {
            fraction = hasCompletion ? 1 : 0
            current = nil
            target = nil
            unit = ""
            return
        }

        let logged = events.compactMap(\.value).reduce(0, +)
        let targetInt = Int(targetValue.rounded())
        let loggedInt = Int(logged.rounded())
        fraction = hasCompletion ? 1 : min(1, logged / targetValue)
        current = hasCompletion ? max(loggedInt, targetInt) : loggedInt
        target = targetInt
        unit = goal.unit ?? ""
    }
}

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

#Preview {
    TodayView()
        .modelContainer(for: [
            User.self, Goal.self, DailyPlan.self, GoalEvent.self,
            LockSet.self, LockSession.self, Streak.self, TimeBank.self, Gym.self
        ], inMemory: true)
}
