// StartActionsView.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: "start focus/lock from the wrist." Every button here sends a
// `WatchToPhoneRequest` through `WatchConnectivityBridge` — see that file's header for exactly
// what is and isn't wired on the phone side yet (nothing, today; flagged in this task's
// knownIssues). The UI is honest about that distinction: a tap shows "requested", never "started"
// — `WatchStateStore.apply(_:)` is what would flip a request into a real running state once the
// phone's next snapshot reflects it.

import Foundation
import SwiftUI

struct StartActionsView: View {
    @Environment(WatchStateStore.self) private var store
    @Environment(WatchConnectivityBridge.self) private var connectivity

    @State private var lastConfirmation: String?

    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.md) {
                if let focusSession = store.snapshot.focusSession {
                    RunningFocusCard(session: focusSession)
                } else {
                    StartFocusCard(store: store, connectivity: connectivity, onSent: showConfirmation(_:))
                }

                if let activeLock = store.snapshot.activeLock {
                    ActiveLockCard(lock: activeLock, connectivity: connectivity)
                } else {
                    StartLockCard(store: store, connectivity: connectivity, onSent: showConfirmation(_:))
                }

                if let error = connectivity.lastSendError {
                    Text(error)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(WatchTheme.Colors.warning)
                        .multilineTextAlignment(.center)
                }

                if let lastConfirmation {
                    Text(lastConfirmation)
                        .font(WatchTheme.Typography.captionEmphasized)
                        .foregroundStyle(WatchTheme.Colors.accent)
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .padding(.vertical, WatchTheme.Spacing.sm)
        }
        .background(WatchTheme.Colors.background)
        .navigationTitle(Copy.watch.actionsTab)
    }

    private func showConfirmation(_ text: String) {
        lastConfirmation = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if lastConfirmation == text { lastConfirmation = nil }
        }
    }
}

// MARK: - Start Focus

private struct StartFocusCard: View {
    let store: WatchStateStore
    let connectivity: WatchConnectivityBridge
    let onSent: (String) -> Void

    /// Mirrors `FocusSessionPreset` (`Core/Sources/Core/Verification/FocusSessionVerifier.swift`)
    /// — the same 25/50/90 values, since this target can't reference that enum directly.
    private static let presetMinutes = [25, 50, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
            Text(Copy.watch.startFocusTitle)
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.text)

            if let goalTitle = store.snapshot.suggestedFocusGoalTitle {
                Text(goalTitle)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(WatchTheme.Colors.muted)
            }

            HStack(spacing: WatchTheme.Spacing.xs) {
                ForEach(Self.presetMinutes, id: \.self) { minutes in
                    Button {
                        start(minutes: minutes)
                    } label: {
                        Text(String(format: Copy.watch.focusPresetMinutesFormat, minutes))
                            .font(WatchTheme.Typography.numeralSmall())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.Colors.Ring.focus)
                    .disabled(store.snapshot.suggestedFocusGoalID == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
    }

    private func start(minutes: Int) {
        guard let goalID = store.snapshot.suggestedFocusGoalID else { return }
        connectivity.send(.startFocusSession(goalID: goalID, plannedMinutes: minutes))
        store.markFocusSessionPending(goalTitle: store.snapshot.suggestedFocusGoalTitle ?? "Focus", plannedMinutes: minutes)
        HapticsPlayer.playActionSent()
        onSent(Copy.watch.focusRequestedConfirmation)
    }
}

private struct RunningFocusCard: View {
    let session: WatchFocusSessionSnapshot
    @Environment(WatchConnectivityBridge.self) private var connectivity

    private var minutesRemaining: Int { max(0, session.secondsRemaining / 60) }

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.xs) {
            Text(session.isPaused ? Copy.watch.focusPausedTitle : Copy.watch.focusRunningTitle)
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.text)
            Text("\(minutesRemaining):" + String(format: "%02d", session.secondsRemaining % 60))
                .font(WatchTheme.Typography.numeralMedium())
                .foregroundStyle(WatchTheme.Colors.Ring.focus)
            Text(session.goalTitle)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(WatchTheme.Colors.muted)

            Button(Copy.watch.endFocusButton) {
                connectivity.send(.endFocusSession(sessionID: session.sessionID))
                HapticsPlayer.playActionSent()
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.Colors.danger)
        }
        .frame(maxWidth: .infinity)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Start Lock

private struct StartLockCard: View {
    let store: WatchStateStore
    let connectivity: WatchConnectivityBridge
    let onSent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
            Text(Copy.watch.startLockTitle)
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.text)
            Text(Copy.watch.startLockSubtitle)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(WatchTheme.Colors.muted)

            Button(Copy.watch.startLockTitle) {
                start()
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.Colors.accent)
            .disabled(store.snapshot.suggestedLockSetID == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
    }

    private func start() {
        guard let lockSetID = store.snapshot.suggestedLockSetID else { return }
        connectivity.send(
            .startLock(
                lockSetID: lockSetID,
                mode: store.snapshot.suggestedLockMode,
                requiredGoalIDs: store.snapshot.suggestedLockRequiredGoalIDs,
                trigger: .manual
            )
        )
        HapticsPlayer.playActionSent()
        onSent(Copy.watch.lockRequestedConfirmation)
    }
}

private struct ActiveLockCard: View {
    let lock: WatchActiveLockSnapshot
    let connectivity: WatchConnectivityBridge

    /// Mirrors `Theme.Motion.holdToCommitDuration` (`Core/Sources/Core/UI/Theme.swift`, 2.0s) —
    /// same hold-to-commit affordance `PrimaryButton`'s `.holdToCommit` variant uses on the phone
    /// for irreversible/high-stakes actions, applied here so a stray wrist tap can never fire
    /// emergency unlock, while a deliberate 2-second hold always can (CLAUDE.md: "Emergency unlock
    /// must always exist... never trap the user" — the hold makes it deliberate, never absent).
    private static let holdToCommitDuration: TimeInterval = 2.0

    @State private var isHolding = false

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.xs) {
            Text(String(format: Copy.watch.activeLockStatusFormat, lock.goalsRemaining))
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.danger)

            emergencyUnlockControl
        }
        .frame(maxWidth: .infinity)
        .padding(WatchTheme.Spacing.sm)
        .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 14))
    }

    /// A plain hold target — deliberately NOT a `Button` wrapping `.onLongPressGesture`. That was
    /// this file's original shape, and it's a real bug fixed here, not a style choice: it directly
    /// contradicts this codebase's own established, working precedent for the identical problem
    /// (`Core/Sources/Core/UI/Components/PrimaryButton.swift`'s `.holdToCommit` style, which this
    /// screen's own doc comment above already says it mirrors, but didn't actually match). Two
    /// concrete failure modes a `Button` + `.onLongPressGesture` combination has that a bare,
    /// gesture-only view does not:
    ///   1. A `Button` installs its own tap gesture recognizer; layering `.onLongPressGesture` on
    ///      top is a double-recognizer conflict SwiftUI does not guarantee resolves in the hold
    ///      gesture's favor, so a real 2-second hold on the wrist is not guaranteed to register.
    ///   2. VoiceOver activates a `Button` via double-tap, which has no way to drive a sustained
    ///      *physical* hold — the previous version's `Button` action was an empty no-op, so a
    ///      VoiceOver user had **no path at all** to Emergency Unlock. That directly violates
    ///      CLAUDE.md's "Emergency unlock must always exist on any lock-type feature. Never ship a
    ///      lock with no way out" and spec §24's identical rule. `.accessibilityAction` below is the
    ///      fix: it fires `fireEmergencyUnlock()` immediately on VoiceOver double-tap, bypassing the
    ///      hold entirely — exactly the bypass `PrimaryButton.holdToCommit`'s own doc comment
    ///      documents doing for the same reason on the phone.
    private var emergencyUnlockControl: some View {
        Text(isHolding ? Copy.watch.emergencyUnlockConfirm : Copy.watch.emergencyUnlockTitle)
            .font(WatchTheme.Typography.captionEmphasized)
            .foregroundStyle(WatchTheme.Colors.danger)
            .padding(.horizontal, WatchTheme.Spacing.sm)
            .padding(.vertical, WatchTheme.Spacing.xxs)
            .background(WatchTheme.Colors.surface2, in: .capsule)
            .overlay(Capsule().strokeBorder(WatchTheme.Colors.danger.opacity(0.6), lineWidth: 1))
            .scaleEffect(isHolding ? 0.96 : 1)
            .animation(WatchTheme.Motion.springStandard, value: isHolding)
            .contentShape(.capsule)
            .onLongPressGesture(
                minimumDuration: Self.holdToCommitDuration,
                pressing: { pressing in isHolding = pressing },
                perform: fireEmergencyUnlock
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.watch.emergencyUnlockTitle)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(perform: fireEmergencyUnlock)
    }

    private func fireEmergencyUnlock() {
        connectivity.send(.emergencyUnlock(sessionID: lock.sessionID))
        HapticsPlayer.playActionSent()
        isHolding = false
    }
}

#Preview {
    NavigationStack {
        StartActionsView()
    }
    .environment(WatchStateStore.shared)
    .environment(WatchConnectivityBridge.shared)
}
