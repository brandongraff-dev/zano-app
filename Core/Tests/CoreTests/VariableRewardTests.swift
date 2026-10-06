// Core/Tests/CoreTests/VariableRewardTests.swift
//
// Tests Core/Sources/Core/Retention/VariableReward.swift (docs/spec.md §8.4 variable rewards;
// Wave 3K of docs/design/buildout-plan.md): the roll is deterministic per session, a repeat roll
// never pays twice, and a pending surprise is revealed exactly once.

import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor
struct VariableRewardTests {
    private static let referenceDate = Date(timeIntervalSince1970: 1_768_478_400)

    private func makeSubject() throws -> (VariableReward, ModelContainer, UUID) {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        try context.save()
        let suite = "zano.tests.variableReward.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (VariableReward(modelContainer: container, defaults: defaults), container, user.id)
    }

    /// First session ID whose roll wins a surprise matching `predicate`.
    private func winningSessionID(where predicate: (VariableRewardOutcome) -> Bool) -> UUID {
        while true {
            let id = UUID()
            if let outcome = VariableReward.outcome(for: id), predicate(outcome) { return id }
        }
    }

    @Test func outcomeIsDeterministicPerSession() {
        for _ in 0..<50 {
            let id = UUID()
            #expect(VariableReward.outcome(for: id) == VariableReward.outcome(for: id))
        }
    }

    @Test func surprisesAreOccasionalNotConstant() {
        let wins = (0..<600).filter { _ in VariableReward.outcome(for: UUID()) != nil }.count
        #expect(wins > 40)
        #expect(wins < 200)
    }

    @Test func repeatRollPaysCoinsOnce() throws {
        let (subject, container, userID) = try makeSubject()
        let sessionID = winningSessionID { if case .bonusCoins = $0 { return true } else { return false } }

        let first = subject.roll(sessionID: sessionID, at: Self.referenceDate)
        let second = subject.roll(sessionID: sessionID, at: Self.referenceDate)
        #expect(first != nil)
        #expect(first == second)

        let context = ModelContext(container)
        let coins = try context.fetch(FetchDescriptor<Coin>(predicate: #Predicate { $0.userID == userID }))
        #expect(coins.count == 1)
        #expect(coins.first?.balance == first?.coins)
    }

    @Test func losingRollGrantsNothing() throws {
        let (subject, _, _) = try makeSubject()
        var losing = UUID()
        while VariableReward.outcome(for: losing) != nil { losing = UUID() }
        #expect(subject.roll(sessionID: losing, at: Self.referenceDate) == nil)
        #expect(subject.consumePendingReveal(now: Self.referenceDate) == nil)
    }

    @Test func pendingRevealIsConsumedOnce() throws {
        let (subject, _, _) = try makeSubject()
        let sessionID = winningSessionID { _ in true }
        let grant = subject.roll(sessionID: sessionID, at: Self.referenceDate)

        #expect(subject.consumePendingReveal(now: Self.referenceDate.addingTimeInterval(5)) == grant)
        #expect(subject.consumePendingReveal(now: Self.referenceDate.addingTimeInterval(6)) == nil)
    }

    @Test func staleRevealIsNotShown() throws {
        let (subject, _, _) = try makeSubject()
        let sessionID = winningSessionID { _ in true }
        subject.roll(sessionID: sessionID, at: Self.referenceDate)

        let late = Self.referenceDate.addingTimeInterval(VariableReward.revealWindow + 1)
        #expect(subject.consumePendingReveal(now: late) == nil)
    }
}
