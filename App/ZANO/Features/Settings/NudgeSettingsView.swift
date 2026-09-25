// NudgeSettingsView.swift
// App / Features / Settings
//
// Settings → Notifications → Nudges. docs/spec.md §8 rule 7 ("Nudge scarcity. Max 2 proactive
// pushes/day"), §9.3 Nudge Optimizer. The user picks: nudges on/off, which kinds (morning plan,
// protein last mile, streak at risk, weekly recap), and quiet hours. The 2/day cap is stated, not
// configurable. Everything persists to `SharedDefaults` through `NudgePreferences.current`, which
// `NudgeSender` reads on every send (it also suppresses everything during a health pause).
//
// All copy is `Copy.settings.nudges*`. Monochrome glass cards; the accent is only the switches.

import SwiftUI
import Core

struct NudgeSettingsView: View {
    @State private var prefs = NudgePreferences.current
    @State private var isHealthPaused = HealthPause.isActive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.settings.nudgesIntro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isHealthPaused {
                    NudgeNote(systemImage: "heart", text: Copy.settings.nudgesPausedNote)
                }

                NudgeCard {
                    NudgeToggleRow(title: Copy.settings.nudgesToggleLabel, isOn: $prefs.enabled)
                }

                NudgeNote(systemImage: "2.circle", text: Copy.settings.nudgesCapNote)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    NudgeSectionHeader(Copy.settings.nudgesTypesSectionTitle)
                    NudgeCard {
                        ForEach(Array(NudgeKind.allCases.enumerated()), id: \.element) { index, kind in
                            if index > 0 { NudgeDivider() }
                            NudgeToggleRow(
                                title: title(for: kind),
                                detail: detail(for: kind),
                                isOn: kindBinding(kind)
                            )
                        }
                    }
                    .disabled(!prefs.enabled)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    NudgeSectionHeader(Copy.settings.nudgesQuietSectionTitle)
                    NudgeCard {
                        NudgeToggleRow(title: Copy.settings.nudgesQuietToggleLabel, isOn: $prefs.quietHoursEnabled)
                        if prefs.quietHoursEnabled {
                            NudgeDivider()
                            NudgeTimeRow(label: Copy.settings.nudgesQuietStartLabel, minutes: $prefs.quietStartMinutes)
                            NudgeDivider()
                            NudgeTimeRow(label: Copy.settings.nudgesQuietEndLabel, minutes: $prefs.quietEndMinutes)
                        }
                    }
                    .disabled(!prefs.enabled)
                    NudgeFooter(Copy.settings.nudgesQuietFooter)
                }

                NudgeFooter(Copy.settings.nudgesSystemFooter)
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.nudgesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prefs = NudgePreferences.current
            isHealthPaused = HealthPause.isActive
        }
        .onChange(of: prefs) { _, newValue in
            NudgePreferences.current = newValue
        }
    }

    private func kindBinding(_ kind: NudgeKind) -> Binding<Bool> {
        Binding(
            get: { prefs.isEnabled(kind) },
            set: { on in
                if on { prefs.disabledKinds.remove(kind) } else { prefs.disabledKinds.insert(kind) }
            }
        )
    }

    private func title(for kind: NudgeKind) -> String {
        switch kind {
        case .morningPlan: Copy.settings.nudgeKindMorningPlanTitle
        case .proteinLastMile: Copy.settings.nudgeKindProteinTitle
        case .streakAtRisk: Copy.settings.nudgeKindStreakTitle
        case .weeklyRecap: Copy.settings.nudgeKindRecapTitle
        }
    }

    private func detail(for kind: NudgeKind) -> String {
        switch kind {
        case .morningPlan: Copy.settings.nudgeKindMorningPlanDetail
        case .proteinLastMile: Copy.settings.nudgeKindProteinDetail
        case .streakAtRisk: Copy.settings.nudgeKindStreakDetail
        case .weeklyRecap: Copy.settings.nudgeKindRecapDetail
        }
    }
}

// MARK: - Pieces

private struct NudgeCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

private struct NudgeToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.minTapTarget)
    }
}

/// A time-of-day row backed by "minutes after local midnight".
private struct NudgeTimeRow: View {
    let label: String
    @Binding var minutes: Int

    private var date: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker(selection: date, displayedComponents: .hourAndMinute) {
            Text(label)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minHeight: Theme.Metrics.minTapTarget)
    }
}

private struct NudgeNote: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

private struct NudgeSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .zanoText(.eyebrow)
            .foregroundStyle(Theme.Colors.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

private struct NudgeFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

private struct NudgeDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}
