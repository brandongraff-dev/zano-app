// EarnModeSettingsView.swift
// App / Features / LockSetup
//
// docs/spec.md §5.2 Earn Rate ("Screen Time Exchange Rate"): the default lock mode (Full vs Earn),
// the minutes each goal type deposits, and how spending works. The rates are the spec's exact
// values (`TimeBankEarnRates`: gym 90, focus 30, protein 30) and read-only here — the spec fixes
// them, so there's no range to adjust within. Spending itself happens on the Lock tab through
// `TimeBankEngine.spendToUnlock(minutes:)`. Emergency unlock is unaffected by any setting here.

//
// Visual pass 2 (2026-10-03): rounded section titles with (i)s instead of captions, a colour sticker
// per goal rate with the minutes as a mint "+90 min" sticker, and today's bank as a big score
// numeral. The expiry note moved behind the "Spending minutes" (i); the spending sentence and the
// Full-lock note (it says emergency unlock always works) stay visible.

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
                    info: Copy.lockSetup.defaultModeFooter
                ) {
                    LockModePicker(mode: $defaultMode)
                    Text(defaultMode == .earn ? Copy.lockSetup.modeEarnDetail : Copy.lockSetup.modeFullDetail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LockRulesSection(title: Copy.lockSetup.earnRatesLabel, info: Copy.lockSetup.earnRatesFooter) {
                    rateRow(Copy.lockSetup.earnRateGym, systemImage: "dumbbell.fill", tint: Theme.Colors.Ring.workout, minutes: TimeBankEarnRates.gymSessionMinutes)
                    Divider().overlay(Theme.Colors.hairline)
                    rateRow(Copy.lockSetup.earnRateFocus, systemImage: "brain.head.profile", tint: Theme.Colors.Ring.focus, minutes: TimeBankEarnRates.focusBlockMinutes)
                    Divider().overlay(Theme.Colors.hairline)
                    rateRow(Copy.lockSetup.earnRateProtein, systemImage: "fork.knife", tint: Theme.Colors.Ring.protein, minutes: TimeBankEarnRates.proteinMinutes)
                }

                LockRulesSection(
                    title: Copy.lockSetup.spendingLabel,
                    info: Copy.lockSetup.expiryBody
                ) {
                    bankRow
                    explainer(Copy.lockSetup.spendingBody)
                    // Stays visible: it says emergency unlock always works.
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

    /// Today's bank: the minutes as a big score numeral in the earned blue.
    private var bankRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Copy.lockSetup.todayBankLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            Text(Copy.lockSetup.todayBankValue(minutes: bankMinutes))
                .font(Theme.Typography.score(size: 24))
                .foregroundStyle(Theme.Colors.accent)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(bankMinutes)))
        }
        .accessibilityElement(children: .combine)
    }

    private func rateRow(_ title: String, systemImage: String, tint: Color, minutes: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SettingsSticker(systemImage: systemImage, tint: tint)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            ZanoSticker(Copy.lockSetup.earnRateValue(minutes: minutes), color: Theme.Colors.Ring.steps, style: .filled, size: .small)
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
