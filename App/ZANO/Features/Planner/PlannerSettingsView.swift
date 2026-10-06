// PlannerSettingsView.swift
// App / ZANO / Features / Planner
//
// Settings > Calendar & reminders (session 27; docs/spec.md §5.30): alerts before calendar events and the
// default for new tasks' reminders. A plain grouped form, like the iOS Settings app.

import SwiftUI
import Core

struct PlannerSettingsView: View {
    @State private var settings = PlannerStore.settings

    var body: some View {
        Form {
            Section {
                Toggle(Copy.planner.eventAlertsToggle, isOn: eventAlertsBinding)
                if settings.eventAlerts {
                    Picker(Copy.planner.leadLabel, selection: leadBinding) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text(Copy.planner.leadOption(minutes)).tag(minutes)
                        }
                    }
                }
            } footer: {
                Text(Copy.planner.eventAlertsFooter)
            }
            Section {
                Toggle(Copy.planner.remindByDefault, isOn: Binding(
                    get: { settings.remindByDefault },
                    set: { settings.remindByDefault = $0; commit() }
                ))
            }
        }
        .navigationTitle(Copy.planner.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Colors.accent)
    }

    private var eventAlertsBinding: Binding<Bool> {
        Binding(
            get: { settings.eventAlerts },
            set: { on in
                settings.eventAlerts = on
                commit()
                if on {
                    Task {
                        _ = await NotificationPermission.requestIfUndetermined()
                        if !PlannerCalendarSource.hasAccess { _ = await FocusLockCalendarSource.shared.requestAccess() }
                        await PlannerReminders.refresh()
                    }
                }
            }
        )
    }

    private var leadBinding: Binding<Int> {
        Binding(
            get: { settings.eventAlertLeadMinutes },
            set: { settings.eventAlertLeadMinutes = $0; commit() }
        )
    }

    private func commit() {
        PlannerStore.settings = settings
        Task { await PlannerReminders.refresh() }
    }
}
