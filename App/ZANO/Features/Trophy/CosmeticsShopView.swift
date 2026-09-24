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
// This screen is the browse/purchase UI for `CosmeticsStore` (`Core/Sources/Core/Retention/
// CosmeticsStore.swift`; its header explains exactly how/why "never sell power" is enforced in that
// file's code, not just documented here). This view adds no new enforcement of its own beyond what
// that file already guarantees structurally — it only ever calls `CosmeticsStore.shared.purchase(_:)`
// with an item taken straight from `CosmeticsStore.catalog` (never a hand-built `CosmeticItem`), so
// every purchase this screen can possibly trigger already has to pass that file's closed-catalog check.
//
// Reached from `TrophyCaseView` (same directory) via a `NavigationLink` and from Settings; it owns no
// navigation chrome of its own beyond `.navigationTitle` — same convention every other
// `App/ZANO/Features` screen follows.
//
// Copy: `Copy.cosmetics.*` / `Copy.common.*` (`Core/Sources/Core/Copy/TrophyCosmeticsCopy.swift`,
// `CommonCopy.swift`). Item icons (SF Symbols) are small, file-scoped reference data below
// (`CosmeticIconMap`), not copy — same convention `TrophyCaseView.swift` uses.

import SwiftUI
import Core

// MARK: - Visual pass (design wave 2026-09-23)
//
// Grade before the pass: D+ (`docs/design/composition-audit.md` 5.3): "it sells cosmetics without
// showing them" and "five acid-green slabs". `docs/design/better-ui-findings.md` ICO-02 calls it
// the most slop per pixel on any screen: a shop of visual goods with abstract glyphs. What it is now
// (purchase, equip, alert and haptic wiring is unchanged; `CosmeticsStore` remains the only source of
// ownership state):
//
//   * Every item shows the thing it sells. Themes are a mini ring in the theme's hue, ring styles are
//     that ring style drawn live at 72% (solid, gradient sweep, dashed, glow trail, double ring),
//     shield backgrounds are a tinted gradient thumbnail with the scene's glyph, coach packs get a
//     glyph plus placeholder message lines. All static: no looping motion in a preview grid.
//     HUE PROXIES: the catalog names themes (Electric Blue, Magenta Pulse, Gold Rush, Ice Mint) whose
//     accent values do not exist in `Theme` yet (a theme "re-skins within the fixed dark palette",
//     `CosmeticsStore`'s catalog comment), so previews borrow the nearest existing `Theme.Colors.Ring`
//     hues (see `CosmeticPreviewPalette`). Swap for the real values when a theme system exists.
//   * The balance is the screen's hero. Coins are what you are here to spend, so "120 coins" leads as
//     a `NumeralText` numeral with a quiet unit (from the existing, pluralizing
//     `Copy.cosmetics.coinBalanceAccessibilityLabel`), not a 17pt pill. Only that wallet and the
//     category chips are pinned; the Pro upsell scrolls with the grid, so the pinned area stays ~120pt
//     instead of ~200pt on a small phone.
//   * Two-column grid of preview tiles instead of five full-width cards each ending in a full-width
//     accent button. The accent is used for what it means: the *selected category chip* and the
//     *equipped* item (an accent edge and a check). Actions are quiet capsules (owned: "Equip", not
//     owned: price with a coin glyph); the unaffordable state is a muted, borderless capsule rather
//     than a 50%-dimmed accent slab (`MOT-04`/`MOT-06`).
//   * Concentric geometry: an 8pt inset inside a 20pt card puts the 12pt preview tile exactly
//     concentric (outer minus inset, `docs/design/2026-ios-trends.md` section 6), and it replaces the
//     old corner-hugging 12pt tile inside a 20pt card (`RAD-02`).
//   * Category chips carry a glyph and reach a 44pt hit target (the visual capsule stays ~32pt),
//     `HIT-03`. The chip row still bleeds to the screen edge so the last chip's cut-off is a scroll cue.
//   * Depth comes from the shared `zanoCard`, taps from `PressableStyle`, hit targets from
//     `minTapTarget()`; the local shims this folder used to carry are gone. The equip state change is
//     now gated for Reduce Motion.

/// Browse-and-purchase UI for `CosmeticsStore` (spec §5.17). A wallet header and category chip row
/// over a scrolling grid of item tiles; each tile's action is either a price capsule (not yet
/// owned), "Equip" (owned) or an "Equipped" mark — `CosmeticsStore.shared` is the single source of
/// truth for which state a tile is in, so this view never tracks ownership/equipped state itself.
public struct CosmeticsShopView: View {
    @State private var selectedCategory: CosmeticCategory = .theme
    @State private var pendingPurchaseKey: String?
    @State private var activeAlert: ShopAlert?
    @State private var purchaseSuccessTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top),
            GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top),
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            walletHeader
            categoryPicker
            itemGrid
        }
        .padding(.top, Theme.Spacing.sm)
        .zanoBackdrop()
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
        .tint(Theme.Colors.interactive)
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1 and
        // `LockSetupView.swift`'s comment for the full rationale. Also matters here specifically:
        // this screen's `.alert` above would otherwise follow the *system* appearance while the
        // rest of the screen stays dark.
        .preferredColorScheme(.dark)
    }

    // MARK: - Wallet

    /// The balance as the screen's hero: a big numeral, a quiet unit, and the one-line subtitle.
    private var walletHeader: some View {
        let balance = CosmeticsStore.shared.coinBalance
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "centsign.circle.fill")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
                // A digit-roll when a purchase changes the balance while this screen is open;
                // `NumeralText` supplies `.numericText()` (identity under Reduce Motion), the
                // value-keyed animation is the driver, gated like every other one.
                NumeralText(Copy.cosmetics.coinBalanceAccessibilityLabel(balance: balance), size: .large)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3), value: balance)
            }
            Text(Copy.cosmetics.screenSubtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    /// Informational, not a warning: the lock glyph is `text` on a neutral disc rather than the old
    /// `warning` tint (`docs/design/typography-color-findings.md` C9), and the banner gets the same
    /// edge as every other surface. Scrolls with the grid.
    private var proUpsellBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "lock.fill", tint: Theme.Colors.text, size: .small)
            Text(Copy.cosmetics.proUpsellBannerText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .zanoCard(radius: Theme.Radius.small)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Category picker

    /// A horizontally scrolling chip row, not a `.segmented` `Picker` — a 4-segment segmented
    /// control (`Copy.cosmetics.categoryTitle`'s real values: "Themes," "Ring styles," "Shield
    /// backgrounds," "Coach voice packs") is a known iOS layout squeeze even at standard text size;
    /// segmented controls truncate/compress rather than wrap. This can't be fixed by shortening the
    /// labels themselves — that text lives in `Copy.cosmetics.categoryTitle(_:)`, outside this file —
    /// so the fix is the layout `FuelView` already uses elsewhere in this codebase for an open-ended
    /// set of options. See `docs/design/ui-stress-test-findings.md` §3.3.
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(CosmeticCategory.allCases, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.cosmetics.categoryPickerAccessibilityLabel)
    }

    private func categoryChip(_ category: CosmeticCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: CosmeticIconMap.chipSystemImage(for: category))
                    .font(Theme.Typography.icon(.xsmall))
                Text(Copy.cosmetics.categoryTitle(category))
                    .font(Theme.Typography.captionEmphasized)
                    .lineLimit(1)
            }
            // Selection is chrome (decision 2026-09-24): `onFill` on a white chip, Spotify-style;
            // green stays reserved for earned states.
            .foregroundStyle(isSelected ? Theme.Colors.onFill : Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isSelected ? Theme.Colors.interactive : Theme.Colors.surface2, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            }
            // The capsule stays ~32pt; the tappable frame is 44pt (`HIT-03`).
            .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.96))
        // Neither state was previously distinguishable to VoiceOver beyond tint (which it can't
        // read at all) — the same "no selected signal" gap §3.4 flags for
        // `SunriseAlarmSetupView.variantRow`, fixed here too since this control was rebuilt anyway.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Item grid

    private var itemGrid: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if !CosmeticsStore.shared.isProSubscriber {
                    proUpsellBanner
                }
                LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.sm) {
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
            }
            .padding(Theme.Spacing.md)
        }
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

/// One item tile: a preview of the thing itself, its name and description, and one quiet action.
/// Purely a rendering of state passed in from `CosmeticsShopView` — never reads `CosmeticsStore`
/// itself, so it's trivially previewable in every ownership/afford combination.
///
/// Geometry: 8pt inset inside a 20pt card, so the 12pt preview corner is concentric. The equipped
/// item wears an accent wash and a 1.5pt accent edge (plus a check on its preview): "chosen", the
/// accent's selection meaning, not a glow (a glow is the reward for *earning*).
private struct CosmeticItemCard: View {
    let item: CosmeticItem
    let isOwned: Bool
    let isEquipped: Bool
    let canAfford: Bool
    let isPurchasing: Bool
    let onPurchase: () -> Void
    let onEquip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            CosmeticPreview(item: item)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isEquipped {
                        Image(systemName: "checkmark")
                            .font(Theme.Typography.icon(.xsmall, weight: .bold))
                            .foregroundStyle(Theme.Colors.onFill)
                            .frame(width: 20, height: 20)
                            .background(Theme.Colors.interactive, in: Circle())
                            .padding(Theme.Spacing.xs)
                            .accessibilityHidden(true)
                    }
                }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.cosmetics.title(forKey: item.key))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                Text(Copy.cosmetics.itemDescription(forKey: item.key))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            .accessibilityElement(children: .combine)

            actionRow
        }
        .padding(Theme.Spacing.xs)
        .zanoCard(radius: Theme.Radius.medium, fill: isEquipped ? Theme.Colors.surface2 : Theme.Colors.surface)
        .overlay {
            // Equipped = the current selection, so it is marked in achromatic chrome, not green.
            if isEquipped {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Colors.interactive, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isEquipped)
    }

    /// Equipped: a quiet accent mark, not a dead button. Owned: an "Equip" capsule. Not owned: a
    /// price capsule with a coin glyph, muted and non-interactive when the balance is short.
    @ViewBuilder
    private var actionRow: some View {
        if isEquipped {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.interactive)
                Text(Copy.cosmetics.equippedButtonTitle)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .accessibilityElement(children: .combine)
        } else if isOwned {
            ShopActionCapsule(
                title: Copy.cosmetics.equipButtonTitle,
                action: onEquip
            )
        } else {
            ShopActionCapsule(
                title: Copy.cosmetics.purchaseButtonTitle(priceCoins: item.priceCoins),
                systemImage: "centsign.circle.fill",
                isEnabled: canAfford && !isPurchasing,
                isBusy: isPurchasing,
                action: onPurchase
            )
        }
    }
}

/// The one action per tile. A 32pt capsule in a 44pt tappable frame. Neutral (`surface2` fill, light
/// edge, `text` label); disabled is a borderless muted capsule, never a dimmed accent slab.
private struct ShopActionCapsule: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                if isBusy {
                    // `SwiftUI.ProgressView` spelled out: this module also declares a `ProgressView`
                    // struct (the Progress tab), which an unqualified `ProgressView()` would silently
                    // resolve to. See `LockedOutMomentView.swift`'s comment on the same gotcha.
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Colors.muted)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.icon(.xsmall))
                }
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isEnabled ? Theme.Colors.surface2 : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isEnabled ? Theme.Colors.hairlineStrong : Theme.Colors.hairline,
                        lineWidth: Theme.Metrics.edgeWidth
                    )
            }
            .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.96))
        .disabled(!isEnabled)
    }
}

// MARK: - Previews of the things being sold

/// Which existing `Theme` hue stands in for each named cosmetic. The catalog's theme names have no
/// accent values in `Theme` (see the visual-pass note at the top of this file), so previews borrow
/// the nearest `Theme.Colors.Ring` hue: an honest proxy, easy to replace with real values later.
private enum CosmeticPreviewPalette {
    static func tint(forKey key: String) -> Color {
        switch key {
        case "theme_electric_blue": Theme.Colors.Ring.sleepOnTime
        case "theme_magenta_pulse": Theme.Colors.Ring.stretchMobility
        case "theme_gold_rush": Theme.Colors.Ring.sunriseAlarm
        case "theme_ice_mint": Theme.Colors.Ring.mealPrep
        case "shield_city_skyline": Theme.Colors.Ring.focus
        case "shield_gym_floor": Theme.Colors.Ring.protein
        case "shield_mountain_dawn": Theme.Colors.warning
        case "shield_abstract_wave": Theme.Colors.Ring.water
        case "shield_classic": Theme.Colors.muted
        default: Theme.Colors.accent
        }
    }
}

/// A static, decorative rendering of one cosmetic. Hidden from accessibility (the tile's title and
/// description carry the meaning).
private struct CosmeticPreview: View {
    let item: CosmeticItem

    private var tint: Color { CosmeticPreviewPalette.tint(forKey: item.key) }

    var body: some View {
        ZStack {
            backdrop
            art
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch item.category {
        case .theme:
            ZStack {
                Theme.Colors.background
                RadialGradient(
                    colors: [tint.opacity(0.35), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 90
                )
            }
        case .ringStyle, .coachVoicePack:
            Theme.Colors.surface2
        case .shieldBackground:
            LinearGradient(
                colors: [tint.opacity(0.55), Theme.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // The glyphs below are artwork inside a fixed 96pt preview tile, so they are literal sizes rather
    // than text-relative icons.
    @ViewBuilder
    private var art: some View {
        switch item.category {
        case .theme:
            CosmeticMiniRing(style: .solid, tint: tint, progress: 0.72, diameter: 64)
        case .ringStyle:
            CosmeticMiniRing(style: ringStyle, tint: tint, progress: 0.72, diameter: 64)
        case .shieldBackground:
            Image(systemName: CosmeticIconMap.systemImage(forKey: item.key, category: item.category))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Colors.text.opacity(0.9))
        case .coachVoicePack:
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: CosmeticIconMap.systemImage(forKey: item.key, category: item.category))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                // Placeholder message lines: the pack changes how the coach's lines are presented,
                // and showing real sample copy would need new `Copy` members.
                VStack(spacing: Theme.Spacing.xxs) {
                    Capsule().fill(Theme.Colors.track).frame(width: 64, height: 6)
                    Capsule().fill(Theme.Colors.hairline).frame(width: 44, height: 6)
                }
            }
        }
    }

    private var ringStyle: CosmeticMiniRing.Style {
        switch item.key {
        case "ring_gradient_sweep": .gradient
        case "ring_dashed_pulse": .dashed
        case "ring_glow_trail": .glow
        case "ring_double_ring": .double
        default: .solid
        }
    }
}

/// A miniature ring drawn in one of the five catalog ring styles. Static on purpose (a "pulse" or
/// "trail" is described by its shape, not animated, inside a browse grid).
private struct CosmeticMiniRing: View {
    enum Style {
        case solid, gradient, dashed, glow, double
    }

    let style: Style
    let tint: Color
    let progress: Double
    let diameter: CGFloat

    private var line: CGFloat { diameter * 0.14 }
    /// The double ring keeps a thin outer ring, so the main ring insets further to make room.
    private var mainInset: CGFloat { line / 2 + (style == .double ? line * 0.9 : 0) }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: mainInset)
                .stroke(Theme.Colors.Ring.track(for: tint), lineWidth: line)

            arc
                .rotationEffect(.degrees(-90))

            if style == .double {
                Circle()
                    .inset(by: line * 0.15)
                    .trim(from: 0, to: progress)
                    .stroke(tint.opacity(0.5), style: StrokeStyle(lineWidth: line * 0.3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private var arc: some View {
        let trimmed = Circle().inset(by: mainInset).trim(from: 0, to: progress)
        switch style {
        case .gradient:
            trimmed.stroke(
                AngularGradient(colors: [tint.opacity(0.25), tint], center: .center),
                style: StrokeStyle(lineWidth: line, lineCap: .round)
            )
        case .dashed:
            trimmed.stroke(
                tint,
                style: StrokeStyle(lineWidth: line, lineCap: .butt, dash: [line * 0.6, line * 0.5])
            )
        case .glow:
            trimmed
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .shadow(color: tint.opacity(0.7), radius: line)
        case .solid, .double:
            trimmed.stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
        }
    }
}

/// SF Symbol per catalog key, with a per-category fallback for any key this map doesn't (yet)
/// special-case — e.g. a future catalog addition still renders *something* sensible instead of a
/// blank icon slot. Reference data only, not copy — see this file's header.
///
/// Chosen from training-knowledge recall of Apple's SF Symbols catalog, not confirmed against the
/// SF Symbols app or an Xcode build (no Mac available — see CLAUDE.md's environment status). Names
/// avoided here on purpose for being unusually specific compound names that could not be verified
/// with confidence; everything used is a plain, single-glyph symbol or a very common `.circle.fill`/
/// `.fill` variant of one. Still worth a spot-check on a Mac before shipping — a wrong name renders
/// as blank space, not a crash, so this is a cosmetic-polish risk only, never a functional one.
private enum CosmeticIconMap {
    /// Category chip glyphs: what each category *is*, at a glance.
    static func chipSystemImage(for category: CosmeticCategory) -> String {
        switch category {
        case .theme: "paintpalette.fill"
        case .ringStyle: "circle.circle"
        case .shieldBackground: "shield.fill"
        case .coachVoicePack: "quote.bubble.fill"
        }
    }

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
    .preferredColorScheme(.dark)
}
