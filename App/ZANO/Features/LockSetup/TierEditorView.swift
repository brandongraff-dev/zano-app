// TierEditorView.swift
// App / Features / LockSetup
//
// docs/spec.md §2 "Partial unlocks are possible ('finish 2 of 3 goals to unlock messaging apps, all
// 3 for TikTok')", §4 v2 "Partial unlock tiers (messaging vs social vs games)". A per-lock-set
// ladder: each tier names some apps and how many goals open them early. Everything else still
// unlocks together when all goals are done (the normal earned unlock), so there's no "all goals"
// tier to configure. Saved through `PartialUnlockTierStore` (Core, App Group, device-local — the
// tiers hold FamilyControls tokens, which never leave the device) and applied by
// `LockEngineManager.evaluateUnlockEligibility` whenever a goal completes.

import SwiftUI
import FamilyControls
import Core

struct TierEditorView: View {
    let lockSetID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [TierDraft] = []
    @State private var didLoad = false
    @State private var errorMessage: String?

    private static let maxGoals = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.lockSetup.tiersIntro)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)

                if drafts.isEmpty {
                    Text(Copy.lockSetup.tiersEmpty)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.horizontal, Theme.Spacing.xs)
                }

                ForEach($drafts) { $draft in
                    LockRulesSection {
                        TextField(Copy.lockSetup.tierNamePlaceholder, text: $draft.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .accessibilityLabel(Copy.lockSetup.tierNameLabel)
                        Divider().overlay(Theme.Colors.hairline)
                        Stepper(
                            Copy.lockSetup.tierThreshold(goals: draft.goalCount),
                            value: $draft.goalCount,
                            in: 1...Self.maxGoals
                        )
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        Divider().overlay(Theme.Colors.hairline)
                        Text(Copy.lockSetup.tierAppsLabel)
                            .zanoText(.eyebrow)
                            .foregroundStyle(Theme.Colors.muted)
                        AppPickerView(selection: $draft.selection)
                        Button(Copy.lockSetup.tierRemoveButton, role: .destructive) {
                            let id = draft.id
                            drafts.removeAll { $0.id == id }
                        }
                        .font(Theme.Typography.captionEmphasized)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                    }
                }

                Button {
                    drafts.append(
                        TierDraft(
                            name: Copy.lockSetup.tierDefaultName(index: drafts.count + 1),
                            goalCount: min((drafts.map(\.goalCount).max() ?? 0) + 1, Self.maxGoals)
                        )
                    )
                } label: {
                    Label(Copy.lockSetup.tierAddButton, systemImage: "plus")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                }
                .buttonStyle(.pressable)
                .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }
            .padding(Theme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .zanoBackdrop()
        .navigationTitle(Copy.lockSetup.tiersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.lockSetup.saveButtonLabel, action: save)
            }
        }
        .onAppear(perform: load)
        .alert(
            Copy.lockSetup.saveErrorTitle,
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(Copy.common.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        drafts = PartialUnlockTierStore.tiers(for: lockSetID).map { tier in
            TierDraft(
                id: tier.id,
                name: tier.name,
                goalCount: max(1, tier.requiredCompletedGoalCount),
                selection: tier.selection ?? FamilyActivitySelection()
            )
        }
    }

    private func save() {
        guard drafts.allSatisfy({ !$0.selection.isEmptySelection }) else {
            errorMessage = Copy.lockSetup.tierNeedsApps
            return
        }
        do {
            let tiers = try drafts.enumerated().map { index, draft in
                let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return try PartialUnlockTier(
                    id: draft.id,
                    name: trimmed.isEmpty ? Copy.lockSetup.tierDefaultName(index: index + 1) : trimmed,
                    requiredCompletedGoalCount: draft.goalCount,
                    selection: draft.selection
                )
            }
            PartialUnlockTierStore.setTiers(tiers, for: lockSetID)
            dismiss()
        } catch {
            errorMessage = Copy.lockSetup.saveErrorMessage
        }
    }
}

/// Editable, in-memory tier — becomes a `PartialUnlockTier` on save.
private struct TierDraft: Identifiable {
    var id = UUID()
    var name: String
    var goalCount: Int
    var selection = FamilyActivitySelection()
}

private extension FamilyActivitySelection {
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
