// Core/Sources/Core/Verification/QuickRepeatSuggester.swift
//
// docs/spec.md §5.19 Quick Repeats & Food Memory:
//   "Meal photos build a personal library. 'Your usual chicken bowl (48g)?' appears as a one-tap
//   suggestion at the times the user typically eats it."
// docs/spec.md §3 Goal Catalog & Verification, Protein row, Tier B verification methods include
// "quick-repeat of recent meals" — the reason this file lives under Verification/ alongside
// GymVerifier/FocusSessionVerifier/GymAutoDetect rather than a Fuel-specific folder: deciding
// which remembered meal (if any) is worth a one-tap re-confirmation right now is a
// verification-adjacent surfacing decision, not UI. `Models/Meal.swift`'s own header agrees:
// "the basis for Quick Repeats... Tier B verification source for the Protein goal (spec §3)."
//
// Reads `Models/Meal.swift` (this task's own read, not this task's file, never edited) directly.
// That file's header is explicit that `embedding` (pgvector, server-side cosine similarity) is
// deliberately NOT mirrored on-device, and that on-device similarity ranking "is a new
// field/decision for that session, not an extension of this one." So "the same meal logged
// again" is detected here the only way on-device data supports: a normalized signature of each
// meal's `MealItem.name`s (``QuickRepeatSuggester/signature(for:)``), not vector similarity.
//
// Reads `Intents/QuickRepeatMealIntent.swift` (also this task's own read, also not edited) for
// its real, current shape: it takes a `MealEntity` (id + label), fetches the matching `Meal` row
// itself, and copies its `items`/`proteinG` into a fresh, pre-confirmed `Meal` for today. This
// file's public contract — `suggestedQuickRepeat(at:) async -> Meal?` — is intentionally the
// *upstream* half of that flow: it hands back the real, existing `Meal` history row worth
// repeating (if any), so a caller can build `MealEntity(id: meal.id, label: ...)` and drive
// `QuickRepeatMealIntent` exactly the way `NFCTagMapper.swift` already drives
// `LogProteinIntent`/`LogWaterIntent` for its own intents. Building that `MealEntity` and wiring
// it into `App/ZANO/Features/Fuel/FuelView.swift` is explicitly NOT this file's job — see this
// task's `knownIssues`; `FuelView.swift` is a different, in-flight agent's file this task must
// never touch, even though (per this task's own read of it) it already contains an inline,
// near-identical grouping+ranking heuristic (its private `quickRepeats` computed property) built
// independently for its own display purposes. That duplication is real and is exactly the kind
// CLAUDE.md's "never duplicate the same logic in two places" rule is about — flagged as a
// follow-up refactor for whichever session next owns FuelView.swift, not fixed here.
//
// Design beyond the naive "average hour of day" FuelView's own heuristic uses: a recurring meal
// can plausibly have more than one typical time (a chicken bowl eaten at both lunch and dinner
// should surface two windows, not one meaningless midpoint between them, and spec §5.19 itself
// says "times", plural). ``typicalEatWindows(for:calendar:)`` below clusters a recurring meal's
// historical timestamps by time-of-day using a circular (not arithmetic) mean, so a cluster that
// straddles midnight doesn't wrongly average to noon, then scores/matches against those windows
// at call time. This is the same "simplified single-pass greedy clustering, not a textbook
// algorithm" tradeoff `Verification/GymAutoDetect.swift` already documents for its own (2-D,
// lat/lon) clustering — same shape of compromise, different (1-D, circular) domain.
//
// No Mac/compiler exists to build or run this. The clustering/signature/distance pieces are pure,
// static, side-effect-free functions specifically so a future session with a working Swift
// toolchain can unit-test them directly in `CoreTests` without standing up a `ModelContainer` —
// flagged in this task's `knownIssues` as not yet done here.

import Foundation
import SwiftData
import os

/// Given a user's confirmed meal history, detects which remembered meals recur and roughly when
/// (by time of day) each one is typically eaten, then answers "is right now one of those times,
/// and if so, which meal?" for `at(date:)` callers.
///
/// `@MainActor final class` with a `.shared` singleton and an injectable `modelContainer`, not a
/// bare `Sendable` type or an `actor`: identical reasoning to `Retention/StreakEngine.swift`'s own
/// declaration-site comment — every realistic call site (a SwiftUI Fuel screen, an App Intent's
/// `@MainActor perform()`) is already on the main actor or happy to hop onto it, and a
/// `@MainActor final class` is implicitly `Sendable`, which is what lets `.shared` and
/// `suggestedQuickRepeat(at:)` stay callable from any isolation domain despite owning a
/// non-`Sendable` `ModelContext`.
@MainActor
public final class QuickRepeatSuggester {
    public static let shared = QuickRepeatSuggester()

    // MARK: - Tunables (public, explainable-heuristic constants — mirrors
    // `GymAutoDetect`'s own fully-public tunables so another session can read or override them
    // in a test rather than needing to reverse-engineer magic numbers).
    //
    // All marked `nonisolated`: they're plain immutable `Sendable` values (`Int`/`Double`) with
    // no dependency on this class's MainActor-isolated state (`context`/`modelContainer`), and
    // they're read from the `nonisolated` pure clustering functions below (and, for
    // `minutesPerDay`, from the file-scope `CircularMinuteCluster`/`TypicalEatWindow` types too)
    // — without this, those functions couldn't read them without an actor hop, defeating the
    // point of making the clustering pipeline synchronously unit-testable in the first place.

    /// How far back to look for meal history when mining patterns, relative to the `date` a call
    /// is asked about (not always `.now` — see `suggestedQuickRepeat(at:)`'s own comment on why
    /// that matters for testability). Old enough to capture a real weekly/rotational eating
    /// pattern, recent enough that a genuinely changed habit (e.g. a new job's lunch schedule)
    /// isn't permanently dragged toward stale timestamps.
    public nonisolated static let lookbackDays = 120

    /// A meal must have been confirmed-and-logged at least this many times within the lookback
    /// window before it counts as "recurring" at all. Matches the threshold
    /// `App/ZANO/Features/Fuel/FuelView.swift`'s own (independently written, unduplicated-from-
    /// here) `quickRepeats` heuristic already uses, so the two happen to agree today even though
    /// they don't share code yet.
    public nonisolated static let minimumOccurrences = 2

    /// Upper bound on how many historical meals a single lookup fetches, so one very
    /// meal-logging-heavy user's history can't make every call unboundedly expensive. 120 days at
    /// several meals/day comfortably fits under this.
    public nonisolated static let historyFetchLimit = 400

    /// Minutes-of-day are folded onto a circle of this size (24h × 60min) so time-of-day
    /// clustering/distance wraps correctly at midnight instead of treating 23:59 and 00:00 as far
    /// apart.
    public nonisolated static let minutesPerDay = 1_440

    /// While clustering one recurring meal's historical timestamps by time-of-day
    /// (``typicalEatWindows(for:calendar:)``), a new timestamp joins the nearest existing cluster
    /// only if it's within this many minutes of that cluster's running circular mean; otherwise it
    /// starts a new cluster. Loose enough to absorb ordinary day-to-day drift around one mealtime,
    /// tight enough that genuinely different mealtimes (lunch vs. dinner) don't merge into one.
    public nonisolated static let clusterJoinRadiusMinutes = 60

    /// Baseline "close enough to right now" match tolerance (minutes) for a typical-eat-time
    /// window at call time, before ``matchToleranceMinutes(for:)``'s spread adjustment.
    public nonisolated static let baseMatchToleranceMinutes = 30
    /// How much wider the match tolerance can grow, on top of the base, for a window whose
    /// historical timestamps were loosely scattered rather than tightly clustered — see
    /// ``matchToleranceMinutes(for:)``.
    public nonisolated static let toleranceSpreadRangeMinutes = 60
    /// Hard ceiling on match tolerance regardless of how scattered a window's history is — past
    /// this point "typical eat time" has stopped meaning anything specific enough to suggest.
    public nonisolated static let maxMatchToleranceMinutes = 90

    /// After a recurring meal's most-recent occurrence, how long ``suggestedQuickRepeat(at:)``
    /// stays quiet about suggesting that same meal again — anti-annoyance, not a hard rule from
    /// spec §5.19: nothing is worse for a "your usual?" suggestion's credibility than repeating
    /// itself minutes after the user just logged (or quick-repeated) exactly that meal. Shorter
    /// than the gap between two distinct typical-eat-time windows of the same meal (e.g. lunch vs.
    /// dinner chicken bowl), so a second, later window for the same meal can still fire today.
    public nonisolated static let recentRepeatCooldownMinutes = 180

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "QuickRepeatSuggester")

    /// Not `private`, only so `CoreTests` can construct an isolated instance against an in-memory
    /// container — mirrors `StreakEngine`/`LockEngineManager`/`FocusSessionVerifier`'s own
    /// convention. Every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public contract

    /// Whether `date` is one of the times the user typically eats one of their recurring meals
    /// and, if so, that meal's most recent confirmed `Meal` row — the exact shape a caller needs
    /// to build `MealEntity(id: meal.id, label: ...)` and drive `QuickRepeatMealIntent`.
    ///
    /// `date` is a parameter, not always resolved internally to `.now`, so a caller mining a
    /// widget timeline (several future entries computed ahead of time) or a unit test (a fixed,
    /// reproducible clock) both get a real answer for their own point in time rather than only
    /// ever "right now". History considered for any given `date` is bounded to `ts <= date`
    /// (never leaks lookahead from meals logged after the moment being asked about) and
    /// `ts >= date - lookbackDays` (see ``lookbackDays``).
    ///
    /// Never throws (matches `StreakEngine`'s CONTRACTS-style methods): a missing local `User`
    /// row, an empty history, or nothing matching `date` closely enough are all just "no
    /// suggestion right now", not error conditions a caller needs to handle separately. Logged,
    /// not silently swallowed, when it's the missing-user or fetch-failure case specifically.
    public func suggestedQuickRepeat(at date: Date) async -> Meal? {
        guard let user = try? fetchCurrentUser() else {
            logger.notice("suggestedQuickRepeat: no local User row — nothing to suggest.")
            return nil
        }

        let userID = user.id
        let cutoff = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: date) ?? .distantPast
        var descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { meal in
                meal.userID == userID && meal.confirmed && meal.ts >= cutoff && meal.ts <= date
            }
        )
        descriptor.sortBy = [SortDescriptor(\.ts, order: .reverse)]
        descriptor.fetchLimit = Self.historyFetchLimit

        let history: [Meal]
        do {
            history = try context.fetch(descriptor)
        } catch {
            logger.error("suggestedQuickRepeat: history fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        let patterns = Self.recurringPatterns(from: history, calendar: calendar)
        guard !patterns.isEmpty else { return nil }

        let targetMinute = Self.minuteOfDay(for: date, calendar: calendar)
        var best: (pattern: RecurringMealPattern, window: TypicalEatWindow, distance: Int)?

        for pattern in patterns {
            // Anti-annoyance cooldown (see `recentRepeatCooldownMinutes`'s doc comment). Always
            // non-negative: `mostRecentTimestamp` comes from history already bounded to
            // `ts <= date` above.
            let minutesSinceLastLogged = date.timeIntervalSince(pattern.mostRecentTimestamp) / 60
            guard minutesSinceLastLogged >= Double(Self.recentRepeatCooldownMinutes) else { continue }

            for window in pattern.windows {
                let distance = Self.circularDistance(targetMinute, window.meanMinuteOfDay)
                guard distance <= Self.matchToleranceMinutes(for: window) else { continue }

                let isBetter: Bool
                if let current = best {
                    isBetter = distance < current.distance
                        || (distance == current.distance && window.sampleCount > current.window.sampleCount)
                        || (distance == current.distance
                            && window.sampleCount == current.window.sampleCount
                            && pattern.mostRecentTimestamp > current.pattern.mostRecentTimestamp)
                } else {
                    isBetter = true
                }
                if isBetter {
                    best = (pattern, window, distance)
                }
            }
        }

        return best?.pattern.representative
    }

    /// Normalized identity for "the same remembered meal" — every item name lowercased, trimmed,
    /// sorted, and joined, so item order and incidental casing/whitespace from the vision model
    /// (or manual entry) never split one real recurring meal into two groups. `public` so a
    /// caller that wants to group meals the exact same way this file does (e.g. a future
    /// `FuelView.swift` refactor onto this suggester, per this task's `knownIssues`) doesn't have
    /// to re-derive the normalization and risk drifting from it.
    public nonisolated static func signature(for items: [MealItem]) -> String {
        items
            .map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .sorted()
            .joined(separator: "|")
    }

    // MARK: - User lookup

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `StreakEngine.fetchCurrentUser()`/`LockEngineManager.fetchCurrentUser()` each use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw QuickRepeatSuggesterError.noSignedInUser
        }
        return user
    }

    // MARK: - Pattern mining (pure, static — unit-testable without a `ModelContainer`)

    /// Groups confirmed meal history by ``signature(for:)`` and keeps only groups that recur at
    /// least ``minimumOccurrences`` times, each carrying its own clustered typical-eat-time
    /// windows. Meals with no protein estimate yet or an empty item list are skipped — same guard
    /// `FuelView.swift`'s own (independent) heuristic applies, for the same reason: neither is a
    /// meaningful "usual" to repeat.
    private nonisolated static func recurringPatterns(from history: [Meal], calendar: Calendar) -> [RecurringMealPattern] {
        var groups: [String: [Meal]] = [:]
        for meal in history {
            guard meal.proteinG != nil, !meal.items.isEmpty else { continue }
            groups[signature(for: meal.items), default: []].append(meal)
        }

        return groups.values.compactMap { meals in
            guard meals.count >= minimumOccurrences,
                  let representative = meals.max(by: { $0.ts < $1.ts }) else { return nil }
            let windows = typicalEatWindows(for: meals.map(\.ts), calendar: calendar)
            guard !windows.isEmpty else { return nil }
            return RecurringMealPattern(
                representative: representative,
                occurrenceCount: meals.count,
                windows: windows,
                mostRecentTimestamp: representative.ts
            )
        }
    }

    /// Clusters one recurring meal's historical timestamps into one or more typical time-of-day
    /// windows. See this file's header comment for why this is a circular-mean clustering, not an
    /// arithmetic-average one, and why it's a deliberate simplified-greedy tradeoff rather than a
    /// textbook algorithm.
    nonisolated static func typicalEatWindows(for timestamps: [Date], calendar: Calendar = .current) -> [TypicalEatWindow] {
        let minutes = timestamps.map { minuteOfDay(for: $0, calendar: calendar) }.sorted()
        guard !minutes.isEmpty else { return [] }

        var clusters: [CircularMinuteCluster] = []
        for minute in minutes {
            if let index = clusters.firstIndex(where: {
                circularDistance($0.meanMinute, minute) <= clusterJoinRadiusMinutes
            }) {
                clusters[index].add(minute)
            } else {
                clusters.append(CircularMinuteCluster(first: minute))
            }
        }

        // One merge pass: the chronological greedy pass above can leave two clusters that end up
        // within radius of each other's *final* mean without ever having been compared directly
        // (most commonly a midnight-wraparound case — one cluster forms near 23:5x, another near
        // 00:1x). Repeatedly merging the closest under-radius pair until none remain fixes that
        // without needing to reorder or redo the pass above. Cluster counts here are always tiny
        // (one recurring meal's history), so the naive O(n²) pair scan is not a real cost.
        var merged = true
        while merged, clusters.count > 1 {
            merged = false
            searchPairs: for i in clusters.indices {
                for j in clusters.indices where j > i {
                    if circularDistance(clusters[i].meanMinute, clusters[j].meanMinute) <= clusterJoinRadiusMinutes {
                        clusters[i].merge(clusters[j])
                        clusters.remove(at: j)
                        merged = true
                        break searchPairs
                    }
                }
            }
        }

        return clusters
            .map { TypicalEatWindow(meanMinuteOfDay: $0.meanMinute, sampleCount: $0.count, concentration: $0.resultantLength) }
            .sorted { $0.sampleCount > $1.sampleCount }
    }

    private nonisolated static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Shortest distance between two minute-of-day values around a `minutesPerDay`-size circle
    /// (e.g. 23:50 and 00:10 are 20 minutes apart, not ~1,420).
    nonisolated static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let diff = abs(a - b) % minutesPerDay
        return min(diff, minutesPerDay - diff)
    }

    /// Explainable v1 heuristic (same spirit as `GymAutoDetect.confidence(visitCount:
    /// averageDwellMinutes:)`'s own comment: spec prescribes the *shape* of the feature, not an
    /// exact formula): a window whose historical timestamps were tightly clustered (high
    /// `concentration`, near 1) gets a tolerance near `baseMatchToleranceMinutes`; a window built
    /// from loosely scattered timestamps (`concentration` near 0) gets pulled out toward
    /// `maxMatchToleranceMinutes`, since "typical" was already a looser claim for that meal.
    nonisolated static func matchToleranceMinutes(for window: TypicalEatWindow) -> Int {
        let widened = Double(baseMatchToleranceMinutes) + (1 - window.concentration) * Double(toleranceSpreadRangeMinutes)
        return min(maxMatchToleranceMinutes, max(baseMatchToleranceMinutes, Int(widened.rounded())))
    }
}

// MARK: - Internal pattern/clustering types

/// One recurring meal, identified by ``QuickRepeatSuggester/signature(for:)``, with the typical
/// time-of-day windows mined from its own history.
private struct RecurringMealPattern {
    /// The most recently logged `Meal` in this group — what gets returned, since it's the
    /// freshest record of exactly what "this meal" looks like right now (current item breakdown,
    /// most recently confirmed protein figure), matching what `QuickRepeatMealIntent` would copy
    /// forward if the user were to manually pick the same meal from `MealQuery.allEntities()`
    /// today.
    let representative: Meal
    let occurrenceCount: Int
    let windows: [TypicalEatWindow]
    let mostRecentTimestamp: Date
}

/// One clustered "time of day this meal tends to get eaten" — e.g. the lunch and dinner versions
/// of the same recurring chicken bowl become two separate windows rather than one meaningless
/// average between them.
struct TypicalEatWindow {
    /// Circular mean minute-of-day (`0..<1_440`) of every timestamp folded into this window.
    let meanMinuteOfDay: Int
    let sampleCount: Int
    /// Circular "mean resultant length", `0...1`: how tightly this window's historical timestamps
    /// clustered around `meanMinuteOfDay` (1 = always the exact same minute, 0 = scattered evenly
    /// across the whole day). Feeds ``QuickRepeatSuggester/matchToleranceMinutes(for:)``.
    let concentration: Double
}

/// Running circular-mean accumulator for one time-of-day cluster, built by summing each folded-in
/// minute's position on the unit circle (`(sin θ, cos θ)`) rather than averaging minute values
/// arithmetically — the standard circular-statistics mean, needed because a cluster straddling
/// midnight (23:50, 00:10, ...) would otherwise average to noon.
private struct CircularMinuteCluster {
    private(set) var count: Int
    private var sumSine: Double
    private var sumCosine: Double

    init(first minute: Int) {
        count = 1
        (sumSine, sumCosine) = Self.vector(for: minute)
    }

    var meanMinute: Int {
        let angle = atan2(sumSine / Double(count), sumCosine / Double(count))
        let minute = angle / (2 * .pi) * Double(QuickRepeatSuggester.minutesPerDay)
        let wrapped = minute.truncatingRemainder(dividingBy: Double(QuickRepeatSuggester.minutesPerDay))
        return Int((wrapped < 0 ? wrapped + Double(QuickRepeatSuggester.minutesPerDay) : wrapped).rounded())
    }

    /// Mean resultant length of the accumulated vectors, `0...1` — see
    /// ``TypicalEatWindow/concentration``'s doc comment for what this measures.
    var resultantLength: Double {
        let magnitude = (sumSine * sumSine + sumCosine * sumCosine).squareRoot()
        return min(1, magnitude / Double(count))
    }

    mutating func add(_ minute: Int) {
        let (sine, cosine) = Self.vector(for: minute)
        sumSine += sine
        sumCosine += cosine
        count += 1
    }

    mutating func merge(_ other: CircularMinuteCluster) {
        sumSine += other.sumSine
        sumCosine += other.sumCosine
        count += other.count
    }

    private static func vector(for minute: Int) -> (sine: Double, cosine: Double) {
        let angle = Double(minute) / Double(QuickRepeatSuggester.minutesPerDay) * 2 * .pi
        return (sin(angle), cos(angle))
    }
}

/// Errors this file's private `fetchCurrentUser()` throws internally. Never propagated out of
/// `suggestedQuickRepeat(at:)` (non-throwing by contract) — kept only so that helper has a typed
/// failure to `try?` at its one call site, mirroring `StreakEngineError`'s identical convention.
enum QuickRepeatSuggesterError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
