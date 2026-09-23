// AlarmRingingView.swift
// App / Features / SunriseAlarm
//
// Owned by: this session's task (App/ZANO/Features/SunriseAlarm/*). Do not edit from another
// session — CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §5.10 "★ Bedtime Gate & Sunrise Alarm" — the full-screen ringing experience itself:
//   "1. Alarm fires at the set time with escalating sound/haptics.
//    2. The ONLY dismiss is tapping the Sunrise Tag...
//    3. Snooze exists but costs something: 1 snooze max (5 min), or it breaks the morning goal.
//    4. Tapping the tag = alarm off + morning goal verified + the day's lock arms automatically.
//    5. Distracting apps stay locked from wake until the day's goals are earned...
//    6. Escape hatch: a 60-second hold + 'I'm not home' option. No one gets trapped."
// plus the four dismiss variants (Tag/Steps/Focus/Squad) from that section's "Variants (settings)"
// list, and the safety copy: "Never promise 'this will always wake you.'" The spec calls this "the
// most demoed mechanic in the whole app", so this file is where the app's visual identity has to
// hold up hardest.
//
// This is the app's own in-app ringing UI — distinct from whatever system UI AlarmKit itself draws
// (iOS 26+ tier) or the system notification banner (iOS 17–18 fallback tier, spec §5.10's
// Technical path). Assumption, not verified against a Mac: this view is shown whenever
// `SunriseAlarmManager.shared.isRinging` is true — i.e. whenever the app is foregrounded during an
// active alarm, on *either* tier.
//
// CLAUDE.md / spec §5.10 point 6 / §24: "Any lock/alarm feature must always keep an escape hatch —
// never trap the user." Enforced the same way `ShieldPreview.swift` enforces it for the shield
// screen: the escape-hatch controls are unconditional `View` content in this file's `body`, not
// gated behind any variant/settings branch. As of the design-quality wave they are also *pinned*
// (`safeAreaInset(edge: .bottom)`) instead of sitting at the end of a scroll, so the hatch is on
// screen at every viewport size (docs/design/better-layout-findings.md §7.2 / H3).
//
// Reuses `EmergencyUnlock.holdDuration` (`Core/Sources/Core/LockEngine/EmergencyUnlock.swift`,
// public, = 60) as this screen's own hold duration rather than re-declaring the same "60-second
// hold" constant a second time. The alarm's escape hatch does not call `LockEngineManager`/
// `EmergencyUnlock` itself: silencing a ringing alarm and ending a shielded lock session are
// different concerns.
//
// The "I'm not home" option is a toggle next to the 60-second hold, not a separate instant bypass —
// mirroring `EmergencyUnlock.setAppliesStreakPenalty`'s "toggle beside the hold control changes what
// completing the hold does" pattern. Flagged as a UX decision, not spec-literal text.
//
// The Tag variant is a two-step handshake: (1) `NFCTagMapper.shared.scanAndHandle` does the
// goal-verification + lock-arming side of "tapping the tag", then (2) this file calls
// `SunriseAlarmManager.shared.dismissViaTag(tagID:)` for the alarm-specific side. Both must fire; see
// `scanTagAndDismiss()`.
//
// VISUAL DESIGN (design-quality wave, 2026-09-23). Everything below is treatment only: the dismiss
// logic, escape-hatch hold mechanics, VoiceOver actions, escalation phases, pulse loop and haptics
// are unchanged. What changed, and why (each item cites the audit that asked for it):
//   * The flat full-screen tint wash became a radial "sunrise" glow anchored behind the clock. Same
//     `isPulsing` opacity mechanism and the same fixed 0.22 under Reduce Motion, but the light now
//     falls off toward the edges, so secondary copy is no longer sitting on the peak of the tint
//     (typography-color-findings C4: muted text on the wash measured 2.6:1 at peak).
//   * The clock is the hero: 88pt rounded bold (Dynamic-Type scaled), up from 44pt
//     (composition-audit offender 8; the old comment here admitted Theme had no bigger step).
//   * The phase label became a tint-filled chip with a dark label (16:1 on the waking hue) so the
//     escalation reads even when the wash is at its dimmest, and carries a glyph so phase is not
//     communicated by hue alone (Theme's warning/sunriseAlarm hues are 11° apart).
//   * The dismiss card gets a top-lit 1px edge instead of a flat fill (better-ui DEP-01/02); the
//     Tag glyph gets static target rings and an NFC "waves" symbol effect that Reduce Motion turns
//     off; Steps/Focus rings carry a big numeral in the ring centre.
//   * Snooze is a real 44pt control instead of 17pt grey text (better-layout HIT-02 / 3.2).
//   * The escape hatch is a pinned 56pt danger capsule with a progress fill whose label inverts
//     under the fill (so it stays legible as the fill sweeps, better-ui BRK-02), with the "I'm not
//     home" toggle above it (better-layout 1.10). Only one ring is on screen now, so the task and
//     the way out no longer compete at equal size.
//   * `ProgressView()` is qualified as `SwiftUI.ProgressView()`: the app declares its own
//     `ProgressView` screen type, so the bare name mounted the whole Progress tab in the spinner slot
//     (better-ui BRK-01).
//
// Copy: every string is an existing `Copy.alarmRinging.*` / `SunriseAlarmCopy.*` key. Numbers
// ("12", "/40", "3:00", "60s") are formatted here the same way the previous version formatted them.
// No new keys were added because `Core/Sources/Core/Copy` is outside this file list.

import SwiftUI
import Core

/// Full-screen alarm-ringing UI: escalating visual/haptic state, the four dismiss variants (spec
/// §5.10), a "1 left"-style snooze, and the always-present, always-pinned 60-second escape hatch.
/// See the file header for the presentation assumption and the tag-dismiss two-step handshake.
@MainActor
struct AlarmRingingView: View {
    @Environment(\.dismiss) private var dismiss
    /// Gates the background glow pulse per this task's hard rule and
    /// `docs/design/animation-opportunities.md`'s Sunrise Alarm section, Part 1 refinement #1: a
    /// full-screen, escalating, strobing background with zero reduced-motion path was the single
    /// highest-stakes instance of that doc's Part 0 systemic gap. Also gates the NFC "waves" symbol
    /// effect and the phase-chip swap. The escalating *haptic* cadence (`pulseHapticTick`, below) is
    /// unaffected by Reduce Motion and deliberately keeps running unchanged — it should carry more
    /// of the urgency signal when visuals are dialed back, not be silenced too.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero clock size. `Theme.Typography` has no numeral step above 44pt (its largest is
    /// `numeralLarge`), and this is the one screen that must be readable half-asleep at arm's
    /// length, so the size lives here as a Dynamic-Type-scaled metric. Migrate to a
    /// `Theme.Typography.numeralHero` if/when that token lands
    /// (docs/design/competitive-research.md §0 punch list #2).
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 88

    /// The 3-minute Focus-dismiss timer's total duration (spec §5.10: "3-minute journal/stretch
    /// timer").
    private static let focusDurationSeconds = 180

    private var manager: SunriseAlarmManager { .shared }

    @State private var now = Date.now
    @State private var isPulsing = false
    @State private var pulseHapticTick = 0

    @State private var dismissVariant: SunriseAlarmManager.DismissVariant = .tag
    @State private var stepsTarget = 40
    @State private var isSettingsLoaded = false
    @State private var didDismiss = false
    @State private var dismissError: String?

    // Tag
    @State private var isScanningTag = false

    // Focus
    @State private var focusSecondsRemaining = AlarmRingingView.focusDurationSeconds
    @State private var isFocusRunning = false
    @State private var focusTask: Task<Void, Never>?

    // Escape hatch
    @State private var isHoldingEscapeHatch = false
    @State private var holdProgress: Double = 0
    @State private var isNotHome = false
    @State private var holdTask: Task<Void, Never>?
    @State private var escapeHapticTick = 0
    @State private var escapeError: String?

    private var elapsed: TimeInterval {
        guard let since = manager.ringingSince else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    private var phase: RingingPhase { .current(elapsed: elapsed) }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            sunriseGlow

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    variantContent
                    snoozeControl

                    Text(Copy.alarmRinging.standardAlarmFootnote)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Spacing.xs)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The escape hatch is chrome, not content: it never scrolls away and is on screen at
            // every viewport size (spec §5.10 point 6, CLAUDE.md "never trap the user").
            .safeAreaInset(edge: .bottom, spacing: 0) {
                escapeDock
            }
        }
        .task { await loadDismissVariant() }
        .task { await tickClock() }
        .task { await runPulseLoop() }
        .onChange(of: manager.isRinging) { _, isRinging in
            if !isRinging { dismiss() }
        }
        .onDisappear {
            focusTask?.cancel()
            holdTask?.cancel()
        }
        .sensoryFeedback(trigger: escapeHapticTick) { _, _ in
            .impact(weight: .light, intensity: 0.6)
        }
        .sensoryFeedback(trigger: pulseHapticTick) { _, _ in
            switch phase {
            case .waking: nil
            case .urgent: .impact(weight: .medium, intensity: 0.5)
            case .critical: .impact(weight: .heavy, intensity: 0.9)
            }
        }
        .interactiveDismissDisabled()
        .persistentSystemOverlays(.hidden)
        // Fixed, dark-only design system. This full-screen presentation used to set the scheme only
        // inside `#Preview`, so it depended on the presenter's scheme
        // (docs/design/typography-color-findings.md C11).
        .preferredColorScheme(.dark)
    }

    // MARK: - Sunrise glow

    /// The alarm's atmosphere: a radial glow anchored behind the clock, tinted by escalation phase.
    ///
    /// Pulses via exactly the mechanism the previous flat wash used — the *opacity* of one static
    /// gradient, driven by `isPulsing` — and holds at the same fixed 0.22 under Reduce Motion (the
    /// midpoint of the 0.10...0.32 range: same phase-tint colour, same legibility, just held still
    /// instead of looping). Deliberately opacity-only: HIG's Reduce Motion guidance asks apps not to
    /// animate blur or depth, and this animates neither. See `runPulseLoop()` for the matching gate
    /// on the animation that drives `isPulsing`.
    private var sunriseGlow: some View {
        RadialGradient(
            colors: [phase.tint, phase.tint.opacity(0)],
            center: UnitPoint(x: 0.5, y: 0.2),
            startRadius: 0,
            endRadius: 460
        )
        .opacity(reduceMotion ? 0.22 : (isPulsing ? 0.32 : 0.10))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            phaseChip

            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: clockSize, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(Theme.Colors.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            // `text`, not `muted`: this is the one instruction the screen exists to deliver, and it
            // sits close to the glow's peak (typography-color-findings C4).
            Text(Copy.alarmRinging.headline)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        // No `.scaleEffect`/`.animation` on `isPulsing` here — see
        // `docs/design/animation-opportunities.md` Sunrise Alarm Part 1, refinement #2. The clock
        // used to wobble on a spring while the background pulsed on its own easeInOut, two curves
        // keyed off one boolean that fell out of phase at the `.critical` cadence. The clock is the
        // one piece of information this screen must stay perfectly legible under stress (deciding
        // whether there's time to snooze); the chip, the glow pulse and the escalating haptics
        // already carry the urgency signal without it.
    }

    /// Phase label as a tint-filled capsule with a dark label. Dark-on-tint is 14:1 (waking), 10.8:1
    /// (urgent) and 5.8:1 (critical), independent of where the glow is in its pulse, and the glyph
    /// means the phase is not carried by hue alone.
    private var phaseChip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: phase.symbol)
                .font(.system(size: 13, weight: .bold))
            Text(eyebrowText)
                .font(Theme.Typography.captionEmphasized)
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(Theme.Colors.onFill)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(phase.tint, in: Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: phase)
    }

    private var eyebrowText: String {
        switch phase {
        case .waking: Copy.alarmRinging.eyebrowWaking
        case .urgent: Copy.alarmRinging.eyebrowUrgent
        case .critical: Copy.alarmRinging.eyebrowCritical
        }
    }

    // MARK: - Variant content

    @ViewBuilder
    private var variantContent: some View {
        if isSettingsLoaded {
            card {
                switch dismissVariant {
                case .tag: tagDismissContent
                case .steps: stepsDismissContent
                case .focus: focusDismissContent
                case .squad: squadDismissContent
                }
            }
        } else {
            // Qualified: the app declares its own `ProgressView` screen, which shadows SwiftUI's
            // spinner for any bare `ProgressView()` in this module (better-ui BRK-01).
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity, minHeight: AlarmMetrics.loadingHeight)
        }
    }

    private var tagDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            tagGlyph

            Text(Copy.alarmRinging.tagPromptLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            Text(NFCTagSetupInstructions.placementGuidance(for: .sunrise))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)

            PrimaryButton(
                title: Copy.alarmRinging.tagScanButtonLabel,
                systemImage: "wave.3.right",
                isEnabled: !isScanningTag && NFCReader.isAvailable
            ) {
                scanTagAndDismiss()
            }

            if isScanningTag {
                SwiftUI.ProgressView()
            }
        }
    }

    /// Static target rings around an NFC "waves" glyph. The waves animate (variable-colour sweep)
    /// only when Reduce Motion is off; the rings never move.
    private var tagGlyph: some View {
        let tint = Theme.Colors.Ring.sunriseAlarm
        return ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.10), lineWidth: 1)
                .frame(width: AlarmMetrics.glyphOuterRing, height: AlarmMetrics.glyphOuterRing)
            Circle()
                .strokeBorder(tint.opacity(0.20), lineWidth: 1)
                .frame(width: AlarmMetrics.glyphInnerRing, height: AlarmMetrics.glyphInnerRing)
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: AlarmMetrics.glyphDisc, height: AlarmMetrics.glyphDisc)
            Image(systemName: "wave.3.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        }
        .accessibilityHidden(true)
    }

    private var stepsDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            let walked = min(manager.stepsWalked, stepsTarget)
            AlarmDial(
                progress: Double(manager.stepsWalked) / Double(max(1, stepsTarget)),
                color: Theme.Colors.Ring.steps,
                value: "\(walked)",
                caption: "/\(stepsTarget)",
                accessibilityLabel: Copy.alarmRinging.stepsPromptLabel(target: stepsTarget),
                accessibilityValue: "\(walked)/\(stepsTarget)"
            )
            Text(Copy.alarmRinging.stepsPromptLabel(target: stepsTarget))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
        }
        .task(id: manager.stepsWalked) {
            guard manager.stepsWalked >= stepsTarget else { return }
            await performDismiss { try await manager.dismissViaSteps() }
        }
    }

    private var focusDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            AlarmDial(
                progress: 1 - (Double(focusSecondsRemaining) / Double(Self.focusDurationSeconds)),
                color: Theme.Colors.Ring.focus,
                value: formattedFocusTime,
                caption: nil,
                accessibilityLabel: Copy.alarmRinging.focusPromptLabel,
                accessibilityValue: formattedFocusTime
            )
            Text(Copy.alarmRinging.focusPromptLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            if !isFocusRunning {
                PrimaryButton(title: Copy.alarmRinging.focusStartButtonLabel) {
                    startFocusCountdown()
                }
            }
        }
    }

    private var formattedFocusTime: String {
        String(format: "%d:%02d", focusSecondsRemaining / 60, focusSecondsRemaining % 60)
    }

    private var squadDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.Ring.sunriseAlarm.opacity(0.14))
                    .frame(width: AlarmMetrics.glyphDisc, height: AlarmMetrics.glyphDisc)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.Colors.Ring.sunriseAlarm)
            }
            .accessibilityHidden(true)

            Text(Copy.alarmRinging.squadPromptLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            // `.holdToCommit` (2s, `PrimaryButton`'s own built-in variant) — an honesty-based
            // confirmation so a reflexive half-asleep tap can't accidentally confirm "I'm up".
            PrimaryButton(title: Copy.alarmRinging.squadConfirmButtonLabel, style: .holdToCommit) {
                dismissViaSquad()
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            content()
            if let dismissError {
                Text(dismissError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .zanoCard(radius: Theme.Radius.large)
    }

    // MARK: - Snooze (spec §5.10: "1 snooze max (5 min), or it breaks the morning goal")

    @ViewBuilder
    private var snoozeControl: some View {
        if manager.snoozesRemainingToday > 0 {
            Button {
                snooze()
            } label: {
                Label(
                    Copy.alarmRinging.snoozeButtonLabel(remaining: manager.snoozesRemainingToday),
                    systemImage: "zzz"
                )
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: AlarmMetrics.minTapTarget)
                .background(Theme.Colors.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
            }
            .buttonStyle(AlarmPressStyle())
        } else {
            Text(Copy.alarmRinging.snoozeUsedLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Escape hatch (spec §5.10 point 6, §24 — see file header for the toggle+hold design)

    private var escapeDock: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // The toggle changes what completing the hold means, so it sits *above* the control it
            // configures (docs/design/better-layout-findings.md 1.10).
            Toggle(Copy.alarmRinging.imNotHomeToggleLabel, isOn: $isNotHome)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .tint(Theme.Colors.warning)
                .frame(minHeight: AlarmMetrics.minTapTarget)

            escapeHatchHoldControl

            Text(Copy.alarmRinging.escapeHatchHoldHint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let escapeError {
                Text(escapeError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            Theme.Colors.background.opacity(0.94)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.Colors.hairline)
                        .frame(height: Theme.Metrics.edgeWidth)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// A 56pt danger capsule that fills left-to-right as the 60-second hold progresses. Danger, not
    /// accent: accent means "earned", and this exit costs the morning goal. The label is drawn
    /// twice — light underneath, dark on top masked to the fill's width — so each glyph flips
    /// colour exactly where the fill crosses it and never sits light-on-red (3.1:1) mid-hold.
    private var escapeHatchHoldControl: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Colors.surface)

            GeometryReader { proxy in
                Rectangle()
                    .fill(Theme.Colors.danger)
                    .frame(width: proxy.size.width * holdProgress)
            }

            escapeHatchBarLabel(foreground: Theme.Colors.text)

            escapeHatchBarLabel(foreground: Theme.Colors.onFill)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * holdProgress)
                    }
                }
        }
        .frame(height: AlarmMetrics.holdBarHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.danger.opacity(isHoldingEscapeHatch ? 0 : 0.5), lineWidth: 1.5)
        )
        .scaleEffect(isHoldingEscapeHatch ? 0.98 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginEscapeHatchHold() }
                .onEnded { _ in endEscapeHatchHold() }
        )
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard, value: isHoldingEscapeHatch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.alarmRinging.escapeHatchHoldLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Copy.alarmRinging.escapeHatchHoldHint)
        // VoiceOver's double-tap activates this accessibility action rather than driving the
        // `DragGesture` above — a sustained physical hold has no VoiceOver equivalent. Without
        // this, a VoiceOver user could not fire the escape hatch at all: a raw `DragGesture` does
        // not respond to double-tap activation, and `.isButton` alone adds no activation path.
        // This is the one control spec §5.10 point 6 / CLAUDE.md's "no one gets trapped" guarantee
        // most depends on, so it fires immediately on activation rather than requiring VoiceOver
        // users to somehow sustain a touch-and-hold — exactly mirroring
        // `PrimaryButton.holdToCommit`'s identical, already-shipped fix (see that file's own
        // comment on `.accessibilityAction`). See `docs/design/ui-stress-test-findings.md` §1.1.
        .accessibilityAction {
            guard !isHoldingEscapeHatch else { return }
            escapeHapticTick += 1
            Task { await completeEscapeHatchHold() }
        }
    }

    /// One layer of the hold bar's label. Called twice with different foregrounds (see
    /// `escapeHatchHoldControl`), so both layers must lay out identically.
    private func escapeHatchBarLabel(foreground: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))

            Text(
                isHoldingEscapeHatch
                    ? SunriseAlarmCopy.escapeHatchHolding(secondsRemaining: escapeHatchRemainingSeconds)
                    : Copy.alarmRinging.escapeHatchSectionLabel
            )
            .font(Theme.Typography.headline)
            .lineLimit(1)

            Spacer(minLength: Theme.Spacing.sm)

            if !isHoldingEscapeHatch {
                Text(escapeHatchSecondsLabel)
                    .font(Theme.Typography.numeralSmall())
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
    }

    private var escapeHatchRemainingSeconds: Int {
        Int((EmergencyUnlock.holdDuration * (1 - holdProgress)).rounded(.up))
    }

    private var escapeHatchSecondsLabel: String {
        "\(escapeHatchRemainingSeconds)s"
    }

    // MARK: - Clock / pulse loops

    private func tickClock() async {
        while !Task.isCancelled {
            now = .now
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Drives both the background glow pulse and, past the `.waking` phase, a matching haptic tick
    /// — spec §5.10 point 1: "escalating sound/haptics." The alarm's actual siren-style audio
    /// while the app may not even be foregrounded is `SunriseAlarmManager`'s job (AlarmKit or a
    /// looping local-notification sound, per §5.10's Technical path), not this view's; this loop
    /// only covers the escalating feel while this screen itself is on screen.
    private func runPulseLoop() async {
        while !Task.isCancelled {
            // `nil`, not a zero-duration animation, under Reduce Motion — same idiom as
            // `Theme.Motion.standard(reduceMotion:)`: fully disables implicit animation for this
            // toggle rather than still running the animation machinery for no visible benefit.
            // `isPulsing` itself still flips (the glow's `.opacity` reads `reduceMotion` directly
            // and ignores this value anyway — see `sunriseGlow` — but other call sites, and a future
            // reader of this state, shouldn't have to know that), and the haptic tick below is
            // unconditional either way.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: phase.pulseDuration)) {
                isPulsing.toggle()
            }
            if phase != .waking {
                pulseHapticTick += 1
            }
            try? await Task.sleep(for: .seconds(phase.pulseDuration))
        }
    }

    // MARK: - Load

    private func loadDismissVariant() async {
        guard !isSettingsLoaded else { return }
        let settings = await manager.currentSettings()
        dismissVariant = settings.dismissVariant
        stepsTarget = settings.stepsTarget
        isSettingsLoaded = true
    }

    // MARK: - Dismiss actions

    /// Runs one dismiss path exactly once per screen presentation (`didDismiss` guard) — the
    /// Steps variant in particular can otherwise re-fire its `.task(id:)` on every subsequent step
    /// tick after the target is already reached, and this keeps every variant's success/failure
    /// handling in one place instead of four near-duplicate `do`/`catch` blocks.
    private func performDismiss(_ action: @escaping () async throws -> Void) async {
        guard !didDismiss else { return }
        didDismiss = true
        dismissError = nil
        do {
            try await action()
        } catch {
            didDismiss = false
            dismissError = error.localizedDescription
        }
    }

    /// The Tag variant's two-step handshake — see file header. Also covers a tag that hasn't been
    /// mapped yet: rather than send a groggy, already-late user to a settings screen mid-ring, a
    /// first-ever scan of *any* unmapped tag from this screen registers it as the Sunrise Tag on
    /// the spot (reusing `Copy.sunriseAlarm.defaultTagLabel`, the same default `SunriseAlarmSetupView`
    /// uses) and immediately proceeds.
    private func scanTagAndDismiss() {
        guard !isScanningTag else { return }
        isScanningTag = true
        dismissError = nil
        Task {
            do {
                let outcome = try await NFCTagMapper.shared.scanAndHandle(
                    alertMessage: Copy.alarmRinging.tagScanAlertMessage,
                    noMatchMessage: Copy.alarmRinging.tagScanNoMatchMessage
                )
                isScanningTag = false
                switch outcome {
                case .handled(let action, let tagID):
                    guard case .sunriseKey = action else {
                        dismissError = Copy.alarmRinging.wrongTagErrorText
                        return
                    }
                    await performDismiss { try await manager.dismissViaTag(tagID: tagID) }

                case .unmapped(let tagID):
                    let mapping = NFCTagMapping(
                        id: tagID,
                        kind: .sunrise,
                        label: Copy.sunriseAlarm.defaultTagLabel,
                        action: .sunriseKey
                    )
                    await NFCTagMapper.shared.saveMapping(mapping)
                    await performDismiss { try await manager.dismissViaTag(tagID: tagID) }
                }
            } catch NFCReaderFailure.cancelled {
                isScanningTag = false
            } catch {
                isScanningTag = false
                dismissError = error.localizedDescription
            }
        }
    }

    private func startFocusCountdown() {
        guard !isFocusRunning else { return }
        isFocusRunning = true
        focusTask?.cancel()
        focusTask = Task {
            while focusSecondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                focusSecondsRemaining -= 1
            }
            guard !Task.isCancelled else { return }
            await performDismiss { try await manager.dismissViaFocusCompletion() }
        }
    }

    private func dismissViaSquad() {
        Task {
            await performDismiss { try await manager.dismissViaSquadConfirmation() }
        }
    }

    private func snooze() {
        Task {
            do {
                _ = try await manager.snooze()
            } catch {
                dismissError = error.localizedDescription
            }
        }
    }

    // MARK: - Escape hatch hold (mirrors `PrimaryButton`'s internal `.holdToCommit` mechanics,
    // this screen's own 60s duration — see file header)

    private func beginEscapeHatchHold() {
        guard !isHoldingEscapeHatch else { return }
        isHoldingEscapeHatch = true
        holdProgress = 0
        escapeError = nil

        let totalMs = max(1, Int(EmergencyUnlock.holdDuration * 1000))
        let tickMs = 100

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            var elapsedMs = 0
            var lastDecile = 0
            while elapsedMs < totalMs {
                try? await Task.sleep(for: .milliseconds(tickMs))
                if Task.isCancelled { return }
                elapsedMs += tickMs
                let progress = min(1, Double(elapsedMs) / Double(totalMs))
                holdProgress = progress
                let decile = Int(progress * 10)
                if decile != lastDecile {
                    lastDecile = decile
                    escapeHapticTick += 1
                }
            }
            guard !Task.isCancelled else { return }
            await completeEscapeHatchHold()
        }
    }

    private func endEscapeHatchHold() {
        guard isHoldingEscapeHatch, holdProgress < 1 else { return }
        holdTask?.cancel()
        holdTask = nil
        isHoldingEscapeHatch = false
        // Previously ungated — mirrors `PrimaryButton.endHold()`'s identical cancel-spring, which
        // already guards this exact reset with `reduceMotion`. See
        // `docs/design/ui-stress-test-findings.md` §2.5.
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
            holdProgress = 0
        }
    }

    private func completeEscapeHatchHold() async {
        isHoldingEscapeHatch = false
        do {
            try await manager.triggerEscapeHatch(reason: isNotHome ? .imNotHome : .other)
        } catch {
            escapeError = error.localizedDescription
            // Same gate as `endEscapeHatchHold()` above — see that call's comment.
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
                holdProgress = 0
            }
        }
    }
}

// MARK: - Escalation phase

/// The three visual/haptic escalation stages of an unattended alarm (spec §5.10: "escalating
/// sound/haptics"). Purely a pacing device — no dismiss logic reads this, it only drives how
/// insistent the screen looks/feels the longer it goes unanswered. File-scoped: nothing outside
/// this screen needs it.
private enum RingingPhase: Sendable, Equatable {
    case waking
    case urgent
    case critical

    static func current(elapsed: TimeInterval) -> RingingPhase {
        switch elapsed {
        case ..<20: .waking
        case ..<60: .urgent
        default: .critical
        }
    }

    var tint: Color {
        switch self {
        case .waking: Theme.Colors.Ring.sunriseAlarm
        case .urgent: Theme.Colors.warning
        case .critical: Theme.Colors.danger
        }
    }

    /// The chip's glyph. `Ring.sunriseAlarm` (`#FFD60A`) and `warning` (`#FFB020`) are only 11°
    /// apart, so hue alone cannot separate waking from urgent; the glyph and the label can.
    var symbol: String {
        switch self {
        case .waking: "sunrise.fill"
        case .urgent: "sun.max.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    var pulseDuration: Double {
        switch self {
        case .waking: 1.6
        case .urgent: 0.9
        case .critical: 0.45
        }
    }
}

// MARK: - Local design constants
//
// Sizes specific to this screen's artwork. Edges, hit targets and the card surface are the shared
// ones (review pass: the private `AlarmDepth` edge tokens and `AlarmCardSurface` this file carried
// before `Theme.Colors.hairline` / `zanoCard` existed were removed).

private enum AlarmMetrics {
    /// HIG minimum hit target.
    static let minTapTarget: CGFloat = Theme.Metrics.minTapTarget
    /// Height of the pinned escape-hatch capsule.
    static let holdBarHeight: CGFloat = 56
    /// Reserve for the loading state so the card doesn't pop in from nothing.
    static let loadingHeight: CGFloat = 160
    /// Tag glyph: filled disc, inner ring, outer ring.
    static let glyphDisc: CGFloat = 64
    static let glyphInnerRing: CGFloat = 92
    static let glyphOuterRing: CGFloat = 120
}

// MARK: - Components

/// A `GoalRing` with a real numeral in its centre. `GoalRing`'s own text centre is capped at 28pt;
/// the dismiss task is the thing the user is looking at, so the number is `numeralLarge` (44pt)
/// with an optional muted suffix ("/40"). The ring's own accessibility is replaced by one element
/// that reads the task and its live value, so VoiceOver still hears "12/40" rather than a bare
/// percentage.
private struct AlarmDial: View {
    let progress: Double
    let color: Color
    let value: String
    let caption: String?
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        ZStack {
            GoalRing(progress: progress, color: color, size: .large)

            VStack(spacing: 0) {
                Text(value)
                    .font(Theme.Typography.numeralLarge())
                    .foregroundStyle(Theme.Colors.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let caption {
                    Text(caption)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(accessibilityValue))
    }
}

/// Press feedback for the alarm's secondary controls (snooze). Same numbers as
/// `PrimaryButton`'s standard press (fast spring, 0.97) and the same Reduce Motion rule: keep the
/// opacity dip (it is real information — "the interface heard you") but drop the scale and settle.
private struct AlarmPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.16, dampingFraction: 0.75),
                value: configuration.isPressed
            )
    }
}

#Preview {
    AlarmRingingView()
        .preferredColorScheme(.dark)
}
