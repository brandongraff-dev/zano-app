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
// `SunriseAlarmManager.Settings` row `SunriseAlarmSetupView.swift` (same directory, same session)
// owns the other half of — see that file's header for the full ASSUMED API this shares. The two
// screens never clobber each other: each loads the *whole* current `Settings` value, mutates only
// the fields it renders UI for, and saves the whole value back — exactly the pattern
// `SunriseAlarmSetupView` documents on its own `save()`.
//
// "Phone becomes a clock" / the actual DeviceActivity-scheduled shield that "auto-arms at
// bedtime" is `LockEngineManager`'s job (a `LockTrigger.schedule` lock, spec §11) once a bedtime is
// saved here — wiring a recurring nightly schedule to this saved `bedtime` is background/scheduling
// work outside a single settings screen's scope (mirrors `LockEngineManager.
// armScheduleMonitoring`'s own doc comment: "the *recurring* daily/weekly schedule... has no model
// yet... a cross-module integration point for a future session"). This screen's job ends at
// persisting the user's chosen bedtime + wind-down preference; see `knownIssues`.
//
// Copy keys this file references (Core/Sources/Core/Copy, not this session's file — see
// `SunriseAlarmSetupView.swift`'s header for the full precedent): `Copy.bedtimeGate.screenTitle`,
// `bedtimeSectionHeader`, `bedtimeLabel`, `windDownSectionHeader`, `windDownToggleLabel`,
// `windDownHelperText`, `pickupsInfoHeader`, `pickupsInfoText`, `wakeAlarmLinkLabel`,
// `wakeAlarmLinkDetail`, `saveButtonLabel`, `saveErrorTitle`. Plus `Copy.common.ok`.

import SwiftUI
import Core

/// Bedtime Gate setup: bedtime picker + optional wind-down reminder, with a link through to
/// `SunriseAlarmSetupView` since the two are one feature (spec §5.10) presented as companion
/// screens rather than a single overloaded form.
@MainActor
struct BedtimeGateSetupView: View {
    @State private var settings = SunriseAlarmManager.Settings()
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var errorAlert: BedtimeGateSetupErrorAlert?

    var body: some View {
        Form {
            Section(Copy.bedtimeGate.bedtimeSectionHeader) {
                DatePicker(
                    Copy.bedtimeGate.bedtimeLabel,
                    selection: $settings.bedtime,
                    displayedComponents: .hourAndMinute
                )
            }

            Section {
                Toggle(Copy.bedtimeGate.windDownToggleLabel, isOn: $settings.windDownReminderEnabled)
            } header: {
                Text(Copy.bedtimeGate.windDownSectionHeader)
            } footer: {
                Text(Copy.bedtimeGate.windDownHelperText)
            }

            Section {
                Text(Copy.bedtimeGate.pickupsInfoText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            } header: {
                Text(Copy.bedtimeGate.pickupsInfoHeader)
            }

            Section {
                NavigationLink {
                    SunriseAlarmSetupView()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(Theme.Colors.Ring.sunriseAlarm)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Copy.bedtimeGate.wakeAlarmLinkLabel)
                                .foregroundStyle(Theme.Colors.text)
                            Text(Copy.bedtimeGate.wakeAlarmLinkDetail)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                    }
                }
            }
        }
        .navigationTitle(Copy.bedtimeGate.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.bedtimeGate.saveButtonLabel) { save() }
                    .disabled(isSaving)
            }
        }
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
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1 and
        // `LockSetupView.swift`'s comment for the full rationale.
        .preferredColorScheme(.dark)
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await SunriseAlarmManager.shared.saveSettings(settings)
                isSaving = false
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
