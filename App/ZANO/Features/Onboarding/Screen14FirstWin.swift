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
    @State private var phase: Phase = .intro
    @State private var focusSessionID: UUID?
    @State private var lockSessionID: UUID?
    @State private var secondsRemaining = Self.plannedMinutes * 60
    @State private var countdownTask: Task<Void, Never>?
    @State private var emergencyUnlock: EmergencyUnlock?
    @State private var confettiBurstID = 0
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
        ZStack {
            content
            if phase == .celebrating {
                OnboardingConfettiView(trigger: confettiBurstID)
            }
        }
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
        case .intro: introView
        case .running: runningView
        case .celebrating: celebratingView
        case .notVerified: notVerifiedView
        case .widgetPrompt: widgetPromptView
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            ZStack {
                Circle().fill(Theme.Colors.surface2).frame(width: 96, height: 96)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.firstWinEyebrow)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .textCase(.uppercase)
                Text(Copy.onboarding.firstWinHeadline)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.onboarding.firstWinSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: Theme.Spacing.xl)

            PrimaryButton(
                title: Copy.onboarding.firstWinStartButton,
                isEnabled: !isStarting
            ) {
                Task { await start() }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.lg)

            Text(Copy.onboarding.firstWinRunningHeadline)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            GoalRing(
                progress: progressFraction,
                color: Theme.Colors.Ring.focus,
                size: .large,
                center: .text(formattedCountdown)
            )

            Text(Copy.onboarding.firstWinRunningDetail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: Theme.Spacing.lg)

            if let emergencyUnlock {
                EmergencyHoldControl(emergencyUnlock: emergencyUnlock)
                    .padding(.bottom, Theme.Spacing.lg)
                    .onChange(of: emergencyUnlock.phase) { _, newPhase in
                        if newPhase == .unlocked {
                            Task { await handleEmergencyUnlock() }
                        }
                    }
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

    // MARK: - Celebrating

    private var celebratingView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            Image(systemName: "flame.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)
                .symbolEffect(.bounce, value: confettiBurstID)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.firstWinCelebrationTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.onboarding.firstWinCelebrationSubtitle(streak: 1))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            StreakPill(count: 1)

            Spacer(minLength: Theme.Spacing.xl)

            PrimaryButton(title: Copy.onboarding.firstWinDoneButton) {
                phase = .widgetPrompt
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    // MARK: - Not verified (emergency-unlock exit — calm, no shame, spec §8 rule 9)

    private var notVerifiedView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.firstWinNotVerifiedTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.onboarding.firstWinNotVerifiedSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: Theme.Spacing.xl)

            PrimaryButton(title: Copy.onboarding.firstWinDoneButton) {
                finishOnboarding()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    // MARK: - Widget prompt

    private var widgetPromptView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer(minLength: Theme.Spacing.lg)

                widgetGlyph

                Text(Copy.onboarding.firstWinWidgetPromptHeadline)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    widgetStep(number: 1, text: Copy.onboarding.firstWinWidgetPromptStep1)
                    widgetStep(number: 2, text: Copy.onboarding.firstWinWidgetPromptStep2)
                    widgetStep(number: 3, text: Copy.onboarding.firstWinWidgetPromptStep3)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer(minLength: Theme.Spacing.lg)

                PrimaryButton(title: Copy.onboarding.firstWinDoneButton) {
                    finishOnboarding()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    /// A grid-icon glyph standing in for a Home Screen widget, matching `ShieldPreview.swift`'s
    /// own precedent of building a badge from two known-safe SF Symbols in a `ZStack` rather than
    /// trusting a single compound symbol name (e.g. a `"widget.*"` glyph) this environment has no
    /// way to verify exists on the current SDK — see this task's `knownIssues`.
    private var widgetGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Colors.surface2)
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Theme.Colors.muted)
                )
                .symbolEffect(.pulse, options: .repeating)

            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.background)
                )
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 3))
        }
    }

    private func widgetStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("\(number)")
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 20, height: 20)
                .background(Theme.Colors.accent, in: Circle())
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: 0)
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
            confettiBurstID += 1
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

// MARK: - Emergency hold control

/// A 60-second press-and-hold bound to a Core `EmergencyUnlock` instance — CLAUDE.md: "Any
/// lock/shield feature must always keep an emergency-unlock path." `PrimaryButton`'s own
/// `.holdToCommit` style is hardcoded to `Theme.Motion.holdToCommitDuration` (2s, per that file's
/// header) and so isn't reusable for `EmergencyUnlock.holdDuration`'s fixed 60s, hence this small,
/// screen-local control instead of a shared Core component — emergency-unlock UI isn't one of
/// docs/spec.md §15's named core components.
@MainActor
private struct EmergencyHoldControl: View {
    let emergencyUnlock: EmergencyUnlock

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface2)
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.Colors.danger.opacity(0.85))
                        .frame(width: proxy.size.width * emergencyUnlock.progress)
                }
            }
            .frame(width: 160, height: 6)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in emergencyUnlock.beginHold() }
                .onEnded { _ in emergencyUnlock.cancelHold() }
        )
        .animation(Theme.Motion.springStandard, value: emergencyUnlock.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.onboarding.firstWinEmergencyLabel)
    }

    private var label: String {
        emergencyUnlock.phase == .holding
            ? "\(emergencyUnlock.secondsRemaining)s"
            : Copy.onboarding.firstWinEmergencyLabel
    }
}

// MARK: - Confetti

/// A short, tasteful confetti burst — docs/spec.md §15 Motion: "unlock celebration <= 1.2s". Not
/// one of §15's named Core components, so kept screen-local rather than added to `Core/UI`.
private struct OnboardingConfettiView: View {
    let trigger: Int

    @State private var isBursting = false

    private struct Particle: Identifiable {
        let id = UUID()
        let xOffset: CGFloat
        let delay: Double
        let rotation: Double
        let color: Color
    }

    private static let palette: [Color] = [
        Theme.Colors.accent,
        Theme.Colors.Ring.protein,
        Theme.Colors.Ring.focus,
        Theme.Colors.Ring.water,
        Theme.Colors.warning,
    ]

    private let particles: [Particle] = (0..<28).map { index in
        Particle(
            xOffset: CGFloat.random(in: -140...140),
            delay: Double.random(in: 0...0.15),
            rotation: Double.random(in: 0...360),
            color: palette[index % palette.count]
        )
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Capsule()
                    .fill(particle.color)
                    .frame(width: 6, height: 12)
                    .rotationEffect(.degrees(isBursting ? particle.rotation : 0))
                    .offset(x: particle.xOffset, y: isBursting ? 380 : -20)
                    .opacity(isBursting ? 0 : 1)
                    .animation(
                        .easeOut(duration: Theme.Motion.unlockCelebrationMaxDuration).delay(particle.delay),
                        value: isBursting
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { burst() }
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        isBursting = false
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            isBursting = true
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
