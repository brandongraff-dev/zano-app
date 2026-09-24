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
//
// Design-quality pass (docs/design/{better-ui,typography-color,2026-ios-trends,composition-audit}):
//
//   * BUG FIX — the hold-to-commit label was unreadable mid-hold. It was `text` (#F5F5F7) for the
//     whole label while an accent fill swept under it: 1.11:1 where they overlap (1.35 at the old
//     0.9-alpha fill). On the app's signature confirmation — Emergency Unlock, "begin lock", the
//     onboarding commitment — the words vanished exactly as the user committed. The label is now
//     drawn twice: `text` on the track, and `onFill` (16.4:1 on accent) masked to the fill's
//     width, so each glyph flips colour at the exact pixel the fill reaches it.
//   * Controls are capsules (iOS 26 concentric shapes; the 12pt rounded rect read as the previous
//     era beside the system tab bar) and at least 52pt tall.
//   * Disabled no longer means "the accent at 50%" — a muddy olive slab (#618424, not in the
//     palette) that still read as *the* primary action. Disabled is `surface2` with a `muted`
//     label. (Five of Today's eight states used to render as this.)
//   * `tint` lets a destructive/exit action stop wearing the earned/unlock accent: the Emergency
//     Unlock's hold used to fill acid-green — the "earned" colour — while the user *bailed out*.
//   * `.secondary` gives every second-tier action a real control (six screens hand-rolled one).
//   * The hold fill advances in linear per-tick animations instead of 20fps steps, has a straight
//     trailing edge (it is clipped to the capsule, not a squashed rounded rect), and the 100%
//     moment settles as before.

import SwiftUI

/// ZANO's primary call-to-action button. Supports a normal tap (`.standard`), a press-and-hold
/// confirmation gesture (`.holdToCommit`) for consequential actions (e.g. committing a lock-in
/// plan, confirming an emergency unlock) where a single accidental tap shouldn't fire the action,
/// and a quieter `.secondary` for second-tier actions.
public struct PrimaryButton: View {

    public enum Style: Sendable, Equatable {
        /// A normal, single-tap button.
        case standard
        /// Requires a continuous ~2s press (`Theme.Motion.holdToCommitDuration`) before `action`
        /// fires. Releasing early cancels and resets the fill with no effect.
        case holdToCommit
        /// A bordered `surface2` capsule with a `text` label: the second action on a screen
        /// ("Restore purchases", "Share", "Snooze"). Never competes with an accent CTA.
        case secondary
    }

    /// The fill hue of `.standard` and the sweep/border hue of `.holdToCommit`.
    public enum Tint: Sendable, Equatable {
        /// The earned/unlock accent. The default — use it only for the one primary action on a
        /// screen and for earned states (spec §15: "ONE accent only").
        case accent
        /// An exit that costs something (emergency unlock, ending a lock early).
        case danger
        /// A caution-level action.
        case warning

        var color: Color {
            switch self {
            case .accent: Theme.Colors.accent
            case .danger: Theme.Colors.danger
            case .warning: Theme.Colors.warning
            }
        }
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let isEnabled: Bool
    private let tint: Tint
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
    ///   - style: `.standard`, `.holdToCommit` or `.secondary`. Defaults to `.standard`.
    ///   - isEnabled: Disables interaction and shows the disabled treatment when `false`.
    ///     Defaults to `true`. Prefer not to use a disabled button for *status* ("Focus running…"):
    ///     that is information, not an unavailable action — show it as a status row instead.
    ///   - tint: Fill hue for `.standard`, sweep hue for `.holdToCommit`. Defaults to `.accent`.
    ///   - action: For `.standard`/`.secondary`, called on tap. For `.holdToCommit`, called once
    ///     the full hold duration completes.
    public init(
        title: String,
        systemImage: String? = nil,
        style: Style = .standard,
        isEnabled: Bool = true,
        tint: Tint = .accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isEnabled = isEnabled
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        switch style {
        case .standard:
            Button(action: action) { label }
                .buttonStyle(PrimaryButtonStyle(kind: .filled, tint: tint))
                .disabled(!isEnabled)
        case .secondary:
            Button(action: action) { label }
                .buttonStyle(PrimaryButtonStyle(kind: .secondary, tint: tint))
                .disabled(!isEnabled)
        case .holdToCommit:
            holdToCommitBody
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.medium))
                    // Decorative: a `Button` label folds its child images into the spoken label, so
                    // without this VoiceOver reads the symbol's name before the title.
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Theme.Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        // Horizontal inset was missing entirely (optical-alignment finding,
        // docs/design/apple-design-review.md §8.1): with only vertical padding, the title/icon
        // sit flush against the button's edge — especially visible on the `.holdToCommit`
        // variant, which also draws a stroke border right at that same edge.
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
    }

    // MARK: - Hold to commit

    /// The label twice: `text` on the unfilled track, and `onFill` masked to the fill's width on
    /// top — so the colour flips at exactly the pixel the sweeping fill reaches. See the file
    /// header (the label used to be `text` throughout: 1.11:1 over the accent fill).
    private var holdLabel: some View {
        label
            .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    label
                        .foregroundStyle(Theme.Colors.onFill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: proxy.size.width * holdProgress)
                        }
                }
            }
    }

    private var holdToCommitBody: some View {
        holdLabel
            .background {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surface2)
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(tint.color)
                            .frame(width: proxy.size.width * holdProgress)
                    }
                    // Clipping a rectangle to the capsule gives the fill a straight trailing edge
                    // that never squashes into a pill while it is narrow (a rounded-rect fill
                    // clamped its radius below 24pt of width).
                    .clipShape(Capsule())
                }
            }
            .overlay(
                // Enabled: a tint outline that hands over to the fill once the hold begins.
                // Disabled: the neutral hairline, exactly like the disabled `.standard` button — not
                // a second 50% opacity on top of an already-`muted` label (which fell to ~2.5:1).
                Capsule()
                    .strokeBorder(
                        isEnabled ? tint.color.opacity(isHolding ? 0 : 0.5) : Theme.Colors.hairline,
                        lineWidth: isEnabled ? 1.5 : 1
                    )
            )
            .compositingGroup()
            .scaleEffect(isHolding && !reduceMotion ? 0.98 : 1)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginHoldIfNeeded() }
                    .onEnded { _ in endHold() }
            )
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: isHolding)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: hapticTick)
            .sensoryFeedback(.success, trigger: commitTick)
            // A gesture-driven control is not a `Button`, so it does not announce "dimmed" on its
            // own; `.disabled` does that for VoiceOver (the hold guard in `beginHoldIfNeeded` is
            // what actually blocks the gesture).
            .disabled(!isEnabled)
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
        let tickAnimation: Animation? = reduceMotion ? nil : .linear(duration: Double(tickMs) / 1000)

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            var elapsedMs = startingMs
            var lastDecile = Int(holdProgress * 10)
            while elapsedMs < totalMs {
                try? await Task.sleep(for: .milliseconds(tickMs))
                if Task.isCancelled { return }
                elapsedMs += tickMs
                let progress = min(1, Double(elapsedMs) / Double(totalMs))
                // Each tick eases linearly into the next, so the fill glides instead of stepping
                // at 20fps. Reduce Motion: no interpolation (the steps are the information).
                withAnimation(tickAnimation) {
                    holdProgress = progress
                }
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

/// `ButtonStyle` for `PrimaryButton.Style.standard` (a solid `tint` capsule) and `.secondary` (a
/// bordered `surface2` capsule). Reads `isEnabled` from the environment so the disabled treatment
/// is a real palette state (`surface2` + `muted`), not a dimmed accent.
private struct PrimaryButtonStyle: ButtonStyle {
    enum Kind {
        case filled
        case secondary
    }

    let kind: Kind
    let tint: PrimaryButton.Tint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let isFilled = kind == .filled && isEnabled

        return configuration.label
            .foregroundStyle(labelColor)
            .background {
                Capsule()
                    .fill(fillColor)
                    // Accent glow only on the *pressed* CTA (spec §16: "inner glow on active
                    // elements") — never a resting shadow: drop shadows don't show on near-black,
                    // and a glow on every button would dilute the one that matters.
                    .shadow(color: isFilled && pressed ? tint.color.opacity(0.35) : .clear, radius: 14)
            }
            .overlay {
                if isFilled {
                    // A 1px top-lit highlight: the same edge light the cards get.
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Theme.Colors.specular, Theme.Colors.specular.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                } else {
                    Capsule().strokeBorder(
                        kind == .secondary && isEnabled ? Theme.Colors.hairlineStrong : Theme.Colors.hairline,
                        lineWidth: 1
                    )
                }
            }
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed ? 0.92 : 1)
            .contentShape(Capsule())
            // Every button tap, app-wide — this is squarely the "tens of times/day" frequency
            // tier, so the press curve itself must stay fast (`Theme.Motion.pressFeedback`);
            // reduced motion keeps the opacity feedback (it's real information — "the interface
            // heard you") but drops the spring's settle and the scale.
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: pressed)
    }

    private var fillColor: Color {
        switch kind {
        case .filled: isEnabled ? tint.color : Theme.Colors.surface2
        case .secondary: Theme.Colors.surface2
        }
    }

    /// `onFill` (16.4:1 on accent, 5.8:1 on danger, 10.8:1 on warning) on a filled control; `text`
    /// on the secondary; `muted` (5.2:1 on `surface2`) whenever disabled.
    private var labelColor: Color {
        guard isEnabled else { return Theme.Colors.muted }
        switch kind {
        case .filled: return Theme.Colors.onFill
        case .secondary: return Theme.Colors.text
        }
    }
}

#Preview("PrimaryButton") {
    VStack(spacing: Theme.Spacing.md) {
        PrimaryButton(title: "Start focus", systemImage: "timer", action: {})
        PrimaryButton(title: "Restore purchases", style: .secondary, action: {})
        PrimaryButton(title: "Unavailable", isEnabled: false, action: {})
        PrimaryButton(title: "Hold to commit", style: .holdToCommit, action: {})
        PrimaryButton(title: "Hold to unlock now", systemImage: "exclamationmark.triangle.fill", style: .holdToCommit, tint: .danger, action: {})
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
