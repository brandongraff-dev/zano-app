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
// preview card `App/ZANO/Features/Progress/ProgressView.swift` already renders inline on the
// Progress tab (that file is owned by a different session this same batch; read, not edited,
// here). The two intentionally differ in one way: ProgressView's card only lists badges that
// already exist (`if badges.isEmpty { ... } else { ForEach(badges) ... }`); this screen shows the
// full, spec-named milestone set as a grid — earned tiles lit up with their badge's real
// `earnedAt`, not-yet-earned tiles shown locked/dimmed — because a "trophy case" that only ever
// shows what's already won isn't showing the case, just the trophies. Both screens read the same
// `Badge` rows via `@Query` and the same `Copy.badges.*` keys (see ASSUMED API below), so a badge
// earned anywhere shows up identically in both places with zero duplication of award logic —
// neither this file nor ProgressView.swift ever inserts a `Badge`; that's `StreakEngine`/
// `ComebackMode`/(future) other engines' job exclusively.
//
// Reads `Badge` directly via `@Query`, exactly like `ProgressView.swift` (read in full before
// writing this file) — this screen is read-only, same as that one: it never mutates a `Badge` row
// itself. `CosmeticsStore.shared` (this task's other owned file,
// `Core/Sources/Core/Retention/CosmeticsStore.swift`) supplies the coin balance shown here and
// backs the "Open the Shop" link into `CosmeticsShopView` (this task's third owned file, same
// directory) — Trophy Case and the Cosmetics Shop are one spec section (§5.17) and one coin
// economy, so linking them directly here (rather than making the user find the shop through
// Settings) is this task's own UX call, flagged in `decisions`.
//
// ── The six milestone badge keys below ──
//
// `first_earned_unlock`, `streak_7`, `streak_30`, `streak_100`, `protein_1000g_week`,
// `gym_50_sessions` are exactly spec §5.17's own list, and exactly the same keys/SF Symbols
// `ProgressView.swift`'s file-scoped `ProgressBadgeIconMap` already uses for its `streak_7`/
// `streak_30`/`streak_100`/`protein_1000g_week`/`gym_50_sessions`/`first_earned_unlock` cases
// (that enum also has `streak_14`/`streak_365`/`comeback` cases this screen's canonical grid
// omits — see "Other achievements" below for where those still show up). Icons are re-declared
// locally, inline on each `TrophyMilestone` entry in the `milestones` array below, rather than
// imported: `ProgressBadgeIconMap` is `private` to ProgressView.swift's file scope (Swift access
// control, not a cross-target boundary — same App module, still can't reach a `private` symbol in
// a different file), and this task does not own that file to change its access level. Keeping the
// same SF Symbol choices here is a
// deliberate visual-consistency decision, not a coincidence — flagged in `decisions` in case a
// future session changes one without knowing to update the other.
//
// **No engine currently awards most of these badges.** Grepping the whole repo before writing
// this file found only `StreakEngine.awardComebackBadge` (`"comeback_<date>"`) and
// `ComebackMode.awardChallengeCompleteBadge` (`"comeback_challenge_<date>"`) actually inserting
// `Badge` rows today — nothing yet awards `first_earned_unlock`, `streak_7`, `streak_30`,
// `streak_100`, `protein_1000g_week`, or `gym_50_sessions`. That's expected and correctly
// reflected here: every one of those six tiles renders "locked" until a future session (most
// likely `StreakEngine` for the three streak milestones, `GymVerifier` for the 50-session badge,
// and whichever engine ends up owning weekly protein totals for the 1,000g badge) adds the actual
// award call. Flagged prominently in `knownIssues` — this is real, not a placeholder bug in this
// screen.
//
// ASSUMED API — `Copy.trophyCase.*` / `Copy.cosmetics.*` / `Copy.badges.*` / `Copy.common.*`
// (`Core/Sources/Core/Copy`, not owned by this task). Follows the exact precedent
// `LockSetupView.swift`/`ProgressView.swift` already set: reference `Copy.<feature>.*` by name
// and list every assumed member here. `Copy.badges.*` and `Copy.common.ok` are not new — they're
// the same members `ProgressView.swift`'s own ASSUMED API block already lists; repeated here only
// because this file also depends on them, not because this file is redefining them.
//
//   Copy.trophyCase.screenTitle: String                              // "Trophy Case"
//   Copy.trophyCase.screenSubtitle: String                           // e.g. "Every milestone,
//                                                                     // earned the real way."
//   Copy.trophyCase.progressLabel(earned: Int, total: Int) -> String // "4 of 6 unlocked"
//   Copy.trophyCase.openShopButtonTitle: String                      // "Cosmetics Shop"
//   Copy.trophyCase.lockedAccessibilityHint: String                  // "Not yet earned"
//   Copy.trophyCase.otherAchievementsSectionTitle: String            // "More Achievements"
//   Copy.badges.title(forKey: String) -> String                      // per-badge display title,
//                                                                     // keyed by `Badge.key`
//   Copy.badges.earnedOnLabel(date: Date) -> String                  // "Earned Mar 3"
//   Copy.cosmetics.coinBalanceAccessibilityLabel(balance: Int) -> String  // "120 coins"
//   Copy.common.ok: String                                           // already assumed elsewhere
//
// Badge icon (SF Symbol) mapping is kept as small, file-scoped reference data, not copy — same
// convention `ProgressView.swift`'s own `ProgressBadgeIconMap` and `GoalRow.swift`'s `icon`
// parameter already establish.

import SwiftUI
import SwiftData
import Core

/// The dedicated Trophy Case screen (spec §5.17) — a milestone badge grid plus an entry point
/// into the Cosmetics Shop. Meant to be pushed onto an existing `NavigationStack` (from Progress
/// or Settings, whichever a future session wires up) rather than presenting its own, matching
/// `ProgressView`/`LockSetupView`'s convention of never owning navigation chrome themselves.
public struct TrophyCaseView: View {
    @Query(sort: \Badge.earnedAt, order: .reverse) private var badges: [Badge]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headerCard
                milestonesSection
                if !otherEarnedBadges.isEmpty {
                    otherAchievementsSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .navigationTitle(Copy.trophyCase.screenTitle)
        .task { await CosmeticsStore.shared.refresh() }
    }

    // MARK: - Header (coin balance + Shop entry point)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.trophyCase.progressLabel(earned: earnedMilestoneCount, total: milestones.count))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.trophyCase.screenSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer(minLength: 0)
                CoinBalancePill(balance: CosmeticsStore.shared.coinBalance)
            }

            NavigationLink {
                CosmeticsShopView()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "bag.fill")
                        .foregroundStyle(Theme.Colors.accent)
                    Text(Copy.trophyCase.openShopButtonTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.muted)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    // MARK: - Milestones grid (spec §5.17's exact six)

    /// One tile per spec §5.17 milestone, in the order spec lists them. Static, not derived from
    /// `badges`, so every milestone shows (locked, if unearned) even for a brand-new user with
    /// zero `Badge` rows — the entire point of a trophy *case* over a bare "here's what you've
    /// won so far" list.
    private let milestones: [TrophyMilestone] = [
        TrophyMilestone(key: "first_earned_unlock", systemImage: "star.circle.fill"),
        TrophyMilestone(key: "streak_7", systemImage: "flame"),
        TrophyMilestone(key: "streak_30", systemImage: "flame.fill"),
        TrophyMilestone(key: "streak_100", systemImage: "crown.fill"),
        TrophyMilestone(key: "protein_1000g_week", systemImage: "fork.knife.circle.fill"),
        TrophyMilestone(key: "gym_50_sessions", systemImage: "dumbbell.fill"),
    ]

    private var earnedMilestoneCount: Int {
        milestones.filter { milestone in badges.contains { $0.key == milestone.key } }.count
    }

    private var milestonesSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.sm)],
            spacing: Theme.Spacing.md
        ) {
            ForEach(milestones) { milestone in
                TrophyTile(milestone: milestone, badge: badges.first { $0.key == milestone.key })
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.trophyCase.otherAchievementsSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(otherEarnedBadges) { badge in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "rosette")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Copy.badges.title(forKey: badge.key))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text)
                            Text(Copy.badges.earnedOnLabel(date: badge.earnedAt))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
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

/// One tile in the milestones grid — locked (dimmed, `lock.fill`) if `badge == nil`, lit up with
/// the milestone's real icon and earned date otherwise.
private struct TrophyTile: View {
    let milestone: TrophyMilestone
    let badge: Badge?

    private var isEarned: Bool { badge != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(isEarned ? Theme.Colors.accent.opacity(0.16) : Theme.Colors.surface2)
                    .frame(width: 60, height: 60)
                Image(systemName: isEarned ? milestone.systemImage : "lock.fill")
                    .font(.system(size: isEarned ? 24 : 18, weight: .semibold))
                    .foregroundStyle(isEarned ? Theme.Colors.accent : Theme.Colors.muted)
            }
            Text(Copy.badges.title(forKey: milestone.key))
                .font(Theme.Typography.caption)
                .foregroundStyle(isEarned ? Theme.Colors.text : Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let badge {
                Text(Copy.badges.earnedOnLabel(date: badge.earnedAt))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isEarned ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        guard let badge else {
            return Text("\(Copy.badges.title(forKey: milestone.key)), \(Copy.trophyCase.lockedAccessibilityHint)")
        }
        return Text("\(Copy.badges.title(forKey: milestone.key)), \(Copy.badges.earnedOnLabel(date: badge.earnedAt))")
    }
}

/// A small coin-balance capsule, shared visually (not by import — see `CosmeticsShopView.swift`'s
/// own copy of this same tiny view) between this screen's header and the shop's.
private struct CoinBalancePill: View {
    let balance: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "seal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
            Text("\(balance)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.cosmetics.coinBalanceAccessibilityLabel(balance: balance))
    }
}

#Preview {
    NavigationStack {
        TrophyCaseView()
    }
    .modelContainer(for: [Badge.self, Coin.self, User.self], inMemory: true)
}
