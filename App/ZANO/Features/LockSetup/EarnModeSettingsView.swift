// EarnModeSettingsView.swift
// App / Features / LockSetup
//
// docs/spec.md §5.2 Earn Rate ("Screen Time Exchange Rate"): the default lock mode (Full vs Earn),
// the minutes each goal type deposits, and how spending works. The rates are the spec's exact
// values (`TimeBankEarnRates`: gym 90, focus 30, protein 30) and read-only here — the spec fixes
// them, so there's no range to adjust within. Spending itself happens on the Lock tab through
// `TimeBankEngine.spendToUnlock(minutes:)`. Emergency unlock is unaffected by any setting here.

import SwiftUI
import Core

struct EarnModeSettingsView: View {
    @State private var defaultMode: LockMode = LockPreferences.defaultMode

    private var bankMinutes: Int {
        SharedDefaults.earnedMinutesMirrorIsForToday ? SharedDefaults.earnedMinutesRemainingToday : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                LockRulesSection(
                    title: Copy.lockSetup.defaultModeLabel,
                    footer: Copy.lockSetup.defaultModeFooter
                ) {
                    LockModePicker(mode: $defaultMode)
                    Text(defaultMode == .earn ? Copy.lockSetup.modeEarnDetail : Copy.lockSetup.modeFullDetail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LockRulesSection(title: Copy.lockSetup.earnRatesLabel, footer: Copy.lockSetup.earnRatesFooter) {
                    rateRow(Copy.lockSetup.earnRateGym, systemImage: "dumbbell.fill", minutes: TimeBankEarnRates.gymSessionMinutes)
                    Divider().overlay(Theme.Colors.hairline)
                    rateRow(Copy.lockSetup.earnRateFocus, systemImage: "brain.head.profile", minutes: TimeBankEarnRates.focusBlockMinutes)
                    Divider().overlay(Theme.Colors.hairline)
                    rateRow(Copy.lockSetup.earnRateProtein, systemImage: "fork.knife", minutes: TimeBankEarnRates.proteinMinutes)
                }

                LockRulesSection(title: Copy.lockSetup.spendingLabel) {
                    HStack {
                        Text(Copy.lockSetup.todayBankLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        Spacer()
                        Text(Copy.lockSetup.todayBankValue(minutes: bankMinutes))
                            .font(Theme.Typography.numeralSmall())
                            .foregroundStyle(Theme.Colors.accent)
                            .monospacedDigit()
                    }
                    explainer(Copy.lockSetup.spendingBody)
                    explainer(Copy.lockSetup.expiryBody)
                    explainer(Copy.lockSetup.fullLockNote)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.lockSetup.earnModeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: defaultMode) { _, newValue in
            LockPreferences.defaultMode = newValue
        }
        .tint(Theme.Colors.interactive)
        .preferredColorScheme(.dark)
    }

    private func rateRow(_ title: String, systemImage: String, minutes: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
                .frame(width: Theme.Metrics.iconBadgeSmall)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            Text(Copy.lockSetup.earnRateValue(minutes: minutes))
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
