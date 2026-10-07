// BuddyMomentsTests.swift
// Core / Tests / CoreTests
//
// Session 36: the buddy's faces on the Fuel tab and in the focus flow
// (Core/Sources/Core/UI/Buddy/BuddyMoments.swift), and the focus Live Activity's new `outcome`
// field still decoding content written before it existed. Pure; no shared state.

import Testing
import Foundation
@testable import Core

@Suite("Buddy moments — Fuel and focus faces")
struct BuddyMomentsTests {

    // MARK: - Moment from a logged amount

    @Test func momentFollowsTheLoggedAmount() {
        #expect(BuddyPose.Moment(logged: 0, target: 150) == .needed)
        #expect(BuddyPose.Moment(logged: 25, target: 150) == .doing)
        #expect(BuddyPose.Moment(logged: 150, target: 150) == .done)
        #expect(BuddyPose.Moment(logged: 180, target: 150) == .done)
    }

    @Test func aGoalWithNoTargetYetIsNeverDone() {
        #expect(BuddyPose.Moment(logged: 0, target: 0) == .needed)
        #expect(BuddyPose.Moment(logged: 25, target: 0) == .doing)
    }

    // MARK: - Fuel tab

    @Test func justLoggedEatsOrSips() {
        #expect(BuddyPose.fuelPage(protein: .doing, water: .needed, justLogged: .protein) == .eating)
        #expect(BuddyPose.fuelPage(protein: .needed, water: .doing, justLogged: .water) == .sipping)
    }

    @Test func aLogThatFinishesTheGoalIsProud() {
        #expect(BuddyPose.fuelPage(protein: .done, water: .needed, justLogged: .protein) == .proud)
        #expect(BuddyPose.fuelPage(protein: .doing, water: .done, justLogged: .water) == .proud)
    }

    @Test func everyFuelGoalDoneIsProud() {
        #expect(BuddyPose.fuelPage(protein: .done, water: .done, justLogged: nil) == .proud)
        #expect(BuddyPose.fuelPage(protein: .done, water: nil, justLogged: nil) == .proud)
        #expect(BuddyPose.fuelPage(protein: nil, water: .done, justLogged: nil) == .proud)
    }

    @Test func nothingLoggedIsHungryThenThirsty() {
        #expect(BuddyPose.fuelPage(protein: .needed, water: .needed, justLogged: nil) == .hungry)
        #expect(BuddyPose.fuelPage(protein: .doing, water: .needed, justLogged: nil) == .thirsty)
        #expect(BuddyPose.fuelPage(protein: nil, water: .needed, justLogged: nil) == .thirsty)
        #expect(BuddyPose.fuelPage(protein: .done, water: .needed, justLogged: nil) == .thirsty)
    }

    @Test func underWayOrNoFuelGoalsEats() {
        #expect(BuddyPose.fuelPage(protein: .doing, water: .doing, justLogged: nil) == .eating)
        #expect(BuddyPose.fuelPage(protein: .done, water: .doing, justLogged: nil) == .eating)
        #expect(BuddyPose.fuelPage(protein: nil, water: nil, justLogged: nil) == .eating)
    }

    @Test func fuelFacesAreNeverSad() {
        let moments: [BuddyPose.Moment?] = [nil, .needed, .doing, .done]
        let logged: [GoalType?] = [nil, .protein, .water]
        for protein in moments {
            for water in moments {
                for justLogged in logged {
                    let pose = BuddyPose.fuelPage(protein: protein, water: water, justLogged: justLogged)
                    #expect(![BuddyPose.sad, .drained, .meh].contains(pose), "\(String(describing: protein)) \(String(describing: water)) \(String(describing: justLogged))")
                }
            }
        }
    }

    // MARK: - Focus

    @Test func focusFaceFollowsTheBlock() {
        #expect(BuddyPose.focus(isPaused: false) == .focused)
        #expect(BuddyPose.focus(isPaused: true) == .idle)
        #expect(BuddyPose.focus(isPaused: false, outcome: .done) == .proud)
        #expect(BuddyPose.focus(isPaused: true, outcome: .done) == .proud)
        #expect(BuddyPose.focus(isPaused: false, outcome: .broken) == .idle, "an early end rests, never sad")
    }

    @Test func focusContentWithoutAnOutcomeStillDecodes() throws {
        let old = Data(#"{"secondsRemaining":120,"isPaused":false}"#.utf8)
        let state = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: old)
        #expect(state.secondsRemaining == 120)
        #expect(state.outcome == nil)

        let ended = FocusActivityAttributes.ContentState(secondsRemaining: 0, isPaused: false, outcome: .done)
        let roundTripped = try JSONDecoder().decode(
            FocusActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(ended)
        )
        #expect(roundTripped == ended)
    }
}
