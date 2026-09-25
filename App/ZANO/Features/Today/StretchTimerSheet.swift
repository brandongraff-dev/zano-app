// StretchTimerSheet.swift
// App / ZANO / Features / Today
//
// The Stretch / mobility row's action (docs/spec.md §3, Tier B: "Guided 5-min timer with device flat
// on floor"). A thin screen over `StretchVerifier`: it starts the session, shows the countdown and
// whether the phone reads as flat, and ends the session when the timer runs out. `StretchVerifier`
// writes the `GoalEvent` and calls `GoalCompletionCoordinator` itself, so this view never logs
// anything on its own.
//
// Stopping early (or swiping the sheet away, once it's allowed) ends the session, which logs a miss
// row; it never blocks the user. The screen stays awake while the timer runs: the phone is meant to
// lie on the floor, and a sleeping screen would suspend the countdown's display.

import SwiftUI
import UIKit
import Core

struct StretchTimerSheet: View {
    let goalID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case starting
        case running(sessionID: UUID)
        case finished(verified: Bool)
        case failed
    }

    @State private var phase: Phase = .starting
    @State private var live: StretchSessionState?
    /// Bumped by "Try again" to restart the session task.
    @State private var attempt = 0

    private var runningSessionID: UUID? {
        if case .running(let id) = phase { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .navigationTitle(Copy.today.stretchTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(runningSessionID != nil)
        .task(id: attempt) { await run() }
        .onChange(of: runningSessionID) { _, id in
            UIApplication.shared.isIdleTimerDisabled = id != nil
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            endIfRunning()
        }
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .finished(verified: true) }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .starting, .running:
            timer
        case .finished(let verified):
            result(verified: verified)
        case .failed:
            Text(Copy.today.stretchStartFailed)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.warning)
                .multilineTextAlignment(.center)
        }
    }

    private var timer: some View {
        let total = StretchVerifier.sessionMinutes * 60
        let remaining = live?.secondsRemaining ?? total
        let fraction = total > 0 ? Double(total - remaining) / Double(total) : 0
        return VStack(spacing: Theme.Spacing.lg) {
            GoalRing(
                progress: fraction,
                color: Theme.Colors.Ring.stretchMobility,
                size: .hero,
                center: .text(Self.clock(remaining))
            )
            .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.today.stretchRemainingSpoken(seconds: remaining))

            Text(Copy.today.stretchInstruction)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let flat = live?.isCurrentlyFlat {
                Label(
                    flat ? Copy.today.stretchFlat : Copy.today.stretchNotFlat,
                    systemImage: flat ? "checkmark.circle.fill" : "iphone.gen3"
                )
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(flat ? Theme.Colors.accent : Theme.Colors.warning)
            }
        }
    }

    private func result(verified: Bool) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: verified ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(verified ? Theme.Colors.accent : Theme.Colors.muted)
                .accessibilityHidden(true)
            Text(verified ? Copy.today.stretchDoneTitle : Copy.today.stretchMissedTitle)
                .font(Theme.Typography.titleLarge)
                .foregroundStyle(Theme.Colors.text)
            if !verified {
                Text(Copy.today.stretchMissedDetail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .starting, .running:
            PrimaryButton(title: Copy.today.stretchStop, style: .secondary) {
                endIfRunning()
                dismiss()
            }
        case .finished(let verified):
            if !verified {
                PrimaryButton(title: Copy.today.stretchTryAgain) { attempt += 1 }
            }
            PrimaryButton(title: Copy.today.stretchClose, style: verified ? .standard : .secondary) { dismiss() }
        case .failed:
            PrimaryButton(title: Copy.today.stretchClose, style: .secondary) { dismiss() }
        }
    }

    // MARK: - Session

    private func run() async {
        phase = .starting
        live = nil
        let sessionID: UUID
        do {
            sessionID = try await StretchVerifier.shared.startSession(goalID: goalID)
        } catch {
            phase = .failed
            return
        }
        phase = .running(sessionID: sessionID)

        while !Task.isCancelled {
            guard let state = StretchVerifier.shared.liveState(sessionID: sessionID) else { return }
            live = state
            if state.secondsRemaining <= 0 { break }
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled, runningSessionID == sessionID else { return }
        let verified = (try? await StretchVerifier.shared.endSession(sessionID: sessionID)) ?? false
        phase = .finished(verified: verified)
    }

    /// Ends a session still running (Stop, or the sheet going away). Logs a miss row in
    /// `StretchVerifier`; a real unlock can never depend on it.
    private func endIfRunning() {
        guard let sessionID = runningSessionID else { return }
        phase = .starting
        Task { _ = try? await StretchVerifier.shared.endSession(sessionID: sessionID) }
    }

    /// `"4:05"`.
    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }
}
