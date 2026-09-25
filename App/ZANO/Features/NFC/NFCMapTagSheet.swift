// NFCMapTagSheet.swift
// App / ZANO / Features / NFC
//
// The one-screen "what does this tag do" sheet (spec Tag Pack: "app maps it to an action in one
// screen"). Replaces Settings' `MapTagSheet` (named differently so both compile while the old one
// is being removed). Order on screen:
//   1. a live preview of the confirmation a tap will show ("+25 g protein logged"),
//   2. where the tag goes (placement grid; picking one pre-fills its suggested action),
//   3. what it does (all tag actions, each with a one-line explanation),
//   4. the action's one parameter (grams / ml / minutes / lock set / goal), if it has one,
//   5. a name (optional: falls back to the placement's name).
// Placement guidance from `NFCTagSetupInstructions` sits under the grid.

import SwiftUI
import SwiftData
import Core

struct NFCMapTagSheet: View {
    let tagID: UUID
    /// Non-nil when editing a saved tag.
    let existing: NFCTagMapping?
    /// Placement to start from for a new tag (e.g. `.lockCard` from Lock Card setup).
    let initialKind: NFCTagKind
    let onSaved: (NFCTagMapping) -> Void
    let onCancel: () -> Void

    init(
        tagID: UUID,
        existing: NFCTagMapping? = nil,
        initialKind: NFCTagKind = .custom,
        onSaved: @escaping (NFCTagMapping) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.tagID = tagID
        self.existing = existing
        self.initialKind = initialKind
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    @Query(sort: \Goal.title) private var allGoals: [Goal]
    @Query private var gyms: [Gym]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kind: NFCTagKind = .custom
    @State private var choice: NFCActionChoice = .logProtein
    @State private var proteinGrams = 25
    @State private var waterMilliliters = 750
    @State private var focusMinutes = 25
    @State private var selectedLockSetID: UUID?
    @State private var selectedGoalID: UUID?
    @State private var label = ""
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var saveFailed = false

    private static let focusPresets = [25, 50, 90]
    private static let proteinPresets = [20, 25, 30, 40]
    private static let waterPresets = [500, 750, 1000]

    /// Goals a tap may check off: honesty/one-tap tiers only (custom, reading, cold shower/sauna),
    /// never auto-verified ones — a tag must not stand in for a gym geofence.
    private var honorGoals: [Goal] {
        allGoals.filter { $0.active && [.custom, .reading, .coldShowerSauna].contains($0.type) }
    }

    private var hasConfirmedGym: Bool { gyms.contains { $0.confirmed } }
    private var hasDefaultLockSet: Bool { lockSets.contains { $0.isDefault } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    previewCard
                    kindSection
                    actionSection
                    parameterSection
                        .transition(.opacity)
                    labelSection
                }
                .padding(Theme.Spacing.md)
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: choice)
            }
            .scrollDismissesKeyboard(.interactively)
            .zanoBackdrop(glow: Theme.Colors.accent, intensity: 0.1)
            .navigationTitle(existing == nil ? Copy.nfc.mapSheetNewTitle : Copy.nfc.mapSheetEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) { save() }
                        .fontWeight(.semibold)
                        .disabled(resolvedAction == nil || isSaving)
                }
            }
            .onAppear(perform: loadInitialState)
            .onChange(of: kind) { _, newValue in
                guard hasLoaded else { return }
                if let suggested = newValue.suggestedAction { apply(suggested) }
            }
            .alert(Copy.nfc.mapSaveFailedTitle, isPresented: $saveFailed) {
                Button(Copy.common.ok, role: .cancel) {}
            } message: {
                Text(Copy.nfc.mapSaveFailedMessage)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.selection, trigger: kind)
        .sensoryFeedback(.selection, trigger: choice)
    }

    // MARK: Preview

    /// What a tap will say — the same line `TagTapToastView` shows after a real tap.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.nfc.mapPreviewEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: choice.symbol, tint: choice.tint, size: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(previewLine)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .contentTransition(.numericText())
                    Text(choice.detail)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoHero(radius: Theme.Radius.large, tint: choice.tint)
        .accessibilityElement(children: .combine)
    }

    private var previewLine: String {
        switch choice {
        case .logProtein: Copy.nfc.toastProtein(grams: proteinGrams)
        case .logWater: Copy.nfc.toastWater(milliliters: waterMilliliters)
        case .logCreatine: Copy.nfc.toastCreatine
        case .startFocus: Copy.nfc.toastFocusStarted(minutes: focusMinutes)
        case .gymCheckIn: Copy.nfc.toastGymCheckIn
        case .startLock, .lockCardToggle: Copy.nfc.toastLockStarted
        case .sunriseKey: Copy.nfc.toastSunrise
        case .logCustomGoal:
            Copy.nfc.toastCustomGoal(title: honorGoals.first { $0.id == selectedGoalID }?.title ?? Copy.nfc.actionCustomGoal)
        }
    }

    // MARK: Placement

    private var kindSection: some View {
        NFCSection(
            title: Copy.nfc.mapKindSectionTitle,
            footer: NFCTagSetupInstructions.placementGuidance(for: kind)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 4),
                spacing: Theme.Spacing.xs
            ) {
                ForEach(NFCTagKind.allCases) { option in
                    NFCKindTile(kind: option, isSelected: kind == option) {
                        kind = option
                    }
                }
            }
        }
    }

    // MARK: Action

    private var actionSection: some View {
        NFCSection(title: Copy.nfc.mapActionSectionTitle) {
            VStack(spacing: 0) {
                ForEach(NFCActionChoice.allCases) { option in
                    NFCChoiceRow(
                        title: option.title,
                        detail: option == choice ? option.detail : nil,
                        systemImage: option.symbol,
                        tint: option.tint,
                        isSelected: option == choice
                    ) {
                        choice = option
                    }
                    if option != NFCActionChoice.allCases.last {
                        NFCRowDivider(inset: Theme.Spacing.md + Theme.Metrics.iconBadgeSmall + Theme.Spacing.sm)
                    }
                }
            }
            .zanoCard()
        }
    }

    // MARK: Parameter

    @ViewBuilder
    private var parameterSection: some View {
        switch choice {
        case .logProtein:
            amountPicker(
                title: Copy.nfc.mapProteinAmountTitle,
                value: $proteinGrams,
                presets: Self.proteinPresets,
                step: 5,
                range: 5...100,
                format: { Copy.nfc.proteinAmount(grams: $0) }
            )
        case .logWater:
            amountPicker(
                title: Copy.nfc.mapWaterAmountTitle,
                value: $waterMilliliters,
                presets: Self.waterPresets,
                step: 50,
                range: 100...2000,
                format: { Copy.nfc.waterAmount(milliliters: $0) }
            )
        case .startFocus:
            amountPicker(
                title: Copy.nfc.mapFocusLengthTitle,
                value: $focusMinutes,
                presets: Self.focusPresets,
                step: 5,
                range: 5...180,
                format: { Copy.nfc.focusLength(minutes: $0) }
            )
        case .startLock:
            lockSetPicker
        case .logCustomGoal:
            goalPicker
        case .gymCheckIn:
            if !hasConfirmedGym { NFCNotice(text: Copy.nfc.mapNoConfirmedGymWarning) }
        case .lockCardToggle:
            if !hasDefaultLockSet { NFCNotice(text: Copy.nfc.mapNoDefaultLockSetWarning) }
        case .logCreatine, .sunriseKey:
            EmptyView()
        }
    }

    private func amountPicker(
        title: String,
        value: Binding<Int>,
        presets: [Int],
        step: Int,
        range: ClosedRange<Int>,
        format: @escaping (Int) -> String
    ) -> some View {
        NFCSection(title: title) {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text(format(value.wrappedValue))
                        .font(Theme.Typography.numeralMedium())
                        .foregroundStyle(Theme.Colors.text)
                        .contentTransition(.numericText(value: Double(value.wrappedValue)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Stepper(title, value: value, in: range, step: step)
                        .labelsHidden()
                }
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(presets, id: \.self) { preset in
                        let selected = value.wrappedValue == preset
                        Button {
                            value.wrappedValue = preset
                        } label: {
                            Text(format(preset))
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected ? Theme.Colors.accentFill : Theme.Colors.surface2)
                                )
                        }
                        .buttonStyle(.pressable(scale: 0.96))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: value.wrappedValue)
        }
    }

    private var lockSetPicker: some View {
        NFCSection(title: Copy.nfc.mapLockSetTitle) {
            if lockSets.isEmpty {
                NFCNotice(text: Copy.nfc.mapNoLockSetsWarning)
            } else {
                VStack(spacing: 0) {
                    ForEach(lockSets) { lockSet in
                        NFCChoiceRow(title: lockSet.name, isSelected: selectedLockSetID == lockSet.id) {
                            selectedLockSetID = lockSet.id
                        }
                        if lockSet.id != lockSets.last?.id { NFCRowDivider() }
                    }
                }
                .zanoCard()
            }
        }
    }

    private var goalPicker: some View {
        NFCSection(title: Copy.nfc.mapGoalTitle) {
            if honorGoals.isEmpty {
                NFCNotice(text: Copy.nfc.mapNoHonorGoalsWarning)
            } else {
                VStack(spacing: 0) {
                    ForEach(honorGoals) { goal in
                        NFCChoiceRow(title: goal.title, isSelected: selectedGoalID == goal.id) {
                            selectedGoalID = goal.id
                        }
                        if goal.id != honorGoals.last?.id { NFCRowDivider() }
                    }
                }
                .zanoCard()
            }
        }
    }

    // MARK: Name

    private var labelSection: some View {
        NFCSection(title: Copy.nfc.mapLabelTitle) {
            TextField(
                text: $label,
                prompt: Text(kind == .custom ? Copy.nfc.mapLabelPlaceholder : kind.nfcLabel)
                    .foregroundStyle(Theme.Colors.muted)
            ) {
                Text(Copy.nfc.mapLabelTitle)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.text)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .zanoCard(radius: Theme.Radius.small)
        }
    }

    // MARK: Logic

    private func loadInitialState() {
        guard !hasLoaded else { return }
        if let existing {
            kind = existing.kind
            label = existing.label
            apply(existing.action)
        } else {
            kind = initialKind
            if let suggested = initialKind.suggestedAction { apply(suggested) }
        }
        if selectedLockSetID == nil {
            selectedLockSetID = lockSets.first(where: \.isDefault)?.id ?? lockSets.first?.id
        }
        if selectedGoalID == nil {
            selectedGoalID = honorGoals.first?.id
        }
        // Set after the kind write so `onChange(of: kind)` doesn't overwrite an existing action.
        DispatchQueue.main.async { hasLoaded = true }
    }

    private func apply(_ action: NFCTagAction) {
        choice = NFCActionChoice(action)
        switch action {
        case .logProtein(let grams): proteinGrams = grams
        case .logWater(let ml): waterMilliliters = ml
        case .startFocus(let minutes): focusMinutes = minutes
        case .startLock(let lockSetID, _, _): selectedLockSetID = lockSetID
        case .logCustomGoal(let goalID): selectedGoalID = goalID
        case .logCreatine, .sunriseKey, .gymCheckIn, .lockCardToggle: break
        }
    }

    /// `nil` when the chosen action is missing its parameter (Save disabled).
    private var resolvedAction: NFCTagAction? {
        switch choice {
        case .logProtein: return proteinGrams > 0 ? .logProtein(grams: proteinGrams) : nil
        case .logWater: return waterMilliliters > 0 ? .logWater(milliliters: waterMilliliters) : nil
        case .logCreatine: return .logCreatine
        case .startFocus: return focusMinutes > 0 ? .startFocus(minutes: focusMinutes) : nil
        case .gymCheckIn: return .gymCheckIn
        case .startLock:
            guard let selectedLockSetID else { return nil }
            // Tag-started locks run Full mode and require all active goals (`StartLockIntent`'s
            // default when `requiredGoalIDs` is empty).
            return .startLock(lockSetID: selectedLockSetID, mode: .full, requiredGoalIDs: [])
        case .lockCardToggle: return .lockCardToggle
        case .sunriseKey: return .sunriseKey
        case .logCustomGoal:
            guard let selectedGoalID, honorGoals.contains(where: { $0.id == selectedGoalID }) else { return nil }
            return .logCustomGoal(goalID: selectedGoalID)
        }
    }

    private func save() {
        guard let action = resolvedAction else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapping = NFCTagMapping(
            id: tagID,
            kind: kind,
            label: trimmed.isEmpty ? kind.nfcLabel : trimmed,
            action: action,
            createdAt: existing?.createdAt ?? .now,
            lastTappedAt: existing?.lastTappedAt
        )
        isSaving = true
        Task {
            await NFCTagMapper.shared.saveMapping(mapping)
            isSaving = false
            Analytics.shared.capture(
                event: existing == nil ? "nfc_tag_mapped" : "nfc_tag_edited",
                properties: ["kind": kind.rawValue, "action": NFCActionChoice(action).rawValue]
            )
            onSaved(mapping)
        }
    }
}
