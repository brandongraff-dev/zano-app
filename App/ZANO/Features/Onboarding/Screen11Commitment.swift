// Screen11Commitment.swift
// App / Features / Onboarding
//
// docs/spec.md §7.11 "Commitment": '"Hold to commit" 2-second press with haptics. Records
// committed_at.' and §16 P4 ("a hold-to-commit button at the bottom with a progress outline").
//
// `committed_at` has no column in docs/spec.md §13's `users` table. `OnboardingFlowState.swift`
// (read, never edited) already models it as `private(set) var committedAt: Date?` set via
// `recordCommitment(at:)` — this screen calls that directly and additionally logs a durable
// `Analytics` event (docs/spec.md §23 "instrument from day one"), since a moment-in-time like this
// has no first-class SwiftData column to live in.
//
// This is also the first point in the flow that creates a real, persisted local `User` row (via
// `onboardingResolveOrCreateUser`, `OnboardingContainerView.swift`) — "committing" is the moment
// onboarding's answers stop being scratch state and become the user's actual account (docs/spec.md
// §8 rule 11, "Endowed progress"). Unchanged by the design pass.
//
// Design pass (composition-audit offender 4, better-ui BRK-02/RAD-04/MOT-08, typography-color C1):
// the one ritual moment in the app was a 22pt title floating in a black void above a 46pt bar whose
// label went unreadable (light text on the sweeping accent fill, 1.1:1) mid-hold. Now the ring IS
// the button — a 208pt ring that fills clockwise under the finger over the 2-second hold, with the
// same escalating haptic ticks `PrimaryButton.holdToCommit` uses (`Theme.Motion.holdToCommitDuration`)
// and no label ever sitting on the fill (the label lives in the ring's center, over the empty part).
// On completion the ring closes, the lock glyph becomes a check with a static glow and a success
// haptic, and the screen advances after a beat instead of vanishing mid-gesture. Release early and
// the ring springs back with no effect.
//
// Accessibility: a sustained hold has no VoiceOver equivalent, so — exactly as `PrimaryButton`
// does — VoiceOver's double-tap activates the commit directly (a deliberate double-tap is not an
// accidental touch). Reduce Motion: no scale, no springs; the fill still tracks the hold (it is
// information), and the advance beat is shortened.
//
// Premium pass (2026-09-24, "light is earned"): committing is a decision, not an earned state, so the
// ring, its glow and the glyph are white (`Theme.Colors.interactive`), matching the white hold
// sweep of `PrimaryButton.holdToCommit`; the backdrop is the shared neutral ambient. The green
// arrives later, at the first real unlock.
//
// The hold logic mirrors `PrimaryButton.holdToCommit` (`Core/UI/Components/PrimaryButton.swift`)
// because that component's bar shape can't be a ring; the timing constant is shared.

import SwiftUI
import SwiftData
import Core

@MainActor
struct Screen11Commitment: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var saveErrorMessage: String?
    @State private var holdProgress: Double = 0
    @State private var isHolding = false
    @State private var isCommitted = false
    @State private var holdTask: Task<Void, Never>?
    /// Bumped on every tenth of the hold so the haptic builds ("charging up").
    @State private var tickCount = 0
    @State private var commitTick = 0

    private static let ringDiameter: CGFloat = 208
    private static let ringLineWidth: CGFloat = 16
    /// The lock/check glyph in the ring's centre: a hero moment, one size above the icon scale.
    private static let glyphSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.sm)

            VStack(spacing: Theme.Spacing.sm) {
                OnboardingKit.Eyebrow(text: Copy.onboarding.commitEyebrow)
                OnboardingKit.DisplayTitle(text: Copy.onboarding.commitHeadline)
                Text(Copy.onboarding.commitSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .accessibilityElement(children: .combine)

            recapChip

            Spacer(minLength: Theme.Spacing.sm)

            holdRing

            Spacer(minLength: Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.Spacing.md)
        .background {
            OnboardingKit.Glow(
                tint: Theme.Colors.interactive,
                opacity: isCommitted ? 0.10 : 0.04,
                anchor: .center
            )
        }
        .alert(
            "",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in if !isPresented { saveErrorMessage = nil } }
            )
        ) {
            Button(Copy.common.ok, role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onDisappear { holdTask?.cancel() }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "commitment", "screen_number": 11]
            )
        }
    }

    // MARK: - Recap

    private var recapChip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "lock.fill")
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(Theme.Colors.muted)
            Text(recapLine)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
    }

    private var recapLine: String {
        let selection = flowState.selectedApps
        let appCount = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
        let goalCount = flowState.mainGoal == .allOfIt ? 3 : 1
        return Copy.onboarding.commitRecapLine(goalCount: goalCount, appCount: appCount)
    }

    // MARK: - The hold ring

    private var holdRing: some View {
        ZStack {
            // The empty ring is the shared `track` (white at 16%), so it reads as "the ring you are
            // about to close" and not as a grey arc that vanishes on near-black.
            Circle()
                .stroke(Theme.Colors.track, lineWidth: Self.ringLineWidth)

            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    Theme.Colors.interactive,
                    style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // A static glow on the active arc, stronger once committed. A function of progress
                // only — never an animated radius.
                .shadow(
                    color: Theme.Colors.interactive.opacity(isCommitted ? 0.35 : (holdProgress > 0 ? 0.18 : 0)),
                    radius: Self.ringLineWidth * 0.7
                )

            ringCenter
        }
        .padding(Self.ringLineWidth / 2)
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        .scaleEffect(isHolding && !reduceMotion ? 1.03 : 1)
        // A wider static glow once committed.
        .shadow(color: Theme.Colors.interactive.opacity(isCommitted ? 0.18 : 0), radius: 24)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in endHold() }
        )
        .animation(reduceMotion ? nil : Theme.Motion.springGesture, value: isHolding)
        .animation(reduceMotion ? nil : Theme.Motion.springCelebration, value: isCommitted)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: tickCount)
        .sensoryFeedback(.success, trigger: commitTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.onboarding.commitHoldButtonLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            complete()
        }
    }

    private var ringCenter: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isCommitted ? "checkmark" : "lock.fill")
                .font(.system(size: Self.glyphSize, weight: .semibold))
                .foregroundStyle(Theme.Colors.interactive)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))

            if !isCommitted {
                Text(isHolding ? Copy.onboarding.commitHoldHint : Copy.onboarding.commitHoldButtonLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Hold gesture

    /// Starts (or no-ops if already running) the hold timer: advances `holdProgress` in fixed ticks
    /// so the ring fills smoothly, and bumps `tickCount` on each decile crossed so the press builds
    /// an escalating haptic — the same shape as `PrimaryButton.holdToCommit`.
    private func beginHold() {
        guard !isCommitted, !isHolding else { return }
        isHolding = true

        // Resume from wherever a previous release's spring-back left `holdProgress` rather than
        // snapping to 0, so grabbing the ring mid-retreat doesn't teleport the fill.
        let totalMs = max(1, Int(Theme.Motion.holdToCommitDuration * 1000))
        let tickMs = 50
        let startingMs = Int(holdProgress * Double(totalMs))

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            var elapsedMs = startingMs
            var lastDecile = Int(holdProgress * 10)
            while elapsedMs < totalMs {
                try? await Task.sleep(for: .milliseconds(tickMs))
                if Task.isCancelled { return }
                elapsedMs += tickMs
                let progress = min(1, Double(elapsedMs) / Double(totalMs))
                // Per-tick interpolation is dropped under Reduce Motion (same rule as
                // `PrimaryButton.holdToCommit`): the fill still tracks the hold in 50ms steps.
                withAnimation(reduceMotion ? nil : .linear(duration: Double(tickMs) / 1000)) {
                    holdProgress = progress
                }
                let decile = Int(progress * 10)
                if decile != lastDecile {
                    lastDecile = decile
                    tickCount += 1
                }
            }
            guard !Task.isCancelled else { return }
            complete()
        }
    }

    /// Releasing before the ring closes cancels and springs the fill back to zero, with no effect.
    private func endHold() {
        guard isHolding, !isCommitted else { return }
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
            holdProgress = 0
        }
    }

    // MARK: - Commit

    /// Fires once the hold completes (or VoiceOver activates the ring). Persists the commitment
    /// (see file header), shows the closed ring, then advances after a beat. This never fails the
    /// *flow* even if the local save throws (shown as a dismissible alert instead): a user who has
    /// just deliberately held a ring for two seconds to commit should not be stuck on this screen
    /// over a SwiftData write error.
    private func complete() {
        guard !isCommitted else { return }
        isCommitted = true
        isHolding = false
        // Closes the ring: the last hold tick, so it follows the same Reduce Motion rule as the ticks
        // in `beginHold()`.
        withAnimation(reduceMotion ? nil : .linear(duration: 0.05)) {
            holdProgress = 1
        }
        commitTick += 1

        persistCommitment()

        Task { @MainActor in
            // Let the closed ring and the check land before the screen changes.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 550))
            flowState.advance()
        }
    }

    private func persistCommitment() {
        flowState.recordCommitment()
        Analytics.shared.capture(
            event: "onboarding_committed",
            properties: ["main_goal": flowState.mainGoal?.rawValue ?? "unspecified"]
        )
        do {
            _ = try onboardingResolveOrCreateUser(coachVoice: flowState.coachVoice, in: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen11Commitment(flowState: flowState)
    }
    .modelContainer(for: User.self, inMemory: true)
}
