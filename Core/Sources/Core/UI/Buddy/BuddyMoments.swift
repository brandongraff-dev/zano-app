// BuddyMoments.swift
// Core / UI / Buddy
//
// Which face the buddy pulls on the Fuel tab and in the focus flow (session 36; docs/spec.md §5.17
// "Buddy emotions", §5.17a page companions). Pure mappings on top of `BuddyPose(goal:moment:)`, so
// Fuel's navigation-bar buddy, Today's focus status row and the Focus Live Activity all agree, and
// the rules are unit-tested (`BuddyTests`).
//
// Every face is encouraging (spec §24): hungry and thirsty read as "ready for it", and a focus block
// that ended early gets the plain resting face, never a sad one.

import Foundation

extension BuddyPose.Moment {
    /// `needed` with nothing logged yet, `doing` once something is, `done` at the target. A goal
    /// with no target yet (0) is never done by this rule: it reads as `doing` once anything is logged.
    public init(logged: Double, target: Double) {
        if target > 0, logged >= target {
            self = .done
        } else if logged > 0 {
            self = .doing
        } else {
            self = .needed
        }
    }
}

extension BuddyPose {
    /// The Fuel tab's buddy. `protein` / `water` are nil when that goal isn't on the plan.
    ///
    /// - Right after a log (`justLogged`): eating or sipping, or proud if that log finished the goal.
    /// - Every fuel goal on the plan done: proud.
    /// - Protein not started: hungry. Otherwise water not started: thirsty.
    /// - Anything else (under way, or no fuel goals at all): eating, the page's usual face.
    public static func fuelPage(protein: Moment?, water: Moment?, justLogged: GoalType?) -> BuddyPose {
        if let justLogged {
            let moment: Moment? = switch justLogged {
            case .protein: protein
            case .water: water
            default: nil
            }
            return BuddyPose(goal: justLogged, moment: moment == .done ? .done : .doing)
        }
        let present = [protein, water].compactMap { $0 }
        if !present.isEmpty, present.allSatisfy({ $0 == .done }) { return .proud }
        if protein == .needed { return .hungry }
        if water == .needed { return .thirsty }
        return .eating
    }

    /// The buddy during a focus block: focused while it runs, resting while paused, proud when the
    /// block verified, and resting (not sad) when it ended early.
    public static func focus(isPaused: Bool, outcome: FocusOutcome? = nil) -> BuddyPose {
        switch outcome {
        case .done: return .proud
        case .broken: return .idle
        case nil: return isPaused ? .idle : BuddyPose(goal: .focusSession, moment: .doing)
        }
    }
}
