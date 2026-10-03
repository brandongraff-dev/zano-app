// AutoFocusGuideView.swift
// App / Features / Settings
//
// docs/spec.md §5.12 Auto-Focus Integration: "When a lock starts, optionally trigger an iOS Focus
// mode via Shortcuts automation so notifications from blocked apps also stop. One-tap setup
// guide." Wave 3L.
//
// All content comes from `AutoFocusSetupInstructions` (Core/Copy); this view only lays it out:
// explainer → numbered steps (pick a Focus → Shortcuts automation on "ZANO Is Opened" → Set Focus
// → Ask Before Running off) → "Open Shortcuts" → "Test it" → "I've set it up"
// (`AutoFocusIntegration.recordSetupCompleted`, an honest self-report: Apple gives apps no way to
// see a user's automations) → NFC add-on, turning it off, limits, troubleshooting.
//
// "Test it": the automation's trigger is "ZANO Is Opened", not a ZANO App Intent, so there is no
// intent to run from here. The honest test is to reopen ZANO; the card says how.
//
// Emergency unlock is untouched: Focus only changes notifications (the limits section says so).
//
// Visual pass 2 (2026-10-03): the long explainer paragraph moved behind an (i) beside the headline
// (the headline says what this is; the steps say how). Step numbers are focus-violet stickers. The
// four reference cards (NFC, turning it off, limits, troubleshooting) fold shut by default
// (`DisclosureGroup`, so VoiceOver gets expanded/collapsed for free), each with a colour sticker.

import SwiftUI
import Core

struct AutoFocusGuideView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSetUp = AutoFocusIntegration.isSetUp
    @State private var doneTick = 0

    /// The Shortcuts app's URL scheme. UNVERIFIED on device: `shortcuts://` is the widely used
    /// scheme but isn't in Apple's documentation; if it fails, `openURL` simply does nothing and
    /// step 2 still says where to go.
    private static let shortcutsURL = URL(string: "shortcuts://")

    private var steps: [AutoFocusSetupInstructions.Step] { AutoFocusSetupInstructions.steps }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                stepsSection
                actions
                AutoFocusFoldCard(title: Copy.settings.autoFocusNFCTitle, systemImage: "wave.3.right", tint: SettingsPalette.tags, paragraphs: [AutoFocusSetupInstructions.nfcTagAddOn])
                AutoFocusFoldCard(title: Copy.settings.autoFocusTurnOffTitle, systemImage: "moon.fill", tint: SettingsPalette.sleep, paragraphs: [AutoFocusSetupInstructions.turnOffExplainer])
                AutoFocusFoldCard(title: Copy.settings.autoFocusLimitsTitle, systemImage: "info", tint: SettingsPalette.sunrise, paragraphs: AutoFocusSetupInstructions.limits)
                AutoFocusFoldCard(title: Copy.settings.autoFocusTroubleshootingTitle, systemImage: "wrench.and.screwdriver.fill", tint: SettingsPalette.gear, paragraphs: AutoFocusSetupInstructions.troubleshooting)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSetUp)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.settings.autoFocusScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: doneTick)
        .onAppear { Analytics.shared.capture(event: "auto_focus_guide_viewed", properties: ["is_set_up": isSetUp]) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isSetUp {
                ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.settings.autoFocusMarkedDone)
            }
            SettingsSticker(systemImage: "moon.circle.fill", tint: SettingsPalette.focus, baseSize: 44)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                Text(Copy.settings.autoFocusHeadline)
                    .zanoText(.title)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ZanoInfoButton(
                    AutoFocusSetupInstructions.explainer,
                    accessibilityLabel: Copy.settings.sectionInfoLabel(Copy.settings.autoFocusScreenTitle)
                )
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SettingsSectionTitle(title: Copy.settings.autoFocusStepsTitle)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(steps) { step in
                    StepRow(step: step, total: steps.count, isLast: step.id == steps.last?.id)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .zanoCard(radius: Theme.Radius.medium)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let shortcutsURL = Self.shortcutsURL {
                PrimaryButton(title: Copy.settings.autoFocusOpenShortcuts, systemImage: "arrow.up.forward.app", style: .secondary) {
                    Analytics.shared.capture(event: "auto_focus_open_shortcuts")
                    openURL(shortcutsURL)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Label(Copy.settings.autoFocusTestTitle, systemImage: "checkmark.circle")
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(Copy.settings.autoFocusTestBody)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoWell(radius: Theme.Radius.medium)
            .accessibilityElement(children: .combine)

            if isSetUp {
                PrimaryButton(title: Copy.settings.autoFocusRemove, style: .secondary, tint: .neutral) {
                    AutoFocusIntegration.recordSetupRemoved()
                    isSetUp = false
                }
            } else {
                PrimaryButton(title: Copy.settings.autoFocusMarkDone, systemImage: "checkmark") {
                    AutoFocusIntegration.recordSetupCompleted()
                    isSetUp = true
                    doneTick += 1
                    Analytics.shared.capture(event: "auto_focus_marked_set_up")
                }
            }
        }
    }

}

/// One numbered step: a number disc, the title, the detail, and a hairline to the next step.
private struct StepRow: View {
    let step: AutoFocusSetupInstructions.Step
    let total: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(verbatim: "\(step.id)")
                .font(Theme.Typography.score(size: 15, weight: .heavy))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SettingsPalette.focus)
                )
                .rotationEffect(.degrees(step.id.isMultiple(of: 2) ? 3 : -3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(step.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.Colors.hairline).frame(height: 1).padding(.leading, 56)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Copy.settings.autoFocusStepLabel(step.id, of: total)). \(step.title). \(step.detail)")
    }
}

/// A reference card that folds shut: a colour sticker and a title; open, its paragraphs.
private struct AutoFocusFoldCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let paragraphs: [String]

    @State private var isOpen = false

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Theme.Spacing.sm)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                SettingsSticker(systemImage: systemImage, tint: tint)
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
            }
            .frame(minHeight: Theme.Metrics.minTapTarget)
        }
        .tint(Theme.Colors.muted)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
    }
}
