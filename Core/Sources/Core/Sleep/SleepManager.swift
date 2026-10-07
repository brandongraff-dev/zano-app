// SleepManager.swift
// Core / Sleep
//
// The sleep wind-down's coordinator (docs/spec.md §5.25): fills in last night's record each morning
// (planned bedtime, whether the phone was left alone after bedtime, optionally Apple Health sleep),
// decides when to ask "How rested do you feel?", saves the answer, and offers the learned bedtime
// suggestion. Everything stays on the phone.
//
// Nothing here arms a lock or changes a goal. Applying a suggestion only moves the Bedtime Gate's
// bedtime, and only when the person taps "Use this bedtime".

import Foundation
import os

@MainActor
public final class SleepManager {
    public static let shared = SleepManager()

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "SleepManager")

    /// Mornings, 4:00 to 13:00: when "How rested do you feel?" is asked.
    static let askFromHour = 4
    static let askUntilHour = 13

    private init() {}

    // MARK: Night ids

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// The evening a morning's night began: before noon it is the day before, otherwise today.
    public static func nightID(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let evening = hour < 12 ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date) : date
        return dayFormatter.string(from: evening)
    }

    /// Whether `date` is a time to ask about last night.
    public static func isAskingTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        (askFromHour..<askUntilHour).contains(calendar.component(.hour, from: date))
    }

    // MARK: Recording

    /// Fills in last night's record on a morning foreground. Cheap and safe to call every foreground.
    public func recordLastNight(now: Date = .now) async {
        let settings = SleepStore.settings
        guard settings.checkInEnabled, Self.isAskingTime(now) else { return }
        let id = Self.nightID(for: now)
        var night = await existingOrNewNight(id: id)

        if night.keptWindDown == nil, let evening = Self.dayFormatter.date(from: id) {
            let bedtime = Calendar.current.date(
                bySettingHour: night.plannedBedtimeMinute / 60, minute: night.plannedBedtimeMinute % 60, second: 0, of: evening
            ) ?? evening
            if let pickedUp = BedtimeGateManager.shared.pickedUpAfterBedtime(nightStarting: bedtime) {
                night.keptWindDown = !pickedUp
            }
        }
        if settings.useHealth, night.sleepMinutes == nil,
           let reading = await SleepHealthReader.lastNight(endingAt: now) {
            night.sleepMinutes = reading.asleepMinutes
            night.asleepMinute = reading.onsetMinuteOfDay
        }
        SleepStore.upsert(night)
    }

    /// The stored record for `id`, or a fresh one planned at the current bedtime.
    private func existingOrNewNight(id: String) async -> SleepNight {
        if let existing = SleepStore.night(id: id) { return existing }
        return SleepNight(id: id, plannedBedtimeMinute: await plannedBedtimeMinute())
    }

    private func plannedBedtimeMinute() async -> Int {
        let bedtime = await SunriseAlarmManager.shared.currentSettings().bedtime
        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        return (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
    }

    // MARK: Asking

    /// `true` when the check-in is on, it is morning, and last night has no answer or skip yet.
    public func needsCheckIn(now: Date = .now) -> Bool {
        guard SleepStore.settings.checkInEnabled, Self.isAskingTime(now) else { return false }
        let id = Self.nightID(for: now)
        if SleepStore.skippedCheckInNight == id { return false }
        return SleepStore.night(id: id)?.rating == nil
    }

    /// Saves the morning answer (1...5) for last night.
    public func submitRating(_ rating: Int, now: Date = .now) async {
        guard (1...5).contains(rating) else { return }
        let id = Self.nightID(for: now)
        var night = await existingOrNewNight(id: id)
        night.rating = rating
        SleepStore.upsert(night)
    }

    public func skipCheckIn(now: Date = .now) {
        SleepStore.skippedCheckInNight = Self.nightID(for: now)
    }

    // MARK: Learning

    public var ratedNightCount: Int { SleepInsightsEngine.rated(SleepStore.nights).count }
    public var insights: [SleepInsight] { SleepInsightsEngine.insights(from: SleepStore.nights) }
    public var isRoughStretch: Bool { SleepInsightsEngine.isRoughStretch(SleepStore.nights) }

    /// A slightly earlier bedtime, if the ratings back one up and it isn't a rough stretch.
    public func bedtimeSuggestion() async -> SleepBedtimeSuggestion? {
        guard !isRoughStretch else { return nil }
        return SleepInsightsEngine.suggestion(from: SleepStore.nights, currentBedtimeMinute: await plannedBedtimeMinute())
    }

    /// Moves the Bedtime Gate's bedtime to `suggestion`. Only called from the person's tap.
    public func apply(_ suggestion: SleepBedtimeSuggestion) async {
        var settings = await SunriseAlarmManager.shared.currentSettings()
        let calendar = Calendar.current
        settings.bedtime = calendar.date(
            bySettingHour: suggestion.bedtimeMinute / 60, minute: suggestion.bedtimeMinute % 60, second: 0, of: settings.bedtime
        ) ?? settings.bedtime
        do {
            try await SunriseAlarmManager.shared.saveSettings(settings)
        } catch {
            logger.error("Applying the bedtime suggestion failed: \(String(describing: error), privacy: .public)")
        }
    }
}
