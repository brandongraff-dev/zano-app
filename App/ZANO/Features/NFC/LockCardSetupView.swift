// LockCardSetupView.swift
// App / ZANO / Features / NFC
//
// Lock Card intro + pairing (spec: Lock Card — "Tap it to your phone to lock, tap again after goals
// to check status"; the phone-stand ritual: tap the card → lock starts → fold it out → stand the
// phone up across the desk).
//
// Pairing = `WriteTagFlow(initialKind: .lockCard)`: the card's tag is programmed/recognized, then
// the map sheet opens pre-set to Lock Card → `.lockCardToggle`, so it's one Save. The toggle never
// unlocks; this screen says so and points at the Emergency Unlock hold, which stays the only
// manual way out of a lock.
//
// Push inside an existing NavigationStack (e.g. from `NFCTagsView`).

import SwiftUI
import SwiftData
import Core

struct LockCardSetupView: View {
    init() {}

    @Query(sort: \LockSet.name) private var lockSets: [LockSet]

    @State private var cards: [NFCTagMapping] = []
    @State private var showPairing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDefaultLockSet: Bool { lockSets.contains { $0.isDefault } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                hero
                ritual
                emergencyNote
                pairing
            }
            .padding(Theme.Spacing.md)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: cards.map(\.id))
        }
        .zanoBackdrop(glow: Theme.Colors.lockedAmbient, intensity: 0.5)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.nfc.lockCardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showPairing) {
            WriteTagFlow(initialKind: .lockCard) { mapping in
                showPairing = false
                if mapping?.kind == .lockCard {
                    TagTapFeedback.shared.show(Copy.nfc.lockCardPairedToast, systemImage: "creditcard.fill")
                }
                Task { await reload() }
            }
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            TagTapScene(phase: cards.isEmpty ? .idle : .success, style: .card)
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.nfc.lockCardEyebrow)
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.accent)
                Text(Copy.nfc.lockCardTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.nfc.lockCardIntro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero(tint: Theme.Colors.lockedAmbient)
    }

    private var ritual: some View {
        NFCSection(title: Copy.nfc.lockCardRitualTitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                NFCStepRow(number: 1, title: Copy.nfc.lockCardStep1Title, detail: Copy.nfc.lockCardStep1Detail)
                NFCStepRow(number: 2, title: Copy.nfc.lockCardStep2Title, detail: Copy.nfc.lockCardStep2Detail)
                NFCStepRow(number: 3, title: Copy.nfc.lockCardStep3Title, detail: Copy.nfc.lockCardStep3Detail)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
        }
    }

    private var emergencyNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: "lock.open")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(Copy.nfc.lockCardEmergencyNote)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoWell()
    }

    @ViewBuilder
    private var pairing: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !cards.isEmpty {
                NFCSection(title: Copy.nfc.lockCardPairedCount(cards.count)) {
                    VStack(spacing: 0) {
                        ForEach(cards) { card in
                            HStack(spacing: Theme.Spacing.sm) {
                                IconBadge(systemName: "creditcard.fill", tint: Theme.Colors.accent, size: .small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.nfcDisplayName)
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(Theme.Colors.text)
                                    Text(card.lastTappedAt.map {
                                        Copy.nfc.lastTappedLabel(relative: $0.formatted(.relative(presentation: .named)))
                                    } ?? Copy.nfc.neverTappedLabel)
                                        .zanoText(.caption)
                                        .foregroundStyle(Theme.Colors.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.nfc.lockCardPairedTitle)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .accessibilityElement(children: .combine)
                            if card.id != cards.last?.id { NFCRowDivider() }
                        }
                    }
                    .zanoCard()
                }
            }

            if !hasDefaultLockSet {
                NFCNotice(text: Copy.nfc.lockCardNoDefaultLockSet)
            }

            PrimaryButton(
                title: cards.isEmpty ? Copy.nfc.lockCardPairButton : Copy.nfc.lockCardPairAnotherButton,
                systemImage: "wave.3.right",
                style: cards.isEmpty ? .standard : .secondary,
                isEnabled: NFCWriter.isAvailable
            ) {
                showPairing = true
            }

            Text(NFCWriter.isAvailable ? Copy.nfc.lockCardWorksWithTags : Copy.nfc.unavailableMessage)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func reload() async {
        cards = await NFCTagMapper.shared.allMappings().filter { mapping in
            if case .lockCardToggle = mapping.action { return true }
            return false
        }
    }
}

#Preview {
    NavigationStack {
        LockCardSetupView()
    }
    .modelContainer(for: [LockSet.self, Goal.self, Gym.self], inMemory: true)
}
