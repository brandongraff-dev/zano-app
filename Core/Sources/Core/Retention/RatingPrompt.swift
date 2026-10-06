// RatingPrompt.swift
// Core / Retention
//
// When to ask for an App Store rating (growth research #8 and §2.8, 2026-10-02): only right after a
// peak moment, never after a bad one.
//
//   Ask after   the 3rd earned unlock, the first gym-verified unlock, or a 7-day streak — each of
//               these at most once.
//   Never       when the unlock that just ended wasn't earned (an emergency unlock), within
//               `cooldownAfterBadMoment` of an emergency unlock or a paywall view, while the streak
//               is "slipped" (Never Miss Twice armed: yesterday was missed), within `minimumGap` of
//               the last ask, or more than `maxAsksPerYear` times in 365 days (Apple's own cap is
//               also 3, and iOS may still show nothing).
//
// The app shows the system prompt (`requestReview` from SwiftUI's environment) when the unlock
// celebration is dismissed — never from a button the user tapped to rate, which Apple ignores.
// `decide(_:now:)` is pure and tested; `triggerIfDue(now:)` reads the store and the ask ledger.

import Foundation
import SwiftData

/// The peak moment a rating ask is tied to.
public enum RatingTrigger: String, Sendable, CaseIterable {
    case thirdEarnedUnlock
    case firstGymUnlock
    case sevenDayStreak
}

/// Everything `RatingPrompt.decide` reads, as plain values.
public struct RatingPromptInputs: Sendable, Equatable {
    public var earnedUnlockCount: Int
    public var gymVerifiedCount: Int
    public var currentStreak: Int
    /// How the most recently ended lock ended. The ask follows an unlock, so it must be `.earned`.
    public var lastUnlockKind: UnlockKind?
    public var lastEmergencyUnlockAt: Date?
    /// `Streak.neverMissTwiceArmed`: the user missed yesterday.
    public var isSlipped: Bool
    public var lastPaywallViewAt: Date?
    public var askDates: [Date]
    public var usedTriggers: Set<RatingTrigger>

    public init(
        earnedUnlockCount: Int = 0,
        gymVerifiedCount: Int = 0,
        currentStreak: Int = 0,
        lastUnlockKind: UnlockKind? = nil,
        lastEmergencyUnlockAt: Date? = nil,
        isSlipped: Bool = false,
        lastPaywallViewAt: Date? = nil,
        askDates: [Date] = [],
        usedTriggers: Set<RatingTrigger> = []
    ) {
        self.earnedUnlockCount = earnedUnlockCount
        self.gymVerifiedCount = gymVerifiedCount
        self.currentStreak = currentStreak
        self.lastUnlockKind = lastUnlockKind
        self.lastEmergencyUnlockAt = lastEmergencyUnlockAt
        self.isSlipped = isSlipped
        self.lastPaywallViewAt = lastPaywallViewAt
        self.askDates = askDates
        self.usedTriggers = usedTriggers
    }
}

@MainActor
public final class RatingPrompt {
    public static let shared = RatingPrompt()

    public nonisolated static let earnedUnlockThreshold = 3
    public nonisolated static let streakThreshold = 7
    public nonisolated static let minimumGap: TimeInterval = 14 * 86_400
    public nonisolated static let maxAsksPerYear = 3
    public nonisolated static let cooldownAfterBadMoment: TimeInterval = 24 * 3600

    static let askDatesKey = "zano.ratingPrompt.askDates.v1"
    static let usedTriggersKey = "zano.ratingPrompt.usedTriggers.v1"
    static let lastPaywallViewKey = "zano.ratingPrompt.lastPaywallView.v1"

    private let modelContainer: ModelContainer
    private let defaults: UserDefaults

    /// `internal` so tests can pass an in-memory container and a throwaway defaults suite.
    init(modelContainer: ModelContainer = .appGroup, defaults: UserDefaults? = nil) {
        self.modelContainer = modelContainer
        self.defaults = defaults ?? .standard
    }

    // MARK: - Pure decision

    /// The trigger to ask for now, or `nil` to stay quiet.
    public nonisolated static func decide(_ inputs: RatingPromptInputs, now: Date) -> RatingTrigger? {
        // Never after a bad moment.
        guard inputs.lastUnlockKind == .earned else { return nil }
        guard !inputs.isSlipped else { return nil }
        if let emergency = inputs.lastEmergencyUnlockAt, now.timeIntervalSince(emergency) < cooldownAfterBadMoment {
            return nil
        }
        if let paywall = inputs.lastPaywallViewAt, now.timeIntervalSince(paywall) < cooldownAfterBadMoment {
            return nil
        }
        // Rate limits.
        if let last = inputs.askDates.max(), now.timeIntervalSince(last) < minimumGap {
            return nil
        }
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        guard inputs.askDates.filter({ $0 > yearAgo }).count < maxAsksPerYear else { return nil }

        // The peak moments, most specific first.
        if inputs.gymVerifiedCount >= 1, !inputs.usedTriggers.contains(.firstGymUnlock) {
            return .firstGymUnlock
        }
        if inputs.currentStreak >= streakThreshold, !inputs.usedTriggers.contains(.sevenDayStreak) {
            return .sevenDayStreak
        }
        if inputs.earnedUnlockCount >= earnedUnlockThreshold, !inputs.usedTriggers.contains(.thirdEarnedUnlock) {
            return .thirdEarnedUnlock
        }
        return nil
    }

    // MARK: - Store-backed

    /// The trigger to ask for right now, from the local store and the ask ledger. Read-only: call
    /// `recordAsked(_:)` once the prompt was actually requested.
    public func triggerIfDue(now: Date = .now) -> RatingTrigger? {
        Self.decide(inputs(now: now), now: now)
    }

    /// Records an ask (the trigger is spent even if iOS chose not to show the prompt).
    public func recordAsked(_ trigger: RatingTrigger, now: Date = .now) {
        var dates = askDates()
        dates.append(now)
        defaults.set(dates.map(\.timeIntervalSince1970), forKey: Self.askDatesKey)
        var used = usedTriggers()
        used.insert(trigger)
        defaults.set(used.map(\.rawValue).sorted(), forKey: Self.usedTriggersKey)
    }

    /// The paywall was on screen. Called by `PaywallViewModel` whenever it loads.
    public func recordPaywallViewed(now: Date = .now) {
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastPaywallViewKey)
    }

    func inputs(now: Date) -> RatingPromptInputs {
        let context = ModelContext(modelContainer)
        var inputs = RatingPromptInputs()

        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        if let userID = (try? context.fetch(userDescriptor))?.first?.id {
            var streakDescriptor = FetchDescriptor<Streak>(predicate: #Predicate<Streak> { $0.userID == userID })
            streakDescriptor.fetchLimit = 1
            if let streak = (try? context.fetch(streakDescriptor))?.first {
                inputs.currentStreak = streak.current
                inputs.isSlipped = streak.neverMissTwiceArmed
            }
        }

        // Ended sessions, filtered in Swift (unlockKind is an enum; same approach as MilestoneEngine).
        let ended = ((try? context.fetch(FetchDescriptor<LockSession>())) ?? [])
            .filter { $0.endedAt != nil && $0.endedAt! <= now.addingTimeInterval(60) }
            .sorted { $0.endedAt! < $1.endedAt! }
        inputs.lastUnlockKind = ended.last?.unlockKind
        inputs.earnedUnlockCount = ended.filter { $0.unlockKind == .earned }.count
        inputs.lastEmergencyUnlockAt = ended.last { $0.unlockKind == .emergency }?.endedAt

        let events = (try? context.fetch(FetchDescriptor<GoalEvent>())) ?? []
        inputs.gymVerifiedCount = events.filter { $0.kind == .complete && $0.goal?.type == .workoutGym }.count

        let paywall = defaults.double(forKey: Self.lastPaywallViewKey)
        inputs.lastPaywallViewAt = paywall > 0 ? Date(timeIntervalSince1970: paywall) : nil
        inputs.askDates = askDates()
        inputs.usedTriggers = usedTriggers()
        return inputs
    }

    private func askDates() -> [Date] {
        (defaults.array(forKey: Self.askDatesKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    private func usedTriggers() -> Set<RatingTrigger> {
        Set((defaults.stringArray(forKey: Self.usedTriggersKey) ?? []).compactMap(RatingTrigger.init(rawValue:)))
    }
}
