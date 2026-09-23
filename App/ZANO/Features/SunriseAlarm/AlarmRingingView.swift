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
// list, and the safety copy: "Never promise 'this will always wake you.'"
//
// This is the app's own in-app ringing UI — distinct from whatever system UI AlarmKit itself draws
// (iOS 26+ tier) or the system notification banner (iOS 17–18 fallback tier, spec §5.10's
// Technical path). Assumption, not verified against a Mac (see this task's `knownIssues`): this
// view is shown whenever `SunriseAlarmManager.shared.isRinging` is true — i.e. whenever the app is
// foregrounded during an active alarm, on *either* tier, not only the fallback tier. That's the
// only reading that gives the fallback tier a full-screen UI at all (it has no system alert screen
// of its own) while still being harmless for the AlarmKit tier (an extra, richer in-app surface
// with the snooze/escape-hatch controls this file builds, layered under whatever AlarmKit itself
// presents). Whoever wires the real presentation (App-level scene/notification routing — outside
// this session's three-file scope) should confirm this against AlarmKit's actual current API
// surface before shipping.
//
// CLAUDE.md / spec §5.10 point 6 / §24: "Any lock/alarm feature must always keep an escape hatch —
// never trap the user." Enforced the same way `ShieldPreview.swift` enforces it for the shield
// screen: the escape-hatch controls are unconditional `View` content in this file's `body`, not
// gated behind any variant/settings branch — every dismiss-variant path renders alongside the same
// always-present escape hatch below it, never instead of it.
//
// Reuses `EmergencyUnlock.holdDuration` (`Core/Sources/Core/LockEngine/EmergencyUnlock.swift`,
// public, = 60) as this screen's own hold duration rather than re-declaring the same "60-second
// hold" constant a second time — deliberate: spec §5.10 point 6 and §4's Emergency Unlock are two
// independent 60-second holds (this one dismisses a loud alarm, that one ends an active lock
// session; the alarm's escape hatch does not call `LockEngineManager`/`EmergencyUnlock` itself,
// since silencing a ringing alarm and ending a shielded lock session are different concerns — see
// `SunriseAlarmManager.EscapeReason`/`triggerEscapeHatch` in `SunriseAlarmSetupView.swift`'s
// ASSUMED API block), but there's no reason for them to drift to different durations, so this file
// reads the existing constant instead of hardcoding `60` a second place. This file does not import
// or call anything else from `EmergencyUnlock.swift`.
//
// The "I'm not home" option is built as a toggle next to the 60-second hold, not a separate instant
// bypass button — mirroring `EmergencyUnlock.setAppliesStreakPenalty`'s own "toggle beside the hold
// control changes what completing the hold does" pattern exactly. Rationale: spec's "no one gets
// trapped" guarantee needs the same 60-second friction on every escape path (so the hatch can't be
// casually tapped away while still in bed), while "I'm not home" changes *what* completing that
// hold means (e.g. whether the day's lock still arms) rather than skipping the hold. Flagged as a
// UX decision in this task's `decisions`, not spec-literal text.
//
// See `SunriseAlarmSetupView.swift` (same directory) for the full `SunriseAlarmManager` ASSUMED API
// this file also depends on — not repeated here. This file additionally relies on two already-real
// Core APIs for the Tag variant: `NFCTagMapper.shared.scanAndHandle` (dispatches a scanned tag to
// the real `SunriseKeyIntent`, which records the morning `GoalEvent` and arms the day's lock — spec
// §5.10 step 4) and `NFCReader`. Because `NFCTagMapper` has no idea an alarm is ringing, a
// successful tag scan is a **two-step handshake**: (1) `NFCTagMapper.shared.scanAndHandle` does the
// goal-verification + lock-arming side of "tapping the tag", then (2) this file calls
// `SunriseAlarmManager.shared.dismissViaTag(tagID:)` to do the alarm-specific side (stop the sound/
// haptics/Live Activity, consume the ringing state). Both must fire; see `scanTagAndDismiss()`.
//
// ASSUMED API — `Copy.alarmRinging.*` (Core/Sources/Core/Copy, not this session's file — see
// `SunriseAlarmSetupView.swift`'s header for the full precedent). Keys this file references:
// headline, eyebrowWaking, eyebrowUrgent, eyebrowCritical, tagPromptLabel, tagScanButtonLabel,
// tagScanAlertMessage, tagScanNoMatchMessage, wrongTagErrorText, stepsPromptLabel(target: Int),
// focusPromptLabel, focusStartButtonLabel, squadPromptLabel, squadConfirmButtonLabel,
// snoozeButtonLabel(remaining: Int), snoozeUsedLabel, escapeHatchSectionLabel,
// escapeHatchHoldLabel, escapeHatchHoldHint, imNotHomeToggleLabel, standardAlarmFootnote. Also
// reuses `Copy.sunriseAlarm.defaultTagLabel` from `SunriseAlarmSetupView.swift`'s own list rather
// than assuming a second, duplicate key for the same "default new tag label" string.

import SwiftUI
import Core

/// Full-screen alarm-ringing UI: escalating visual/haptic state, the four dismiss variants (spec
/// §5.10), a "1 left"-style snooze, and the always-present 60-second escape hatch. See the file
/// header for the presentation assumption and the tag-dismiss two-step handshake.
@MainActor
struct AlarmRingingView: View {
    @Environment(\.dismiss) private var dismiss
    /// Gates the background tint pulse (and the pulse-linked spring this used to drive on the
    /// header clock — see `header` below) per this task's hard rule and
    /// `docs/design/animation-opportunities.md`'s Sunrise Alarm section, Part 1 refinement #1: a
    /// full-screen, escalating, strobing background with zero reduced-motion path was the single
    /// highest-stakes instance of that doc's Part 0 systemic gap in the whole safe set. The
    /// escalating *haptic* cadence (`pulseHapticTick`, below) is unaffected by Reduce Motion and
    /// deliberately keeps running unchanged — it should carry more of the urgency signal when
    /// visuals are dialed back, not be silenced too.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // `reduceMotion` holds at 0.22 — the midpoint of the pulsing 0.10...0.32 range — same
            // phase-tint color, same legibility, just held still instead of looping. See
            // `runPulseLoop()` for the matching gate on the animation that drives `isPulsing`.
            phase.tint
                .opacity(reduceMotion ? 0.22 : (isPulsing ? 0.32 : 0.10))
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    variantContent
                    snoozeControl
                    escapeHatchSection
                }
                .padding(Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: .infinity)
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(eyebrowText)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(phase.tint)
                .textCase(.uppercase)

            // `Theme.Typography` has no numeral size larger than `.numeralLarge()` (44pt) — this
            // screen deliberately doesn't invent a bigger one-off size for a "hero clock" moment;
            // see this task's `knownIssues` for flagging that gap for a future Theme pass instead
            // of working around it here.
            Text(now, format: .dateTime.hour().minute())
                .font(Theme.Typography.numeralLarge())
                .foregroundStyle(Theme.Colors.text)

            Text(Copy.alarmRinging.headline)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
        }
        // No `.scaleEffect`/`.animation` on `isPulsing` here anymore — see
        // `docs/design/animation-opportunities.md` Sunrise Alarm Part 1, refinement #2. The clock
        // used to wobble 1.0→1.04 on a `springStandard` spring (~0.4-0.5s settle) while the
        // background tint above pulses on its own `.easeInOut(phase.pulseDuration)` (0.45-1.6s
        // depending on phase) — two different curves keyed off the same `isPulsing` boolean that
        // visibly fell out of phase at the `.critical` cadence (0.45s), reading as an incoherent
        // "double pulse" instead of one coherent escalating beat. The clock is the one piece of
        // information this screen must stay perfectly legible under stress (deciding whether
        // there's time to snooze); color (`phase.tint` on the eyebrow) + the background pulse +
        // the escalating haptics already carry the urgency signal without it.
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
            ProgressView()
        }
    }

    private var tagDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Colors.Ring.sunriseAlarm)

            Text(Copy.alarmRinging.tagPromptLabel)
                .font(Theme.Typography.body)
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
                ProgressView()
            }
        }
    }

    private var stepsDismissContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            GoalRing(
                progress: Double(manager.stepsWalked) / Double(max(1, stepsTarget)),
                color: Theme.Colors.Ring.steps,
                size: .large,
                center: .text("\(min(manager.stepsWalked, stepsTarget))/\(stepsTarget)")
            )
            Text(Copy.alarmRinging.stepsPromptLabel(target: stepsTarget))
                .font(Theme.Typography.body)
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
            GoalRing(
                progress: 1 - (Double(focusSecondsRemaining) / Double(Self.focusDurationSeconds)),
                color: Theme.Colors.Ring.focus,
                size: .large,
                center: .text(formattedFocusTime)
            )
            Text(Copy.alarmRinging.focusPromptLabel)
                .font(Theme.Typography.body)
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
            Image(systemName: "person.3.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)

            Text(Copy.alarmRinging.squadPromptLabel)
                .font(Theme.Typography.body)
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
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
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
                .foregroundStyle(Theme.Colors.muted)
            }
            .buttonStyle(.plain)
        } else {
            Text(Copy.alarmRinging.snoozeUsedLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    // MARK: - Escape hatch (spec §5.10 point 6, §24 — see file header for the toggle+hold design)

    private var escapeHatchSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Rectangle()
                .fill(Theme.Colors.hairline)
                .frame(height: 1)

            Text(Copy.alarmRinging.escapeHatchSectionLabel)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)

            escapeHatchHoldControl

            Toggle(Copy.alarmRinging.imNotHomeToggleLabel, isOn: $isNotHome)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.text)
                .tint(Theme.Colors.warning)
                .frame(maxWidth: 280)

            Text(Copy.alarmRinging.escapeHatchHoldHint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)

            if let escapeError {
                Text(escapeError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }

            Text(Copy.alarmRinging.standardAlarmFootnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.sm)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var escapeHatchHoldControl: some View {
        GoalRing(
            progress: holdProgress,
            color: Theme.Colors.danger,
            size: .large,
            center: .text(escapeHatchSecondsLabel)
        )
        .scaleEffect(isHoldingEscapeHatch ? 0.97 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginEscapeHatchHold() }
                .onEnded { _ in endEscapeHatchHold() }
        )
        .animation(Theme.Motion.springStandard, value: isHoldingEscapeHatch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.alarmRinging.escapeHatchHoldLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var escapeHatchSecondsLabel: String {
        let remaining = Int((EmergencyUnlock.holdDuration * (1 - holdProgress)).rounded(.up))
        return "\(remaining)s"
    }

    // MARK: - Clock / pulse loops

    private func tickClock() async {
        while !Task.isCancelled {
            now = .now
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Drives both the background tint pulse and, past the `.waking` phase, a matching haptic tick
    /// — spec §5.10 point 1: "escalating sound/haptics." The alarm's actual siren-style audio
    /// while the app may not even be foregrounded is `SunriseAlarmManager`'s job (AlarmKit or a
    /// looping local-notification sound, per §5.10's Technical path), not this view's; this loop
    /// only covers the escalating feel while this screen itself is on screen. Flagged in this
    /// task's `knownIssues`.
    private func runPulseLoop() async {
        while !Task.isCancelled {
            // `nil`, not a zero-duration animation, under Reduce Motion — same idiom as
            // `Theme.Motion.standard(reduceMotion:)`: fully disables implicit animation for this
            // toggle rather than still running the animation machinery for no visible benefit.
            // `isPulsing` itself still flips (the tint's `.opacity` reads `reduceMotion` directly
            // and ignores this value anyway — see `body` — but other call sites, and a future
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
    /// uses) and immediately proceeds — see this task's `decisions`.
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
        withAnimation(Theme.Motion.springStandard) {
            holdProgress = 0
        }
    }

    private func completeEscapeHatchHold() async {
        isHoldingEscapeHatch = false
        do {
            try await manager.triggerEscapeHatch(reason: isNotHome ? .imNotHome : .other)
        } catch {
            escapeError = error.localizedDescription
            withAnimation(Theme.Motion.springStandard) {
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

    var pulseDuration: Double {
        switch self {
        case .waking: 1.6
        case .urgent: 0.9
        case .critical: 0.45
        }
    }
}

#Preview {
    AlarmRingingView()
        .preferredColorScheme(.dark)
}
