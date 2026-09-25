// LockScheduleEditor.swift
// App / Features / LockSetup
//
// docs/spec.md §2 "Lock triggers: Schedule (e.g., 7:00 AM daily)", §4 v1 "Lock via ... daily
// schedule". Per lock set: on/off, days of the week, start time, and an optional end time ("until
// my goals are done" is the default, matching onboarding's plan: "Locks each morning until your
// goals are done"). Persists through `LockScheduler` (Core), which stores the schedule in the App
// Group and registers DeviceActivity windows so `ZANOMonitor` can lock with the app closed.
// Emergency unlock is unaffected: a scheduled lock becomes an ordinary `LockSession`.

import SwiftUI
import Core

struct LockScheduleEditor: View {
    let lockSetID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled = true
    @State private var weekdays: Set<Int> = LockSchedule.allWeekdays
    @State private var start = LockScheduleEditor.time(minuteOfDay: 7 * 60)
    @State private var hasEndTime = false
    @State private var end = LockScheduleEditor.time(minuteOfDay: 9 * 60)
    @State private var mode: LockMode = LockPreferences.defaultMode
    @State private var hasExistingSchedule = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                LockRulesSection(footer: Copy.lockSetup.scheduleEnabledFooter) {
                    Toggle(Copy.lockSetup.scheduleEnabledToggle, isOn: $isEnabled)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                }

                if isEnabled {
                    LockRulesSection(title: Copy.lockSetup.scheduleDaysLabel) {
                        WeekdayChips(selection: $weekdays)
                    }

                    LockRulesSection(
                        footer: hasEndTime ? Copy.lockSetup.scheduleUntilTimeFooter : Copy.lockSetup.scheduleUntilGoalsFooter
                    ) {
                        DatePicker(Copy.lockSetup.scheduleStartLabel, selection: $start, displayedComponents: .hourAndMinute)
                        Divider().overlay(Theme.Colors.hairline)
                        Picker(Copy.lockSetup.scheduleEndLabel, selection: $hasEndTime) {
                            Text(Copy.lockSetup.scheduleUntilGoalsDone).tag(false)
                            Text(Copy.lockSetup.scheduleUntilTime).tag(true)
                        }
                        .pickerStyle(.segmented)
                        if hasEndTime {
                            DatePicker(Copy.lockSetup.scheduleEndTimeLabel, selection: $end, displayedComponents: .hourAndMinute)
                        }
                    }

                    LockRulesSection(
                        title: Copy.lockSetup.scheduleModeLabel,
                        footer: mode == .earn ? Copy.lockSetup.modeEarnDetail : Copy.lockSetup.modeFullDetail
                    ) {
                        LockModePicker(mode: $mode)
                    }

                    Text(Copy.lockSetup.scheduleSkipFooter)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.horizontal, Theme.Spacing.xs)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.warning)
                        .padding(.horizontal, Theme.Spacing.xs)
                }

                if hasExistingSchedule {
                    Button(Copy.lockSetup.scheduleRemoveButton, role: .destructive) {
                        LockScheduler.shared.removeSchedule(for: lockSetID)
                        dismiss()
                    }
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.lockSetup.scheduleTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.lockSetup.saveButtonLabel, action: save)
                    .disabled(isEnabled && validationMessage != nil)
            }
        }
        .onAppear(perform: load)
        .alert(
            Copy.lockSetup.saveErrorTitle,
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(Copy.common.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Model

    private var draft: LockSchedule {
        LockSchedule(
            lockSetID: lockSetID,
            isEnabled: isEnabled,
            weekdays: weekdays,
            startMinuteOfDay: Self.minuteOfDay(start),
            endMinuteOfDay: hasEndTime ? Self.minuteOfDay(end) : nil,
            mode: mode,
            requiredGoalIDs: LockScheduler.shared.schedule(for: lockSetID)?.requiredGoalIDs
        )
    }

    private var validationMessage: String? {
        guard isEnabled else { return nil }
        switch draft.validate() {
        case .none: return nil
        case .noWeekdays: return Copy.lockSetup.scheduleErrorNoDays
        case .windowTooShort, .endOutOfRange: return Copy.lockSetup.scheduleErrorWindow
        case .startOutOfRange: return Copy.lockSetup.scheduleErrorTime
        }
    }

    private func load() {
        guard let saved = LockScheduler.shared.schedule(for: lockSetID) else { return }
        hasExistingSchedule = true
        isEnabled = saved.isEnabled
        weekdays = saved.weekdays
        start = Self.time(minuteOfDay: saved.startMinuteOfDay)
        if let endMinute = saved.endMinuteOfDay {
            hasEndTime = true
            end = Self.time(minuteOfDay: endMinute)
        }
        mode = saved.mode
    }

    private func save() {
        var schedule = draft
        if !isEnabled, let saved = LockScheduler.shared.schedule(for: lockSetID) {
            // Turning it off keeps the rest of the settings for next time.
            schedule = saved
            schedule.isEnabled = false
        }
        do {
            try LockScheduler.shared.save(schedule)
            dismiss()
        } catch LockSchedulerError.invalidSchedule {
            errorMessage = Copy.lockSetup.scheduleErrorWindow
        } catch {
            errorMessage = Copy.lockSetup.scheduleRegistrationFailedMessage
        }
    }

    static func time(minuteOfDay: Int) -> Date {
        Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
    }

    static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: - Summary (used by the lock set editor's rules row)

enum LockScheduleSummary {
    static func text(for schedule: LockSchedule?) -> String {
        guard let schedule, schedule.isEnabled else { return Copy.lockSetup.scheduleRowOff }
        let startText = LockScheduleEditor.time(minuteOfDay: schedule.startMinuteOfDay)
            .formatted(date: .omitted, time: .shortened)
        let endText = schedule.endMinuteOfDay.map {
            LockScheduleEditor.time(minuteOfDay: $0).formatted(date: .omitted, time: .shortened)
        }
        return Copy.lockSetup.scheduleSummary(days: days(schedule.weekdays), start: startText, end: endText)
    }

    private static func days(_ weekdays: Set<Int>) -> String {
        if weekdays == LockSchedule.allWeekdays { return Copy.lockSetup.everyDay }
        if weekdays == [2, 3, 4, 5, 6] { return Copy.lockSetup.weekdaysOnly }
        if weekdays == [1, 7] { return Copy.lockSetup.weekendsOnly }
        let symbols = Calendar.current.shortWeekdaySymbols
        return orderedWeekdays().filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: " ")
    }

    /// Weekdays in the user's locale order (e.g. Monday first).
    static func orderedWeekdays() -> [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

// MARK: - Components (shared by the LockSetup rules screens)

/// A day-of-week chip row, in the user's locale order.
private struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let fullSymbols = Calendar.current.weekdaySymbols
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(LockScheduleSummary.orderedWeekdays(), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isOn ? Theme.Colors.onAccent : Theme.Colors.text)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                        .background(isOn ? Theme.Colors.accent : Theme.Colors.track, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullSymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Full vs Earn, segmented.
struct LockModePicker: View {
    @Binding var mode: LockMode

    var body: some View {
        Picker(Copy.lockSetup.scheduleModeLabel, selection: $mode) {
            Text(Copy.lockSetup.modeFull).tag(LockMode.full)
            Text(Copy.lockSetup.modeEarn).tag(LockMode.earn)
        }
        .pickerStyle(.segmented)
    }
}

/// An eyebrow title, a card of controls, and an optional caption — the rules screens' one layout.
struct LockRulesSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title {
                Text(title)
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                content
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(radius: Theme.Radius.medium)
            if let footer {
                Text(footer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}
