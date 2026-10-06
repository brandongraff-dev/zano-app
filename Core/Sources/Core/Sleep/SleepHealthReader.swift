// SleepHealthReader.swift
// Core / Sleep
//
// Reads last night's sleep from Apple Health, on this phone only, read-only (docs/spec.md §5.25, §24
// "Health data stays on device"). It only runs when the person turned on "Use Apple Health sleep".
//
// HealthKit never says whether read access was granted: a denied read looks like "no data", so this
// simply returns `nil` and the insights fall back to the planned bedtime.
//
// UNVERIFIED (no Mac/device, CLAUDE.md rule 5): `HKCategoryValueSleepAnalysis.asleepCore/Deep/REM/
// Unspecified` (iOS 16+) and the query shape are written from memory; the merge logic is pure and tested.

import Foundation
import HealthKit

public enum SleepHealthReader {
    public struct Reading: Sendable, Equatable {
        public let asleepMinutes: Int
        /// When the longest block of sleep started, minutes after midnight.
        public let onsetMinuteOfDay: Int
    }

    /// One asleep stretch from Health, reduced to plain dates.
    public struct Interval: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// Asks the Health permission sheet for sleep (read only). Returning normally does not mean it was allowed.
    public static func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return }
        let store = HKHealthStore()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestAuthorization(toShare: [], read: [sleep]) { _, _ in
                continuation.resume()
            }
        }
    }

    /// Last night's sleep: asleep stretches from the 20 hours before `now`, overlaps counted once.
    public static func lastNight(endingAt now: Date, calendar: Calendar = .current) async -> Reading? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return nil }
        let start = now.addingTimeInterval(-20 * 3_600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let store = HKHealthStore()
        let intervals: [Interval] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                let plain = (results as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .map { Interval(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: plain)
            }
            store.execute(query)
        }
        return reading(from: intervals, calendar: calendar)
    }

    /// Joins overlapping stretches (two apps can both write the same night), totals them, and reports
    /// when the longest one began. `nil` when there is nothing.
    public static func reading(from intervals: [Interval], calendar: Calendar = .current) -> Reading? {
        var merged: [Interval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.end > interval.start {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = Interval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        guard let longest = merged.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) else { return nil }
        let total = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        let parts = calendar.dateComponents([.hour, .minute], from: longest.start)
        return Reading(
            asleepMinutes: Int(total / 60),
            onsetMinuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        )
    }
}
