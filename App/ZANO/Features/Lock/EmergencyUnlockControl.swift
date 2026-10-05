// EmergencyUnlockControl.swift
// App / ZANO / Features / Lock
//
// The one emergency-unlock control (spec §8 / §14 `EmergencyUnlockIntent`: a 60-second hold with a
// streak-penalty option; CLAUDE.md: every lock keeps a way out). The Lock tab pins it in its bottom
// bar, and the app shell shows it above the paywall if a lock is somehow still on when a
// subscription lapses (spec §21: a billing state must never trap anyone).
//
// It drives Core's `EmergencyUnlock` state machine, which owns the 60-second timer, the
// `LockEngineManager.emergencyUnlock` call and the optional `StreakEngine.recordMiss`. This view is
// only the gesture, the countdown and the penalty toggle.
//
// Gesture: a `DragGesture(minimumDistance: 0)` feeding a `@GestureState`, so a touch the system
// cancels (a call, backgrounding) resets the hold exactly like lifting the finger. VoiceOver has no
// sustained touch, so double-tap starts the same 60-second countdown and a second double-tap stops
// it: the wait is the friction, not the finger.
//
// The control's spoken label stays `Copy.lockStatus.emergencyUnlockTitle` for the whole hold (the UI
// tests find it by that text); the countdown is its value.

import SwiftUI
import Core

struct EmergencyUnlockControl: View {
    let sessionID: UUID

    /// One attempt per hold. Created on the first press (and again after a failure, since a failed
    /// `EmergencyUnlock` is terminal), so nothing is allocated while the control sits idle.
    @State private var attempt: EmergencyUnlock?
    /// The penalty choice before any attempt exists; pushed into each attempt.
    @State private var appliesStreakPenalty = true
    @State private var errorMessage: String?
    @GestureState private var isPressing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: EmergencyUnlock.Phase { attempt?.phase ?? .idle }
    private var progress: Double { attempt?.progress ?? 0 }
    private var secondsRemaining: Int { attempt?.secondsRemaining ?? Int(EmergencyUnlock.holdDuration) }
    private var isBusy: Bool { phase == .completing || phase == .unlocked }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            holdControl

            Toggle(Copy.lockStatus.emergencyPenaltyToggle, isOn: penaltyBinding)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .tint(Theme.Colors.accent)
                .disabled(isBusy)

            Text(Copy.lockStatus.emergencyUnlockFootnote(appliesStreakPenalty: appliesStreakPenalty))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: isPressing) { _, pressing in
            pressing ? beginHold() : cancelHold(announce: false)
        }
        .onChange(of: phase) { _, newPhase in
            handle(newPhase)
        }
        .onChange(of: sessionID) { _, _ in
            attempt = nil
            errorMessage = nil
        }
        .onDisappear { attempt?.cancelHold() }
        // A tick every 10 seconds of the hold, so the wait is felt, not just seen.
        .sensoryFeedback(.impact(weight: .light), trigger: secondsRemaining) { _, new in
            phase == .holding && new > 0 && new % 10 == 0
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: phase) { _, new in new == .unlocked }
    }

    // MARK: - Hold control

    private var holdControl: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.Typography.icon(.medium))
                .accessibilityHidden(true)
            Text(visibleTitle)
                .font(Theme.Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
        }
        .foregroundStyle(Theme.Colors.text)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
        .background {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface2)
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Theme.Colors.danger.opacity(0.85))
                        .frame(width: proxy.size.width * progress)
                }
                .clipShape(Capsule())
            }
        }
        .overlay(
            Capsule().strokeBorder(
                Theme.Colors.danger.opacity(phase == .holding ? 0 : 0.5),
                lineWidth: Theme.Metrics.selectedStroke
            )
        )
        .scaleEffect(phase == .holding && !reduceMotion ? 0.98 : 1)
        .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: phase == .holding)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressing) { _, state, _ in state = true }
        )
        .allowsHitTesting(!isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.lockStatus.emergencyUnlockTitle)
        .accessibilityValue(phase == .holding ? Copy.lockStatus.emergencyUnlockSecondsLeftSpoken(secondsRemaining) : "")
        .accessibilityHint(Copy.lockStatus.emergencyUnlockHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !isBusy else { return }
            if phase == .holding {
                cancelHold(announce: true)
            } else {
                beginHold()
                announce(Copy.lockStatus.emergencyUnlockCountdownStarted)
            }
        }
    }

    private var visibleTitle: String {
        switch phase {
        case .holding: Copy.lockStatus.emergencyUnlockHolding(secondsRemaining: secondsRemaining)
        case .completing, .unlocked: Copy.lockStatus.emergencyUnlockCompleting
        case .idle, .failed: Copy.lockStatus.emergencyUnlockTitle
        }
    }

    private var penaltyBinding: Binding<Bool> {
        Binding(
            get: { appliesStreakPenalty },
            set: { newValue in
                appliesStreakPenalty = newValue
                attempt?.setAppliesStreakPenalty(newValue)
            }
        )
    }

    // MARK: - Actions

    private func beginHold() {
        guard !isBusy else { return }
        if attempt == nil || attempt?.phase == .failed || attempt?.sessionID != sessionID {
            attempt = EmergencyUnlock(sessionID: sessionID, appliesStreakPenalty: appliesStreakPenalty)
        }
        guard attempt?.phase == .idle else { return }
        errorMessage = nil
        attempt?.beginHold()
        Analytics.shared.capture(
            event: "lock_emergency_unlock_started",
            properties: ["streak_penalty": appliesStreakPenalty]
        )
    }

    private func cancelHold(announce shouldAnnounce: Bool) {
        guard phase == .holding else { return }
        attempt?.cancelHold()
        Analytics.shared.capture(event: "lock_emergency_unlock_released_early")
        if shouldAnnounce { announce(Copy.lockStatus.emergencyUnlockCountdownStopped) }
    }

    private func handle(_ newPhase: EmergencyUnlock.Phase) {
        switch newPhase {
        case .unlocked:
            Analytics.shared.capture(
                event: "lock_emergency_unlock_succeeded",
                properties: ["streak_penalty": attempt?.appliesStreakPenalty ?? appliesStreakPenalty]
            )
            announce(Copy.lockStatus.emergencyUnlockDone)
        case .failed:
            errorMessage = Copy.lockStatus.emergencyUnlockFailed
            Analytics.shared.capture(
                event: "lock_emergency_unlock_failed",
                properties: ["reason": attempt?.lastError.map { String(describing: $0) } ?? "unknown"]
            )
            announce(Copy.lockStatus.emergencyUnlockFailed)
        case .idle, .holding, .completing:
            break
        }
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
