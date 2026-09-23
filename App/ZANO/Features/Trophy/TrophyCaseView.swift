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
// `gym_50_sessions` are exactly spec §5.17's own list. Icons are declared locally on each
// `TrophyMilestone` entry rather than imported: `ProgressView.swift`'s `ProgressBadgeIconMap` is
// `private` to that file, and this task does not own it. Keeping the same SF Symbol *family* is a
// deliberate visual-consistency decision — flagged in case a future session changes one without
// knowing to update the other.
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
//     inside a 60pt circle is a double frame (`ICO-09`). `ProgressView.swift`'s `ProgressBadgeIconMap`
//     still uses the circled variants (not this wave's file); reconcile when that file is next touched.
//   * The shop entry uses `paintpalette.fill`, the glyph `SettingsView` uses for the same destination
//     (`ICO-05`), and the coin currency reads as a neutral `centsign.circle.fill` and a numeral with a
//     quiet unit rather than a warning-colored seal (`typography-color-findings.md` C9: `warning` means
//     "needs attention", not "currency").
//   * Depth comes from the shared `zanoCard` recipe; the local `depthCard`/`FeatureBackdrop`/
//     `CardPressStyle` shims this folder used to carry are gone.

/// The dedicated Trophy Case screen (spec §5.17) — a milestone badge grid plus an entry point
/// into the Cosmetics Shop. Meant to be pushed onto an existing `NavigationStack` (from Progress
/// or Settings) rather than presenting its own, matching `ProgressView`/`LockSetupView`'s convention
/// of never owning navigation chrome themselves.
public struct TrophyCaseView: View {
    @Query(sort: \Badge.earnedAt, order: .reverse) private var badges: [Badge]

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
        .zanoBackdrop(glow: earnedMilestoneCount > 0 ? Theme.Colors.accent : nil, intensity: 0.12)
        .navigationTitle(Copy.trophyCase.screenTitle)
        .task { await CosmeticsStore.shared.refresh() }
        .tint(Theme.Colors.accent)
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1 and
        // `LockSetupView.swift`'s comment for the full rationale.
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero (progress ring + coin balance)

    private var heroCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // The headline beside it ("4 of 6 earned") already says this; announcing the ring as well
            // would read the same fact twice.
            GoalRing(
                progress: milestoneProgress,
                color: Theme.Colors.accent,
                size: .custom(128),
                center: .value("\(earnedMilestoneCount)", unit: "/\(milestones.count)")
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.trophyCase.progressLabel(earned: earnedMilestoneCount, total: milestones.count))
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Copy.trophyCase.screenSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TrophyCoinPill(balance: CosmeticsStore.shared.coinBalance)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(
            radius: Theme.Radius.large,
            tint: earnedMilestoneCount > 0 ? Theme.Colors.accent : nil,
            active: allMilestonesEarned
        )
    }

    // MARK: - Milestones grid (spec §5.17's exact six)

    /// One tile per spec §5.17 milestone, in the order spec lists them. Static, not derived from
    /// `badges`, so every milestone shows (locked, if unearned) even for a brand-new user with
    /// zero `Badge` rows — the entire point of a trophy *case* over a bare "here's what you've
    /// won so far" list.
    private let milestones: [TrophyMilestone] = [
        TrophyMilestone(key: "first_earned_unlock", systemImage: "star.fill"),
        TrophyMilestone(key: "streak_7", systemImage: "flame"),
        TrophyMilestone(key: "streak_30", systemImage: "flame.fill"),
        TrophyMilestone(key: "streak_100", systemImage: "crown.fill"),
        TrophyMilestone(key: "protein_1000g_week", systemImage: "fork.knife"),
        TrophyMilestone(key: "gym_50_sessions", systemImage: "dumbbell.fill"),
    ]

    private var earnedMilestoneCount: Int {
        milestones.filter { milestone in badges.contains { $0.key == milestone.key } }.count
    }

    private var allMilestonesEarned: Bool {
        !milestones.isEmpty && earnedMilestoneCount == milestones.count
    }

    private var milestoneProgress: Double {
        guard !milestones.isEmpty else { return 0 }
        return min(1, Double(earnedMilestoneCount) / Double(milestones.count))
    }

    /// Three equal columns, six tiles, two rows: no adaptive-minimum guesswork, and every tile is
    /// the same size whether its title wraps to one line or two (the title reserves two lines).
    private var milestonesSection: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top),
                count: 3
            ),
            spacing: Theme.Spacing.sm
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
    private var otherEarnedBadges: [Badge] {
        let milestoneKeys = Set(milestones.map(\.key))
        return badges.filter { !milestoneKeys.contains($0.key) }
    }

    private var otherAchievementsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.trophyCase.otherAchievementsSectionTitle)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)

            // One card, hairline rows: these are a dense list, so they get dividers between rows
            // instead of a card per row (`docs/design/competitive-research.md` 3.1: MyFitnessPal's
            // failure was hero-scale cards on every list row).
            VStack(spacing: 0) {
                ForEach(Array(otherEarnedBadges.enumerated()), id: \.offset) { index, badge in
                    if index > 0 {
                        TrophyDivider()
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        IconBadge(systemName: "rosette", tint: Theme.Colors.accent, size: .small)
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

/// One canonical milestone tile definition — a stable `Badge.key` paired with the SF Symbol shown
/// once it's earned. Not copy (see this file's header) — display title comes from
/// `Copy.badges.title(forKey:)`.
private struct TrophyMilestone: Identifiable {
    let key: String
    let systemImage: String
    var id: String { key }
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
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
        // Earned = an accent wash and an accent-dim edge (`accentDim` is the token for "a
        // highlighted border"); the disc carries the glow, so the card itself stays flat.
        .zanoCard(radius: Theme.Radius.medium, tint: isEarned ? Theme.Colors.accent : nil)
        .overlay {
            if isEarned {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Colors.accentDim, lineWidth: Theme.Metrics.edgeWidth)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springStandard, value: isEarned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .sensoryFeedback(.success, trigger: celebrationTick)
        .onChange(of: isEarned) { old, new in
            guard new, !old else { return }
            celebrate()
        }
    }

    /// The badge disc. Earned: accent-washed with a static accent glow. Locked: `surface2` with the
    /// milestone's own glyph at reduced opacity and a small lock badge tucked into the lower
    /// trailing edge (a `background` cutout ring keeps it legible over the disc).
    private var badgeDisc: some View {
        ZStack {
            Circle()
                .fill(isEarned ? Theme.Colors.accentWash : Theme.Colors.surface2)
            Circle()
                .strokeBorder(
                    isEarned ? Theme.Colors.accentDim : Theme.Colors.hairline,
                    lineWidth: Theme.Metrics.edgeWidth
                )

            if let ringProgress {
                Circle()
                    .stroke(Theme.Colors.accent, lineWidth: 2)
                    .scaleEffect(1 + 0.6 * ringProgress)
                    .opacity(0.6 * (1 - ringProgress))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Fixed-size art inside a fixed 60pt disc (the disc, not the glyph, is the layout unit),
            // so this stays a literal size rather than a text-relative icon.
            Image(systemName: milestone.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isEarned ? Theme.Colors.accent : Theme.Colors.muted)
                .opacity(isEarned ? 1 : 0.55)

            if !isEarned {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: 20, height: 20)
                    .background(Theme.Colors.background, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                    }
                    .offset(x: 20, y: 20)
                    .accessibilityHidden(true)
            }

            if hasCelebrated {
                CelebrationBurst(trigger: celebrationTick, particleCount: 14)
                    .frame(width: 84, height: 84)
            }
        }
        .frame(width: 60, height: 60)
        // Static glow on the *earned* state only (`2026-ios-trends.md` 3.3.C); never animated.
        .shadow(color: isEarned ? Theme.Colors.accent.opacity(0.35) : Color.clear, radius: 12)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62),
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
            Image(systemName: "centsign.circle.fill")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
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

#Preview {
    NavigationStack {
        TrophyCaseView()
    }
    .modelContainer(for: [Badge.self, Coin.self, User.self], inMemory: true)
}
