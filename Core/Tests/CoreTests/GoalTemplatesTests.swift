// GoalTemplatesTests.swift
// Core / Tests / CoreTests
//
// The starter plans (session 22; docs/spec.md §5.28) stay safe and sane: every goal type can gate a lock
// (none are restrictive or unfinished), each template is small, types don't repeat inside one, targets are
// positive, and every template has copy.

import Testing
import Foundation
@testable import Core

@Suite("Goal templates — safe, small, complete")
struct GoalTemplatesTests {

    @Test func everyTemplateIsAdditiveAndSmall() {
        #expect(GoalTemplates.all.count == 7)
        for template in GoalTemplates.all {
            #expect(!template.items.isEmpty && template.items.count <= 5, "\(template.id)")
            let types = template.items.map(\.type)
            #expect(Set(types).count == types.count, "\(template.id) repeats a goal type")
            for item in template.items {
                #expect(item.type.canGateLock, "\(template.id): \(item.type) can't complete a lock")
                #expect(item.type != .custom, "\(template.id)")
                if let target = item.target { #expect(target > 0, "\(template.id) \(item.type)") }
            }
        }
    }

    @Test func templateIdsAreUniqueAndLookUp() {
        let ids = GoalTemplates.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(GoalTemplates.template(id: "student")?.items.first?.type == .focusSession)
        #expect(GoalTemplates.template(id: "nope") == nil)
    }

    @Test func everyTemplateHasCopy() {
        for template in GoalTemplates.all {
            #expect(Copy.goalTemplates.title(for: template) != template.id, "\(template.id) has no title")
            #expect(!Copy.goalTemplates.subtitle(for: template).isEmpty, "\(template.id) has no subtitle")
        }
    }

    @Test func nothingRestrictiveCanSneakIn() {
        // Titles and subtitles never talk about eating less, weight or fasting (docs/spec.md §24).
        let banned = ["calorie", "weight", "fast", "diet", "lose", "cut "]
        for template in GoalTemplates.all {
            let words = (Copy.goalTemplates.title(for: template) + " " + Copy.goalTemplates.subtitle(for: template)).lowercased()
            for word in banned { #expect(!words.contains(word), "\(template.id) mentions \(word)") }
        }
    }

    @Test func theStudyPlansUseWholeTwentyFiveMinuteBlocks() {
        let student = GoalTemplates.template(id: "student")?.items.first { $0.type == .focusSession }
        #expect((student?.target ?? 0) % 25 == 0, "four Pomodoro blocks")
    }
}
