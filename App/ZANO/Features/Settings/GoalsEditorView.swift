// GoalsEditorView.swift
// App / Features / Settings
//
// The one place to change goals after onboarding (polish pass 2026-09-24). Pushed from Settings'
// "Goals" row, and presented from Today as `NavigationStack { GoalsEditorView() }` (so this view
// sets a title but owns no `NavigationStack`, and adds no close button — a modal presenter adds
// its own toolbar or relies on the sheet's swipe-down).
//
// docs/spec.md §3 (goal catalog + verification tiers), §8 rule 1 (start small), §24 (ADDITIVE goals
// only — no calorie ceilings, weight targets, or fasting). Every `GoalType` can be added (all are
// additive); a custom goal is a user-named daily habit whose name is checked for restrictive goals.
// Adding happens in `GoalTypePickerSheet` (App/ZANO/Features/Goals), which also offers the goal's
// setup step. Targets can go down as well as up (a smaller bar is always allowed), but never to
// zero: a zero target would read as "done" without doing anything.
//
// Each card shows how its goal is verified and, when its setup step isn't done (no gym saved, no
// tag mapped, Health never asked), a "Set up" button that opens that step.
//
// Removing a goal sets `Goal.active = false` rather than deleting the row: `Goal` cascades its
// `GoalEvent` history on delete, and a user taking a goal off their plan should not lose their
// record. Re-adding a type reactivates the most recent inactive goal of that type
// (`GoalCreation.add`).

import SwiftUI
import SwiftData
import Core

struct GoalsEditorView: View {
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var users: [User]
    @Query private var gyms: [Gym]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pendingRemoval: Goal?
    @State private var isChoosingNewGoal = false
    @State private var saveFailed = false
    @State private var stepTick = 0
    @State private var activeSetup: GoalSetupStep?
    /// `nil` until first loaded, so no "Needs setup" flashes before the status is known.
    @State private var setupStatus: GoalSetupStatus?
    @State private var setupRefreshTick = 0

    /// `true` when shown as a sheet (from Today or Fuel): adds a Done button. Pushed from Settings,
    /// the back button already closes it.
    private let showsDoneButton: Bool
    @Environment(\.dismiss) private var dismiss

    init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    private var currentUser: User? { users.first }

    private var activeGoals: [Goal] {
        goals.filter(\.active)
    }

    /// Re-runs the setup-status load when the goal list, gyms, or a setup sheet change.
    private var setupStatusKey: [String] {
        activeGoals.map(\.type.rawValue) + ["gym:\(hasConfirmedGym)", "tick:\(setupRefreshTick)"]
    }

    private var hasConfirmedGym: Bool { gyms.contains(where: \.confirmed) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if activeGoals.isEmpty {
                    emptyState
                } else {
                    goalList
                }
                addSection
            }
            .padding(Theme.Spacing.md)
            .animation(
                reduceMotion ? .easeOut(duration: 0.18) : Theme.Motion.springStandard,
                value: activeGoals.map(\.id)
            )
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.goalsEditorTitle)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.done) { dismiss() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: stepTick)
        .onAppear { Analytics.shared.capture(event: "goals_editor_viewed") }
        .confirmationDialog(
            Copy.settings.goalRemoveConfirmTitle(title: pendingRemoval?.title ?? ""),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in if !isPresented { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { goal in
            Button(Copy.settings.goalRemoveButtonLabel, role: .destructive) { remove(goal) }
            Button(Copy.common.cancel, role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text(Copy.settings.goalRemoveConfirmMessage)
        }
        .sheet(isPresented: $isChoosingNewGoal, onDismiss: { setupRefreshTick += 1 }) {
            GoalTypePickerSheet()
        }
        .sheet(item: $activeSetup, onDismiss: { setupRefreshTick += 1 }) { step in
            GoalSetupDestination(step: step)
        }
        .task(id: setupStatusKey) {
            setupStatus = await GoalSetupStatus.load(
                for: activeGoals.map(\.type),
                hasConfirmedGym: hasConfirmedGym
            )
        }
        .alert(Copy.settings.saveErrorTitle, isPresented: $saveFailed) {
            Button(Copy.common.ok, role: .cancel) {}
        } message: {
            Text(Copy.settings.saveErrorMessage)
        }
    }

    // MARK: - Goals

    private var goalList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.settings.goalsYourGoalsSectionTitle)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(activeGoals) { goal in
                    goalCard(goal)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }

            Text(Copy.settings.goalsFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private func goalCard(_ goal: Goal) -> some View {
        let rule = GoalTargetRule(type: goal.type, unit: goal.unit)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                GoalTypeGlyph(type: goal.type)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(goal.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let target = goal.targetValue {
                        Text(summary(for: goal, value: Int(target)))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Menu {
                    Button(role: .destructive) {
                        pendingRemoval = goal
                    } label: {
                        Label(Copy.settings.goalRemoveMenuLabel, systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.Typography.icon(.medium))
                        .foregroundStyle(Theme.Colors.muted)
                        .minTapTarget()
                }
                .accessibilityLabel(Copy.common.moreOptions(for: goal.title))
            }

            verificationRow(goal)

            if let target = goal.targetValue {
                targetStepper(goal: goal, value: Int(target), rule: rule)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    /// How the goal is verified, plus a "Set up" button when its setup step isn't done. A required
    /// step (gym, Health, Sunrise Tag) is flagged "Needs setup"; an optional tag is just offered.
    private func verificationRow(_ goal: Goal) -> some View {
        let step = GoalCatalog.setupStep(for: goal.type)
        let missing = step != nil && (setupStatus?.isMissing(for: goal.type) ?? false)
        let required = GoalCatalog.setupIsRequired(for: goal.type)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                GoalVerificationChip(type: goal.type)
                Spacer(minLength: 0)
                if missing, let step { setupButton(step, required: required) }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GoalVerificationChip(type: goal.type)
                if missing, let step { setupButton(step, required: required) }
            }
        }
    }

    private func setupButton(_ step: GoalSetupStep, required: Bool) -> some View {
        Button {
            Analytics.shared.capture(event: "goal_setup_started", properties: ["step": step.rawValue, "from": "goals_editor"])
            activeSetup = step
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                if required {
                    Circle()
                        .fill(Theme.Colors.warning)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(required ? Copy.goals.setupNeededLabel : step.shortTitle)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(required ? Theme.Colors.text : Theme.Colors.accent)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.icon(.xsmall))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.96))
        .accessibilityLabel(step.shortTitle)
        .accessibilityHint(required ? Copy.goals.setupNeededLabel : "")
    }

    /// Minus / value / plus on glass. One VoiceOver element with an adjustable action, so the
    /// target is changed by swiping up/down instead of hunting for two small buttons.
    private func targetStepper(goal: Goal, value: Int, rule: GoalTargetRule) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            stepButton(systemImage: "minus", isEnabled: value > rule.range.lowerBound) {
                setTarget(goal, to: value - rule.step, rule: rule)
            }
            .accessibilityLabel(Copy.settings.goalTargetDecreaseLabel(title: goal.title))

            Text("\(value)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .frame(maxWidth: .infinity)

            stepButton(systemImage: "plus", isEnabled: value < rule.range.upperBound) {
                setTarget(goal, to: value + rule.step, rule: rule)
            }
            .accessibilityLabel(Copy.settings.goalTargetIncreaseLabel(title: goal.title))
        }
        .padding(Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.title)
        .accessibilityValue(summary(for: goal, value: value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setTarget(goal, to: value + rule.step, rule: rule)
            case .decrement: setTarget(goal, to: value - rule.step, rule: rule)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .zanoGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.92))
        .disabled(!isEnabled)
    }

    private func summary(for goal: Goal, value: Int) -> String {
        Copy.settings.goalTargetSummary(type: goal.type, value: value, unit: goal.unit)
    }

    // MARK: - Empty + add

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Copy.settings.goalsEmptyTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.settings.goalsEmptyMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    @ViewBuilder
    private var addSection: some View {
        if currentUser == nil {
            Text(Copy.settings.goalsNeedsProfileMessage)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity)
        } else {
            PrimaryButton(title: Copy.settings.goalsAddButtonLabel, systemImage: "plus") {
                isChoosingNewGoal = true
            }
        }
    }

    // MARK: - Persistence

    private func setTarget(_ goal: Goal, to newValue: Int, rule: GoalTargetRule) {
        let clamped = min(max(newValue, rule.range.lowerBound), rule.range.upperBound)
        guard Double(clamped) != goal.targetValue else { return }
        goal.targetValue = Double(clamped)
        if save() {
            stepTick += 1
        }
    }

    private func remove(_ goal: Goal) {
        pendingRemoval = nil
        goal.active = false
        if save() {
            Analytics.shared.capture(event: "goal_removed", properties: ["type": goal.type.rawValue])
            if goal.type == .steps {
                let id = goal.id
                Task { await StepsVerifier.shared.stopObserving(goalID: id) }
            }
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveFailed = true
            return false
        }
    }
}

#Preview {
    NavigationStack {
        GoalsEditorView()
    }
    .modelContainer(for: [User.self, Goal.self, Gym.self], inMemory: true)
}
