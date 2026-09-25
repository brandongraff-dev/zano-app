// NFCTagsView.swift
// App / ZANO / Features / NFC
//
// The NFC tags screen (replaces `NFCTagSetupDetailView` inside `SettingsView.swift`). Push it from
// Settings inside that screen's NavigationStack; it sets its own title and has no stack of its own.
//
//   - hero: what tags do + the one accent CTA, "Add a tag" (→ `WriteTagFlow`: blank tags get
//     programmed, ZANO tags get recognized, then mapped),
//   - Lock Card row (→ `LockCardSetupView`),
//   - your tags: name, what a tap does, when it was last tapped; tap a row to edit, menu to remove,
//   - folded help: the Shortcuts no-touch automation and troubleshooting (`NFCTagSetupInstructions`).

import SwiftUI
import SwiftData
import Core

struct NFCTagsView: View {
    init() {}

    @Query(sort: \Goal.title) private var goals: [Goal]

    @State private var mappings: [NFCTagMapping] = []
    @State private var hasLoaded = false
    @State private var showWriteFlow = false
    @State private var editing: NFCTagMapping?
    @State private var pendingRemoval: NFCTagMapping?
    @State private var isHowItWorksExpanded = false
    @State private var isTroubleshootingExpanded = false
    @State private var tapFeedback = TagTapFeedback.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ordinaryTags: [NFCTagMapping] {
        mappings.filter { $0.kind != .lockCard }
    }

    private var lockCards: [NFCTagMapping] {
        mappings.filter { $0.kind == .lockCard }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                hero
                lockCardRow
                if !ordinaryTags.isEmpty {
                    yourTagsSection
                }
                helpGroup(title: Copy.nfc.howItWorksSectionTitle, isExpanded: $isHowItWorksExpanded) {
                    Text(NFCTagSetupInstructions.backgroundReadExplainer)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(NFCTagSetupInstructions.shortcutsAutomationSteps) { step in
                        NFCStepRow(number: step.id, title: step.title, detail: step.detail)
                    }
                }
                helpGroup(title: Copy.nfc.troubleshootingSectionTitle, isExpanded: $isTroubleshootingExpanded) {
                    ForEach(NFCTagSetupInstructions.troubleshooting, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(Theme.Colors.muted)
                                .frame(width: 4, height: 4)
                                .accessibilityHidden(true)
                            Text(tip)
                                .zanoText(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: mappings.map(\.id))
        }
        .zanoBackdrop(glow: Theme.Colors.accent, intensity: 0.12)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.nfc.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            if !hasLoaded {
                hasLoaded = true
                isHowItWorksExpanded = mappings.isEmpty
            }
        }
        // A tap elsewhere (background URL, Today) updates "last tapped" here.
        .onChange(of: tapFeedback.current?.id) { _, _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showWriteFlow) {
            WriteTagFlow { _ in
                showWriteFlow = false
                Task { await reload() }
            }
        }
        .sheet(item: $editing) { mapping in
            NFCMapTagSheet(
                tagID: mapping.id,
                existing: mapping,
                onSaved: { _ in
                    editing = nil
                    Task { await reload() }
                },
                onCancel: { editing = nil }
            )
        }
        .confirmationDialog(
            Copy.nfc.removeConfirmTitle(label: pendingRemoval?.nfcDisplayName ?? Copy.nfc.unnamedTagLabel),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { mapping in
            Button(Copy.nfc.removeTagButton, role: .destructive) {
                Task { await remove(mapping) }
            }
            Button(Copy.common.cancel, role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text(Copy.nfc.removeConfirmMessage)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            TagTapScene(phase: .idle)
                .scaleEffect(0.8)
                .frame(height: 150)

            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.nfc.heroTitle)
                    .zanoText(.title)
                    .foregroundStyle(Theme.Colors.text)
                Text(NFCWriter.isAvailable
                     ? (mappings.isEmpty ? Copy.nfc.emptyTagsMessage : Copy.nfc.heroMessage)
                     : Copy.nfc.unavailableMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            PrimaryButton(
                title: Copy.nfc.addTagButton,
                systemImage: "plus",
                isEnabled: NFCWriter.isAvailable
            ) {
                showWriteFlow = true
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero()
    }

    // MARK: Lock Card

    private var lockCardRow: some View {
        NavigationLink {
            LockCardSetupView()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "creditcard.fill", tint: Theme.Colors.accent, size: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.nfc.lockCardRowTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(lockCards.isEmpty ? Copy.nfc.lockCardRowUnpairedSubtitle : Copy.nfc.lockCardRowPairedSubtitle)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !lockCards.isEmpty {
                    ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.nfc.lockCardPairedTitle)
                }
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Your tags

    private var yourTagsSection: some View {
        NFCSection(title: Copy.nfc.yourTagsSectionTitle) {
            VStack(spacing: 0) {
                ForEach(ordinaryTags) { mapping in
                    tagRow(mapping)
                    if mapping.id != ordinaryTags.last?.id {
                        NFCRowDivider(inset: Theme.Spacing.md + Theme.Metrics.iconBadgeMedium + Theme.Spacing.sm)
                    }
                }
            }
            .zanoCard()
        }
    }

    private func tagRow(_ mapping: NFCTagMapping) -> some View {
        let choice = NFCActionChoice(mapping.action)
        return HStack(spacing: Theme.Spacing.sm) {
            Button {
                editing = mapping
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    IconBadge(systemName: choice.symbol, tint: choice.tint, size: .medium)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.nfcDisplayName)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Text(mapping.action.nfcSummary(goalTitle: goalTitle(for: mapping.action)))
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                        Text(lastTappedText(mapping))
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .combine)

            Menu {
                Button {
                    editing = mapping
                } label: {
                    Label(Copy.nfc.editTagButton, systemImage: "slider.horizontal.3")
                }
                Button(role: .destructive) {
                    pendingRemoval = mapping
                } label: {
                    Label(Copy.nfc.removeTagButton, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .minTapTarget()
            }
            .accessibilityLabel(Copy.common.moreOptions(for: mapping.nfcDisplayName))
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.sm)
        .contextMenu {
            Button {
                editing = mapping
            } label: {
                Label(Copy.nfc.editTagButton, systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                pendingRemoval = mapping
            } label: {
                Label(Copy.nfc.removeTagButton, systemImage: "trash")
            }
        }
    }

    private func goalTitle(for action: NFCTagAction) -> String? {
        guard case .logCustomGoal(let goalID) = action else { return nil }
        return goals.first { $0.id == goalID }?.title
    }

    private func lastTappedText(_ mapping: NFCTagMapping) -> String {
        guard let date = mapping.lastTappedAt else { return Copy.nfc.neverTappedLabel }
        return Copy.nfc.lastTappedLabel(relative: date.formatted(.relative(presentation: .named)))
    }

    // MARK: Help

    private func helpGroup<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // `DisclosureGroup`'s content closure is escaping; build the content once up front.
        let inner = content()
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                inner
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.sm)
        } label: {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
        }
        .tint(Theme.Colors.muted)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Data

    private func reload() async {
        mappings = await NFCTagMapper.shared.allMappings()
    }

    private func remove(_ mapping: NFCTagMapping) async {
        pendingRemoval = nil
        _ = await NFCTagMapper.shared.removeMapping(for: mapping.id)
        Analytics.shared.capture(event: "nfc_tag_removed", properties: ["kind": mapping.kind.rawValue])
        await reload()
    }
}

#Preview {
    NavigationStack {
        NFCTagsView()
    }
    .modelContainer(for: [Goal.self, LockSet.self, Gym.self], inMemory: true)
}
