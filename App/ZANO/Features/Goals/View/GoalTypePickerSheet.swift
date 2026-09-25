// GoalTypePickerSheet.swift
// App / Features / Goals / View
//
// Adding a goal, in three steps inside one sheet (docs/spec.md §3 goal catalog + tiers, §8 rule 1
// start small, §24 additive goals only):
//   1. Choose — every goal type, grouped (Move, Fuel, Mind, Mornings, Your own), each with its ring
//      color icon, one line on what it is, and how it's verified.
//   2. Target — a sensible default and presets per type (or a name, for a custom goal). Binary
//      goals (creatine, cold shower, …) have no number to pick.
//   3. Next step — only when the goal needs setup that isn't done yet: save a gym, set up a tag,
//      or connect Apple Health. Types with nothing to set up close the sheet on add.
//
// The goal is saved at the end of step 2, so step 3 hides the back button (going back would add
// it twice). Owns its `NavigationStack`; present it with `.sheet { GoalTypePickerSheet() }`.

import SwiftUI
import SwiftData
import Core

struct GoalTypePickerSheet: View {
    /// Called after a goal is saved (new or reactivated).
    let onGoalAdded: (Goal) -> Void

    init(onGoalAdded: @escaping (Goal) -> Void = { _ in }) {
        self.onGoalAdded = onGoalAdded
    }

    fileprivate enum Route: Hashable {
        case target(GoalType)
        case nextStep(GoalType, title: String, step: GoalSetupStep)
    }

    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var users: [User]
    @Query private var gyms: [Gym]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []
    @State private var activeSetup: GoalSetupStep?
    @State private var saveFailed = false
    @State private var isAdding = false
    @State private var addedTick = 0

    private var activeTypes: Set<GoalType> {
        Set(goals.filter(\.active).map(\.type))
    }

    var body: some View {
        NavigationStack(path: $path) {
            GoalTypeChooser(activeTypes: activeTypes) { type in
                path.append(.target(type))
            }
            .navigationTitle(Copy.goals.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel) { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .target(let type):
                    GoalTargetStep(type: type, isAdding: isAdding) { target, customTitle in
                        add(type, target: target, customTitle: customTitle)
                    }
                case .nextStep(let type, let title, let step):
                    GoalNextStep(type: type, title: title, step: step) {
                        activeSetup = step
                    } onLater: {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: addedTick)
        .sheet(item: $activeSetup, onDismiss: { dismiss() }) { step in
            GoalSetupDestination(step: step)
        }
        .alert(Copy.settings.saveErrorTitle, isPresented: $saveFailed) {
            Button(Copy.common.ok, role: .cancel) {}
        } message: {
            Text(Copy.settings.saveErrorMessage)
        }
        .onAppear { Analytics.shared.capture(event: "goal_picker_viewed") }
    }

    private func add(_ type: GoalType, target: Int?, customTitle: String?) {
        guard !isAdding, let user = users.first else { return }
        isAdding = true
        let goal: Goal
        do {
            goal = try GoalCreation.add(
                type: type,
                target: target,
                customTitle: customTitle,
                user: user,
                existingGoals: goals,
                in: modelContext
            )
        } catch {
            isAdding = false
            saveFailed = true
            return
        }
        addedTick += 1
        onGoalAdded(goal)

        guard let step = GoalCatalog.setupStep(for: type) else {
            dismiss()
            return
        }
        let title = goal.title
        let hasGym = gyms.contains(where: \.confirmed)
        Task {
            let status = await GoalSetupStatus.load(for: [type], hasConfirmedGym: hasGym)
            isAdding = false
            if status.isMissing(for: type) {
                path.append(.nextStep(type, title: title, step: step))
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Step 1: choose

private struct GoalTypeChooser: View {
    let activeTypes: Set<GoalType>
    let onChoose: (GoalType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.goals.pickerSubtitle)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(GoalCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(category.title)
                            .zanoText(.eyebrow)
                            .foregroundStyle(Theme.Colors.muted)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(category.types, id: \.self) { type in
                                row(type)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
    }

    private func row(_ type: GoalType) -> some View {
        let isAdded = activeTypes.contains(type) && !GoalCatalog.allowsMultiple(type)
        let title = Copy.onboarding.planGoalTitle(for: type)
        return Button {
            onChoose(type)
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                GoalTypeGlyph(type: type)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.goals.description(for: type))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    GoalVerificationChip(type: type)
                        .padding(.top, Theme.Spacing.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isAdded {
                    Text(Copy.goals.pickerAlreadyAdded)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                } else {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
            .opacity(isAdded ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isAdded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAdded ? Copy.goals.pickerAlreadyAddedSpoken(title: title) : title)
    }
}

// MARK: - Step 2: target

private struct GoalTargetStep: View {
    let type: GoalType
    let isAdding: Bool
    let onAdd: (_ target: Int?, _ customTitle: String?) -> Void

    @State private var value: Int
    @State private var customTitle = ""
    @State private var stepTick = 0
    @FocusState private var nameFocused: Bool

    private let rule: GoalTargetRule

    init(type: GoalType, isAdding: Bool, onAdd: @escaping (_ target: Int?, _ customTitle: String?) -> Void) {
        self.type = type
        self.isAdding = isAdding
        self.onAdd = onAdd
        let rule = GoalTargetRule(type: type, unit: nil)
        self.rule = rule
        _value = State(initialValue: rule.defaultValue)
    }

    private var trimmedName: String {
        customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsRestrictive: Bool {
        type == .custom && GoalCatalog.isRestrictive(customTitle: trimmedName)
    }

    private var canAdd: Bool {
        guard !isAdding else { return false }
        guard type == .custom else { return true }
        return !trimmedName.isEmpty && !nameIsRestrictive
    }

    private var summary: String {
        Copy.settings.goalTargetSummary(type: type, value: value, unit: rule.unit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if type == .custom { nameField }
                if rule.hasTarget {
                    targetPicker
                } else {
                    Text(type == .mealPrep ? Copy.goals.targetWeeklyMessage : Copy.goals.targetBinaryMessage)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zanoCard()
                }
            }
            .padding(Theme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.goals.addGoalButton, systemImage: "plus", isEnabled: canAdd) {
                onAdd(rule.hasTarget ? value : nil, type == .custom ? trimmedName : nil)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .zanoBackdrop(glow: Theme.Colors.Ring.color(for: type))
        .navigationTitle(Copy.onboarding.planGoalTitle(for: type))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: stepTick)
        .onAppear { if type == .custom { nameFocused = true } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            GoalTypeGlyph(type: type, progress: 1)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.goals.description(for: type))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                GoalVerificationChip(type: type)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.goals.customNameEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
            TextField(Copy.goals.customNamePlaceholder, text: $customTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(Theme.Spacing.md)
                .zanoWell(radius: Theme.Radius.small)
                .onChange(of: customTitle) { _, newValue in
                    if newValue.count > 40 { customTitle = String(newValue.prefix(40)) }
                }
            Text(nameIsRestrictive ? Copy.goals.customNameRestrictiveMessage : Copy.goals.customNameFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(nameIsRestrictive ? Theme.Colors.warning : Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private var targetPicker: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(Copy.goals.targetEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.Spacing.sm) {
                stepButton(systemImage: "minus", isEnabled: value > rule.range.lowerBound) {
                    set(value - rule.step)
                }
                Text(summary)
                    .font(Theme.Typography.numeralMedium())
                    .foregroundStyle(Theme.Colors.text)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                stepButton(systemImage: "plus", isEnabled: value < rule.range.upperBound) {
                    set(value + rule.step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.goals.targetEyebrow)
            .accessibilityValue(summary)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(value + rule.step)
                case .decrement: set(value - rule.step)
                @unknown default: break
                }
            }

            if !rule.presets.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(rule.presets, id: \.self) { preset in
                        presetChip(preset)
                    }
                }
            }

            Text(Copy.goals.targetFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: Theme.Colors.Ring.color(for: type))
    }

    private func presetChip(_ preset: Int) -> some View {
        let selected = preset == value
        return Button {
            set(preset)
        } label: {
            Text(preset.formatted())
                .font(Theme.Typography.captionEmphasized)
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.text)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                .background {
                    if selected {
                        Capsule(style: .continuous).fill(Theme.Colors.accentFill)
                    } else {
                        ZanoGlass(Capsule(style: .continuous))
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.pressable(scale: 0.95))
        .accessibilityLabel(Copy.settings.goalTargetSummary(type: type, value: preset, unit: rule.unit))
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    private func set(_ newValue: Int) {
        let clamped = rule.clamped(newValue)
        guard clamped != value else { return }
        withAnimation(Theme.Motion.springStandard) { value = clamped }
        stepTick += 1
    }
}

// MARK: - Step 3: next step

private struct GoalNextStep: View {
    let type: GoalType
    let title: String
    let step: GoalSetupStep
    let onSetUp: () -> Void
    let onLater: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    GoalRing(
                        progress: 1,
                        color: Theme.Colors.Ring.color(for: type),
                        size: .medium,
                        center: .icon(systemName: goalIconName(for: type))
                    )
                    .accessibilityHidden(true)
                    Text(Copy.goals.addedTitle(title: title))
                        .zanoText(.title)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(Copy.goals.nextStepEyebrow)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        IconBadge(systemName: step.systemImage, tint: Theme.Colors.accent, size: .medium)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(step.title)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.text)
                            Text(step.message)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PrimaryButton(title: step.buttonTitle, systemImage: step.systemImage) {
                        Analytics.shared.capture(event: "goal_setup_started", properties: ["step": step.rawValue])
                        onSetUp()
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoHero(tint: Theme.Colors.accent)
            }
            .padding(Theme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.goals.setupLaterButton, style: .secondary) { onLater() }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xs)
        }
        .zanoBackdrop(glow: Theme.Colors.Ring.color(for: type))
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    GoalTypePickerSheet()
        .modelContainer(for: [User.self, Goal.self, Gym.self], inMemory: true)
}
