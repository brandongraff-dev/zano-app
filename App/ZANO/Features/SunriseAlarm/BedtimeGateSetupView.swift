// BedtimeGateSetupView.swift
// App / Features / SunriseAlarm
//
// Owned by: this session's task (App/ZANO/Features/SunriseAlarm/*). Do not edit from another
// session — CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §5.10 "★ Bedtime Gate & Sunrise Alarm" — the Bedtime Gate half:
//   "Lock auto-arms at the user's set bedtime; phone becomes a clock.
//    Optional wind-down Live Activity: 'Bedtime lock in 10 min.'
//    Pickups after bedtime break the Sleep goal (§3) and are shown gently in the morning recap."
//
// This screen owns exactly the bedtime + wind-down-reminder half of the shared
// `SunriseAlarmManager.Settings` row `SunriseAlarmSetupView.swift` (same directory) owns the other
// half of. The two screens never clobber each other: each loads the *whole* current `Settings`
// value, mutates only the fields it renders UI for, and saves the whole value back. The manager is
// real now (`Core/Sources/Core/Verification/SunriseAlarmManager.swift`); copy keys are the real
// `Copy.bedtimeGate.*` (`Core/Sources/Core/Copy/SunriseAlarmScreenCopy.swift`).
//
// "Phone becomes a clock" / the actual DeviceActivity-scheduled shield that "auto-arms at bedtime"
// is `LockEngineManager`'s job (a `LockTrigger.schedule` lock, spec §11) once a bedtime is saved
// here; wiring a recurring nightly schedule to this saved `bedtime` is scheduling work outside a
// single settings screen's scope. This screen's job ends at persisting the user's chosen bedtime +
// wind-down preference.
//
// VISUAL DESIGN (design-quality wave, 2026-09-23). The previous version was a stock `Form`: a
// one-line `DatePicker`, a switch, a caption paragraph, a link row, and a toolbar-only Save that
// gave no feedback (docs/design/composition-audit.md offender 9, better-layout 1.11 / 3.7 / 4.4,
// better-ui DEP-05). It is now the companion of `SunriseAlarmSetupView`: the bedtime is the hero
// (`SleepTimeCard`, shared, 64pt numeral with a tap-to-reveal wheel), the wind-down switch, pickup
// note and wake-alarm link are cards on the same surface, and Save is a pinned button that dismisses
// with a `.success` haptic. The wake-alarm link shows the wake time it leads to, which is a number
// the screen already has and makes the two halves read as one night. The shared building blocks
// (`SleepSetup*`, `SleepTimeCard`) live at the bottom of `SunriseAlarmSetupView.swift`.
//
// Save is disabled until the saved settings have loaded, so an early tap can no longer overwrite the
// saved row with defaults.

import SwiftUI
import Core

/// Bedtime Gate setup: bedtime picker + optional wind-down reminder, with a link through to
/// `SunriseAlarmSetupView` since the two are one feature (spec §5.10) presented as companion
/// screens rather than a single overloaded form.
@MainActor
struct BedtimeGateSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings = SunriseAlarmManager.Settings()
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var saveTick = 0
    @State private var errorAlert: BedtimeGateSetupErrorAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SleepTimeCard(
                    systemImage: "moon.zzz.fill",
                    tint: Theme.Colors.Ring.sleepOnTime,
                    label: Copy.bedtimeGate.bedtimeLabel,
                    time: $settings.bedtime
                )

                windDownSection

                pickupsSection

                wakeAlarmLink
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { Theme.Colors.background.ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SleepSetupSaveBar(
                title: Copy.bedtimeGate.saveButtonLabel,
                isEnabled: isLoaded && !isSaving
            ) {
                save()
            }
        }
        .navigationTitle(Copy.bedtimeGate.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        // No root tint exists yet (that lives in `ZANOApp`), so the wind-down switch, the nav back
        // button and the wheel would otherwise render system blue/green.
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: saveTick)
        .task {
            guard !isLoaded else { return }
            settings = await SunriseAlarmManager.shared.currentSettings()
            isLoaded = true
        }
        .alert(
            errorAlert?.title ?? "",
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { isPresented in if !isPresented { errorAlert = nil } }
            ),
            presenting: errorAlert
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { errorAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1.
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var windDownSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.bedtimeGate.windDownSectionHeader)

            SleepSetupCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Toggle(Copy.bedtimeGate.windDownToggleLabel, isOn: $settings.windDownReminderEnabled)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .frame(minHeight: SleepSetupMetrics.minTapTarget)

                    Text(Copy.bedtimeGate.windDownHelperText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pickupsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.bedtimeGate.pickupsInfoHeader)

            SleepSetupCard {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    SleepSetupIconBadge(systemImage: "moon.stars.fill", tint: Theme.Colors.muted)

                    Text(Copy.bedtimeGate.pickupsInfoText)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The link to the other half of the feature, styled as a card and showing the wake time it
    /// leads to. `chevron.forward` (not `.right`) so it mirrors in right-to-left layouts.
    private var wakeAlarmLink: some View {
        NavigationLink {
            SunriseAlarmSetupView()
        } label: {
            SleepSetupCard {
                HStack(spacing: Theme.Spacing.sm) {
                    SleepSetupIconBadge(systemImage: "alarm.fill", tint: Theme.Colors.Ring.sunriseAlarm)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(Copy.bedtimeGate.wakeAlarmLinkLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        Text(Copy.bedtimeGate.wakeAlarmLinkDetail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(settings.wakeTime, format: .dateTime.hour().minute())
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.text)

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(SleepSetupPressStyle())
    }

    // MARK: - Actions

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await SunriseAlarmManager.shared.saveSettings(settings)
                isSaving = false
                saveTick += 1
                dismiss()
            } catch {
                isSaving = false
                errorAlert = BedtimeGateSetupErrorAlert(
                    title: Copy.bedtimeGate.saveErrorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }
}

/// File-scoped alert payload — mirrors `LockSetupView.swift`'s `LockSetupErrorAlert` and
/// `SunriseAlarmSetupView.swift`'s `SunriseAlarmSetupErrorAlert`.
private struct BedtimeGateSetupErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack {
        BedtimeGateSetupView()
    }
    .preferredColorScheme(.dark)
}
