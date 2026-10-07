// SleepInsightsView.swift
// App / ZANO / Features / Sleep
//
// Settings > Sleep insights (session 18; docs/spec.md §5.25): turn the morning check-in on, optionally
// use Apple Health sleep, see what seems to help (only once there are 10 rated nights, with the
// counts), and take or leave a gentle bedtime suggestion. Patterns, never medical advice; kind during
// a rough stretch; one button deletes it all.

import SwiftUI
import Core

struct SleepInsightsView: View {
    @State private var settings = SleepStore.settings
    @State private var ratedNights = SleepManager.shared.ratedNightCount
    @State private var insights = SleepManager.shared.insights
    @State private var roughStretch = SleepManager.shared.isRoughStretch
    @State private var suggestion: SleepBedtimeSuggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.sleep.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Toggle(Copy.sleep.checkInToggle, isOn: checkInBinding)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    if settings.checkInEnabled {
                        Toggle(isOn: healthBinding) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(Copy.sleep.healthToggle)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.text)
                                Text(Copy.sleep.healthDetail)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.muted)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .zanoCard()

                if settings.checkInEnabled { learningSection }

                Text(Copy.sleep.footer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)

                if ratedNights > 0 {
                    PrimaryButton(title: Copy.sleep.deleteButton, style: .secondary) {
                        SleepStore.resetAll()
                        settings = SleepStore.settings
                        reload()
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.sleep.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.sleep.nightsRated(ratedNights))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            if roughStretch {
                Text(Copy.sleep.roughStretch)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if ratedNights < SleepInsightsEngine.minRatedNights {
                Text(Copy.sleep.needsMoreNights)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                Text(Copy.sleep.insightsTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                if insights.isEmpty {
                    Text(Copy.sleep.noPatternYet)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    Text(Copy.sleep.insightLine(insight))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zanoCard()
                }
                if let suggestion { suggestionCard(suggestion) }
            }
        }
    }

    private func suggestionCard(_ suggestion: SleepBedtimeSuggestion) -> some View {
        let bedtime = Calendar.current.date(
            bySettingHour: suggestion.bedtimeMinute / 60, minute: suggestion.bedtimeMinute % 60, second: 0, of: .now
        ) ?? .now
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.sleep.suggestionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.sleep.suggestionBody(bedtime: bedtime, suggestion: suggestion))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.xs) {
                PrimaryButton(title: Copy.sleep.useBedtimeButton(bedtime: bedtime)) {
                    Task {
                        await SleepManager.shared.apply(suggestion)
                        self.suggestion = nil
                    }
                }
                PrimaryButton(title: Copy.sleep.notNowButton, style: .secondary) { self.suggestion = nil }
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    // MARK: State

    private func reload() {
        ratedNights = SleepManager.shared.ratedNightCount
        insights = SleepManager.shared.insights
        roughStretch = SleepManager.shared.isRoughStretch
        Task { suggestion = await SleepManager.shared.bedtimeSuggestion() }
    }

    private var checkInBinding: Binding<Bool> {
        Binding(
            get: { settings.checkInEnabled },
            set: { value in
                settings.checkInEnabled = value
                if !value { settings.useHealth = false }
                SleepStore.settings = settings
            }
        )
    }

    private var healthBinding: Binding<Bool> {
        Binding(
            get: { settings.useHealth },
            set: { value in
                settings.useHealth = value
                SleepStore.settings = settings
                if value { Task { await SleepHealthReader.requestAccess() } }
            }
        )
    }
}

#Preview {
    NavigationStack { SleepInsightsView() }
        .preferredColorScheme(.dark)
}
