// GoalTemplates.swift
// Core / Retention
//
// Starter plans for real life (session 22, 2026-10-05; docs/spec.md §5.28, §8 rule 1 "start small"):
// "Student", "Exam week", "Remote work day", "Night shift", "New parent", "Back to the gym",
// "Gentle start". One tap adds the goals for someone in that situation, so setup is a choice instead of
// a form. Targets are modest on purpose and the adaptive engine moves them from there (§9.1).
//
// Every item is additive (§24): there is no template with a calorie, weight or fasting goal, and a
// test holds the whole catalog to goal types that can gate a lock. A target is in the goal type's own
// unit (minutes of focus, ml of water, grams of protein, steps, workouts a week); the app clamps it to
// the goal's allowed range when it creates the goal, and binary goals (reading, stretching) ignore it.
//
// "Pomodoro" lives in the focus targets: 100 minutes is four 25-minute blocks (the 25-minute focus
// preset) with short breaks between.

import Foundation

public struct GoalTemplate: Sendable, Identifiable, Equatable {
    public struct Item: Sendable, Equatable {
        public let type: GoalType
        public let target: Int?

        public init(_ type: GoalType, target: Int? = nil) {
            self.type = type
            self.target = target
        }
    }

    public let id: String
    public let items: [Item]

    public init(id: String, items: [Item]) {
        self.id = id
        self.items = items
    }
}

public enum GoalTemplates {
    /// In the order they are offered.
    public static let all: [GoalTemplate] = [
        GoalTemplate(id: "student", items: [
            .init(.focusSession, target: 100), .init(.reading), .init(.water, target: 2_000), .init(.steps, target: 6_000),
        ]),
        GoalTemplate(id: "examWeek", items: [
            .init(.focusSession, target: 180), .init(.stretchMobility), .init(.water, target: 2_500),
        ]),
        GoalTemplate(id: "remoteWork", items: [
            .init(.focusSession, target: 120), .init(.steps, target: 5_000), .init(.stretchMobility), .init(.water, target: 2_500),
        ]),
        GoalTemplate(id: "nightShift", items: [
            .init(.water, target: 2_500), .init(.protein, target: 100), .init(.steps, target: 4_000), .init(.stretchMobility),
        ]),
        GoalTemplate(id: "newParent", items: [
            .init(.water, target: 2_000), .init(.protein, target: 80), .init(.steps, target: 3_000),
        ]),
        GoalTemplate(id: "backToGym", items: [
            .init(.workoutGym, target: 3), .init(.protein, target: 100), .init(.water, target: 2_500),
        ]),
        GoalTemplate(id: "gentleStart", items: [
            .init(.water, target: 1_500), .init(.steps, target: 3_000),
        ]),
    ]

    public static func template(id: String) -> GoalTemplate? {
        all.first { $0.id == id }
    }
}
