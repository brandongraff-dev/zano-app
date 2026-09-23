// CosmeticsShopView.swift
// App / Features / Trophy
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §5.17 Trophy Case & Cosmetics: "Coins from verified goals buy themes, ring styles,
// shield backgrounds, and coach voice packs. Cosmetics only; never sell power (no buying
// unlocks)." docs/spec.md §21 Monetization & Paywall lists "cosmetics" under Pro, and repeats the
// hard rule generally: "Never sell: unlocks, streak restores, or anything that lets money bypass
// the goal."
//
// This screen is the browse/purchase UI for `CosmeticsStore` (this task's other owned file,
// `Core/Sources/Core/Retention/CosmeticsStore.swift` — read in full before writing this one; its
// header explains exactly how/why "never sell power" is enforced in that file's code, not just
// documented here). This view itself adds no new enforcement of its own beyond what that file
// already guarantees structurally — it only ever calls `CosmeticsStore.shared.purchase(_:)` with
// an item taken straight from `CosmeticsStore.catalog` (never a hand-built `CosmeticItem`), so
// every purchase this screen can possibly trigger already has to pass that file's closed-catalog
// check.
//
// Reached from `TrophyCaseView` (this same task, same directory) via a `NavigationLink`; also
// usable standalone (e.g. a future Settings "Cosmetics" row) since it owns no navigation chrome
// of its own beyond `.navigationTitle` — same convention every other `App/ZANO/Features` screen
// in this codebase follows.
//
// ASSUMED API — `Copy.cosmetics.*` / `Copy.common.*` (`Core/Sources/Core/Copy`, not owned by this
// task). Follows the exact precedent `LockSetupView.swift`/`ProgressView.swift`/
// `TrophyCaseView.swift` (this task's sibling file) already set.
//
//   Copy.cosmetics.screenTitle: String                                  // "Cosmetics Shop"
//   Copy.cosmetics.screenSubtitle: String                               // e.g. "Spend coins you
//                                                                       // earned from real goals."
//   Copy.cosmetics.categoryPickerAccessibilityLabel: String             // "Category" — VoiceOver
//                                                                       // label for the segmented
//                                                                       // picker; not shown as text
//   Copy.cosmetics.categoryTitle(_ category: CosmeticCategory) -> String
//       // "Themes" / "Ring Styles" / "Shield Backgrounds" / "Coach Voice Packs"
//   Copy.cosmetics.title(forKey: String) -> String                      // per-item display name,
//                                                                       // keyed like
//                                                                       // Copy.badges.title(forKey:)
//   Copy.cosmetics.itemDescription(forKey: String) -> String            // one-line flavor text
//   Copy.cosmetics.equipButtonTitle: String                             // "Equip"
//   Copy.cosmetics.equippedButtonTitle: String                          // "Equipped"
//   Copy.cosmetics.equippedBadgeLabel: String                           // small inline tag
//   Copy.cosmetics.purchaseButtonTitle(priceCoins: Int) -> String       // "Buy · 250"
//   Copy.cosmetics.proUpsellBannerText: String                          // shown when
//                                                                       // !isProSubscriber
//   Copy.cosmetics.proRequiredAlertTitle: String
//   Copy.cosmetics.proRequiredAlertMessage: String
//   Copy.cosmetics.insufficientCoinsAlertTitle: String
//   Copy.cosmetics.insufficientCoinsAlertMessage(shortBy: Int) -> String
//   Copy.cosmetics.coinBalanceAccessibilityLabel(balance: Int) -> String  // shared with
//                                                                        // TrophyCaseView; declared
//                                                                        // once, canonical here
//   Copy.common.ok: String                                              // already assumed
//                                                                       // elsewhere (LockSetupView)
//   Copy.common.somethingWentWrongTitle: String                         // new, generic
//   Copy.common.somethingWentWrongMessage: String                       // new, generic
//
// Every catalog key `Copy.cosmetics.title(forKey:)`/`itemDescription(forKey:)` needs copy for —
// the exact keys `CosmeticsStore.catalog` defines today, listed here as a checklist for whoever
// implements `Copy.cosmetics`:
//   theme_classic, theme_electric_blue, theme_magenta_pulse, theme_gold_rush, theme_ice_mint,
//   ring_solid, ring_gradient_sweep, ring_dashed_pulse, ring_glow_trail, ring_double_ring,
//   shield_classic, shield_city_skyline, shield_gym_floor, shield_mountain_dawn,
//   shield_abstract_wave, coachpack_stock, coachpack_captain_intensity, coachpack_zen_minimal,
//   coachpack_data_stream, coachpack_hype_squad
//
// Item icons (SF Symbols) are kept as small, file-scoped reference data below (`CosmeticIconMap`)
// — not copy, same convention `TrophyCaseView.swift`'s `TrophyMilestone`/`ProgressView.swift`'s
// `ProgressBadgeIconMap` already establish.

import SwiftUI
import Core

/// Browse-and-purchase UI for `CosmeticsStore` (spec §5.17). A segmented category picker over a
/// scrolling list of item cards; each card's action row is either "Buy · N coins" (not yet owned)
/// or "Equip"/"Equipped" (owned) — `CosmeticsStore.shared` is the single source of truth for which
/// state a card is in, so this view never tracks ownership/equipped state itself.
public struct CosmeticsShopView: View {
    @State private var selectedCategory: CosmeticCategory = .theme
    @State private var pendingPurchaseKey: String?
    @State private var activeAlert: ShopAlert?
    @State private var purchaseSuccessTick = 0

    public init() {}

    public var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            header
            if !CosmeticsStore.shared.isProSubscriber {
                proUpsellBanner
            }
            categoryPicker
            itemList
        }
        .padding(.top, Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .navigationTitle(Copy.cosmetics.screenTitle)
        .task { await CosmeticsStore.shared.refresh() }
        .sensoryFeedback(.success, trigger: purchaseSuccessTick)
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(Copy.common.ok))
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(Copy.cosmetics.screenSubtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.sm)
            CoinBalancePill(balance: CosmeticsStore.shared.coinBalance)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var proUpsellBanner: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
            Text(Copy.cosmetics.proUpsellBannerText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        Picker(Copy.cosmetics.categoryPickerAccessibilityLabel, selection: $selectedCategory) {
            ForEach(CosmeticCategory.allCases, id: \.self) { category in
                Text(Copy.cosmetics.categoryTitle(category)).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Item list

    private var itemList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CosmeticsStore.items(in: selectedCategory)) { item in
                    CosmeticItemCard(
                        item: item,
                        isOwned: CosmeticsStore.shared.isOwned(item),
                        isEquipped: CosmeticsStore.shared.isEquipped(item),
                        canAfford: CosmeticsStore.shared.coinBalance >= item.priceCoins,
                        isPurchasing: pendingPurchaseKey == item.key,
                        onPurchase: { purchase(item) },
                        onEquip: { equip(item) }
                    )
                }
            }
            .padding(Theme.Spacing.md)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func purchase(_ item: CosmeticItem) {
        guard pendingPurchaseKey == nil else { return }
        pendingPurchaseKey = item.key
        Task {
            let outcome = await CosmeticsStore.shared.purchase(item)
            pendingPurchaseKey = nil
            handle(outcome)
        }
    }

    private func equip(_ item: CosmeticItem) {
        CosmeticsStore.shared.equip(item)
    }

    private func handle(_ outcome: CosmeticPurchaseOutcome) {
        switch outcome {
        case .purchased:
            purchaseSuccessTick += 1
        case .alreadyOwned:
            break
        case .proRequired:
            activeAlert = ShopAlert(
                title: Copy.cosmetics.proRequiredAlertTitle,
                message: Copy.cosmetics.proRequiredAlertMessage
            )
        case .insufficientCoins(let shortBy):
            activeAlert = ShopAlert(
                title: Copy.cosmetics.insufficientCoinsAlertTitle,
                message: Copy.cosmetics.insufficientCoinsAlertMessage(shortBy: shortBy)
            )
        case .noSignedInUser, .unknownItem, .storeFailure:
            activeAlert = ShopAlert(
                title: Copy.common.somethingWentWrongTitle,
                message: Copy.common.somethingWentWrongMessage
            )
        }
    }
}

// MARK: - File-scoped supporting types

private struct ShopAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// One item card: icon, title/description, an "Equipped" tag when applicable, and the buy/equip
/// action row. Purely a rendering of state passed in from `CosmeticsShopView` — never reads
/// `CosmeticsStore` itself, so it's trivially previewable in every ownership/afford combination.
private struct CosmeticItemCard: View {
    let item: CosmeticItem
    let isOwned: Bool
    let isEquipped: Bool
    let canAfford: Bool
    let isPurchasing: Bool
    let onPurchase: () -> Void
    let onEquip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.Colors.surface2)
                        .frame(width: 44, height: 44)
                    Image(systemName: CosmeticIconMap.systemImage(forKey: item.key, category: item.category))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOwned ? Theme.Colors.accent : Theme.Colors.muted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(Copy.cosmetics.title(forKey: item.key))
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        if isEquipped {
                            Text(Copy.cosmetics.equippedBadgeLabel)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.background)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accent, in: Capsule())
                        }
                    }
                    Text(Copy.cosmetics.itemDescription(forKey: item.key))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            actionRow
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    @ViewBuilder
    private var actionRow: some View {
        if isOwned {
            PrimaryButton(
                title: isEquipped ? Copy.cosmetics.equippedButtonTitle : Copy.cosmetics.equipButtonTitle,
                systemImage: isEquipped ? "checkmark.circle.fill" : nil,
                isEnabled: !isEquipped,
                action: onEquip
            )
        } else {
            PrimaryButton(
                title: Copy.cosmetics.purchaseButtonTitle(priceCoins: item.priceCoins),
                systemImage: "seal.fill",
                isEnabled: canAfford && !isPurchasing,
                action: onPurchase
            )
        }
    }
}

/// A small coin-balance capsule — visually identical to, but a separate file-scoped copy of,
/// `TrophyCaseView.swift`'s own `CoinBalancePill` (both `private`, so neither file can reach the
/// other's; duplicating ~15 lines here matches this codebase's existing convention of small,
/// self-contained per-file view helpers, e.g. `ProgressView.swift`'s `BadgeTile`).
private struct CoinBalancePill: View {
    let balance: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "seal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
            // See the identical comment on `TrophyCaseView.swift`'s copy of this same tiny view —
            // docs/design/animation-opportunities.md row 12. Kept as a duplicated, file-scoped
            // change (not factored into a shared helper) for the same reason the view itself is
            // already duplicated rather than shared, per this file's own header comment.
            Text("\(balance)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
                .contentTransition(.numericText(value: Double(balance)))
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3), value: balance)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.cosmetics.coinBalanceAccessibilityLabel(balance: balance))
    }
}

/// SF Symbol per catalog key, with a per-category fallback for any key this map doesn't (yet)
/// special-case — e.g. a future catalog addition still renders *something* sensible instead of a
/// blank icon slot. Reference data only, not copy — see this file's header.
///
/// Chosen from training-knowledge recall of Apple's SF Symbols catalog, not confirmed against the
/// SF Symbols app or an Xcode build (no Mac available this session — see CLAUDE.md's environment
/// status). Names avoided here on purpose for being unusually specific compound names this task
/// could not verify with confidence (e.g. an invented "circles.hexagonpath"-style combination);
/// everything actually used above is a plain, single-glyph symbol or a very common `.circle.fill`/
/// `.fill` variant of one, which is the safest bet without being able to check. Still worth a
/// spot-check on a Mac before shipping — a wrong name renders as blank space, not a crash, so this
/// is a cosmetic-polish risk only, never a functional one.
private enum CosmeticIconMap {
    static func systemImage(forKey key: String, category: CosmeticCategory) -> String {
        switch key {
        case "theme_classic": "circle.lefthalf.filled"
        case "theme_electric_blue": "bolt.circle.fill"
        case "theme_magenta_pulse": "waveform.circle.fill"
        case "theme_gold_rush": "crown.fill"
        case "theme_ice_mint": "snowflake"

        case "ring_solid": "circle.circle"
        case "ring_gradient_sweep": "smallcircle.filled.circle"
        case "ring_dashed_pulse": "circle.dashed"
        case "ring_glow_trail": "circle.dotted"
        case "ring_double_ring": "target"

        case "shield_classic": "shield.fill"
        case "shield_city_skyline": "building.2.fill"
        case "shield_gym_floor": "figure.strengthtraining.traditional"
        case "shield_mountain_dawn": "sun.horizon.fill"
        case "shield_abstract_wave": "water.waves"

        case "coachpack_stock": "quote.bubble.fill"
        case "coachpack_captain_intensity": "flame.fill"
        case "coachpack_zen_minimal": "leaf.fill"
        case "coachpack_data_stream": "chart.bar.fill"
        case "coachpack_hype_squad": "megaphone.fill"

        default: fallbackSystemImage(for: category)
        }
    }

    private static func fallbackSystemImage(for category: CosmeticCategory) -> String {
        switch category {
        case .theme: "paintpalette.fill"
        case .ringStyle: "circle.circle"
        case .shieldBackground: "shield.fill"
        case .coachVoicePack: "quote.bubble.fill"
        }
    }
}

#Preview {
    NavigationStack {
        CosmeticsShopView()
    }
}
