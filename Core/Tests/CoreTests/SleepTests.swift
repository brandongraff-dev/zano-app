// SleepTests.swift
// Core / Tests / CoreTests
//
// Coverage for the sleep wind-down (session 18; docs/spec.md §5.25): the insights engine says nothing
// without enough nights, only reports clear differences, never claims something hurts, suggests at
// most a 30-minute earlier bedtime, and goes quiet during a rough stretch; Health intervals merge;
// night ids and asking times behave. `SleepStore` reads the App Group defaults (no test seam, see
// StoreTests.swift): its test saves and restores real values and the suite is `.serialized`.

import Testing
import Foundation
@testable import Core

@Suite("Sleep wind-down — insights, suggestion, Health merge, storage", .serialized)
struct SleepTests {

    private static func night(
        _ day: Int, bed: Int = 22 * 60 + 30, asleep: Int? = nil, slept: Int? = nil, kept: Bool? = nil, rating: Int? = nil
    ) -> SleepNight {
        SleepNight(id: String(format: "2026-09-%02d", day), plannedBedtimeMinute: bed, asleepMinute: asleep,
                   sleepMinutes: slept, keptWindDown: kept, rating: rating)
    }

    // MARK: Enough data

    @Test func saysNothingUntilTenRatedNights() {
        let nine = (1...9).map { Self.night($0, kept: $0 % 2 == 0, rating: $0 % 2 == 0 ? 5 : 2) }
        #expect(SleepInsightsEngine.insights(from: nine).isEmpty)
        #expect(SleepInsightsEngine.suggestion(from: nine, currentBedtimeMinute: 22 * 60 + 30) == nil)
    }

    @Test func unratedNightsDoNotCount() {
        let nights = (1...20).map { Self.night($0, kept: true, rating: $0 <= 9 ? 4 : nil) }
        #expect(SleepInsightsEngine.rated(nights).count == 9)
        #expect(SleepInsightsEngine.insights(from: nights).isEmpty)
    }

    // MARK: Insights

    @Test func windDownKeptShowsWhenItClearlyHelped() {
        var nights: [SleepNight] = []
        for day in 1...6 { nights.append(Self.night(day, kept: true, rating: 4)) }
        for day in 7...12 { nights.append(Self.night(day, kept: false, rating: 3)) }
        let found = SleepInsightsEngine.insights(from: nights)
        let windDown = found.first { $0.kind == .windDown }
        #expect(windDown != nil)
        #expect(windDown?.betterNights == 6)
        #expect(windDown?.otherNights == 6)
        #expect(windDown.map { $0.delta >= 0.5 } == true)
    }

    @Test func aSmallDifferenceIsNotReported() {
        var nights: [SleepNight] = []
        for day in 1...6 { nights.append(Self.night(day, kept: true, rating: 4)) }
        for day in 7...12 { nights.append(Self.night(day, kept: false, rating: 4)) }
        #expect(SleepInsightsEngine.insights(from: nights).first { $0.kind == .windDown } == nil)
    }

    @Test func neverReportsThatWindDownHurt() {
        var nights: [SleepNight] = []
        for day in 1...6 { nights.append(Self.night(day, kept: true, rating: 2)) }
        for day in 7...12 { nights.append(Self.night(day, kept: false, rating: 5)) }
        #expect(SleepInsightsEngine.insights(from: nights).first { $0.kind == .windDown } == nil)
    }

    @Test func needsFourNightsOnEachSide() {
        var nights: [SleepNight] = []
        for day in 1...3 { nights.append(Self.night(day, kept: true, rating: 5)) }
        for day in 4...12 { nights.append(Self.night(day, kept: false, rating: 3)) }
        #expect(SleepInsightsEngine.insights(from: nights).first { $0.kind == .windDown } == nil)
    }

    @Test func sevenHoursOrMoreShowsWhenItHelped() {
        var nights: [SleepNight] = []
        for day in 1...5 { nights.append(Self.night(day, slept: 8 * 60, rating: 5)) }
        for day in 6...10 { nights.append(Self.night(day, slept: 5 * 60, rating: 3)) }
        let duration = SleepInsightsEngine.insights(from: nights).first { $0.kind == .duration }
        #expect(duration?.betterNights == 5)
    }

    // MARK: Bedtime suggestion

    @Test func suggestsAtMostThirtyMinutesEarlier() {
        // Nights around 21:30 felt much better than nights around 22:30; today's bedtime is 22:30.
        var nights: [SleepNight] = []
        for day in 1...5 { nights.append(Self.night(day, bed: 21 * 60 + 30, rating: 5)) }
        for day in 6...10 { nights.append(Self.night(day, bed: 22 * 60 + 30, rating: 3)) }
        let suggestion = SleepInsightsEngine.suggestion(from: nights, currentBedtimeMinute: 22 * 60 + 30)
        #expect(suggestion?.bedtimeMinute == 22 * 60, "one 30-minute step, not all the way to 21:30")
        #expect(suggestion?.basedOnNights == 5)
    }

    @Test func neverSuggestsALaterBedtime() {
        var nights: [SleepNight] = []
        for day in 1...5 { nights.append(Self.night(day, bed: 23 * 60 + 30, rating: 5)) }
        for day in 6...10 { nights.append(Self.night(day, bed: 22 * 60 + 30, rating: 3)) }
        #expect(SleepInsightsEngine.suggestion(from: nights, currentBedtimeMinute: 22 * 60 + 30) == nil)
    }

    @Test func neverSuggestsBeforeHalfPastEight() {
        var nights: [SleepNight] = []
        for day in 1...5 { nights.append(Self.night(day, bed: 20 * 60, rating: 5)) }
        for day in 6...10 { nights.append(Self.night(day, bed: 20 * 60 + 40, rating: 2)) }
        #expect(SleepInsightsEngine.suggestion(from: nights, currentBedtimeMinute: 20 * 60 + 40) == nil)
    }

    @Test func pastMidnightBedtimesSortAfterLateEveningOnes() {
        #expect(SleepNight.eveningOffset(ofMinuteOfDay: 23 * 60 + 30) < SleepNight.eveningOffset(ofMinuteOfDay: 30))
        #expect(SleepNight(id: "x", plannedBedtimeMinute: 22 * 60, asleepMinute: 15).effectiveBedtimeMinute == 15)
    }

    // MARK: A rough stretch

    @Test func fiveLowMorningsInARowIsARoughStretch() {
        let low = (1...5).map { Self.night($0, rating: $0 % 2 == 0 ? 1 : 2) }
        #expect(SleepInsightsEngine.isRoughStretch(low))
        let mixed = low + [Self.night(6, rating: 4)]
        #expect(!SleepInsightsEngine.isRoughStretch(mixed))
        #expect(!SleepInsightsEngine.isRoughStretch(Array(low.prefix(4))))
    }

    // MARK: Health merge

    @Test func overlappingSleepIsCountedOnce() {
        let calendar = Calendar(identifier: .gregorian)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let reading = SleepHealthReader.reading(from: [
            .init(start: base, end: base.addingTimeInterval(4 * 3_600)),
            .init(start: base.addingTimeInterval(2 * 3_600), end: base.addingTimeInterval(6 * 3_600)),
            .init(start: base.addingTimeInterval(7 * 3_600), end: base.addingTimeInterval(8 * 3_600)),
        ], calendar: calendar)
        #expect(reading?.asleepMinutes == 7 * 60, "0-6h merged, plus a separate 1h")
        let parts = calendar.dateComponents([.hour, .minute], from: base)
        #expect(reading?.onsetMinuteOfDay == (parts.hour ?? 0) * 60 + (parts.minute ?? 0), "onset is when the longest block began")
        #expect(SleepHealthReader.reading(from: []) == nil)
    }

    // MARK: Night ids and asking time

    @Test func aMorningBelongsToTheEveningBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
        #expect(SleepManager.nightID(for: morning, calendar: calendar) == "2026-09-09")
        #expect(SleepManager.nightID(for: afternoon, calendar: calendar) == "2026-09-10")
        #expect(SleepManager.isAskingTime(morning, calendar: calendar))
        #expect(!SleepManager.isAskingTime(afternoon, calendar: calendar))
    }

    // MARK: Storage

    @Test func storeKeepsTheLastHundredTwentyNightsAndReplacesById() {
        let savedSettings = SleepStore.settings
        let savedNights = SleepStore.nights
        defer {
            SleepStore.settings = savedSettings
            SleepStore.nights = savedNights
        }
        SleepStore.nights = []
        for day in 0..<130 { SleepStore.upsert(SleepNight(id: String(format: "2026-%03d", day), plannedBedtimeMinute: 1_350)) }
        #expect(SleepStore.nights.count == SleepStore.maxNights)
        #expect(SleepStore.nights.first?.id == "2026-010", "the oldest are dropped")
        SleepStore.upsert(SleepNight(id: "2026-129", plannedBedtimeMinute: 1_350, rating: 4))
        #expect(SleepStore.nights.count == SleepStore.maxNights)
        #expect(SleepStore.night(id: "2026-129")?.rating == 4)
    }
}
