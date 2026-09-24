// LockStatusView.swift
// App / ZANO / Features / Lock
//
// The Lock screen — docs/spec.md §15 ("Screens: Today, Lock, Fuel, Progress, Squad, Settings...").
// §16 doesn't give Lock its own P1-style mockup prompt (P1 covers Today only), so this screen's
// layout is derived from this task's brief ("current lock session detail: required goals, progress,
// time context") plus the Living Shield's own state model (spec §5.1) and the emergency-unlock
// guarantee that applies to every lock/shield surface (CLAUDE.md: "Any lock/shield feature must
// always keep an emergency-unlock path. Never trap the user.").
//
// Premium UI pass (2026-09-24, docs/design/premium-ui-plan.md):
//
// - The hero is the same vault Today uses (`LockVaultCard`): the open-goal count as one huge
//   condensed number, the locked apps dimmed behind a lock (on device), and a bar segment per
//   required goal in that goal's color. Earn Mode keeps its Time Bank body on the same `zanoHero`
//   surface. Nothing locked: the next scheduled lock time.
// - The page light follows the state (`zanoAmbient`): cool while locked, warming as goals finish.
// - Required goals are the same rows as Today (`GoalActionList`), read-only here, open goals first.
// - The three-line "time context" is three quiet caption rows at the bottom.
// - Emergency unlock is pinned to the bottom in a `StickyActionBar`, always visible while locked:
//   `EmergencyUnlockControl`, Core's `EmergencyUnlock` state machine behind a 60-second hold with a
//   visible countdown and the streak-penalty toggle (spec §8, §14; the shield's "60-second hold").
//   It's the one place on this screen that is red. VoiceOver double-tap starts/stops the countdown.
// - While locked the screen leads with the ZANO mark on a navy halo, charged by required goals done,
//   like Today's hero. A running lock is navy/grey, never `danger`.
// - Goal rows here are read-only; a "Go to Today" link under them says where to act.
// - Large navigation title, like every other tab.
//
// Shared pieces (`LockVaultCard`, `GoalActionList`, `GoalDayProgress`, `goalIconName`) live in
// `Features/Today`.
//
// No `NavigationStack` of its own: this view is pushed from `TodayView`'s hero card via
// `navigationDestination`, and is also a tab root that `ContentView` wraps in its own
// `NavigationStack` — either host already supplies navigation chrome, so nesting a second one here
// would be wrong in the pushed case. `.navigationTitle`/`.navigationBarTitleDisplayMode` below work
// in both hosts.
//
// Every animation here is gated on `@Environment(\.accessibilityReduceMotion)`; the wash and glow
// are dropped under Reduce Transparency. Engine calls (`LockEngineManager`, `TimeBankEngine`)
// follow this task's SYSTEM CONTRACTS shape exactly; nothing here has been compiled or rendered (no
// Mac/Swift toolchain).
//
// Copy note: user-facing strings go through `Copy.lockStatus.*` (`Core/Sources/Core/Copy/
// LockStatusCopy.swift`). Strings this pass added (`hero*`, `goal*`, `timeBankExpiryNote`) briefly
// lived in an `extension Copy.lockStatus` at the bottom of this file; the review pass moved them into
// `LockStatusCopy.swift` verbatim, so call sites are unchanged. The screen calls `timeBankExpiryNote`,
// not `timeBankFootnote` (same words now). The emergency button's text is load-bearing for the UI
// tests ("Hold to unlock in an emergency").
//
// The Time Bank fill is Core's `TimeBankBar` (review pass): this file used to carry a private
// `BankBar` for a taller bar with a visible track, but `TimeBankBar` now has both (12 pt,
// `Theme.Colors.track`), plus the glow and the low-balance pulse, so the copy was removed.
//
// Analytics (gap-fill wave, spec §23): this screen logs its own screen view and flushes
// `SharedDefaults.shieldImpressionCount` — the on-device-only tally `ShieldConfigurationExtension`
// increments locally since shield extensions cannot do networking (spec §11, §27) — into a single
// aggregate `Analytics` event the next time this screen opens. See the "Analytics" MARK below.

import Foundation
import SwiftUI
import SwiftData
import Core

struct LockStatusView: View {

    /// Takes the person to Today, where the goal rows are actionable: a tab switch from the Lock tab,
    /// a pop when this screen was pushed from Today. `nil` hides the link.
    private let onGoToToday: (() -> Void)?

    init(onGoToToday: (() -> Void)? = nil) {
        self.onGoToToday = onGoToToday
    }

    // MARK: - Data

    @Query private var users: [User]
    @Query private var goals: [Goal]
    @Query private var goalEvents: [GoalEvent]
    @Query private var dailyPlans: [DailyPlan]
    @Query private var lockSessions: [LockSession]
    @Query private var timeBanks: [TimeBank]
    @Query private var lockSets: [LockSet]

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Local state

    /// The idle state's "Start a lock now" is running `StartLockIntent`.
    @State private var isStartingLock = false
    @State private var actionError: String?
    @State private var timeBankRemainingMinutes: Int?

    /// `TimeBankBar`'s own suggested "low" line ("e.g. `remainingMinutes <= 5`").
    private static let lowBankThreshold = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if activeSession != nil {
                    lockedMark
                }
                heroCard

                if !requiredGoals.isEmpty {
                    goalsSection
                }

                contextSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The canvas, with a faint accent wash from the top edge while the reward is in hand
        // (spendable minutes, or every goal done). Static, and dropped under Reduce Transparency.
        .zanoAmbient(reduceTransparency ? .neutral : ambientState)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            emergencyBar
        }
        // A lock starting is felt, not just seen.
        .sensoryFeedback(.impact(weight: .medium), trigger: activeSession?.id) { oldValue, newValue in
            oldValue == nil && newValue != nil
        }
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.lockStatus.screenTitle)
        // Large, like every other tab (it used to fall back to a small inline title here).
        .navigationBarTitleDisplayMode(.large)
        .task(id: timeBankTaskKey) {
            timeBankRemainingMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)
        }
        .task {
            logScreenView()
            flushShieldImpressions()
        }
    }

    // MARK: - Analytics (spec §23: "Instrument from day one: every screen view, every intent,
    // every unlock kind, every shield impression").
    //
    // This screen is the natural place to flush ``SharedDefaults/shieldImpressionCount``: shield
    // extensions cannot do networking (spec §11, §27) so `ShieldConfigurationExtension` only
    // increments that on-device counter locally, and the main app reports the accumulated total
    // via `Analytics` the next time it opens the Lock screen — count-only, no per-impression
    // detail, per spec §23/§24.

    /// Fires once per appearance of this screen, in a plain (non-`id`-keyed) `.task` so it isn't
    /// re-triggered by `timeBankTaskKey` changing underneath it.
    private func logScreenView() {
        Analytics.shared.capture(
            event: "lock_screen_viewed",
            properties: [
                "is_locked": activeSession != nil,
                "mode": activeSession?.mode?.rawValue ?? "none",
                "goals_remaining": remainingRequiredGoalCount
            ]
        )
    }

    /// Reads and resets ``SharedDefaults/shieldImpressionCount`` and reports the total as a
    /// single aggregate event. No-op (and no event fired) when the count is already `0`, so
    /// opening this screen with no shield impressions to report doesn't spam an empty event.
    private func flushShieldImpressions() {
        let count = SharedDefaults.flushShieldImpressionCount()
        guard count > 0 else { return }
        Analytics.shared.capture(event: "shield_impression", properties: ["count": count])
    }

    // MARK: - Hero

    private enum HeroState: Equatable {
        /// Nothing is locked.
        case unlocked
        /// Locked in Earn Mode: the bank is the hero, open goals are secondary.
        case bank(minutes: Int, total: Int, goalsLeft: Int)
        /// Locked in Full mode with goals still open: the open-goal count is the hero.
        case goals(remaining: Int, total: Int)
        /// Locked in Full mode, every required goal done; the engine is about to release it.
        case allDone
    }

    private var heroState: HeroState {
        guard let session = activeSession else { return .unlocked }
        if session.mode == .earn {
            return .bank(
                minutes: displayedRemainingMinutes,
                total: todaysTimeBank?.earnedMin ?? 0,
                goalsLeft: remainingRequiredGoalCount
            )
        }
        let remaining = remainingRequiredGoalCount
        guard remaining > 0 else { return .allDone }
        return .goals(remaining: remaining, total: max(requiredGoals.count, remaining))
    }

    /// A nearly-spent bank (never an empty one that was never earned) borrows `warning`.
    private func isBankLow(minutes: Int, total: Int) -> Bool {
        total > 0 && minutes <= Self.lowBankThreshold
    }

    /// The card glows only when every goal is done; the reward stays rare.
    private var heroIsEarned: Bool {
        if case .allDone = heroState { return true }
        return false
    }

    /// Every state but Earn Mode's bank is the shared vault (`LockVaultCard`, also Today's hero), so
    /// the two screens show the lock the same way. The bank keeps its own body (a Time Bank bar is
    /// not a goal count) on the same hero surface.
    @ViewBuilder
    private var heroCard: some View {
        switch heroState {
        case .unlocked:
            idleHero
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroAccessibilityLabel)
        case .goals(let remaining, _):
            LockVaultCard(
                status: .locked,
                eyebrow: Copy.today.heroLockedEyebrow(lockSetName: shownLockSet?.name),
                detail: activeSession.map {
                    Copy.today.heroLockedSince($0.startedAt.formatted(date: .omitted, time: .shortened))
                },
                numeralLine: Copy.today.heroGoalsToUnlockLine(count: remaining),
                caption: Copy.today.heroRemainingGoals(orderedRequiredGoals.filter { !isGoalDoneToday($0) }.map(\.title)),
                segments: vaultSegments,
                appTokensBlob: shownLockSet?.appTokensBlob,
                changeKey: remaining
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
        case .allDone:
            LockVaultCard(
                status: .earned,
                eyebrow: Copy.lockStatus.heroEyebrowUnlocking,
                message: Copy.lockStatus.heroAllDone,
                segments: vaultSegments,
                appTokensBlob: shownLockSet?.appTokensBlob
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
        case .bank:
            bankHeroCard
        }
    }

    // MARK: - Idle (nothing locked)

    /// Nothing running: the ZANO star at rest (uncharged: the Lock tab can't read screen time, and
    /// "at rest" is the point), an "Unlocked" status pill, "No lock running", then either the next
    /// scheduled lock as a numeral or a line saying what to do. The start action sits in the bottom
    /// bar (`emergencyBar`), where the emergency hold lives while locked, so the bar never jumps
    /// position between the two states.
    private var idleHero: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.Colors.lockedAmbient.opacity(reduceTransparency ? 0 : 0.55), Theme.Colors.lockedAmbient.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                ZanoLivingMark(charge: 0, height: 84)
            }
            .frame(height: 190)

            ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.lockStatus.unlockedHeadline)

            Text(Copy.lockStatus.idleHeadline)
                .font(Theme.Typography.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .padding(.top, Theme.Spacing.xxs)

            if let next = SharedDefaults.nextScheduledLockAt {
                VStack(spacing: 2) {
                    Text(nextLockLabel(next))
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                    NumeralText(next.formatted(date: .omitted, time: .shortened), size: .large)
                        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: Int(next.timeIntervalSince1970))
                }
                .padding(.top, Theme.Spacing.xs)
            } else {
                Text(canStartLock ? Copy.lockStatus.idleReadyDetail : Copy.lockStatus.idleSetupDetail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// `StartLockIntent` resolves the default lock set and every active goal itself; it throws with
    /// no default set, so the button only shows when both exist.
    private var canStartLock: Bool {
        activeSession == nil && lockSets.contains(where: \.isDefault) && goals.contains(where: \.active)
    }

    /// Same App Intent Siri, Shortcuts and the Control use (CLAUDE.md: every user action is an
    /// intent), in Earn Mode like Today's begin-lock.
    private func startLock() {
        actionError = nil
        isStartingLock = true
        Analytics.shared.capture(event: "lock_idle_start_tapped")
        Task {
            defer { isStartingLock = false }
            do {
                _ = try await StartLockIntent(mode: .earn).perform()
            } catch {
                showError(Copy.lockStatus.lockStartFailed)
            }
        }
    }

    /// Sets the bottom bar's error line and announces it (a line appearing at the bottom is missed
    /// by anyone not looking there).
    private func showError(_ message: String) {
        actionError = message
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Locked mark (matches Today's hero)

    /// The ZANO mark on a navy halo, charged by how much of the lock's work is done.
    private var lockedMark: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Colors.lockedAmbient.opacity(reduceTransparency ? 0 : 0.6), Theme.Colors.lockedAmbient.opacity(0)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 130
                    )
                )
                .frame(maxWidth: 260, maxHeight: 260)
                .aspectRatio(1, contentMode: .fit)
            ZanoLivingMark(charge: lockedCharge, height: 120)
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: lockedCharge)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .accessibilityHidden(true)
    }

    /// Required goals done over required goals; full once everything is done.
    private var lockedCharge: Double {
        switch heroState {
        case .allDone: return 1
        case .goals(let remaining, let total):
            return Double(total - remaining) / Double(max(total, 1))
        case .bank(_, _, let goalsLeft):
            let total = max(requiredGoals.count, goalsLeft)
            return total == 0 ? 1 : Double(total - goalsLeft) / Double(total)
        case .unlocked:
            return 0
        }
    }

    private var vaultSegments: [VaultSegment] {
        orderedRequiredGoals.map {
            VaultSegment(id: $0.id, color: Theme.Colors.Ring.color(for: $0.type), isDone: isGoalDoneToday($0), progress: dayProgress(for: $0).fraction)
        }
    }

    /// The lock set being shielded (or the default one while nothing runs). Only its name and the
    /// on-device token blob are used.
    private var shownLockSet: LockSet? {
        if let id = activeSession?.lockSetID, let match = lockSets.first(where: { $0.id == id }) { return match }
        return lockSets.first(where: \.isDefault) ?? lockSets.first
    }

    /// Cold while locked, warming as required goals complete, accent once earned or while spendable
    /// minutes are banked.
    private var ambientState: ZanoAmbientState {
        switch heroState {
        case .allDone:
            return .earned
        case .bank(let minutes, let total, _):
            return minutes > 0 && !isBankLow(minutes: minutes, total: total) ? .earned : .locked
        case .goals(let remaining, let total):
            let done = total - remaining
            return done > 0 ? .progress(Double(done) / Double(max(total, 1))) : .locked
        case .unlocked:
            return .neutral
        }
    }

    private var bankHeroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            heroTopRow
            heroBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .zanoHero(
            tint: reduceTransparency ? nil : heroWashTint,
            active: heroIsEarned && !reduceTransparency
        )
        // One announcement for the card instead of a swipe through its parts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: heroState)
    }

    private var heroTopRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: heroBadgeSymbol, tint: heroBadgeTint, size: .small)
            Text(heroEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var heroBody: some View {
        switch heroState {
        case .unlocked:
            if let next = SharedDefaults.nextScheduledLockAt {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(nextLockLabel(next))
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                    heroNumeral(
                        next.formatted(date: .omitted, time: .shortened),
                        color: Theme.Colors.text,
                        glows: false,
                        changeKey: Int(next.timeIntervalSince1970)
                    )
                }
            } else {
                Text(Copy.lockStatus.noScheduleLine)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .bank(let minutes, let total, _):
            let isLow = isBankLow(minutes: minutes, total: total)
            // Earned minutes are the accent's job; a nearly-spent bank borrows `warning`.
            let numeralColor: Color = isLow ? Theme.Colors.warning : (minutes > 0 ? Theme.Colors.accent : Theme.Colors.text)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroNumeral(
                    Copy.lockStatus.heroBankLine(minutes: minutes),
                    color: numeralColor,
                    glows: minutes > 0 && !isLow,
                    changeKey: minutes
                )
                // Decorative here (the hero card speaks the balance); no `label`, so the bar is just
                // the fill, on the shared `track`, with the low-balance tint and one-shot pulse.
                TimeBankBar(remainingMinutes: minutes, totalMinutes: total, isLow: isLow)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(Copy.lockStatus.timeBankHeading)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.lockStatus.timeBankExpiryNote)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .goals(let remaining, let total):
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroNumeral(
                    Copy.lockStatus.heroGoalsLeftLine(count: remaining),
                    color: Theme.Colors.text,
                    glows: false,
                    changeKey: remaining
                )
                SegmentedProgress(total: total, done: total - remaining, filled: Theme.Colors.accent)
            }

        case .allDone:
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "checkmark", tint: Theme.Colors.accent, size: .medium)
                Text(Copy.lockStatus.heroAllDone)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The hero number with its unit on the same baseline (`NumeralText` styles the caller-composed
    /// line: "45" over "min available"; "10:30" over "PM"). It rolls the digits when the value
    /// changes (inert under Reduce Motion, where the ambient animation is nil). `glows` adds a
    /// static text glow for spendable earned minutes only, dropped under Reduce Transparency —
    /// never an animated blur radius.
    private func heroNumeral(_ line: String, color: Color, glows: Bool, changeKey: Int) -> some View {
        NumeralText(line, size: .hero, color: color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: Theme.Colors.accent.opacity(glows && !reduceTransparency ? 0.35 : 0), radius: 14)
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: changeKey)
    }

    /// "Next lock", with the weekday when it isn't today ("Next lock · Wednesday"). The weekday is
    /// locale-formatted date data, not copy.
    private func nextLockLabel(_ date: Date) -> String {
        guard !Calendar.current.isDateInToday(date) else { return Copy.lockStatus.heroNextLock }
        return Copy.lockStatus.heroNextLockOn(day: date.formatted(.dateTime.weekday(.wide)))
    }

    private var heroEyebrow: String {
        switch heroState {
        case .unlocked:
            return Copy.lockStatus.unlockedHeadline
        case .bank(_, _, let goalsLeft):
            switch goalsLeft {
            case 0: return Copy.lockStatus.heroEyebrowLocked
            case 1: return Copy.lockStatus.lockedHeadlineSingular
            default: return Copy.lockStatus.lockedHeadlinePlural(goalsLeft)
            }
        case .goals:
            return Copy.lockStatus.heroEyebrowLocked
        case .allDone:
            return Copy.lockStatus.heroEyebrowUnlocking
        }
    }

    private var heroBadgeSymbol: String {
        switch heroState {
        case .unlocked: "lock.open.fill"
        case .bank, .goals: "lock.fill"
        case .allDone: "checkmark"
        }
    }

    /// Quiet grey for a running lock (red is reserved for emergency), `accent` once it is
    /// earned/released.
    private var heroBadgeTint: Color {
        switch heroState {
        case .bank, .goals: Theme.Colors.textSecondary
        case .unlocked, .allDone: Theme.Colors.accent
        }
    }

    /// The hero surface's wash: navy while locked, accent once earned.
    private var heroWashTint: Color {
        switch heroState {
        case .bank, .goals: Theme.Colors.lockedAmbient
        case .unlocked, .allDone: Theme.Colors.accent
        }
    }

    private var heroAccessibilityLabel: String {
        var parts = [heroEyebrow]
        switch heroState {
        case .unlocked:
            parts.append(Copy.lockStatus.idleHeadline)
            if let next = SharedDefaults.nextScheduledLockAt {
                parts.append("\(Copy.lockStatus.nextLockPrefix) \(next.formatted(date: .omitted, time: .shortened))")
            } else {
                parts.append(canStartLock ? Copy.lockStatus.idleReadyDetail : Copy.lockStatus.idleSetupDetail)
            }
        case .bank(let minutes, _, let goalsLeft):
            parts.append(Copy.lockStatus.heroBankLine(minutes: minutes))
            if goalsLeft > 0 {
                parts.append(CoachVoiceTone.goalsRemainingClause(voice, remaining: goalsLeft))
            }
        case .goals(let remaining, _):
            parts.append(Copy.lockStatus.heroGoalsLeftLine(count: remaining))
            parts.append(CoachVoiceTone.goalsRemainingClause(voice, remaining: remaining))
        case .allDone:
            parts.append(Copy.lockStatus.heroAllDone)
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Required goals

    private var requiredGoals: [Goal] {
        guard let session = activeSession else { return [] }
        let requiredIDs = Set(session.requiredGoalIDs)
        return goals.filter { requiredIDs.contains($0.id) }
    }

    /// Open goals first, then done ones, each group in its stored order.
    private var orderedRequiredGoals: [Goal] {
        requiredGoals.filter { !isGoalDoneToday($0) } + requiredGoals.filter { isGoalDoneToday($0) }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.lockStatus.requiredGoalsHeading)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .padding(.leading, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)

            // Same rows as Today, read-only here: Lock is where you check what the lock is waiting
            // on; Today is where you act on it.
            GoalActionList(items: orderedRequiredGoals.map(statusItem(for:))) { _ in }

            if let onGoToToday, remainingRequiredGoalCount > 0 {
                Button {
                    Analytics.shared.capture(event: "lock_go_to_today_tapped")
                    onGoToToday()
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Text(Copy.lockStatus.goToTodayTitle)
                        Image(systemName: "chevron.forward")
                            .font(Theme.Typography.icon(.xsmall))
                            .accessibilityHidden(true)
                    }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .padding(.leading, Theme.Spacing.xxs)
            }
        }
    }

    private func statusItem(for goal: Goal) -> GoalActionItem {
        let p = dayProgress(for: goal)
        let primary: String
        if let target = p.target, !p.isComplete {
            primary = Copy.lockStatus.goalValue(current: p.current ?? 0, target: target, unit: p.unit)
        } else {
            primary = p.isComplete ? Copy.lockStatus.goalDone : Copy.lockStatus.goalNotYet
        }
        return GoalActionItem(
            id: goal.id,
            title: goal.title,
            icon: goalIconName(for: goal.type),
            color: Theme.Colors.Ring.color(for: goal.type),
            progress: p.fraction,
            primaryLine: primary,
            isRequired: true,
            trailing: p.isComplete ? .done : .none
        )
    }


    // MARK: - Time context (trivia, so: caption rows at the bottom, not a card)

    @ViewBuilder
    private var contextSection: some View {
        if let session = activeSession {
            let trigger = Copy.lockStatus.triggerLine(session.trigger)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                contextRow(icon: "clock.fill") {
                    Text(Copy.lockStatus.lockedSincePrefix)
                    Text(session.startedAt, style: .time)
                }
                if !trigger.isEmpty {
                    contextRow(icon: "hand.tap.fill") {
                        Text(trigger)
                    }
                }
                if let nextLockAt = SharedDefaults.nextScheduledLockAt {
                    contextRow(icon: "calendar") {
                        Text(Copy.lockStatus.nextLockPrefix)
                        Text(nextLockAt, style: .time)
                    }
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .padding(.horizontal, Theme.Spacing.xxs)
        }
    }

    private func contextRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(Theme.Typography.icon(.xsmall))
                .frame(width: Theme.Spacing.md)
            content()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Time Bank (Earn Mode only — spec §5.2)

    private var displayedRemainingMinutes: Int {
        timeBankRemainingMinutes ?? todaysTimeBank?.remainingMin ?? 0
    }

    private var timeBankTaskKey: String {
        "\(todaysTimeBank?.earnedMin ?? 0)-\(todaysTimeBank?.spentMin ?? 0)"
    }

    // MARK: - Emergency unlock (CLAUDE.md: every lock keeps a way out — no exceptions)

    /// Pinned, so "always available" is also "always visible". Also carries `actionError`.
    @ViewBuilder
    private var emergencyBar: some View {
        if activeSession != nil || actionError != nil || canStartLock {
            StickyActionBar(extendsToBottomEdge: false) {
                VStack(spacing: Theme.Spacing.xs) {
                    if let actionError {
                        Text(actionError)
                            .font(Theme.Typography.caption)
                            // `warning`: red is reserved for the emergency control itself.
                            .foregroundStyle(Theme.Colors.warning)
                            .multilineTextAlignment(.center)
                    }
                    if let session = activeSession {
                        EmergencyUnlockControl(sessionID: session.id)
                    } else if canStartLock {
                        PrimaryButton(
                            title: Copy.lockStatus.idleStartLockTitle,
                            systemImage: "lock.fill",
                            isEnabled: !isStartingLock,
                            action: startLock
                        )
                    }
                }
            }
        }
    }

    // MARK: - Derived state

    private var voice: CoachVoice { users.first?.coachVoice ?? .hype }
    private var activeSession: LockSession? { lockSessions.first(where: \.isActive) }

    private var remainingRequiredGoalCount: Int {
        requiredGoals.filter { !isGoalDoneToday($0) }.count
    }

    private var todaysTimeBank: TimeBank? {
        timeBanks.first { Calendar.current.isDateInToday($0.date) }
    }

    // MARK: - Per-goal progress (the computation itself is `GoalDayProgress`, shared with Today)

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

#Preview {
    NavigationStack {
        LockStatusView()
            .modelContainer(for: [
                User.self, Goal.self, DailyPlan.self, GoalEvent.self,
                LockSet.self, LockSession.self, TimeBank.self
            ], inMemory: true)
    }
}
