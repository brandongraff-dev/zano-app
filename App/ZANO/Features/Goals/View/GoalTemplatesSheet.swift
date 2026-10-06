// GoalTemplatesSheet.swift
// App / ZANO / Features / Goals / View
//
// "Starter plans" (session 22; docs/spec.md §5.28): pick a plan that matches your week (Student, Exam week,
// Remote work day, Night shift, New parent, Back to the gym, Gentle start) and add its goals in one tap.
// Goals already on the plan are left exactly as they are; nothing is removed. Goals are created through
// `GoalCreation.add`, the same path as the goal picker, so targets are clamped, tiers set and verifiers
// started the usual way.

import SwiftUI
import SwiftData
import Core

struct GoalTemplatesSheet: View {
    @Query private var users: [User]
    @Query private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var message: String?
    @State private var failed = false

    private var user: User? { users.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(Copy.goalTemplates.intro)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(failed ? Theme.Colors.danger : Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(GoalTemplates.all) { template in
                        card(template)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .zanoBackdrop()
            .navigationTitle(Copy.goalTemplates.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.done) { dismiss() }
                }
            }
        }
    }

    private func card(_ template: GoalTemplate) -> some View {
        let alreadyOn = template.items.filter { item in goals.contains { $0.active && $0.type == item.type } }.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.goalTemplates.title(for: template))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.goalTemplates.subtitle(for: template))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if alreadyOn > 0 {
                Text(alreadyOn == template.items.count ? Copy.goalTemplates.alreadyAllOn : Copy.goalTemplates.alreadyOn(count: alreadyOn))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            PrimaryButton(
                title: Copy.goalTemplates.addButton,
                style: .secondary,
                isEnabled: user != nil && alreadyOn < template.items.count
            ) { add(template) }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    private func add(_ template: GoalTemplate) {
        guard let user else { return }
        do {
            for item in template.items where !goals.contains(where: { $0.active && $0.type == item.type }) {
                _ = try GoalCreation.add(
                    type: item.type, target: item.target, customTitle: nil, user: user,
                    existingGoals: goals, in: modelContext
                )
            }
            failed = false
            message = Copy.goalTemplates.doneNote
        } catch {
            failed = true
            message = Copy.goalTemplates.failed
        }
    }
}
