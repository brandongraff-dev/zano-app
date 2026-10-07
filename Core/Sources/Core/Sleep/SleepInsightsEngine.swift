// SleepInsightsEngine.swift
// Core / Sleep
//
// Pure logic (docs/spec.md §5.25, §9.1 spirit: rules before models, explainable, on device). It looks
// at the nights a person rated and says only what the numbers support, with the counts shown:
//
//   * It needs 10 rated nights before it says anything, and 4 nights on each side of a comparison.
//   * An insight only appears when the better side beats the other by half a point out of five. It
//     never claims something *hurts* ("later bedtimes were worse" is not reported), so it can't nag.
//   * It reports patterns, not causes: copy says "on nights you...", never "because".
//   * The bedtime suggestion moves at most 30 minutes earlier than the current bedtime at a time, never
//     before 8:30 pm, and never later; it only ever suggests, the person decides.
//   * A rough stretch (the last 5 ratings all 1 or 2) is reported on its own so the screen can be kind
//     instead of cheerful, and so ZANO doesn't push a sleep plan at someone who is struggling.

import Foundation

public enum SleepInsightsEngine {
    public static let minRatedNights = 10
    public static let minGroupNights = 4
    public static let minDelta = 0.5
    public static let enoughSleepMinutes = 7 * 60
    public static let consistencyWindowMinutes = 30
    public static let suggestionStepMinutes = 30
    /// 20:30, as an offset from 18:00.
    public static let earliestSuggestedOffset = 150
    public static let roughStretchLength = 5

    static func rated(_ nights: [SleepNight]) -> [SleepNight] {
        nights.filter { ($0.rating).map { (1...5).contains($0) } ?? false }
    }

    static func average(_ nights: [SleepNight]) -> Double {
        guard !nights.isEmpty else { return 0 }
        return Double(nights.compactMap(\.rating).reduce(0, +)) / Double(nights.count)
    }

    // MARK: Insights

    public static func insights(from nights: [SleepNight]) -> [SleepInsight] {
        let all = rated(nights)
        guard all.count >= minRatedNights else { return [] }
        var found: [SleepInsight] = []

        // Wind-down kept vs not.
        let known = all.filter { $0.keptWindDown != nil }
        compare(better: known.filter { $0.keptWindDown == true }, other: known.filter { $0.keptWindDown == false }, kind: .windDown, into: &found)

        // At least 7 hours asleep vs fewer.
        let measured = all.filter { $0.sleepMinutes != nil }
        compare(
            better: measured.filter { ($0.sleepMinutes ?? 0) >= enoughSleepMinutes },
            other: measured.filter { ($0.sleepMinutes ?? 0) < enoughSleepMinutes },
            kind: .duration, into: &found
        )

        // Bedtime close to the usual one vs not.
        let offsets = all.map(\.bedtimeOffset).sorted()
        let median = offsets[offsets.count / 2]
        compare(
            better: all.filter { abs($0.bedtimeOffset - median) <= consistencyWindowMinutes },
            other: all.filter { abs($0.bedtimeOffset - median) > consistencyWindowMinutes },
            kind: .consistency, into: &found
        )

        return found.sorted { $0.delta > $1.delta }
    }

    private static func compare(better: [SleepNight], other: [SleepNight], kind: SleepInsightKind, into found: inout [SleepInsight]) {
        guard better.count >= minGroupNights, other.count >= minGroupNights else { return }
        let first = average(better), second = average(other)
        guard first - second >= minDelta else { return }
        found.append(SleepInsight(kind: kind, betterAverage: first, otherAverage: second, betterNights: better.count, otherNights: other.count))
    }

    // MARK: Bedtime suggestion

    /// A slightly earlier bedtime, when nights with an earlier bedtime were clearly better rated.
    public static func suggestion(from nights: [SleepNight], currentBedtimeMinute: Int) -> SleepBedtimeSuggestion? {
        let all = rated(nights)
        guard all.count >= minRatedNights else { return nil }
        let overall = average(all)

        // Group by half hour of the evening offset.
        var groups: [Int: [SleepNight]] = [:]
        for night in all { groups[night.bedtimeOffset / 30, default: []].append(night) }
        let candidates = groups.filter { $0.value.count >= minGroupNights }
        guard let best = candidates.max(by: { average($0.value) < average($1.value) }),
              average(best.value) - overall >= minDelta
        else { return nil }

        let bestOffset = best.key * 30
        let currentOffset = SleepNight.eveningOffset(ofMinuteOfDay: currentBedtimeMinute)
        guard bestOffset < currentOffset else { return nil }
        let stepped = max(bestOffset, currentOffset - suggestionStepMinutes)
        guard stepped >= earliestSuggestedOffset else { return nil }
        return SleepBedtimeSuggestion(
            bedtimeMinute: (stepped + 18 * 60) % 1_440,
            basedOnNights: best.value.count,
            groupAverage: average(best.value),
            overallAverage: overall
        )
    }

    // MARK: A rough stretch

    public static func isRoughStretch(_ nights: [SleepNight]) -> Bool {
        let recent = rated(nights).sorted { $0.id < $1.id }.suffix(roughStretchLength)
        return recent.count == roughStretchLength && recent.allSatisfy { ($0.rating ?? 5) <= 2 }
    }
}
