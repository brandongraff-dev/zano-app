// GoalTemplatesCopy.swift
// Core / Copy
//
// Display copy for the goal templates (session 22; docs/spec.md §5.28). Plain and encouraging.

import Foundation

extension Copy {
    public enum goalTemplates {
        public static let startButton = "Start from a template"
        public static let sheetTitle = "Starter plans"
        public static let intro = "Pick the one that sounds like your week. You can change or remove any goal later, and ZANO adjusts the targets as you go."
        public static let addButton = "Add these goals"
        public static let doneNote = "Added. You can change any of them in Goals."
        public static let alreadyAllOn = "All of these are already on your plan."
        public static func alreadyOn(count: Int) -> String {
            count == 1 ? "1 is already on your plan and stays as it is." : "\(count) are already on your plan and stay as they are."
        }
        public static let failed = "Couldn't add them. Try again."

        public static func title(for template: GoalTemplate) -> String {
            switch template.id {
            case "student": "Student"
            case "examWeek": "Exam week"
            case "remoteWork": "Remote work day"
            case "nightShift": "Night shift"
            case "newParent": "New parent"
            case "backToGym": "Back to the gym"
            case "gentleStart": "Gentle start"
            default: template.id
            }
        }

        public static func subtitle(for template: GoalTemplate) -> String {
            switch template.id {
            case "student": "Four 25-minute study blocks, reading, water and a walk."
            case "examWeek": "Three hours of focus with stretch breaks and plenty of water."
            case "remoteWork": "Two hours of deep work, a walk and a stretch to break up the day."
            case "nightShift": "Water, protein and a short walk, whenever your day starts."
            case "newParent": "Small and doable: water, protein and a little walking."
            case "backToGym": "Three workouts a week, with protein and water behind them."
            case "gentleStart": "Just water and a short walk. A first win."
            default: ""
            }
        }
    }
}
