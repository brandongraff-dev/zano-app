// TrophyCaseView.swift
// App / Features / Trophy
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §5.17 Trophy Case & Cosmetics: "Badges for milestones (first earned unlock,
// 7/30/100-day streaks, 1,000g protein week, 50 gym sessions). Coins from verified goals buy
// themes, ring styles, shield backgrounds, and coach voice packs."
//
// This is the dedicated, full-screen Trophy Case — a richer companion to the small "Trophy Case"
// preview card `App/ZANO/Features/Progress/ProgressView.swift` renders inline on the Progress tab.
// The two intentionally differ in one way: ProgressView's card only lists badges that already exist;
// this screen shows the full, spec-named milestone set as a grid — earned tiles lit up with their
// badge's real `earnedAt`, not-yet-earned tiles shown locked — because a "trophy case" that only ever
// shows what's already won isn't showing the case, just the trophies. Both screens read the same
// `Badge` rows via `@Query` and the same `Copy.badges.*` keys, so a badge earned anywhere shows up
// identically in both places with zero duplication of award logic — neither this file nor
// ProgressView.swift ever inserts a `Badge`; that's `StreakEngine`/`ComebackMode`/(future) other
// engines' job exclusively.
//
// Reads `Badge` directly via `@Query`, exactly like `ProgressView.swift` — this screen is read-only:
// it never mutates a `Badge` row itself. `CosmeticsStore.shared` supplies the coin balance shown here
// and backs the link into `CosmeticsShopView` (same directory) — Trophy Case and the Cosmetics Shop
// are one spec section (§5.17) and one coin economy, so linking them directly here (rather than making
// the user find the shop through Settings) is this task's own UX call.
//
// ── The six milestone badge keys below ──
//
// `first_earned_unlock`, `streak_7`, `streak_30`, `streak_100`, `protein_1000g_week`,
// `gym_50_sessions` are exactly spec §5.17's own list (`TrophyMilestone.milestoneKeys`). Their
// glyphs, and the disc they sit in, come from `TrophyBadgeDisc.swift` (this folder), which the
// Progress trophy strip uses too, so the two screens can't drift apart.
//
// **No engine currently awards most of these badges.** Only `StreakEngine.awardComebackBadge`
// (`"comeback_<date>"`) and `ComebackMode.awardChallengeCompleteBadge` (`"comeback_challenge_<date>"`)
// actually insert `Badge` rows today — nothing yet awards `first_earned_unlock`, `streak_7`,
// `streak_30`, `streak_100`, `protein_1000g_week`, or `gym_50_sessions`. Every one of those six tiles
// renders "locked" until a future session adds the actual award call. Real, not a bug in this screen.
//
// Copy: `Copy.trophyCase.*` / `Copy.cosmetics.*` / `Copy.badges.*` / `Copy.common.*`
// (`Core/Sources/Core/Copy/TrophyCosmeticsCopy.swift`). Badge icon (SF Symbol) mapping is small,
// file-scoped reference data, not copy.

import SwiftUI
import SwiftData
import Core

// MARK: - Visual pass (design wave 2026-09-23)
//
// Grade before the pass: C+ (`docs/design/composition-audit.md` section 4): "good tile + earn moment;
// header card has 3 jobs". What it is now, composition and visual treatment only (every `@Query`, the
// `CosmeticsStore` refresh, the earn-edge celebration and all accessibility wiring are unchanged):
//
//   * The header card had three jobs (progress headline, subtitle + coin pill, and a nested full-width
//     shop link) and no lead. It is one hero: the shared `GoalRing` (earned count as its centre
//     numeral, target beneath) with the headline, subtitle and coin balance beside it. The ring used
//     to be a bespoke copy because `GoalRing` had a `surface2` track and a fixed centre; it now has
//     hue-tinted tracks and value centres, so the copy is gone and the ring behaves like every other
//     ring in the app (track, glow, completion pulse, Reduce Motion). The shop link is a single quiet
//     row at the bottom. The coin pill stays in the card rather than the nav bar: iOS 26 wraps toolbar
//     items in glass, and a `surface2` capsule inside a glass capsule is glass-on-glass
//     (`docs/design/2026-ios-trends.md` section 2.1).
//   * The hero and earned tiles wash with the accent only once something is *earned* (the accent means
//     earned/unlocked, spec section 15): an empty case is neutral, and a full one gets the static glow.
//   * Locked milestones were six identical padlocks (`ICO-01`): carrying zero information about what
//     there is to win. A locked tile shows the milestone's own glyph, dimmed, with a small lock
//     badge; the disc, not the label, carries the dimming (the 0.55 opacity on the whole tile put the
//     title at 2.56:1 contrast, `typography-color-findings.md` C6).
//   * Every tile has a status line ("Earned Mar 3" / the existing `lockedAccessibilityHint`), so tiles
//     align to the same baseline.
//   * Icons swap `star.circle.fill` / `fork.knife.circle.fill` for the un-circled glyphs: a circle
//     inside a 60pt circle is a double frame (`ICO-09`). (Reconciled with Progress since: both
//     now read `TrophyBadgeGlyph.forKey(_:)`.)
//   * The shop entry uses `paintpalette.fill`, the glyph `SettingsView` uses for the same destination
//     (`ICO-05`), and the coin currency reads as a neutral `centsign.circle.fill` and a numeral with a
//     quiet unit rather than a warning-colored seal (`typography-color-findings.md` C9: `warning` means
//     "needs attention", not "currency").
//   * Depth comes from the shared `zanoCard` recipe; the local `depthCard`/`FeatureBackdrop`/
//     `CardPressStyle` shims this folder used to carry are gone.

// MARK: - Polish pass (2026-09-24, later)
//
//   * Earned badges are silver (`metallic`, the logo's metal) with an `onFill` glyph, via the shared
//     `TrophyBadgeDisc` (same disc as the Progress trophy strip). Locked sockets are a solid
//     hairline ring on `surface2`, no dashes. The per-tile card chrome is gone: discs and titles
//     float in the grid. The first earned unlock draws the ZANO star; both streak badges are
//     `flame.fill`. The coin glyph is a small metallic disc, not a grey cent sign.
//   * The earn animation uses `Theme.Motion.springCelebration`.
//
// MARK: - Premium pass (2026-09-24, docs/design/premium-ui-plan.md, "light is earned")
//
//   * Hero: the earned count as an 88pt compressed numeral ("2" + "of 6 earned") on the one
//     elevated `zanoHero` surface, with a six-segment shelf (one segment per milestone, accent when
//     earned) instead of a ring that repeated the same number. Day 1 gets a guidance line.
//   * Earned tiles read as trophies: a FILLED accent disc with the glyph in `onFill` and a static
//     accent glow. Locked tiles are clean rather than muddy: an open disc with a dashed hairline,
//     the milestone's own glyph in `muted` at full opacity, and the lock badge.
//   * "More badges" lists each key once (newest occurrence) and never a milestone key, so nothing
//     in it can repeat a tile in the grid. Its header is a sentence-case headline, not tracked caps.
//   * Chrome is achromatic: the screen tint (back button) is `interactive`, and the backdrop is
//     `zanoAmbient` (`.earned` only once the whole case is full).

/// The dedicated Trophy Case screen (spec §5.17) — a milestone badge grid plus an entry point
/// into the Cosmetics Shop. Meant to be pushed onto an existing `NavigationStack` (from Progress
/// or Settings) rather than presenting its own, matching `ProgressView`/`LockSetupView`'s convention
/// of never owning navigation chrome themselves.
public struct TrophyCaseView: View {
    @Query(sort: \Badge.earnedAt, order: .reverse) private var badges: [Badge]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                heroCard
                milestonesSection
                if !otherEarnedBadges.isEmpty {
                    otherAchievementsSection
                }
                shopLink
            }
            .padding(Theme.Spacing.md)
        }
        .zanoAmbient(allMilestonesEarned && !reduceTransparency ? .earned : .neutral)
        .navigationTitle(Copy.trophyCase.screenTitle)
        .task { await CosmeticsStore.shared.refresh() }
        .tint(Theme.Colors.interactive)
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1 and
        // `LockSetupView.swift`'s comment for the full rationale.
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero (earned count + shelf + coin balance)

    private var heroCard: some View {
        let earned = earnedMilestoneCount
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                // "2" huge, "of 6 earned" quiet on the same baseline: one fact, read once.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    NumeralText(
                        "\(earned)",
                        size: .hero,
                        color: earned > 0 ? Theme.Colors.accent : Theme.Colors.text
                    )
                    Text(Copy.trophyCase.progressTotalLabel(total: milestones.count))
                        .zanoText(.titleLarge)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.trophyCase.progressLabel(earned: earned, total: milestones.count))
                .accessibilityAddTraits(.isHeader)

                Text(earned > 0 ? Copy.trophyCase.screenSubtitle : Copy.trophyCase.emptyHeroMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TrophyShelf(earnedFlags: milestones.map { milestone in
                badges.contains { $0.key == milestone.key }
            })

            TrophyCoinPill(balance: CosmeticsStore.shared.coinBalance)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoHero(
            radius: Theme.Radius.large,
            tint: earned > 0 ? Theme.Colors.accent : nil,
            active: allMilestonesEarned
        )
    }

    // MARK: - Milestones grid (spec §5.17's exact six)

    /// One tile per spec §5.17 milestone, in the order spec lists them. Static, not derived from
    /// `badges`, so every milestone shows (locked, if unearned) even for a brand-new user with
    /// zero `Badge` rows — the entire point of a trophy *case* over a bare "here's what you've
    /// won so far" list.
    private let milestones: [TrophyMilestone] = TrophyMilestone.milestoneKeys.map(TrophyMilestone.init(key:))

    private var earnedMilestoneCount: Int {
        milestones.filter { milestone in badges.contains { $0.key == milestone.key } }.count
    }

    private var allMilestonesEarned: Bool {
        !milestones.isEmpty && earnedMilestoneCount == milestones.count
    }

    /// Three equal columns, six tiles, two rows: no adaptive-minimum guesswork, and every tile is
    /// the same size whether its title wraps to one line or two (the title reserves two lines).
    private var milestonesSection: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top),
                count: 3
            ),
            spacing: Theme.Spacing.lg
        ) {
            ForEach(milestones) { milestone in
                TrophyTile(milestone: milestone, badge: badges.first { $0.key == milestone.key })
            }
        }
    }

    // MARK: - Other achievements (per-occurrence badges outside the fixed six, e.g. "comeback_*")

    /// Any earned `Badge` whose key isn't one of the six canonical milestones above — e.g.
    /// `StreakEngine`'s dated `"comeback_<yyyy-MM-dd>"` badges or `ComebackMode`'s
    /// `"comeback_challenge_<yyyy-MM-dd>"` ones. Those are stamped per-occurrence (a fresh key
    /// every time), not a single lifetime type, so they don't fit the fixed grid above — but
    /// hiding them here would mean a real, earned badge silently never shows up on this screen.
    /// Listed newest-first (matching this file's `@Query` sort).
    ///
    /// Each key appears once (its newest row, since `badges` is newest-first): a key written twice
    /// (a retried award, a sync replay) must not list twice.
    private var otherEarnedBadges: [Badge] {
        let milestoneKeys = Set(milestones.map(\.key))
        var seen: Set<String> = []
        return badges.filter { badge in
            guard !milestoneKeys.contains(badge.key) else { return false }
            return seen.insert(badge.key).inserted
        }
    }

    private var otherAchievementsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.trophyCase.otherAchievementsSectionTitle)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.Spacing.xxs)

            // One card, hairline rows: these are a dense list, so they get dividers between rows
            // instead of a card per row (`docs/design/competitive-research.md` 3.1: MyFitnessPal's
            // failure was hero-scale cards on every list row).
            VStack(spacing: 0) {
                ForEach(Array(otherEarnedBadges.enumerated()), id: \.element.key) { index, badge in
                    if index > 0 {
                        TrophyDivider()
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        TrophyBadgeDisc(
                            isEarned: true,
                            glyph: .forKey(badge.key),
                            diameter: Theme.Metrics.iconBadgeSmall
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(Copy.badges.title(forKey: badge.key))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text)
                            Text(Copy.badges.earnedOnLabel(date: badge.earnedAt))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(radius: Theme.Radius.medium)
        }
    }

    // MARK: - Shop entry

    /// A single quiet row at the bottom: the shop is where spent coins go, not the point of this
    /// screen. The glyph is `text` on a neutral disc (accent stays reserved for earned states).
    private var shopLink: some View {
        NavigationLink {
            CosmeticsShopView()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "paintpalette.fill", tint: Theme.Colors.text, size: .small)
                Text(Copy.trophyCase.openShopButtonTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
                // "chevron.forward" (not the literal "chevron.right"), matching every other
                // disclosure chevron — the semantic, auto-mirroring name so this row's chevron flips
                // to point left in an RTL locale instead of staying pinned to the physical right. See
                // `docs/design/ui-stress-test-findings.md` §2.4.
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .zanoCard(radius: Theme.Radius.medium)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - File-scoped supporting types

/// One canonical milestone tile definition — a stable `Badge.key`; its glyph comes from the shared
/// `TrophyBadgeGlyph.forKey(_:)`. Not copy (see this file's header) — display title comes from
/// `Copy.badges.title(forKey:)`.
struct TrophyMilestone: Identifiable {
    let key: String
    var id: String { key }
    var glyph: TrophyBadgeGlyph { .forKey(key) }

    /// Spec §5.17's six milestones, in spec order. Also drives the not-yet-earned tiles in the
    /// Progress trophy strip, so the two screens list the same set.
    static let milestoneKeys = [
        "first_earned_unlock",
        "streak_7",
        "streak_30",
        "streak_100",
        "protein_1000g_week",
        "gym_50_sessions",
    ]
}

/// A one-device-pixel divider between the rows of a dense list card: `Theme.Colors.hairline` at
/// exactly 1 physical pixel, so it stays "crisp 1px" (spec section 16) at every display scale.
/// `Divider()` is a system-tinted line that ignores `Theme`.
private struct TrophyDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

/// One tile in the milestones grid — locked (the milestone's own glyph, dimmed, with a lock badge) if
/// `badge == nil`, lit up with the milestone's real icon and earned date otherwise.
///
/// Per `docs/design/animation-opportunities.md` row 11: this screen has no engine wired up to award
/// most of these six milestones yet (see this file's header), so the celebratory moment below is
/// written to already be correct the day one is — a `false → true` edge on `isEarned` while this
/// screen happens to be open fires a one-shot burst + expanding ring, rather than needing a follow-up
/// patch once an engine exists. A tile that's *already* earned when this view first appears never
/// fires this (`.onChange(of:)` only reports changes after the initial value, not the initial value
/// itself), so re-opening Trophy Case doesn't re-celebrate old badges.
private struct TrophyTile: View {
    let milestone: TrophyMilestone
    let badge: Badge?

    /// Fires `CelebrationBurst` (`Core/Sources/Core/UI/Components/CelebrationBurst.swift`) on every
    /// increment. Left ungated by Reduce Motion here on purpose: `CelebrationBurst` already has its
    /// own internal reduced-motion fallback (a plain cross-fade, no radial travel), so this tile still
    /// gets *some* positive confirmation either way, matching "never drop feedback to literally
    /// nothing" rather than suppressing the whole burst.
    @State private var celebrationTick = 0
    /// Gates *mounting* `CelebrationBurst` into the view tree at all — not just whether it's
    /// visible. `CelebrationBurst.body` fires a burst from its own `.onAppear` unconditionally, so
    /// including it in every tile's `ZStack` unconditionally would confetti-burst every tile, locked
    /// ones included, the instant this screen first renders. Only inserting the view once
    /// `celebrate()` has actually run keeps its unconditional first-appear fire correct instead of a
    /// bug: by the time it mounts, `celebrationTick` has already moved past 0, so that first appear
    /// *is* the real celebration.
    @State private var hasCelebrated = false
    /// Drives the expanding accent ring below — `nil` when idle, `0 → 1` while animating. This one
    /// *is* skipped entirely under Reduce Motion (see `celebrate()`): it's a supplementary visual
    /// flourish, not the primary feedback channel (the icon/disc crossfade below carries that).
    @State private var ringProgress: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEarned: Bool { badge != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            badgeDisc

            VStack(spacing: Theme.Spacing.xxs) {
                // Title keeps its color (`text` earned, `muted` locked: 5.64:1); only the disc is
                // dimmed. Two lines reserved so a one-line and a two-line title do not make tiles
                // of different heights.
                Text(Copy.badges.title(forKey: milestone.key))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isEarned ? Theme.Colors.text : Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                Text(statusLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // No card per tile: the disc and its title float in the grid, the way objects sit on a
        // shelf. The disc is the object; a slab behind each one was a frame around a frame.
        .padding(.horizontal, Theme.Spacing.xxs)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springStandard, value: isEarned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .sensoryFeedback(.success, trigger: celebrationTick)
        .onChange(of: isEarned) { old, new in
            guard new, !old else { return }
            celebrate()
        }
    }

    /// The shared `TrophyBadgeDisc` (silver when earned, an empty hairline socket when not), plus
    /// this screen's one-shot earn moment: an expanding accent ring and a burst.
    private var badgeDisc: some View {
        ZStack {
            TrophyBadgeDisc(isEarned: isEarned, glyph: milestone.glyph)

            if let ringProgress {
                Circle()
                    .stroke(Theme.Colors.accent, lineWidth: 2)
                    .scaleEffect(1 + 0.6 * ringProgress)
                    .opacity(0.6 * (1 - ringProgress))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if hasCelebrated {
                CelebrationBurst(trigger: celebrationTick, particleCount: 14)
                    .frame(width: TrophyBadgeDisc.defaultDiameter * 1.4, height: TrophyBadgeDisc.defaultDiameter * 1.4)
            }
        }
        .frame(width: TrophyBadgeDisc.defaultDiameter, height: TrophyBadgeDisc.defaultDiameter)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springCelebration,
            value: isEarned
        )
    }

    /// Every tile has one, so earned and locked tiles keep the same height and baseline.
    private var statusLine: String {
        if let badge {
            return Copy.badges.earnedOnLabel(date: badge.earnedAt)
        }
        return Copy.trophyCase.lockedAccessibilityHint
    }

    /// One-shot moment for the `false → true` edge only — see the type doc comment. Well inside
    /// `Theme.Motion.unlockCelebrationMaxDuration` (1.2s): the ring's own animation is 0.5s.
    private func celebrate() {
        celebrationTick += 1
        hasCelebrated = true
        guard !reduceMotion else { return }
        ringProgress = 0
        withAnimation(.easeOut(duration: 0.5)) {
            ringProgress = 1
        }
    }

    private var accessibilityLabel: Text {
        guard let badge else {
            return Text("\(Copy.badges.title(forKey: milestone.key)), \(Copy.trophyCase.lockedAccessibilityHint)")
        }
        return Text("\(Copy.badges.title(forKey: milestone.key)), \(Copy.badges.earnedOnLabel(date: badge.earnedAt))")
    }
}

/// One segment per milestone, in grid order: accent when earned, `track` when not. A trophy shelf
/// at a glance, so the hero does not need a second rendering of the count (the old ring).
private struct TrophyShelf: View {
    let earnedFlags: [Bool]

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(earnedFlags.enumerated()), id: \.offset) { _, earned in
                Capsule()
                    .fill(earned ? Theme.Colors.accent : Theme.Colors.track)
                    .frame(height: 6)
                    .shadow(color: earned ? Theme.Colors.accent.opacity(0.35) : Color.clear, radius: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small coin-balance capsule for this screen's hero. (The Cosmetics Shop, where the balance is the
/// point of the screen, draws its own larger wallet header instead of reusing this pill.) Neutral
/// colors: `warning` is "needs attention soon", not "currency"
/// (`docs/design/typography-color-findings.md` C9). The balance is a numeral with a quiet unit
/// ("120 coins", straight from `Copy.cosmetics`, so it pluralizes), not a bare digit run.
private struct TrophyCoinPill: View {
    let balance: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var balanceText: String {
        Copy.cosmetics.coinBalanceAccessibilityLabel(balance: balance)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            TrophyCoinGlyph()
            // A digit-roll, not a hard cut, when a badge/purchase changes the balance while this
            // screen is open — docs/design/animation-opportunities.md row 12. `NumeralText` applies
            // `.numericText()` (identity under Reduce Motion); the value-keyed animation below is the
            // driver, gated per the wave-wide Reduce Motion rule.
            NumeralText(balanceText, size: .small)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3), value: balance)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balanceText)
    }
}

/// The coin: a small brushed-silver disc with a top-lit rim, the same metal as an earned badge
/// (coins are earned too), instead of a grey cent sign. Sized to the caption line it sits in.
struct TrophyCoinGlyph: View {
    @ScaledMetric private var diameter: CGFloat

    /// - Parameter diameterAtDefaultSize: the disc at the default text size; it scales with Dynamic
    ///   Type from there.
    init(diameterAtDefaultSize: CGFloat = 14) {
        _diameter = ScaledMetric(wrappedValue: diameterAtDefaultSize, relativeTo: .footnote)
    }

    var body: some View {
        Circle()
            .fill(Theme.Colors.metallic)
            .overlay {
                Circle().strokeBorder(Theme.Colors.specular, lineWidth: Theme.Metrics.edgeWidth)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        TrophyCaseView()
    }
    .modelContainer(for: [Badge.self, Coin.self, User.self], inMemory: true)
}
