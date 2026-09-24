// Screen14FirstWin.swift
// App / Features / Onboarding
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). See
// `Screen9WakeUp.swift`'s header for the full `Copy.onboarding.*` / `OnboardingFlowState` assumed
// API this file depends on.
//
// docs/spec.md §7.14 "First win": '"Start your first lock now. 10-minute focus to unlock."
// Immediate loop completion. Streak = Day 1. Confetti. Prompt to add the Home Screen widget with
// an animated guide.' This is docs/spec.md §2's entire Core Loop (LOCK -> DO THE GOAL -> VERIFIED
// -> UNLOCK + STREAK) run for real, once, inside onboarding — the whole reason the first-win
// mechanic works as a retention device (spec §8 rule 11: "Endowed progress: streak starts at Day 1
// after onboarding's first win").
//
// Real system calls used (all SYSTEM CONTRACTS exact shapes from this task's brief, or already on
// disk elsewhere in this batch): `FocusSessionVerifier.shared.startSession`/`.endSession`
// (Core/Sources/Core/Verification/FocusSessionVerifier.swift), `LockSetManager.shared.
// createLockSet` (Core/Sources/Core/LockEngine/LockSetManager.swift, already implemented this
// batch), `LockEngineManager.shared.startLock`/`.endLock` (Core/Sources/Core/LockEngine/
// LockEngineManager.swift), `StreakEngine.shared.recordEarnedUnlock` (contract; Retention module,
// not yet on disk as of this file), and the Core `EmergencyUnlock` state machine (Core/Sources/
// Core/LockEngine/EmergencyUnlock.swift, already implemented this batch) for the mandatory
// emergency-unlock path — CLAUDE.md: "Any lock/shield feature must always keep an emergency-unlock
// path. Never trap the user." `appliesStreakPenalty: false` on that instance is a deliberate
// product choice: there is no streak yet to penalize on the very first lock of a brand-new
// account, so charging a "miss" against a streak that hasn't started would be wrong, not just
// unnecessary.
//
// Real device caveat (CLAUDE.md "current environment status"): `FamilyControls`/`ManagedSettings`
// authorization and shields do not work in Simulator/Preview. The real-shield path
// (`applyRealLockIfPossible`) is wrapped so any failure there (no authorization yet, no apps
// selected in Q2, Simulator) degrades to "the 10-minute focus timer and its verification still run
// for real, just with no ManagedSettings shield backing it" rather than blocking this screen — the
// focus-session + streak loop is the part of docs/spec.md §2 that must always work.
//
// Known gap (flagged in this task's `knownIssues`, not silently patched): this screen intentionally
// does not wire `scenePhase` to `FocusSessionVerifier.pauseSession`/`resumeSession` the way spec §3
// ("leaving the app pauses timer") describes, because doing so correctly also requires pausing this
// screen's own local countdown display in lockstep (`FocusActivityAttributes.ContentState.isPaused`'s
// own doc comment names this exact cross-module gap and defers it to "the screen that hosts the
// timer"). Half-wiring just the engine side without the matching UI-countdown pause would let this
// screen's own local timer hit zero and call `endSession` while the engine's real elapsed-active-time
// is still short (because it was paused), silently under-verifying a session the UI just showed as
// complete — worse than leaving both unpaused. Left as a real TODO for whichever session builds this
// properly across the whole app (Today screen's focus timer needs the exact same fix), not guessed
// at here.
//
// DESIGN PASS (composition-audit offender 4 / scorecard row 14, better-ui HIT-06/MOT-08/ICO-06,
// better-layout 3.9/6.3/7.6/7.7, typography-color C7, competitive-research §3.2/§3.4). Every
// presentational piece changed; the Core Loop code above (`start`, `finish`, `handleEmergencyUnlock`,
// the countdown, the lock/streak calls) is the same logic, minus the confetti trigger the old
// celebration used (the celebration now stages itself). What was wrong: a lone SF
// Symbol in a circle per phase; a *second*, weaker celebration language (a 56pt flame, a five-colour
// confetti palette that broke "ONE accent") next to `UnlockCelebrationView`'s seal; a 160x6pt
// emergency bar — a 60-second safety control at the smallest size in the app, with no VoiceOver
// action at all; a widget "guide" that was a pulsing grid glyph on a loop nobody could turn off;
// and a CTA that floated up the page on the widget phase.
//
//   intro        the ring the user is about to fill, empty, "10 min" inside it — the same object they
//                watch fill in the next phase — then a sentence-case eyebrow, display headline,
//                subtitle.
//   running      the same ring as a 200pt hero with the countdown in it. The exit is no longer a
//                bar: it is a 52pt capsule (`EmergencyHoldControl`) pinned at the bottom on the
//                shared action bar, danger-tinted, whose fill sweeps along the capsule as you hold
//                and whose label inverts under the fill (no light-on-accent, 1.11:1) — the same
//                grammar as `PrimaryButton.holdToCommit`, at 60 seconds. Not another big ring: the
//                alarm's two-equal-rings problem (composition-audit offender 8) is not repeated.
//                VoiceOver gets an action (double-tap starts the 60s countdown, again cancels).
//   celebrating  one language for the whole product: `UnlockCelebrationView`'s vocabulary — the ring
//                closes, the burst (accent-only `CelebrationBurst`) fires, "Earned." in accent — with
//                the streak as the hero numeral inside the ring (96pt, counting 0 to 1) and a week row
//                whose today is checked (the Duolingo streak-moment structure, competitive-research
//                §3.2). Timeline: 0.25s beat, ring fills 0.6s, then burst + tick + one haptic at
//                ~0.85s — inside `Theme.Motion.unlockCelebrationMaxDuration`, and "Done" is live from
//                the first frame.
//   not verified calm and neutral (spec §8 rule 9): a counterclockwise arrow ("try again"), not a
//                muted checkmark seal that told the wrong story (better-ui ICO-06).
//   widget       a mock of the widget itself (a ring and a streak, both TRUE at this moment: the
//                focus ring is full and the streak is 1) and the three steps lighting up in turn once
//                (the spec's "animated guide"), all lit under Reduce Motion — replacing a looping
//                pulse. Step numbers are neutral discs, not accent decoration.
//
// Premium pass (2026-09-24, "light is earned"): the intro is a moment, not a form — a 248pt ring in
// the focus color over its own focus-colored halo, "10" in the compressed hero numeral inside it,
// and a neutral ambient backdrop (no green before anything is earned). Green appears only once the
// session verifies (celebration, week dot, streak flame). The widget mock's "+" badge is white: it is
// an affordance, not a reward.
//
// Liveliness pass (2026-09-24): the payoff is the star. The celebration's hero is `ZanoLivingMark`,
// arriving nearly charged (where the header left it) and filling to FULL charge as the session
// verifies, with a ZANO Blue bloom that swells behind it and the accent burst firing as it lands. The
// streak numeral now sits under the star instead of inside a ring. The intro's backdrop is the
// scaffold's flow ambient (brightest at step 14) instead of a flat `zanoAmbient(.neutral)`.
//
// Every animation is gated on `accessibilityReduceMotion`. The header chrome is hidden on this
// screen (`OnboardingScaffold`), so every phase owns its whole screen and pins its CTA to the
// shared action bar.

import SwiftUI
import SwiftData
import Core
import os

/// `@MainActor` explicitly (not just relying on `View`'s own `body` inference): every private
/// helper below — `resolveFocusGoal`, `applyRealLockIfPossible`, `finish`, `handleEmergencyUnlock`
/// — calls into `@MainActor` Core engines (`LockEngineManager`, `LockSetManager`,
/// `FocusSessionVerifier`, `IntentSupport`), several of them synchronously (`IntentSupport.
/// activeGoal` has no `async` in its own signature), so they need this type itself statically
/// MainActor-isolated rather than depending on `View` conformance's isolation inference — this
/// session's own `write-swift` guidance and Swift 6 strict concurrency, verified against the
/// exact contract shapes on disk (`Core/Sources/Core/LockEngine`, `.../Verification`,
/// `.../Intents/IntentSupport.swift`) rather than guessed.
@MainActor
struct Screen14FirstWin: View {
    @Bindable var flowState: OnboardingFlowState
    var onFinished: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .intro
    @State private var focusSessionID: UUID?
    @State private var lockSessionID: UUID?
    @State private var secondsRemaining = Self.plannedMinutes * 60
    @State private var countdownTask: Task<Void, Never>?
    @State private var emergencyUnlock: EmergencyUnlock?
    @State private var isStarting = false
    @State private var errorMessage: String?

    /// Spec §7.14's own worked example ("10-minute focus to unlock") — deliberately not one of
    /// `FocusSessionPreset`'s 25/50/90 presets (`FocusSessionVerifier.swift`): a first win needs to
    /// be reachable in onboarding itself, and `startSession(plannedMinutes:)` accepts any positive
    /// value by design (see that type's own doc comment) precisely so a custom-duration entry point
    /// like this one isn't blocked on the preset list.
    private static let plannedMinutes = 10
    private static let logger = Logger(subsystem: "com.zano.app", category: "OnboardingFirstWin")

    private enum Phase: Equatable {
        case intro
        case running
        case celebrating
        case notVerified
        case widgetPrompt
    }

    var body: some View {
        content
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: phase)
            .alert(
                "",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in if !isPresented { errorMessage = nil } }
                )
            ) {
                Button(Copy.common.ok, role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onDisappear { countdownTask?.cancel() }
            .onAppear {
                Analytics.shared.capture(
                    event: "onboarding_screen_viewed",
                    properties: ["screen": "first_win", "screen_number": 14]
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            introView.transition(.opacity)
        case .running:
            runningView.transition(.opacity)
        case .celebrating:
            FirstWinCelebration(streak: 1) { phase = .widgetPrompt }
                .transition(.opacity)
        case .notVerified:
            notVerifiedView.transition(.opacity)
        case .widgetPrompt:
            FirstWinWidgetPrompt(streak: 1) { finishOnboarding() }
                .transition(.opacity)
        }
    }

    // MARK: - Intro

    /// The ring the user is about to fill — empty, with the length of the session inside it. The
    /// running phase is this same ring, filling, so the promise and the thing are one object.
    private var introView: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                FirstWinIntroRing(minutes: Self.plannedMinutes)

                VStack(spacing: Theme.Spacing.sm) {
                    OnboardingKit.Eyebrow(text: Copy.onboarding.firstWinEyebrow)
                    OnboardingKit.DisplayTitle(text: Copy.onboarding.firstWinHeadline)
                    Text(Copy.onboarding.firstWinSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .onboardingKitActionBar {
            PrimaryButton(
                title: Copy.onboarding.firstWinStartButton,
                isEnabled: !isStarting
            ) {
                Task { await start() }
            }
        }
    }

    // MARK: - Running

    private var runningView: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.lg) {
                Text(Copy.onboarding.firstWinRunningHeadline)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)

                GoalRing(
                    progress: progressFraction,
                    color: Theme.Colors.Ring.focus,
                    size: .custom(FirstWinIntroRing.diameter),
                    center: .text(formattedCountdown)
                )

                Text(Copy.onboarding.firstWinRunningDetail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background {
            OnboardingKit.Glow(tint: Theme.Colors.Ring.focus, opacity: 0.10)
        }
        .onboardingKitActionBar {
            if let emergencyUnlock {
                EmergencyHoldControl(emergencyUnlock: emergencyUnlock)
            }
        }
        .onChange(of: emergencyUnlock?.phase) { _, newPhase in
            if newPhase == .unlocked {
                Task { await handleEmergencyUnlock() }
            }
        }
    }

    private var progressFraction: Double {
        let total = Double(Self.plannedMinutes * 60)
        return 1 - (Double(secondsRemaining) / total)
    }

    private var formattedCountdown: String {
        String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    // MARK: - Not verified (emergency-unlock exit — calm, no shame, spec §8 rule 9)

    private var notVerifiedView: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                // A counterclockwise arrow — "go again" — in muted, not a checkmark seal: a check on
                // the not-verified screen told the wrong story (better-ui ICO-06).
                IconBadge(systemName: "arrow.counterclockwise", tint: Theme.Colors.muted, size: .large)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(Copy.onboarding.firstWinNotVerifiedTitle)
                        .zanoText(.titleLarge)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(Copy.onboarding.firstWinNotVerifiedSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.onboarding.firstWinDoneButton) {
                finishOnboarding()
            }
        }
    }

    // MARK: - Core Loop: start

    private func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        do {
            let user = try onboardingResolveOrCreateUser(coachVoice: flowState.coachVoice, in: modelContext)
            let goal = try resolveFocusGoal(for: user)

            lockSessionID = await applyRealLockIfPossible(user: user, requiredGoalID: goal.id)

            let sessionID = try await FocusSessionVerifier.shared.startSession(
                goalID: goal.id,
                plannedMinutes: Self.plannedMinutes
            )
            focusSessionID = sessionID
            if let lockSessionID {
                emergencyUnlock = EmergencyUnlock(sessionID: lockSessionID, appliesStreakPenalty: false)
            }
            secondsRemaining = Self.plannedMinutes * 60
            phase = .running
            startCountdown()
        } catch {
            // Never leave a half-applied shield behind if the focus session itself couldn't
            // start — CLAUDE.md: never trap the user, and a shield with no tracked session to
            // verify against would be exactly that.
            if let lockSessionID {
                try? await LockEngineManager.shared.endLock(sessionID: lockSessionID, unlockKind: .manual)
                self.lockSessionID = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Reuses `IntentSupport.activeGoal` (public, `Core/Sources/Core/Intents/IntentSupport.swift`)
    /// rather than re-implementing the same "find this user's active focus-session goal" lookup —
    /// CLAUDE.md: "never duplicate the same logic in two places." Creates one if none exists yet
    /// (the common case: this is most users' very first `Goal` row).
    private func resolveFocusGoal(for user: User) throws -> Goal {
        if let existing = try IntentSupport.activeGoal(ofType: .focusSession, for: user.id, in: modelContext) {
            return existing
        }
        let goal = Goal(
            type: .focusSession,
            title: Copy.onboarding.firstWinGoalTitle,
            targetValue: Double(Self.plannedMinutes),
            unit: "min",
            cadence: "daily",
            verificationTier: .a,
            user: user
        )
        modelContext.insert(goal)
        try modelContext.save()
        return goal
    }

    /// Best-effort: applies a real `ManagedSettings` shield and starts a real `LockSession` gated
    /// on the focus goal, so the first win is a genuine "locked until verified" cycle (docs/spec.md
    /// §2), not just a bare timer. Never throws outward — see the file header's "real device
    /// caveat." Returns `nil` when there's no default `LockSet` to shield with (Q2's
    /// `flowState.selectedApps` was empty AND `Screen10PlanReveal.swift`'s own best-effort
    /// `persistPlanIfNeeded()` never created one either) or when `LockSetManager`/
    /// `LockEngineManager` throw for any reason (no Family Controls authorization yet, Simulator).
    ///
    /// Prefers the user's already-existing default `LockSet` (created by `Screen10PlanReveal.swift`
    /// when it ran, per that file's header) over creating a second one here — CLAUDE.md "never
    /// duplicate the same logic in two places" extends to never duplicating the same *row* either.
    /// Falls back to creating one from `flowState.selectedApps` directly only if Plan Reveal's own
    /// best-effort persistence didn't run or failed (e.g. a future entry point that skips straight
    /// to this screen).
    private func applyRealLockIfPossible(user: User, requiredGoalID: UUID) async -> UUID? {
        do {
            let lockSetID: UUID
            if let existingDefault = try await LockSetManager.shared.defaultLockSet(for: user.id) {
                lockSetID = existingDefault.id
            } else {
                let selection = flowState.selectedApps
                let hasSelection = !selection.applicationTokens.isEmpty
                    || !selection.categoryTokens.isEmpty
                    || !selection.webDomainTokens.isEmpty
                guard hasSelection else { return nil }
                // `LockSetManager.createLockSet(name:selection:makeDefault:)` takes no `userID:`
                // parameter — it resolves the current device's one local `User` row internally
                // (see that file's own doc comment). Verified against the real, on-disk
                // `LockSetManager.swift` and corrected.
                lockSetID = try await LockSetManager.shared.createLockSet(
                    name: Copy.onboarding.lockSetName,
                    selection: selection,
                    makeDefault: true
                )
            }
            return try await LockEngineManager.shared.startLock(
                lockSetID: lockSetID,
                mode: .full,
                requiredGoalIDs: [requiredGoalID],
                trigger: .manual
            )
        } catch {
            Self.logger.notice("First-win real shield skipped: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while secondsRemaining > 0, phase == .running, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, phase == .running else { return }
                secondsRemaining = max(0, secondsRemaining - 1)
            }
            guard !Task.isCancelled, phase == .running, secondsRemaining == 0 else { return }
            await finish()
        }
    }

    // MARK: - Core Loop: end (natural completion)

    private func finish() async {
        guard let sessionID = focusSessionID else { return }
        focusSessionID = nil
        countdownTask?.cancel()

        let verified = (try? await FocusSessionVerifier.shared.endSession(sessionID: sessionID)) ?? false

        if let lockSessionID {
            let unlockKind: UnlockKind = verified ? .earned : .manual
            try? await LockEngineManager.shared.endLock(sessionID: lockSessionID, unlockKind: unlockKind)
            self.lockSessionID = nil
        }
        emergencyUnlock = nil

        if verified {
            await StreakEngine.shared.recordEarnedUnlock(on: .now)
            Analytics.shared.capture(event: "onboarding_first_win_verified")
            phase = .celebrating
        } else {
            Analytics.shared.capture(event: "onboarding_first_win_not_verified")
            phase = .notVerified
        }
    }

    // MARK: - Core Loop: end (emergency escape hatch)

    /// `EmergencyUnlock` already ended the real `LockSession` with `unlockKind: .emergency` by the
    /// time its `phase` reaches `.unlocked` (see that type's own `completeHold`) — this only needs
    /// to close out the focus-session half (a separate system, per this file's header) and move
    /// this screen to its calm, non-shaming exit state.
    private func handleEmergencyUnlock() async {
        countdownTask?.cancel()
        if let sessionID = focusSessionID {
            focusSessionID = nil
            _ = try? await FocusSessionVerifier.shared.endSession(sessionID: sessionID)
        }
        lockSessionID = nil
        emergencyUnlock = nil
        Analytics.shared.capture(event: "onboarding_first_win_emergency_unlock")
        phase = .notVerified
    }

    private func finishOnboarding() {
        Analytics.shared.capture(event: "onboarding_completed")
        onFinished()
    }
}

// MARK: - Intro ring

/// The first win's promise: the ring the user is about to fill, empty, in the focus color over a
/// static halo of the same color, with the session length as the hero numeral inside it. The
/// running phase is this ring filling. Decorative for VoiceOver (the headline and subtitle say it).
private struct FirstWinIntroRing: View {
    let minutes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Shared with the running phase's ring, so the promise and the timer are one object.
    static let diameter: CGFloat = 248
    /// The halo is wider than the ring; a `background` never affects layout.
    private static let haloDiameter: CGFloat = 420

    private var isShown: Bool { reduceMotion || appeared }

    var body: some View {
        GoalRing(
            progress: 0,
            color: Theme.Colors.Ring.focus,
            size: .custom(Self.diameter),
            center: .none
        )
        .overlay {
            VStack(spacing: 0) {
                OnboardingKit.HeroNumeral(text: "\(minutes)", color: Theme.Colors.text)
                Text(Copy.onboardingReveal.firstWinRingUnit)
                    .zanoText(.unit)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .background {
            // Static: only its opacity changes, once, as the ring arrives (never an animated blur).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Colors.Ring.focus.opacity(0.32), Theme.Colors.Ring.focus.opacity(0)],
                        center: .center,
                        startRadius: Self.diameter * 0.3,
                        endRadius: Self.haloDiameter / 2
                    )
                )
                .frame(width: Self.haloDiameter, height: Self.haloDiameter)
                .opacity(isShown ? 1 : 0)
        }
        .scaleEffect(isShown ? 1 : 0.94)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: appeared)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Emergency hold control

/// A 60-second press-and-hold bound to a Core `EmergencyUnlock` instance — CLAUDE.md: "Any
/// lock/shield feature must always keep an emergency-unlock path." `PrimaryButton`'s own
/// `.holdToCommit` style is hardcoded to `Theme.Motion.holdToCommitDuration` (2s, per that file's
/// header) and so isn't reusable for `EmergencyUnlock.holdDuration`'s fixed 60s, hence this small,
/// screen-local control instead of a shared Core component — emergency-unlock UI isn't one of
/// docs/spec.md §15's named core components.
///
/// It was a 160x6pt bar with a 13pt caption (a ~26pt-tall target, better-ui HIT-06). It is now a
/// 52pt capsule with the same grammar as `PrimaryButton.holdToCommit`: `surface2` track, a `danger`
/// fill that sweeps along it as `EmergencyUnlock.progress` advances, a `danger` outline at rest
/// (an exit that costs something does not wear the accent), and a label drawn twice — `text` on the
/// track and `onFill` masked to the fill's width — so it stays readable under the sweep (`text` on
/// a `danger` fill is 3.1:1; `onFill` on it is 5.8:1). Idle it names the gesture ("Press and hold
/// to end the lock"); holding it counts down the seconds.
///
/// Accessibility: a sustained 60s hold has no VoiceOver equivalent, so the default action starts
/// the same countdown (`beginHold()` needs no finger; the engine completes it on its own after 60s)
/// and, while it runs, cancels it. The seconds remaining are the element's value.
@MainActor
private struct EmergencyHoldControl: View {
    let emergencyUnlock: EmergencyUnlock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHolding: Bool {
        emergencyUnlock.phase == .holding
    }

    private var labelText: String {
        isHolding
            ? Copy.onboardingReveal.firstWinEmergencySeconds(emergencyUnlock.secondsRemaining)
            : Copy.onboardingReveal.firstWinEmergencyHint
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isHolding ? "lock.open.fill" : "lock.fill")
                .font(Theme.Typography.icon(.small))
            Text(labelText)
                .font(Theme.Typography.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
    }

    var body: some View {
        label
            .foregroundStyle(Theme.Colors.text)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    label
                        .foregroundStyle(Theme.Colors.onFill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: proxy.size.width * emergencyUnlock.progress)
                        }
                }
            }
            .background {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surface2)
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Theme.Colors.danger)
                            .frame(width: proxy.size.width * emergencyUnlock.progress)
                    }
                    // Clipping a rectangle to the capsule keeps the fill's trailing edge straight
                    // while it is narrow (the same fix `PrimaryButton`'s hold fill got).
                    .clipShape(Capsule())
                }
            }
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Colors.danger.opacity(isHolding ? 0 : 0.5), lineWidth: 1.5)
            )
            .compositingGroup()
            .scaleEffect(isHolding && !reduceMotion ? 0.98 : 1)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in emergencyUnlock.beginHold() }
                    .onEnded { _ in emergencyUnlock.cancelHold() }
            )
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: isHolding)
            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: emergencyUnlock.progress)
            // The same escalating "charging up" tick `PrimaryButton.holdToCommit` has, one per tenth
            // of the 60 seconds; never on the reset back to zero.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: Int(emergencyUnlock.progress * 10)) { oldValue, newValue in
                newValue > oldValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.onboarding.firstWinEmergencyLabel)
            .accessibilityHint(Copy.onboardingReveal.firstWinEmergencyHint)
            .accessibilityValue(isHolding ? Copy.onboardingReveal.firstWinEmergencySeconds(emergencyUnlock.secondsRemaining) : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isHolding {
                    emergencyUnlock.cancelHold()
                } else {
                    emergencyUnlock.beginHold()
                }
            }
    }
}

// MARK: - Celebration

/// The first win's celebration, in `UnlockCelebrationView`'s vocabulary so the product has one
/// celebration language, not two: a ring that closes, an accent-only burst, "Earned." in accent —
/// with the streak as the hero. See the file header for the timeline. Owns its own staging state
/// (the parent only says which streak to show and what "Done" does).
private struct FirstWinCelebration: View {
    let streak: Int
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The star arrives where the header left it (step 13 of 14) and fills to full on the win.
    @State private var starCharge: Double = 13.0 / 14.0
    @State private var shownStreak = 0
    @State private var showText = false
    @State private var showBurst = false
    @State private var weekDone = false
    @State private var hapticTick = 0

    /// Where the particles radiate from: a frame centred on the star, bigger than it.
    private static let burstFrame: CGFloat = 320
    private static let starHeight: CGFloat = 132
    /// `ZanoLivingMark` eases a charge change over 1.2s; the burst fires as the fill lands.
    private static let fillLandMilliseconds = 850

    /// Reduce Motion shows the final state from the first frame, with no flash of the unearned one.
    private var charge: Double { reduceMotion ? 1 : starCharge }
    private var streakValue: Int { reduceMotion ? streak : shownStreak }
    private var isTextShown: Bool { reduceMotion || showText }
    private var isWeekDone: Bool { reduceMotion || weekDone }

    var body: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.lg) {
                Text(Copy.onboarding.firstWinCelebrationTitle)
                    .font(Theme.Typography.numeralMedium())
                    .foregroundStyle(Theme.Colors.accent)
                    .opacity(isTextShown ? 1 : 0)
                    .accessibilityAddTraits(.isHeader)

                seal

                streakBadge

                Text(Copy.onboardingReveal.firstWinCelebrationBody)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .opacity(isTextShown ? 1 : 0)
                    .offset(y: isTextShown || reduceMotion ? 0 : Theme.Spacing.xs)

                FirstWinWeekRow(isDone: isWeekDone)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background {
            // Static radial glow; only its opacity changes, once, at the unlock beat. Never an
            // animated blur or radius.
            OnboardingKit.Glow(tint: Theme.Colors.accent, opacity: 0.18)
                .opacity(showBurst ? 1 : 0.3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: showBurst)
        }
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.onboarding.firstWinDoneButton, action: onDone)
        }
        .sensoryFeedback(.success, trigger: hapticTick)
        .task { await play() }
    }

    /// The star reaching full charge: the blue bloom swelling behind it, the burst from it.
    private var seal: some View {
        ZStack {
            OnboardingKit.StarBloom(diameter: Self.burstFrame * 1.2)
                .opacity(showBurst ? 1 : 0.35)
                .scaleEffect(showBurst || reduceMotion ? 1 : 0.8)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: showBurst)

            if showBurst {
                // Mounted at the unlock beat so the burst fires exactly once, from the moment the
                // star fills. Accent-only; it handles Reduce Motion itself (in-place cross-fade).
                CelebrationBurst(trigger: 0)
                    .frame(width: Self.burstFrame, height: Self.burstFrame)
            }

            ZanoLivingMark(charge: charge, height: Self.starHeight)
                .scaleEffect(showBurst && !reduceMotion ? 1.04 : 1)
                .animation(reduceMotion ? nil : Theme.Motion.springCelebration, value: showBurst)
                .accessibilityHidden(true)
        }
        .frame(height: Self.burstFrame * 0.62)
    }

    /// The streak: the hero numeral counting 0 to 1, its unit beside it.
    private var streakBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            OnboardingKit.HeroNumeral(text: "\(streakValue)", color: Theme.Colors.text, tier: .large)
                .fixedSize()
            Text(Copy.onboardingReveal.firstWinStreakUnit)
                .zanoText(.unit)
                .foregroundStyle(Theme.Colors.muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// 0.25s beat (the nearly-charged star is seen while the phase cross-fades in) -> the star fills to
    /// full (it eases the fill itself) -> as it lands (~1.1s) the burst fires, the bloom swells, the
    /// streak ticks 0 to 1, today's dot checks, and one success haptic lands. Inside
    /// `Theme.Motion.unlockCelebrationMaxDuration` (give or take the star's own ease tail), and
    /// nothing here gates the "Done" button.
    private func play() async {
        guard !reduceMotion else {
            showBurst = true
            hapticTick += 1
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        starCharge = 1
        withAnimation(Theme.Motion.springStandard) { showText = true }

        try? await Task.sleep(for: .milliseconds(Self.fillLandMilliseconds))
        guard !Task.isCancelled else { return }
        showBurst = true
        hapticTick += 1
        withAnimation(Theme.Motion.springCelebration) {
            shownStreak = streak
            weekDone = true
        }
    }
}

/// Seven day marks with today checked — the week row of the streak moment (competitive-research
/// §3.2: Duolingo shows the streak as a number *and* a week of dots, today checked). The weekday
/// initials come from the user's calendar, starting on their first weekday, so it needs no copy.
/// Decorative: the streak numeral and body line above carry the meaning, so it is hidden from
/// VoiceOver. Today's dot pops in once; under Reduce Motion it is simply checked.
private struct FirstWinWeekRow: View {
    let isDone: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Day: Identifiable {
        let id: Int
        let symbol: String
        let isToday: Bool
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        let firstIndex = calendar.firstWeekday - 1
        let todayIndex = calendar.component(.weekday, from: Date.now) - 1
        return (0..<7).map { offset in
            let index = (firstIndex + offset) % 7
            return Day(id: index, symbol: symbols[index], isToday: index == todayIndex)
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(days) { day in
                VStack(spacing: Theme.Spacing.xs) {
                    Text(day.symbol)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(day.isToday ? Theme.Colors.text : Theme.Colors.muted)
                    dot(for: day)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .accessibilityHidden(true)
    }

    private func dot(for day: Day) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.Colors.track, lineWidth: 2)
            if day.isToday {
                Circle()
                    .fill(Theme.Colors.accent)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(Theme.Typography.icon(.small))
                            .foregroundStyle(Theme.Colors.onAccent)
                    }
                    .scaleEffect(isDone ? 1 : 0.4)
                    .opacity(isDone ? 1 : 0)
            }
        }
        .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
        .animation(reduceMotion ? nil : Theme.Motion.springCelebration, value: isDone)
    }
}

// MARK: - Widget prompt

/// Spec §7.14's "prompt to add the Home Screen widget with an animated guide". A mock of the widget
/// itself — a ring and a streak, both true at this moment (the focus ring is full; the streak is 1)
/// — lands once, then the three steps light up in turn (one pass, not a loop) and rest all lit.
/// Under Reduce Motion everything is shown lit and in place. Step numbers are neutral discs: accent
/// is for the CTA, not decoration.
private struct FirstWinWidgetPrompt: View {
    let streak: Int
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false
    @State private var litSteps = 0

    private static let stepCount = 3
    /// A small Home Screen widget is roughly square at this size on current iPhones.
    private static let widgetSide: CGFloat = 148
    private static let widgetRingDiameter: CGFloat = 64

    private var isLanded: Bool { reduceMotion || hasLanded }
    private var visibleSteps: Int { reduceMotion ? Self.stepCount : litSteps }

    var body: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                widgetMock

                OnboardingKit.DisplayTitle(text: Copy.onboarding.firstWinWidgetPromptHeadline)
                    .padding(.horizontal, Theme.Spacing.lg)

                stepsCard
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.onboarding.firstWinDoneButton, action: onDone)
        }
        .task { await runGuide() }
    }

    /// The widget, and the "add" badge that says what the steps below do with it.
    private var widgetMock: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: Theme.Spacing.xs) {
                GoalRing(
                    progress: 1,
                    color: Theme.Colors.Ring.focus,
                    size: .custom(Self.widgetRingDiameter),
                    center: .icon(systemName: "timer")
                )
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "flame.fill")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("\(streak)")
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.text)
                }
            }
            .frame(width: Self.widgetSide, height: Self.widgetSide)
            .zanoCard(radius: Theme.Radius.large)

            Image(systemName: "plus")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                .background(Theme.Colors.interactive, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 3))
                .offset(x: Theme.Spacing.xxs, y: Theme.Spacing.xxs)
        }
        .scaleEffect(isLanded ? 1 : 0.9)
        .opacity(isLanded ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            step(number: 1, text: Copy.onboarding.firstWinWidgetPromptStep1)
            step(number: 2, text: Copy.onboarding.firstWinWidgetPromptStep2)
            step(number: 3, text: Copy.onboarding.firstWinWidgetPromptStep3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func step(number: Int, text: String) -> some View {
        let isLit = visibleSteps >= number
        return HStack(spacing: Theme.Spacing.sm) {
            Text("\(number)")
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(isLit ? Theme.Colors.onFill : Theme.Colors.muted)
                .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                .background(isLit ? Theme.Colors.text : Theme.Colors.surface2, in: Circle())
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(isLit ? Theme.Colors.text : Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isLit)
        .accessibilityElement(children: .combine)
    }

    /// The widget lands, then each step lights in turn, once.
    private func runGuide() async {
        guard !reduceMotion else { return }
        withAnimation(Theme.Motion.springCelebration) { hasLanded = true }
        try? await Task.sleep(for: .milliseconds(450))
        for step in 1...Self.stepCount {
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.springStandard) { litSteps = step }
            try? await Task.sleep(for: .milliseconds(450))
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen14FirstWin(flowState: flowState)
    }
    .modelContainer(for: [User.self, Goal.self, LockSet.self, LockSession.self], inMemory: true)
}
