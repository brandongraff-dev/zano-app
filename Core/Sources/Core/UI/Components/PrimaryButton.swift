// PrimaryButton.swift
// Core / UI / Components
//
// The app's primary call-to-action button, per docs/spec.md §15's core component list:
// "PrimaryButton (hold-to-commit variant)". This task's brief specifies the hold-to-commit variant
// concretely: a 2-second press + haptics (see `Theme.Motion.holdToCommitDuration`) — matching the
// P4 onboarding mockup in §16 ("a hold-to-commit button at the bottom with a progress outline").
//
// Haptics use SwiftUI's native `.sensoryFeedback` modifier (iOS 17+), not `UIImpactFeedbackGenerator`
// — this keeps the whole file UIKit-free per CLAUDE.md ("No UIKit unless an Apple API requires it").
//
// All copy is caller-supplied (`title`) — this file never hardcodes button text.

import SwiftUI

/// ZANO's primary call-to-action button. Supports a normal tap (`.standard`) and a press-and-hold
/// confirmation gesture (`.holdToCommit`) for consequential actions (e.g. committing a lock-in
/// plan, confirming an emergency unlock) where a single accidental tap shouldn't fire the action.
public struct PrimaryButton: View {

    public enum Style: Sendable, Equatable {
        /// A normal, single-tap button.
        case standard
        /// Requires a continuous ~2s press (`Theme.Motion.holdToCommitDuration`) before `action`
        /// fires. Releasing early cancels and resets the fill with no effect.
        case holdToCommit
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let isEnabled: Bool
    private let action: () -> Void

    @State private var isHolding = false
    @State private var holdProgress: Double = 0
    @State private var hapticTick = 0
    @State private var commitTick = 0
    @State private var holdTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Caller-composed button label (from `Copy`).
    ///   - systemImage: Optional leading SF Symbol name.
    ///   - style: `.standard` or `.holdToCommit`. Defaults to `.standard`.
    ///   - isEnabled: Disables interaction and dims the button when `false`. Defaults to `true`.
    ///   - action: For `.standard`, called on tap. For `.holdToCommit`, called once the full
    ///     hold duration completes.
    public init(
        title: String,
        systemImage: String? = nil,
        style: Style = .standard,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        switch style {
        case .standard:
            Button(action: action) { label }
                .buttonStyle(StandardPrimaryButtonStyle())
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
        case .holdToCommit:
            holdToCommitBody
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(title)
                .font(Theme.Typography.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        // Horizontal inset was missing entirely (optical-alignment finding,
        // docs/design/apple-design-review.md §8.1): with only vertical padding, the title/icon
        // sit flush against the button's rounded-rect edge — especially visible on the
        // `.holdToCommit` variant, which also draws a stroke border right at that same edge.
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Hold to commit

    private var holdToCommitBody: some View {
        label
            .foregroundStyle(Theme.Colors.text)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.Colors.surface2)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.Colors.accent.opacity(0.9))
                            .frame(width: proxy.size.width * holdProgress)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(isHolding ? 0 : 0.4), lineWidth: 1.5)
            )
            .compositingGroup()
            .scaleEffect(isHolding ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginHoldIfNeeded() }
                    .onEnded { _ in endHold() }
            )
            .animation(pressFeedbackAnimation(reduceMotion: reduceMotion), value: isHolding)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: hapticTick)
            .sensoryFeedback(.success, trigger: commitTick)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            // VoiceOver's double-tap activates the standard accessibility action below rather
            // than driving the `DragGesture` above — a sustained physical hold has no VoiceOver
            // equivalent. Without this, a screen-reader user could never fire a `.holdToCommit`
            // action at all, which is unacceptable for anything safety-critical (e.g. Emergency
            // Unlock in `LockStatusView`) per CLAUDE.md/spec §24: "never trap the user." This
            // fires `action()` immediately on VoiceOver activation, bypassing the hold — the
            // 2-second press exists to prevent an accidental *touch*, which isn't a risk VoiceOver
            // navigation (which requires a deliberate double-tap to activate a focused element)
            // shares.
            .accessibilityAction {
                guard isEnabled else { return }
                commitTick += 1
                action()
            }
            .onDisappear { holdTask?.cancel() }
    }

    /// Starts (or no-ops if already running) the hold timer: advances `holdProgress` in fixed
    /// ticks so the fill animates smoothly, and increments `hapticTick` on each decile crossed so
    /// the press builds an escalating "charging up" feel (spec §15: "haptics on every verified
    /// event" — this extends that spirit to the confirmation gesture itself, not just the eventual
    /// verified goal).
    private func beginHoldIfNeeded() {
        guard isEnabled, !isHolding else { return }
        isHolding = true
        // Do NOT hard-reset `holdProgress` to 0 here. If a previous release's cancel-spring
        // (`endHold()`) is still animating the fill back toward 0, forcing it to a literal 0 now
        // makes the fill visibly pop/teleport before immediately climbing again — a hard,
        // un-physical break in an otherwise continuous, redirectable gesture (Apple HIG: "a user
        // must be able to grab a moving element mid-flight and reverse it without waiting for the
        // animation to finish"). Resuming the ascending tick loop from wherever `holdProgress`
        // currently reads fixes this; worst case (re-press right as the spring finishes) is
        // indistinguishable from starting at 0 anyway (docs/design/apple-design-review.md §3.1).
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
                holdProgress = progress
                let decile = Int(progress * 10)
                if decile != lastDecile {
                    lastDecile = decile
                    hapticTick += 1
                }
            }
            guard !Task.isCancelled else { return }
            commitTick += 1
            action()
            // Give the 100% moment a brief settle instead of an instant vanish: without this,
            // `holdProgress` snapped back to 0 with no `withAnimation` at all the instant the
            // hold completed — a "teleporting state" bug on the app's single highest-stakes
            // confirmation control (docs/design/animation-opportunities.md row 2). If `action()`
            // doesn't immediately dismiss/navigate away, the user gets to actually see "full"
            // before the fill clears.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isHolding = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.72)) {
                holdProgress = 0
            }
        }
    }

    /// Cancels an in-progress hold that hasn't reached full commitment yet and springs the fill
    /// back to zero. A hold that already completed (`holdProgress >= 1`) has already fired
    /// `action()` and reset itself in `beginHoldIfNeeded`, so this is a no-op in that case.
    private func endHold() {
        guard isHolding, holdProgress < 1 else { return }
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
            holdProgress = 0
        }
    }
}

/// A dedicated, faster spring for press/hold feedback — Apple HIG's press-feedback budget is
/// 100–160ms, and `Theme.Motion.springStandard` (response 0.35) settles noticeably slower than
/// that. `Theme.swift` isn't editable this run (a sibling task owns it — see this task's
/// knownIssues), so this stays a local, file-scoped helper rather than a new `Theme.Motion`
/// token; promote it to one (`Theme.Motion.pressFeedback`) the next time `Theme.swift` is
/// touched, per docs/design/animation-opportunities.md row 3. `fileprivate` (not a `private`
/// member of `PrimaryButton`) so `StandardPrimaryButtonStyle` below — a sibling type in the same
/// file — can share it instead of duplicating the tuning.
fileprivate func pressFeedbackAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.16, dampingFraction: 0.75)
}

/// `ButtonStyle` for `PrimaryButton.Style.standard`: solid accent fill with a subtle press scale.
private struct StandardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.Colors.background)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            // Every button tap, app-wide — this is squarely the "tens of times/day" frequency
            // tier, so the press curve itself must stay fast (see `pressFeedbackAnimation`
            // above); reduced motion keeps the opacity/scale feedback (it's real information —
            // "the interface heard you") but drops the spring's settle for a flat, quick ease.
            .animation(pressFeedbackAnimation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
