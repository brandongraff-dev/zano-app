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
// Shared pieces (`LockVaultCard`, `GoalActionList`, `goalIconName`) live in `Features/Today`;
// `GoalDayProgress` lives in Core (`LockEngine/GoalDayProgress.swift`).
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
// `LockStatusCopy.swift` verbatim, so call sites are unchanged. The emergency control's spoken label
// is load-bearing for the UI tests ("Hold to unlock in an emergency").
//
// The Time Bank fill is Core's `TimeBankBar` (review pass): this file used to carry a private
// `BankBar` for a taller bar with a visible track, but `TimeBankBar` now has both (12 pt,
// `Theme.Colors.track`), plus the glow and the low-balance pulse, so the copy was removed.
//
// Analytics (gap-fill wave, spec §23): this screen logs its own screen view and flushes
// `SharedDefaults.shieldImpressionCount` — the on-device-only tally `ShieldConfigurationExtension`
// increments locally since shield extensions cannot do networking (spec §11, §27) — into a single
// aggregate `Analytics` event the next time this screen opens. See the "Analytics" MARK below.
//
// Wave 2F (2026-09-25): an Earn Mode lock gets a "Spend minutes" card under the hero (5/15/30/all,
// `TimeBankEngine.spendToUnlock`), which shows "Apps open until 3:45 PM" with a live countdown while
// a spend window runs. The emergency unlock bar below is unchanged and stays visible throughout.
// The idle start uses `LockPreferences.defaultMode`.
//
// Visual direction v2 (2026-10-02, docs/design/visual-direction-v2.md §5): one hero (the vault, on
// raised glass); the separate star above it is gone (Today owns the mascot); the blocking line is two
// glass facts; "Locked since" lives in the vault's chip, not the bottom rows; the borrow and spend
// explanations moved behind an (i). Emergency unlock is unchanged and pinned in every locked state.
//
// Lock trust pass (2026-10-02):
// - Under the hero, one honest line says what the lock is doing: "Blocking 12 apps · ends when your
//   goals are done" (or "· ends at 9:00 PM" for a timed schedule), and during a Time Bank window
//   "Apps open until 3:45 PM · locks again after". Counts only (`LockBlockingSummary`, Core).
// - A calm "Fix it" card (`LockHealthCard`, below) when `LockHealthCheck` finds Screen Time access
//   off while a lock runs or is scheduled, or the shield empty while a lock should be blocking.
//   Checked on appear, on every foreground and when the lock changes. Hidden in screenshot mode.
// - A full lock gets "Need a few minutes?": borrow 5/10/15 min from the Time Bank
//   (`TimeBankEngine.borrowToUnlock`); the lock comes back on its own when the window ends. An
//   Earn Mode lock keeps its existing "Spend minutes" card, which already does this. The emergency
//   unlock bar is unchanged and stays visible in every state.
//
// Pass 2 "playful" (2026-10-03, docs/design/visual-direction-v2.md "Pass 2: playful"): the vault's
// rings light up per goal around a little padlock character (`LockVaultCard`); the blocking facts
// lead with stickers; the borrow card's amounts are minute "coins" (chunky stickers) and its balance
// is a sticker; the idle star sways (`zanoMascot(.idle)`). Emergency unlock: unchanged, still pinned.

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
    @Environment(\.scenePhase) private var scenePhase
    /// The user's buddy (App Group defaults), drawn on the idle hero.
    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    // MARK: - Local state

    /// The idle state's "Start a lock now" is running `StartLockIntent`.
    @State private var isStartingLock = false
    @State private var actionError: String?
    @State private var timeBankRemainingMinutes: Int?

    /// Earn Mode spend control (Wave 2F).
    @State private var spendChoice: SpendChoice = .fifteen
    @State private var isSpending = false
    @State private var spendMessage: String?
    /// End of the running spend window for this lock, from `LockEngineSharedState.spendWindow`.
    @State private var spendWindowEndsAt: Date?

    /// Time Bank borrow on a full lock (trust pass).
    @State private var borrowMinutes = TimeBankBorrow.chipMinutes[0]
    @State private var isBorrowing = false
    @State private var borrowMessage: String?

    /// Screen Time self-check (trust pass).
    @State private var lockHealth: LockHealthStatus = .ok
    @State private var isFixingHealth = false
    @State private var healthMessage: String?

    /// `TimeBankBar`'s own suggested "low" line ("e.g. `remainingMinutes <= 5`").
    private static let lowBankThreshold = 5

    // Split into pieces: one long chain here exceeded the type checker's time limit in CI.
    var body: some View {
        lifecycle(chrome)
    }

    private var chrome: some View {
        ScrollView {
            contentStack
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
        .navigationTitle(Copy.lockStatus.screenTitle)
        .pageBuddy(.guarding)
        // Large, like every other tab (it used to fall back to a small inline title here).
        .navigationBarTitleDisplayMode(.large)
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // v2: one hero (the vault). The star above it is gone: Today owns the mascot.
            heroCard

            if let summary = blockingSummary {
                blockingFacts(summary)
            }

            if showsHealthCard {
                LockHealthCard(
                    status: lockHealth,
                    message: healthMessage,
                    isFixing: isFixingHealth,
                    onFix: fixLockHealth
                )
                .transition(.opacity)
            }

            if activeSession?.mode == .earn {
                spendSection
            }

            if !requiredGoals.isEmpty {
                goalsSection
            }

            if let session = activeSession, session.mode != .earn {
                borrowSection
            }

            contextSection
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }

    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
            .task(id: timeBankTaskKey) {
                timeBankRemainingMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)
            }
            .task {
                logScreenView()
                flushShieldImpressions()
            }
            .task(id: activeSession?.id) {
                refreshSpendWindow()
                refreshLockHealth()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshSpendWindow()
                refreshLockHealth()
            }
            .task(id: spendWindowEndsAt) {
                // Re-read once the window should have closed: it may have been extended, or ended.
                guard let end = spendWindowEndsAt else { return }
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 1))
                guard !Task.isCancelled else { return }
                refreshSpendWindow()
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

    /// Reads and resets ``SharedDefaults/shieldImpressionCount`` and reports the total as a single
    /// aggregate event (none when it's `0`). `ShieldAttemptTally` (Today/Suggestions) does both, so
    /// the flush from either screen counts once. The locked-out card's per-hour count lives in
    /// `LockedOutAttemptTracker` (Core) and needs no flush.
    private func flushShieldImpressions() {
        ShieldAttemptTally.absorbPending()
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
            // v2: the medallion says "locked", so the title is just the set's name; the goal names
            // caption is gone (the goal tiles below name them).
            LockVaultCard(
                status: .locked,
                eyebrow: lockSetTitle,
                detail: activeSession.map {
                    Copy.today.heroLockedSince($0.startedAt.formatted(date: .omitted, time: .shortened))
                },
                numeralLine: Copy.today.heroGoalsToUnlockLine(count: remaining),
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

    /// Nothing running: the user's buddy at rest (was the ZANO star, uncharged: the Lock tab can't read screen time, and
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
                // Buddies (2026-10-03): the user's buddy at rest, where the star used to stand.
                BuddySprite(buddy, pose: .idle, size: 96)
                    .zanoMascot(mood: .idle, size: 96, showsGlow: false)
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
    /// intent), in the user's default mode (`LockPreferences.defaultMode`) like Today's begin-lock.
    private func startLock() {
        actionError = nil
        isStartingLock = true
        Analytics.shared.capture(event: "lock_idle_start_tapped")
        Task {
            defer { isStartingLock = false }
            do {
                let mode = LockModeOption(rawValue: LockPreferences.defaultMode.rawValue) ?? .earn
                _ = try await StartLockIntent(mode: mode).perform()
                _ = await NotificationPermission.requestIfUndetermined()
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

    /// The vault's title: the lock set's name, or "Locked" when it has none.
    private var lockSetTitle: String {
        if let name = shownLockSet?.name, !name.isEmpty { return name }
        return Copy.today.heroLockedCapsuleFallback
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
                // Session 45: minutes a linked parent sent are shown as what they are, not as goals earned.
                let fromFamily = FamilyRewardLedger.minutes(on: .now)
                if fromFamily > 0 {
                    Text(Copy.family.fromFamilyToday(fromFamily))
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
                .font(Theme.Typography.title)
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
            // v2: "Locked since" moved into the vault's chip; only the trigger and the next lock
            // stay down here.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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

    // MARK: - Spend minutes (Earn Mode only — spec §5.2 "a shielded app spends minutes out of it")

    /// The amounts on offer. "All" is whatever is left.
    private enum SpendChoice: CaseIterable, Hashable {
        case five, fifteen, thirty, all

        func minutes(remaining: Int) -> Int {
            switch self {
            case .five: 5
            case .fifteen: 15
            case .thirty: 30
            case .all: remaining
            }
        }
    }

    /// The fixed amounts that fit the bank, then "All" (dropped when it equals a fixed amount).
    private func spendChoices(remaining: Int) -> [SpendChoice] {
        let fixed = [SpendChoice.five, .fifteen, .thirty].filter { $0.minutes(remaining: remaining) < remaining }
        return fixed + [.all]
    }

    /// The selected choice, or "All" when the selection no longer fits the bank.
    private func effectiveSpendChoice(remaining: Int) -> SpendChoice {
        spendChoices(remaining: remaining).contains(spendChoice) ? spendChoice : .all
    }

    /// The running window's end, only while it's in the future.
    private var activeSpendWindowEnd: Date? {
        guard let end = spendWindowEndsAt, end > .now else { return nil }
        return end
    }

    private var spendSection: some View {
        let remaining = displayedRemainingMinutes
        let choice = effectiveSpendChoice(remaining: remaining)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cardHeader(Copy.lockStatus.spendSectionTitle, info: Copy.lockStatus.spendSectionDetail, infoLabel: Copy.lockStatus.spendInfoLabel)

            if let end = activeSpendWindowEnd {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "lock.open.fill")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityHidden(true)
                    Text(Copy.lockStatus.spendUnlockedUntil(end.formatted(date: .omitted, time: .shortened)))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.xs)
                    // `min` keeps the range valid if the window closes between the check and here.
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.accent)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if remaining > 0 {
                    Text(Copy.lockStatus.spendExtendHint)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            } else if remaining == 0 {
                // The explanation lives behind the (i); only the empty state still says something.
                Text(Copy.lockStatus.borrowEmptyEarn)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if remaining > 0 {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(spendChoices(remaining: remaining), id: \.self) { option in
                        spendChip(option, remaining: remaining, isSelected: option == choice)
                    }
                }
                PrimaryButton(
                    title: Copy.lockStatus.spendButtonLabel(minutes: choice.minutes(remaining: remaining)),
                    systemImage: "hourglass",
                    style: .secondary,
                    isEnabled: !isSpending
                ) {
                    spend(minutes: choice.minutes(remaining: remaining))
                }
            }

            if let spendMessage {
                Text(spendMessage)
                    .font(Theme.Typography.caption)
                    // `warning`: red is reserved for the emergency control.
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: spendWindowEndsAt)
    }

    private func spendChip(_ option: SpendChoice, remaining: Int, isSelected: Bool) -> some View {
        let minutes = option.minutes(remaining: remaining)
        return Button {
            spendChoice = option
        } label: {
            Text(Copy.lockStatus.spendChoice(minutes: minutes, isAll: option == .all))
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.Colors.accentWash)
                    } else {
                        ZanoGlass(Capsule(style: .continuous))
                    }
                }
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(Theme.Colors.accent, lineWidth: Theme.Metrics.selectedStroke)
                    }
                }
        }
        .buttonStyle(.pressable(scale: 0.96))
        .accessibilityLabel(Copy.lockStatus.spendChoiceSpoken(minutes: minutes))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func spend(minutes: Int) {
        guard minutes > 0 else { return }
        spendMessage = nil
        isSpending = true
        Analytics.shared.capture(event: "lock_spend_minutes_tapped", properties: ["minutes": minutes])
        Task {
            defer { isSpending = false }
            do {
                switch try await TimeBankEngine.shared.spendToUnlock(minutes: minutes) {
                case .unlocked(let until):
                    spendWindowEndsAt = until
                    AccessibilityNotification.Announcement(
                        Copy.lockStatus.spendUnlockedUntil(until.formatted(date: .omitted, time: .shortened))
                    ).post()
                case .insufficientMinutes(let remaining):
                    spendMessage = Copy.lockStatus.spendNotEnough(remaining: remaining)
                case .noActiveEarnLock:
                    spendMessage = Copy.lockStatus.spendNoEarnLock
                }
            } catch {
                spendMessage = Copy.lockStatus.spendFailed
            }
            timeBankRemainingMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)
        }
    }

    /// Reads the shared spend window; only one for the running lock that hasn't ended counts.
    private func refreshSpendWindow() {
        guard let window = LockEngineSharedState.spendWindow,
              window.sessionID == activeSession?.id,
              window.endsAt > .now
        else {
            spendWindowEndsAt = nil
            return
        }
        spendWindowEndsAt = window.endsAt
    }

    // MARK: - Blocking line (trust pass)

    /// What the lock is blocking and when it ends, for the running lock. `nil` while nothing runs.
    /// The window end comes from view state so the facts flip back the moment the window closes.
    private var blockingSummary: LockBlockingSummary? {
        guard let session = activeSession else { return nil }
        var summary = LockBlockingSummary.current(
            sessionID: session.id,
            lockSetSelectionBlob: shownLockSet?.appTokensBlob,
            requiredGoalCount: session.requiredGoalIDs.count
        )
        summary.openUntil = activeSpendWindowEnd
        return summary
    }

    /// v2: the old one-line "Blocking 12 apps · ends when your goals are done" as two glass facts side
    /// by side ("Blocking 12 apps" / "Ends when your goals are done"), spoken as the original line.
    private func blockingFacts(_ summary: LockBlockingSummary) -> some View {
        let isOpen = summary.openUntil != nil
        return HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            blockingFact(
                icon: isOpen ? "lock.open.fill" : "lock.shield.fill",
                tint: isOpen ? Theme.Colors.accent : Theme.Colors.textSecondary,
                text: Copy.lockStatus.blockingHeadline(summary)
            )
            blockingFact(
                icon: isOpen ? "arrow.uturn.backward" : "flag.checkered",
                tint: Theme.Colors.textSecondary,
                text: Copy.lockStatus.blockingEnding(summary)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.lockStatus.blockingLine(summary))
    }

    private func blockingFact(icon: String, tint: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ZanoSticker(systemImage: icon, color: tint, size: .regular, tilt: -6)
            Text(text)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zanoCard(radius: Theme.Radius.medium)
    }

    // MARK: - Screen Time self-check (trust pass)

    private var showsHealthCard: Bool {
        ScreenshotMode.screen == nil && lockHealth.needsAttention
    }

    private func refreshLockHealth() {
        lockHealth = LockHealthCheck.status(isLockActive: activeSession != nil)
        if !lockHealth.needsAttention { healthMessage = nil }
    }

    private func fixLockHealth() {
        guard !isFixingHealth else { return }
        isFixingHealth = true
        healthMessage = nil
        Analytics.shared.capture(event: "lock_health_fix_tapped", properties: ["screen": "lock", "issue": String(describing: lockHealth)])
        Task {
            defer { isFixingHealth = false }
            let isActive = activeSession != nil
            let result: LockHealthStatus
            switch lockHealth {
            case .screenTimeAccessOff:
                result = await LockHealthCheck.requestScreenTimeAccess(isLockActive: isActive)
            case .shieldMissing:
                result = LockHealthCheck.repairShield(isLockActive: isActive)
            case .ok:
                result = .ok
            }
            lockHealth = result
            let message = result.needsAttention ? Copy.lockStatus.healthFixFailed : Copy.lockStatus.healthFixed
            healthMessage = result.needsAttention ? message : nil
            AccessibilityNotification.Announcement(message).post()
        }
    }

    // MARK: - Borrow from the Time Bank (full locks; Earn Mode uses the spend card above)

    private var borrowSection: some View {
        let remaining = displayedRemainingMinutes
        let choices = TimeBankBorrow.choices(remaining: remaining)
        let selected = choices.contains(borrowMinutes) ? borrowMinutes : (choices.first ?? 0)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cardHeader(Copy.lockStatus.borrowSectionTitle, info: Copy.lockStatus.borrowSectionDetail, infoLabel: Copy.lockStatus.borrowInfoLabel)

            if let end = activeSpendWindowEnd {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "lock.open.fill")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityHidden(true)
                    Text(Copy.lockStatus.spendUnlockedUntil(end.formatted(date: .omitted, time: .shortened)))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.accent)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if !choices.isEmpty {
                    Text(Copy.lockStatus.borrowExtendHint)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if choices.isEmpty {
                Text(Copy.lockStatus.borrowEmptyFull)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The "lock comes back on its own" explanation moved behind the (i).
                ZanoSticker(Copy.lockStatus.borrowBalance(minutes: remaining), systemImage: "hourglass", color: Theme.Colors.accent, size: .small, bounceTrigger: remaining)
                    .fixedSize()
            }

            if !choices.isEmpty {
                if choices.count > 1 {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(choices, id: \.self) { minutes in
                            borrowChip(minutes: minutes, isSelected: minutes == selected)
                        }
                    }
                }
                PrimaryButton(
                    title: Copy.lockStatus.borrowButtonLabel(minutes: selected),
                    systemImage: "hourglass",
                    style: .secondary,
                    isEnabled: !isBorrowing
                ) {
                    borrow(minutes: selected)
                }
            }

            if let borrowMessage {
                Text(borrowMessage)
                    .font(Theme.Typography.caption)
                    // `warning`: red is reserved for the emergency control.
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: spendWindowEndsAt)
    }

    /// A card's title with an (i) that holds its explanation (v2: no explanatory paragraphs on the
    /// main surface).
    private func cardHeader(_ title: String, info: String, infoLabel: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.xs)
            ZanoInfoButton(info, accessibilityLabel: infoLabel)
        }
    }

    /// Pass 2: each amount is a minute "coin": a chunky sticker with an hourglass, filled ZANO Blue
    /// when picked (ink label, 5.3:1), tinted glass otherwise. The coin glyph bounces when picked.
    private func borrowChip(minutes: Int, isSelected: Bool) -> some View {
        Button {
            borrowMinutes = minutes
        } label: {
            HStack(spacing: Theme.Spacing.xxs + 1) {
                Image(systemName: "hourglass.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(Theme.Typography.icon(.small, weight: .heavy))
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    .accessibilityHidden(true)
                Text(Copy.lockStatus.borrowChip(minutes: minutes))
                    .font(Theme.Typography.label.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.Colors.onFill : Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .background { coinFace(isSelected: isSelected) }
        }
        .buttonStyle(.pressable(scale: 0.92))
        .accessibilityLabel(Copy.lockStatus.borrowChipSpoken(minutes: minutes))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: isSelected)
    }

    private func coinFace(isSelected: Bool) -> some View {
        let shape = Capsule(style: .continuous)
        return ZStack {
            if isSelected {
                shape.fill(Theme.Colors.accent)
            } else {
                ZanoGlass(shape)
            }
            // Pass 3 (restraint): a flat coin, no sheen, no glow.
        }
    }

    private func borrow(minutes: Int) {
        guard minutes > 0, !isBorrowing else { return }
        borrowMessage = nil
        isBorrowing = true
        Analytics.shared.capture(event: "lock_borrow_tapped", properties: ["minutes": minutes])
        Task {
            defer { isBorrowing = false }
            do {
                switch try await TimeBankEngine.shared.borrowToUnlock(minutes: minutes) {
                case .unlocked(let until):
                    spendWindowEndsAt = until
                    AccessibilityNotification.Announcement(
                        Copy.lockStatus.spendUnlockedUntil(until.formatted(date: .omitted, time: .shortened))
                    ).post()
                case .insufficientMinutes(let remaining):
                    borrowMessage = remaining == 0
                        ? Copy.lockStatus.borrowEmptyFull
                        : Copy.lockStatus.borrowNotEnough(remaining: remaining)
                case .noActiveLock:
                    borrowMessage = Copy.lockStatus.borrowNoLock
                }
            } catch {
                borrowMessage = Copy.lockStatus.borrowFailed
            }
            timeBankRemainingMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)
        }
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
        let plan = todaysPlan(for: goal)
        return GoalDayProgress(
            goal: goal,
            todaysEvents: todaysEvents(for: goal),
            plannedValue: plan?.plannedValue,
            // A goal switched to Plan B today counts toward the smaller target (spec §5.5).
            planBValue: PlanB.acceptedTarget(for: plan, goalID: goal.id)
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

// MARK: - LockHealthCard (shared with Today)

/// The calm "Fix it" card for `LockHealthCheck`: a warning-tinted (never red) note that ZANO can't
/// block right now, with one button. Used by the Lock tab and Today's hero. Never touches the
/// emergency unlock.
struct LockHealthCard: View {
    let status: LockHealthStatus
    let message: String?
    let isFixing: Bool
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PrimaryButton(
                title: Copy.lockStatus.healthFixButton,
                systemImage: "wrench.and.screwdriver.fill",
                style: .secondary,
                isEnabled: !isFixing,
                action: onFix
            )
            if let message {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private var title: String {
        status == .shieldMissing ? Copy.lockStatus.healthShieldMissingTitle : Copy.lockStatus.healthAccessOffTitle
    }

    private var detail: String {
        status == .shieldMissing ? Copy.lockStatus.healthShieldMissingDetail : Copy.lockStatus.healthAccessOffDetail
    }
}
