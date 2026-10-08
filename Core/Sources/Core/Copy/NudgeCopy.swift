// NudgeCopy.swift
// Core / Copy
//
// User-facing copy for the four proactive nudges `NudgeScheduler` delivers as local notifications
// (docs/spec.md §8 rule 7 "Nudge scarcity", §9.3 Nudge Optimizer; the kinds are `NudgeKind` in
// `Core/Sources/Core/Social/NudgeSender.swift`). Same shape as `OnboardingDripCopy`: keyed by
// `NudgeTone` (whose raw values match `CoachVoice`'s), one `(title, body)` pair per voice.
//
// Rules this copy follows (CLAUDE.md, spec §8 rules 9 and 10, §24):
//   - Additive only. Protein is always "N g to go", never anything about eating less.
//   - No shame and no threats. An open goal is "left today", never "missed"/"failing"; the streak
//     nudge names the smallest next step (Plan B counts) instead of what's lost.
//   - Every string names something the user can still do tonight (spec §8 rule 7).

import Foundation

extension Copy {
    public enum nudges {

        /// Morning plan: today's goals, first thing. `goalTitles` are the user's own goal names.
        public static func morningPlan(tone: NudgeTone, goalTitles: [String]) -> (title: String, body: String) {
            let list = goalList(goalTitles)
            let count = goalTitles.count
            let goalWord = count == 1 ? "goal" : "goals"
            switch tone {
            case .hype:
                return ("Today's plan is set!", "\(list). Let's get it done.")
            case .toughLove:
                return ("Today's plan", "\(list). You set these. Start with the first one.")
            case .chill:
                return ("Here's today", "\(list). One at a time, whenever you're ready.")
            case .data:
                return ("Today: \(count) \(goalWord)", "\(list).")
            }
        }

        /// Protein last mile: most of today's protein is logged and a little is left.
        /// `amountToGo` is already rounded up; `unit` is the goal's unit (usually "g").
        public static func proteinLastMile(tone: NudgeTone, amountToGo: Int, unit: String) -> (title: String, body: String) {
            let amount = "\(amountToGo)\(unit)"
            switch tone {
            case .hype:
                return ("\(amount) to go!", "You're almost there on protein. One more meal or shake and it's done!")
            case .toughLove:
                return ("\(amount) of protein to go", "You're most of the way there. Finish it tonight.")
            case .chill:
                return ("Protein's nearly there", "Just \(amount) to go. A snack would do it.")
            case .data:
                return ("Protein: \(amount) to go", "Most of today's target is logged. \(amount) remaining.")
            }
        }

        /// Streak at risk: the user has a streak and today's goals are still open in the evening.
        public static func streakAtRisk(tone: NudgeTone, streak: Int, goalsOpen: Int) -> (title: String, body: String) {
            let goalWord = goalsOpen == 1 ? "goal" : "goals"
            let dayWord = streak == 1 ? "day" : "days"
            switch tone {
            case .hype:
                return ("\(streak)-day streak. Keep it rolling!", "\(goalsOpen) \(goalWord) left today. There's still time tonight.")
            case .toughLove:
                return ("\(streak)-day streak on the line", "\(goalsOpen) \(goalWord) left today. Tonight still counts, and Plan B counts too.")
            case .chill:
                return ("Still time today", "\(goalsOpen) \(goalWord) left. Plan B counts if tonight's a lighter one.")
            case .data:
                return ("Streak: \(streak) \(dayWord)", "Open today: \(goalsOpen) \(goalWord). Plan B counts toward the streak.")
            }
        }

        /// Weekly recap: the week's card is ready.
        public static func weeklyRecap(tone: NudgeTone) -> (title: String, body: String) {
            switch tone {
            case .hype:
                return ("Your week is in!", "Your weekly recap is ready. Come see what you pulled off.")
            case .toughLove:
                return ("Weekly recap", "Your week, in numbers. Take a look and set up the next one.")
            case .chill:
                return ("Your week, at a glance", "Your recap's ready whenever you want a look.")
            case .data:
                return ("Weekly recap ready", "Rings, best day, streak and time reclaimed for the week.")
            }
        }

        /// Up to three goal names, then "+N more", so a long list never overflows a banner.
        static func goalList(_ titles: [String]) -> String {
            let shown = titles.prefix(3).joined(separator: ", ")
            let extra = titles.count - 3
            return extra > 0 ? "\(shown) +\(extra) more" : shown
        }
    }
}
