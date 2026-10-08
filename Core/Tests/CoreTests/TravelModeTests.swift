// Core/Tests/CoreTests/TravelModeTests.swift
//
// Tests the travel-mode "gym optional" rule (docs/spec.md §5.18) that every lock start and a
// running lock share (`TravelMode.requiredGoalIDs`), and the minutes a Health workout needs to
// count for the gym goal while traveling (`HomeWorkoutVerifier.travelGymRequiredMinutes`).
// Pure functions only: the live travel state sits in the App Group defaults, which tests don't touch.

import Foundation
import Testing
@testable import Core

@Suite("TravelMode — required goals while traveling")
struct TravelModeRequiredGoalsTests {
    private let gym = UUID()
    private let protein = UUID()
    private let steps = UUID()

    @Test("travel mode off keeps every goal, in order")
    func offKeepsAll() {
        let ids = TravelMode.requiredGoalIDs(
            [(id: gym, type: .workoutGym), (id: protein, type: .protein)],
            travelActive: false
        )
        #expect(ids == [gym, protein])
    }

    @Test("travel mode on drops the gym goal")
    func onDropsGym() {
        let ids = TravelMode.requiredGoalIDs(
            [(id: protein, type: .protein), (id: gym, type: .workoutGym), (id: steps, type: .steps)],
            travelActive: true
        )
        #expect(ids == [protein, steps])
    }

    @Test("a gym-only list keeps the gym so the lock can still be earned")
    func gymOnlyKeepsGym() {
        let ids = TravelMode.requiredGoalIDs([(id: gym, type: .workoutGym)], travelActive: true)
        #expect(ids == [gym])
    }

    @Test("an empty list stays empty")
    func emptyStaysEmpty() {
        #expect(TravelMode.requiredGoalIDs([], travelActive: true).isEmpty)
    }
}

@Suite("HomeWorkoutVerifier — gym goal minutes during travel mode")
struct TravelGymWorkoutMinutesTests {
    @Test("uses the gym goal's planned minutes")
    func usesTarget() {
        #expect(HomeWorkoutVerifier.travelGymRequiredMinutes(target: 45) == 45)
    }

    @Test("falls back to the default gym dwell without a target")
    func defaultDwell() {
        #expect(HomeWorkoutVerifier.travelGymRequiredMinutes(target: nil) == GymVerificationDefaults.requiredDwellMinutes)
    }

    @Test("never below the 20-minute workout floor")
    func floor() {
        #expect(HomeWorkoutVerifier.travelGymRequiredMinutes(target: 10) == HomeWorkoutVerificationDefaults.requiredMinutes)
    }
}
