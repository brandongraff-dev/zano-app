// GoalsEditorView.swift
// App / Features / Settings
//
// The one place to change goals after onboarding (polish pass 2026-09-24). Pushed from Settings'
// "Goals" row, and presented from Today as `NavigationStack { GoalsEditorView() }` (so this view
// sets a title but owns no `NavigationStack`, and adds no close button — a modal presenter adds
// its own toolbar or relies on the sheet's swipe-down).
//
// docs/spec.md §3 (goal catalog), §8 rule 1 (start small), §24 (ADDITIVE goals only — no calorie
// ceilings, weight targets, or fasting). The "Add goal" list is exactly the goal types onboarding
// offers (`Screen10PlanReveal.planGoals`: gym workout, focus session, protein) — every one of them
// is "do more of something good". Targets can go down as well as up (a smaller bar is always
// allowed), but never to zero: a zero target would read as "done" without doing anything.
//
// Creation mirrors `Screen10PlanReveal.persistPlanIfNeeded()` field for field: title from
// `Copy.onboarding.planGoalTitle(for:)`, the same `unit` strings ("workouts" / "min" / "g"),
// `cadence: "daily"`, the same verification tiers, attached to the device's one `User`. Onboarding
// stores the workout goal as a weekly count with `cadence: "daily"`; that is mirrored as-is, not
// "fixed" here (flagged in this pass's report).
//
// Removing a goal sets `Goal.active = false` rather than deleting the row: `Goal` cascades its
// `GoalEvent` history on delete, and a user taking a goal off their plan should not lose their
// record. Re-adding a type reactivates the most recent inactive goal of that type.

import SwiftUI
import SwiftData
import Core

struct GoalsEditorView: View {
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var users: [User]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pendingRemoval: Goal?
    @State private var isChoosingNewGoal = false
    @State private var saveFailed = false
    @State private var stepTick = 0

    init() {}

    /// The additive goal types onboarding offers, in onboarding's order.
    private static let addableTypes: [GoalType] = [.workoutGym, .focusSession, .protein]

    private var currentUser: User? { users.first }

    private var activeGoals: [Goal] {
        goals.filter(\.active)
    }

    private var availableTypes: [GoalType] {
        Self.addableTypes.filter { type in !activeGoals.contains { $0.type == type } }
    }

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
        .confirmationDialog(
            Copy.settings.goalsAddDialogTitle,
            isPresented: $isChoosingNewGoal,
            titleVisibility: .visible
        ) {
            ForEach(availableTypes, id: \.self) { type in
                Button(Copy.onboarding.planGoalTitle(for: type)) { add(type) }
            }
            Button(Copy.common.cancel, role: .cancel) {}
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
                GoalRingGlyph(type: goal.type)

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

            if let target = goal.targetValue {
                targetStepper(goal: goal, value: Int(target), rule: rule)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
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
        } else if availableTypes.isEmpty {
            Text(Copy.settings.goalsAllAddedMessage)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
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
        }
    }

    /// Reactivates the newest inactive goal of `type` (keeps its history and target) or creates a
    /// new one exactly the way onboarding does.
    private func add(_ type: GoalType) {
        guard let user = currentUser, Self.addableTypes.contains(type) else { return }

        if let previous = goals.last(where: { $0.type == type && !$0.active && $0.user?.id == user.id }) {
            previous.active = true
        } else {
            let rule = GoalTargetRule(type: type, unit: nil)
            modelContext.insert(Goal(
                type: type,
                title: Copy.onboarding.planGoalTitle(for: type),
                targetValue: Double(rule.defaultValue),
                unit: rule.unit,
                cadence: "daily",
                verificationTier: rule.tier,
                user: user
            ))
        }
        if save() {
            Analytics.shared.capture(event: "goal_added", properties: ["type": type.rawValue])
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

// MARK: - Ring glyph

/// The goal's icon inside a thin ring in the goal's ring color — the same hue its ring uses on
/// Today, so a goal looks the same everywhere.
private struct GoalRingGlyph: View {
    let type: GoalType

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44

    var body: some View {
        let color = Theme.Colors.Ring.color(for: type)
        ZStack {
            Circle()
                .stroke(Theme.Colors.Ring.track(for: color), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: goalIconName(for: type))
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Target rules

/// Sensible target bounds and step per goal type, in the units onboarding stores. Values are
/// identifiers and numbers, not copy.
private struct GoalTargetRule {
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int
    let unit: String?
    let tier: VerificationTier

    init(type: GoalType, unit: String?) {
        switch type {
        case .workoutGym, .workoutHomeOutdoor:
            // Workouts per week (onboarding's Q4 target).
            self.init(range: 1...7, step: 1, defaultValue: 3, unit: "workouts", tier: .a)
        case .focusSession:
            // Minutes; 25 matches onboarding's `FocusSessionPreset.twentyFiveMinutes`.
            self.init(range: 5...180, step: 5, defaultValue: 25, unit: "min", tier: .a)
        case .protein:
            // Grams a day; 120 matches onboarding's placeholder baseline.
            self.init(range: 20...300, step: 5, defaultValue: 120, unit: "g", tier: .b)
        case .steps:
            self.init(range: 1_000...30_000, step: 500, defaultValue: 8_000, unit: "steps", tier: .a)
        case .water where unit == "oz":
            self.init(range: 8...200, step: 8, defaultValue: 64, unit: "oz", tier: .b)
        case .water:
            self.init(range: 250...5_000, step: 250, defaultValue: 2_000, unit: unit ?? "ml", tier: .b)
        default:
            self.init(range: 1...999, step: 1, defaultValue: 1, unit: unit, tier: .c)
        }
    }

    private init(range: ClosedRange<Int>, step: Int, defaultValue: Int, unit: String?, tier: VerificationTier) {
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.unit = unit
        self.tier = tier
    }
}

#Preview {
    NavigationStack {
        GoalsEditorView()
    }
    .modelContainer(for: [User.self, Goal.self], inMemory: true)
}
