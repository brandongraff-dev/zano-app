// AlarmOptionsViews.swift
// App / Features / SunriseAlarm
//
// docs/spec.md §5.10 (Sunrise Alarm). The three rows of the iOS Clock app's alarm editor, in the same
// order and the same words: Repeat (> Weekdays), Sound (> Daybreak) and, below, the backup alarm.
// Tapping Repeat or Sound pushes a checkmark list exactly like the Clock app's, and the Sound list
// plays each tone as you pick it. Everything edits the one shared `SunriseAlarmManager.Settings`
// value that `SunriseAlarmSetupView` owns, so Save writes it all in one go.

import SwiftUI
import AVFoundation
import Core

// MARK: - The rows card

/// Repeat, Sound and the backup alarm as one grouped card of rows: label on the left, current value
/// and a chevron on the right.
struct AlarmOptionsCard: View {
    @Binding var settings: SunriseAlarmManager.Settings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SleepSetupCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        RepeatDaysView(days: $settings.repeatDays)
                    } label: {
                        AlarmOptionRow(
                            title: Copy.sunriseAlarm.repeatRowLabel,
                            value: RepeatDays.summary(settings.repeatDays),
                            chevron: "chevron.right"
                        )
                    }
                    .buttonStyle(SleepSetupPressStyle())

                    AlarmOptionDivider()

                    NavigationLink {
                        AlarmSoundView(sound: $settings.sound)
                    } label: {
                        AlarmOptionRow(
                            title: Copy.sunriseAlarm.soundRowLabel,
                            value: Copy.sunriseAlarm.soundName(settings.sound),
                            chevron: "chevron.right"
                        )
                    }
                    .buttonStyle(SleepSetupPressStyle())

                    AlarmOptionDivider()

                    Toggle(isOn: $settings.backupAlarmEnabled) {
                        Text(Copy.sunriseAlarm.backupRowLabel)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                    }
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .sensoryFeedback(.selection, trigger: settings.backupAlarmEnabled)

                    if settings.backupAlarmEnabled {
                        AlarmOptionDivider()

                        Menu {
                            Picker(Copy.sunriseAlarm.backupAfterLabel, selection: $settings.backupMinutes) {
                                ForEach(SunriseAlarmManager.Settings.backupMinuteOptions, id: \.self) { minutes in
                                    Text(Copy.sunriseAlarm.backupMinutesLabel(minutes)).tag(minutes)
                                }
                            }
                        } label: {
                            AlarmOptionRow(
                                title: Copy.sunriseAlarm.backupAfterLabel,
                                value: Copy.sunriseAlarm.backupMinutesLabel(settings.backupMinutes),
                                chevron: "chevron.up.chevron.down"
                            )
                        }
                        .buttonStyle(SleepSetupPressStyle())
                        .transition(.opacity)
                    }
                }
            }

            Text(Copy.sunriseAlarm.backupFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(Theme.Motion.springStandard, value: settings.backupAlarmEnabled)
    }
}

private struct AlarmOptionRow: View {
    let title: String
    let value: String
    let chevron: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)

            Spacer(minLength: Theme.Spacing.sm)

            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(1)

            Image(systemName: chevron)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Theme.Metrics.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct AlarmOptionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: Theme.Metrics.edgeWidth)
    }
}

// MARK: - Repeat

/// "Every Sunday" ... "Every Saturday" with a checkmark on each selected day, like the Clock app's
/// Repeat screen. Nothing checked means the alarm rings once and turns itself off.
struct RepeatDaysView: View {
    @Binding var days: Set<Int>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SleepSetupCard {
                    VStack(spacing: 0) {
                        ForEach(Array(RepeatDays.orderedWeekdays().enumerated()), id: \.element) { index, weekday in
                            if index > 0 { AlarmOptionDivider() }
                            Button {
                                toggle(weekday)
                            } label: {
                                HStack {
                                    Text(RepeatDays.rowTitle(weekday: weekday))
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.text)
                                    Spacer(minLength: Theme.Spacing.sm)
                                    if days.contains(weekday) {
                                        Image(systemName: "checkmark")
                                            .font(Theme.Typography.icon(.small, weight: .bold))
                                            .foregroundStyle(Theme.Colors.interactive)
                                            .transition(.opacity)
                                    }
                                }
                                .frame(minHeight: Theme.Metrics.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepSetupPressStyle())
                            .accessibilityAddTraits(days.contains(weekday) ? .isSelected : [])
                        }
                    }
                }

                Text(days.isEmpty ? Copy.sunriseAlarm.repeatFooterOnce : Copy.sunriseAlarm.repeatFooterRepeating)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .zanoBackdrop(glow: Theme.Colors.Ring.sunriseAlarm, intensity: 0.16)
        .navigationTitle(Copy.sunriseAlarm.repeatScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Colors.interactive)
        .sensoryFeedback(.selection, trigger: days)
    }

    private func toggle(_ weekday: Int) {
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
    }
}

// MARK: - Sound

/// The wake-up sounds as a checkmark list. Picking one plays a few seconds of it, so you hear what
/// you are choosing.
struct AlarmSoundView: View {
    @Binding var sound: AlarmSoundChoice
    @State private var preview = AlarmSoundPreviewPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.sunriseAlarm.soundSectionHeader)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)

                SleepSetupCard {
                    VStack(spacing: 0) {
                        ForEach(Array(AlarmSoundChoice.allCases.enumerated()), id: \.element) { index, choice in
                            if index > 0 { AlarmOptionDivider() }
                            Button {
                                sound = choice
                                preview.play(choice)
                            } label: {
                                HStack {
                                    Text(Copy.sunriseAlarm.soundName(choice))
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.text)
                                    Spacer(minLength: Theme.Spacing.sm)
                                    if sound == choice {
                                        Image(systemName: "checkmark")
                                            .font(Theme.Typography.icon(.small, weight: .bold))
                                            .foregroundStyle(Theme.Colors.interactive)
                                    }
                                }
                                .frame(minHeight: Theme.Metrics.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepSetupPressStyle())
                            .accessibilityAddTraits(sound == choice ? .isSelected : [])
                        }
                    }
                }

                Text(Copy.sunriseAlarm.soundFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .zanoBackdrop(glow: Theme.Colors.Ring.sunriseAlarm, intensity: 0.16)
        .navigationTitle(Copy.sunriseAlarm.soundScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Colors.interactive)
        .sensoryFeedback(.selection, trigger: sound)
        .onDisappear { preview.stop() }
    }
}

/// Plays a few seconds of a bundled alarm tone for the Sound list. Starts part-way in, where the
/// tone has risen from its soft start, so the preview is representative.
@MainActor
final class AlarmSoundPreviewPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ sound: AlarmSoundChoice) {
        stop()
        guard let url = Bundle.main.url(forResource: sound.resourceName, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.currentTime = 6
        player.play()
        self.player = player
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
    }
}

#Preview("Repeat") {
    NavigationStack { RepeatDaysView(days: .constant(RepeatDays.weekdays)) }
        .preferredColorScheme(.dark)
}

#Preview("Sound") {
    NavigationStack { AlarmSoundView(sound: .constant(.daybreak)) }
        .preferredColorScheme(.dark)
}
