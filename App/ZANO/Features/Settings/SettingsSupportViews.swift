// SettingsSupportViews.swift
// App / Features / Settings
//
// Two small screens pushed from Settings' "About" group (polish pass 2026-09-24):
//
//   * `HelpFeedbackView` — the support address as selectable text plus a mailto button.
//     `Copy.settings.supportEmail` is a PLACEHOLDER the founder must confirm before release.
//   * `PauseForHealthView` — docs/spec.md §24: 'Include a "pause for health reasons" option and
//     disordered-eating-safe copy.' Core has NO pause mechanism yet (no flag that suspends
//     goal-gated locks or streak decay), so this screen does not pretend to pause anything. It says
//     plainly that health comes first and routes to the three real exits that exist today: the
//     Lock tab (emergency unlock), the goals editor (lower or remove a goal), and support.
//     Follow-up: a real pause (a `SharedDefaults` "paused until" date honoured by the lock engine
//     and streak decay) belongs in Core first.
//
// All copy is `Copy.settings.*`. Monochrome, glass rows; one blue fill per screen.

import SwiftUI
import Core

// MARK: - Help & feedback

struct HelpFeedbackView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.settings.helpMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.settings.helpEmailLabel)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                    // Selectable so it can be copied into any mail app, not just the default one.
                    Text(Copy.settings.supportEmail)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .textSelection(.enabled)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                PrimaryButton(
                    title: Copy.settings.helpEmailButtonLabel,
                    systemImage: "envelope"
                ) {
                    openURL(SettingsReferenceData.supportMailURL)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.helpTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pause for health reasons (spec §24)

struct PauseForHealthView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Copy.settings.pauseHeadline)
                        .zanoText(.title)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.settings.pauseMessage)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    PauseOptionCard(
                        systemImage: "lock.open",
                        title: Copy.settings.pauseStopLockTitle,
                        message: Copy.settings.pauseStopLockMessage
                    ) {
                        Button(Copy.settings.pauseStopLockButtonLabel) {
                            AppRouter.shared.selectedTab = .lock
                        }
                        .buttonStyle(PauseLinkButtonStyle())
                    }

                    PauseOptionCard(
                        systemImage: "slider.horizontal.3",
                        title: Copy.settings.pauseEditGoalsTitle,
                        message: Copy.settings.pauseEditGoalsMessage
                    ) {
                        NavigationLink(Copy.settings.pauseEditGoalsButtonLabel) {
                            GoalsEditorView()
                        }
                        .buttonStyle(PauseLinkButtonStyle())
                    }

                    PauseOptionCard(
                        systemImage: "envelope",
                        title: Copy.settings.pauseContactTitle,
                        message: Copy.settings.pauseContactMessage
                    ) {
                        Button(Copy.settings.pauseContactButtonLabel) {
                            openURL(SettingsReferenceData.supportMailURL)
                        }
                        .buttonStyle(PauseLinkButtonStyle())
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.pauseTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One exit: a monochrome glyph, a title, one line of explanation, and its action.
private struct PauseOptionCard<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                .background(Theme.Colors.surface2, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .padding(.top, Theme.Spacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

/// A text link in the accent (blue as text, never as a fill here), with a 44 pt target.
private struct PauseLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.accent)
            .frame(minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
