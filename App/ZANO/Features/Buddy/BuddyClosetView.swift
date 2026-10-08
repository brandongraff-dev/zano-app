// BuddyClosetView.swift
// App / ZANO / Features / Buddy
//
// The Buddy Closet (session 15, 2026-10-05; docs/spec.md §5.17): where coins turn into looks for your
// buddy. A live preview of the buddy wearing whatever is selected, a row of slot chips (Skins, Hats,
// Eyewear, Neckwear, Back, Backdrops) and a grid of tiles, each showing the buddy wearing that one
// item. Tap a tile to try it on, then Buy (coins, through `CosmeticsStore`, the same closed catalog
// and Pro-free spending as the Cosmetics Shop), Wear, or Take off. Wearing saves per buddy in the
// App Group (`BuddyOutfit`), so every buddy sprite in the app draws it.
//
// Cosmetic only. Skins are bought per buddy; everything else is bought once and worn by any buddy.
// Earned gear (`BuddyGear`) is never sold and comes back when a bought item in its slot comes off.

import SwiftUI
import Core

struct BuddyClosetView: View {
    private enum Tab: Hashable, CaseIterable {
        case skin, hat, eyewear, neck, back, backdrop

        var slot: BuddyStyleSlot? {
            switch self {
            case .skin: nil
            case .hat: .hat
            case .eyewear: .eyewear
            case .neck: .neck
            case .back: .back
            case .backdrop: .backdrop
            }
        }

        var title: String { slot.map(Copy.buddyStyle.slotTitle) ?? Copy.buddyStyle.skinsTitle }
    }

    private enum Pick: Hashable {
        case skin(BuddySkin)
        case item(BuddyStyleItem)
    }

    private struct ClosetAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default
    @AppStorage(BuddyGear.storageKey, store: SharedDefaults.store) private var gear: BuddyGear = .bare
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: Tab = .skin
    @State private var worn = BuddyOutfit()
    @State private var pick: Pick?
    @State private var alert: ClosetAlert?
    @State private var isPurchasing = false
    @State private var successTick = 0

    private let store = CosmeticsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                wallet
                previewCard
                tabChips
                note
                grid
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .zanoBackdrop(glow: buddy.color)
        .navigationTitle(Copy.buddyStyle.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Session 47: the family portrait shows this outfit on everyone's phone (does nothing unless Household is live).
        .onDisappear { Task { await HouseholdBuddySync.syncIfNeeded() } }
        .task {
            worn = BuddyOutfit.stored(for: buddy)
            await store.refresh()
        }
        .onChange(of: tab) { _, _ in pick = nil }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.selection, trigger: pick)
        .alert(item: $alert) { shown in
            Alert(title: Text(shown.title), message: Text(shown.message), dismissButton: .default(Text(Copy.common.ok)))
        }
    }

    // MARK: Header

    private var wallet: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TrophyCoinGlyph(diameterAtDefaultSize: 24)
            NumeralText(Copy.cosmetics.coinBalanceAccessibilityLabel(balance: store.coinBalance), size: .large)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewOutfit: BuddyOutfit {
        switch pick {
        case .skin(let skin)?:
            var outfit = worn
            outfit.skin = skin
            return outfit
        case .item(let item)?:
            return worn.wearing(item, in: item.slot)
        case nil:
            return worn
        }
    }

    private var previewCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            OutfitSprite(buddy: buddy, pose: .happy, size: 128, outfit: previewOutfit, gear: gear, showsBackdrop: true)
            Text(pickTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            actionRow
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero()
    }

    private var pickTitle: String {
        switch pick {
        case .skin(let skin)?: Copy.buddyStyle.title(for: skin)
        case .item(let item)?: Copy.buddyStyle.title(for: item)
        case nil: Copy.buddyStyle.screenSubtitle
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if let pick {
            if isOwned(pick) {
                if isWorn(pick) {
                    PrimaryButton(title: Copy.buddyStyle.takeOffButtonTitle, style: .secondary) { takeOff(pick) }
                } else {
                    PrimaryButton(title: Copy.buddyStyle.wearButtonTitle) { wear(pick) }
                }
            } else {
                PrimaryButton(
                    title: Copy.cosmetics.purchaseButtonTitle(priceCoins: cosmetic(pick).priceCoins),
                    isEnabled: !isPurchasing
                ) { buy(pick) }
            }
        }
    }

    // MARK: Tabs and grid

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Tab.allCases, id: \.self) { chip in
                    let selected = chip == tab
                    Button { tab = chip } label: {
                        Text(chip.title)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(selected ? Theme.BuddyColors.onSignature : Theme.Colors.text)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Capsule().fill(selected ? buddy.color : Theme.Colors.glassFill))
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.Colors.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.pressable(scale: 0.94))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var note: some View {
        Text(tab == .skin ? Copy.buddyStyle.skinsNote(buddy: buddy) : Copy.buddyStyle.sharedItemsNote)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var picks: [Pick] {
        if let slot = tab.slot {
            return BuddyStyleItem.allCases.filter { $0.slot == slot }.map(Pick.item)
        }
        return BuddySkin.allCases.map(Pick.skin)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 3)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(picks, id: \.self) { entry in
                tile(entry)
            }
        }
    }

    private func tile(_ entry: Pick) -> some View {
        let name = title(entry)
        let state = stateLabel(entry)
        let selected = pick == entry
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        return Button { pick = entry } label: {
            VStack(spacing: Theme.Spacing.xxs) {
                OutfitSprite(buddy: buddy, pose: .happy, size: 64, outfit: soloOutfit(entry), gear: .bare,
                             showsBackdrop: tab == .backdrop)
                Text(name)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(state)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isWorn(entry) ? buddy.color : Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .top)
            .background { shape.fill(selected ? buddy.color.opacity(0.18) : Theme.Colors.glassFill) }
            .overlay { shape.strokeBorder(selected ? buddy.color : Theme.Colors.hairline, lineWidth: selected ? 2 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.94))
        .accessibilityLabel(Copy.buddyStyle.tileLabel(name, state: state))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The buddy wearing only this one entry, so a tile shows the item and nothing else.
    private func soloOutfit(_ entry: Pick) -> BuddyOutfit {
        switch entry {
        case .skin(let skin): BuddyOutfit(skin: skin)
        case .item(let item): BuddyOutfit().wearing(item, in: item.slot)
        }
    }

    // MARK: State

    private func title(_ entry: Pick) -> String {
        switch entry {
        case .skin(let skin): Copy.buddyStyle.title(for: skin)
        case .item(let item): Copy.buddyStyle.title(for: item)
        }
    }

    private func cosmetic(_ entry: Pick) -> CosmeticItem {
        switch entry {
        case .skin(let skin): BuddyStyleCatalog.cosmeticItem(skin, for: buddy)
        case .item(let item): BuddyStyleCatalog.cosmeticItem(item)
        }
    }

    private func isOwned(_ entry: Pick) -> Bool { store.isOwned(cosmetic(entry)) }

    private func isWorn(_ entry: Pick) -> Bool {
        switch entry {
        case .skin(let skin): worn.skin == skin
        case .item(let item): worn.item(in: item.slot) == item
        }
    }

    private func stateLabel(_ entry: Pick) -> String {
        if isWorn(entry) { return Copy.buddyStyle.equippedTag }
        if isOwned(entry) { return Copy.buddyStyle.ownedTag }
        return Copy.buddyStyle.priceLabel(coins: cosmetic(entry).priceCoins)
    }

    // MARK: Actions

    private func wear(_ entry: Pick) {
        switch entry {
        case .skin(let skin): worn.skin = skin
        case .item(let item): worn = worn.wearing(item, in: item.slot)
        }
        save()
    }

    private func takeOff(_ entry: Pick) {
        switch entry {
        case .skin: worn.skin = nil
        case .item(let item): worn = worn.wearing(nil, in: item.slot)
        }
        save()
    }

    private func save() {
        worn.save(for: buddy)
        WidgetRefresh.reloadAll()
    }

    private func buy(_ entry: Pick) {
        guard !isPurchasing else { return }
        isPurchasing = true
        let item = cosmetic(entry)
        Task {
            let outcome = await store.purchase(item)
            isPurchasing = false
            switch outcome {
            case .purchased:
                successTick += 1
                wear(entry)
            case .alreadyOwned:
                break
            case .insufficientCoins(let shortBy):
                alert = ClosetAlert(
                    title: Copy.cosmetics.insufficientCoinsAlertTitle,
                    message: Copy.cosmetics.insufficientCoinsAlertMessage(shortBy: shortBy)
                )
            case .proRequired, .noSignedInUser, .unknownItem, .storeFailure:
                alert = ClosetAlert(title: Copy.common.somethingWentWrongTitle, message: Copy.common.somethingWentWrongMessage)
            }
        }
    }
}

/// The buddy drawn with an explicit outfit (the live preview and each tile). `BuddySprite` reads the
/// saved outfit; the closet needs to show items that aren't saved yet.
private struct OutfitSprite: View {
    let buddy: Buddy
    let pose: BuddyPose
    let size: CGFloat
    let outfit: BuddyOutfit
    let gear: BuddyGear
    var showsBackdrop = false

    var body: some View {
        Group {
            if let image = buddy.image(pose: pose, gear: gear, outfit: outfit, showsBackdrop: showsBackdrop) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: showsBackdrop && outfit.backdrop != nil ? size * 0.16 : 0))
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { BuddyClosetView() }
        .preferredColorScheme(.dark)
}
