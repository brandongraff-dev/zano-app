// ContextRulesView.swift
// App / ZANO / Features / ContextRules
//
// Settings > Smart unlock rules (session 19; docs/spec.md §5.26): up to three rules, each keeping a
// lock set's apps open on chosen days and hours even while a lock is running. If the person keeps
// ending locks early at about the same time, a card offers a rule for it (they choose the apps; nothing
// changes until they save). Rules only ever open more apps; the emergency unlock is untouched.

import SwiftUI
import SwiftData
import Core

struct ContextRulesView: View {
    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    @Query private var sessions: [LockSession]

    @State private var rules = ContextRuleStore.rules
    @State private var editing: ContextRule?
    @State private var isNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.contextRules.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion, rules.count < ContextRule.maxRules { suggestionCard(suggestion) }

                if rules.isEmpty {
                    Text(Copy.contextRules.emptyState)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rules) { rule in ruleCard(rule) }

                if rules.count < ContextRule.maxRules {
                    PrimaryButton(title: Copy.contextRules.addButton, systemImage: "plus") { startNew(from: nil) }
                } else {
                    Text(Copy.contextRules.maxReached)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }

                Text("\(Copy.contextRules.limitsNote) \(Copy.contextRules.emergencyNote)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.contextRules.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { rule in
            ContextRuleEditor(rule: rule, isNew: isNew, lockSets: lockSets) { saved in
                commit(saved)
            } onDelete: {
                rules.removeAll { $0.id == rule.id }
                ContextRuleScheduler.shared.save(rules)
            }
        }
    }

    // MARK: Pieces

    private func ruleCard(_ rule: ContextRule) -> some View {
        let appsName = lockSets.first { $0.id == rule.lockSetID }?.name ?? Copy.contextRules.appsLabel
        return Button {
            isNew = false
            editing = rule
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(rule.name.isEmpty ? Copy.contextRules.namePlaceholder : rule.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.contextRules.summary(rule, appsName: appsName))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(rule.isEnabled ? Theme.Colors.textSecondary : Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .zanoCard()
        }
        .buttonStyle(.pressable(scale: 0.98))
    }

    private func suggestionCard(_ suggestion: ContextRuleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.contextRules.suggestionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.contextRules.suggestionBody(suggestion))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: Copy.contextRules.suggestionYes) { startNew(from: suggestion) }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    // MARK: State

    /// Emergency unlocks from the last six weeks, newest pattern first.
    private var suggestion: ContextRuleSuggestion? {
        let times = sessions.filter { $0.unlockKind == .emergency }.compactMap(\.endedAt)
        return ContextRuleSuggester.suggestion(emergencyUnlockTimes: times, now: .now)
    }

    private func startNew(from suggestion: ContextRuleSuggestion?) {
        guard let firstSet = lockSets.first else {
            editing = ContextRule(name: "", lockSetID: UUID())
            isNew = true
            return
        }
        var rule = ContextRule(name: "", lockSetID: firstSet.id)
        if let suggestion {
            rule.weekdays = [suggestion.weekday]
            rule.startMinuteOfDay = suggestion.startMinuteOfDay
            rule.endMinuteOfDay = suggestion.endMinuteOfDay
        }
        isNew = true
        editing = rule
    }

    private func commit(_ saved: ContextRule) {
        if let index = rules.firstIndex(where: { $0.id == saved.id }) {
            rules[index] = saved
        } else if rules.count < ContextRule.maxRules {
            rules.append(saved)
        }
        ContextRuleScheduler.shared.save(rules)
        rules = ContextRuleStore.rules
    }
}

/// Edits one rule: a name, which lock set's apps stay open, the days, and the hours.
private struct ContextRuleEditor: View {
    @State var rule: ContextRule
    let isNew: Bool
    let lockSets: [LockSet]
    let onSave: (ContextRule) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var start: Binding<Date> { timeBinding(\.startMinuteOfDay) }
    private var end: Binding<Date> { timeBinding(\.endMinuteOfDay) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.contextRules.namePlaceholder, text: $rule.name)
                    Toggle(Copy.contextRules.enabledLabel, isOn: $rule.isEnabled)
                }
                Section(Copy.contextRules.appsLabel) {
                    if lockSets.isEmpty {
                        Text(Copy.contextRules.noLockSets)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    } else {
                        Picker(Copy.contextRules.appsLabel, selection: $rule.lockSetID) {
                            ForEach(lockSets, id: \.id) { set in Text(set.name).tag(set.id) }
                        }
                    }
                }
                Section(Copy.contextRules.daysLabel) {
                    dayChips
                    if rule.weekdays.isEmpty {
                        Text(Copy.contextRules.invalidDays).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.danger)
                    }
                }
                Section {
                    DatePicker(Copy.contextRules.fromLabel, selection: start, displayedComponents: .hourAndMinute)
                    DatePicker(Copy.contextRules.toLabel, selection: end, displayedComponents: .hourAndMinute)
                    if rule.endMinuteOfDay - rule.startMinuteOfDay < ContextRule.minimumWindowMinutes {
                        Text(Copy.contextRules.invalidTimes).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.danger)
                    }
                }
                if !isNew {
                    Section {
                        Button(Copy.contextRules.deleteButton, role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? Copy.contextRules.editorTitleNew : Copy.contextRules.editorTitleEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.contextRules.cancelButton) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.contextRules.saveButton) {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(!rule.isValid || (lockSets.isEmpty))
                }
            }
        }
    }

    private var dayChips: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(1...7, id: \.self) { day in
                let on = rule.weekdays.contains(day)
                Button {
                    if on { rule.weekdays.remove(day) } else { rule.weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(Theme.Typography.captionEmphasized)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(on ? Theme.BuddyColors.onSignature : Theme.Colors.text)
                        .background(Circle().fill(on ? Theme.Colors.accentFill : Theme.Colors.glassFill))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<ContextRule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = rule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                rule[keyPath: keyPath] = LockSchedule.minuteOfDayForUI(date)
            }
        )
    }
}

#Preview {
    NavigationStack { ContextRulesView() }
        .preferredColorScheme(.dark)
}
