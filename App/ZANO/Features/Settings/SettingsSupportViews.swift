// SettingsSupportViews.swift
// App / Features / Settings
//
// Two small screens pushed from Settings' "About" group (polish pass 2026-09-24):
//
//   * `HelpFeedbackView` — the support address as selectable text plus a mailto button.
//     `Copy.settings.supportEmail` is a PLACEHOLDER the founder must confirm before release.
//   * `PauseForHealthView` — docs/spec.md §24: 'Include a "pause for health reasons" option and
//     disordered-eating-safe copy.' A real pause now (`Core/Retention/HealthPause.swift`): a toggle,
//     a length (3 days / 1 week / 2 weeks / until I turn it off), the end date, and "Resume now".
//     Starting one releases an active lock with no streak penalty; while paused there are no
//     scheduled locks, no counted misses and no nudges. Calm copy, no guilt. Goals editor and the
//     support contact stay as the other two exits.
//   * `HealthPauseStatusCapsule` — the small "Health pause on" capsule at the top of Settings; it
//     renders nothing when no pause is active and re-renders on any pause write (`@AppStorage` on
//     `SharedDefaults.healthPauseRevisionKey`).
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

    @State private var isPaused = HealthPause.isActive
    @State private var endsAt = HealthPause.endsAt
    @State private var length: HealthPause.Length = .oneWeek
    @State private var isWorking = false

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

                pauseCard
                lengthCard
                whatHappensCard

                VStack(spacing: Theme.Spacing.sm) {
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
        .onAppear(perform: refresh)
    }

    // MARK: Toggle + status

    private var pauseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle(isOn: Binding(get: { isPaused }, set: { setPaused($0) })) {
                Text(Copy.settings.pauseToggleLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
            }
            .disabled(isWorking)
            .frame(minHeight: Theme.Metrics.minTapTarget)

            if isPaused {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.settings.pauseActiveTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(statusLine)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                PrimaryButton(
                    title: Copy.settings.pauseResumeButtonLabel,
                    systemImage: "play.fill",
                    style: .secondary,
                    isEnabled: !isWorking
                ) {
                    setPaused(false)
                }

                Text(Copy.settings.pauseResumeFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var statusLine: String {
        guard let endsAt else { return Copy.settings.pauseActiveOpenEnded }
        return Copy.settings.pauseActiveUntil(PauseDateText.format(endsAt))
    }

    // MARK: Length picker

    private var lengthCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.settings.pauseLengthTitle)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(HealthPause.Length.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack {
                            Text(title(for: option))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text)
                            Spacer()
                            if option == length {
                                Image(systemName: "checkmark")
                                    .font(Theme.Typography.icon(.small))
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityAddTraits(option == length ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

            if isPaused {
                Text(Copy.settings.pauseActiveExtendHint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(for option: HealthPause.Length) -> String {
        switch option {
        case .threeDays: Copy.settings.pauseLengthThreeDays
        case .oneWeek: Copy.settings.pauseLengthOneWeek
        case .twoWeeks: Copy.settings.pauseLengthTwoWeeks
        case .untilTurnedOff: Copy.settings.pauseLengthUntilOff
        }
    }

    // MARK: What a pause does

    private var whatHappensCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.settings.pauseWhatHappensTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            PauseFactRow(systemImage: "lock.open", text: Copy.settings.pauseWhatHappensLocks)
            PauseFactRow(systemImage: "flame", text: Copy.settings.pauseWhatHappensStreak)
            PauseFactRow(systemImage: "bell.slash", text: Copy.settings.pauseWhatHappensNudges)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    // MARK: Actions

    private func refresh() {
        isPaused = HealthPause.isActive
        endsAt = HealthPause.endsAt
    }

    private func choose(_ option: HealthPause.Length) {
        length = option
        // While paused, a new length restarts the pause from now (said so under the picker).
        if isPaused { setPaused(true) }
    }

    private func setPaused(_ on: Bool) {
        guard !isWorking else { return }
        if on {
            isWorking = true
            let days = length.days
            Task {
                await HealthPause.startReleasingActiveLock(days: days)
                refresh()
                isWorking = false
            }
        } else {
            HealthPause.end()
            refresh()
        }
    }
}

/// "Oct 2" style end date, shared by the pause screen and the Settings capsule.
enum PauseDateText {
    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// One line of "while you're paused": a small monochrome glyph and a sentence.
private struct PauseFactRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Settings status capsule

/// Shown at the top of Settings only while a health pause is active; taps through to the pause
/// screen. Renders nothing otherwise.
struct HealthPauseStatusCapsule: View {
    /// Any `HealthPause` write bumps this key, so the capsule appears/disappears immediately.
    @AppStorage(SharedDefaults.healthPauseRevisionKey, store: SharedDefaults.store)
    private var revision = 0

    var body: some View {
        let _ = revision
        if HealthPause.isActive {
            NavigationLink {
                PauseForHealthView()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(Theme.Typography.icon(.small))
                        .accessibilityHidden(true)
                    Text(label)
                        .font(Theme.Typography.captionEmphasized)
                    Image(systemName: "chevron.forward")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.Colors.text)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(minHeight: Theme.Metrics.minTapTarget)
                .zanoGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Copy.settings.pauseStatusCapsuleHint)
        }
    }

    private var label: String {
        guard let endsAt = HealthPause.endsAt else { return Copy.settings.pauseStatusCapsule }
        return Copy.settings.pauseStatusCapsuleUntil(PauseDateText.format(endsAt))
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
