// ProgressView.swift
// App / Features / Progress
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// The type below is named `ProgressView`, matching this file's name and every other screen in
// this codebase (`LockSetupView` in `LockSetupView.swift`, etc.). That name also exists in SwiftUI
// itself (the spinner control) — a same-named type declared in this module shadows the imported
// SwiftUI one with no ambiguity error (Swift always prefers a local-module declaration over an
// identically-named imported one), and this file never references the SwiftUI spinner, so there is
// no self-conflict. A different file that needs the SwiftUI spinner *and* this screen's type in the
// same scope would spell the former `SwiftUI.ProgressView(...)` to disambiguate — flagged here once
// rather than worked around by renaming this screen away from the convention every other screen in
// `App/ZANO/Features` follows.
//
// docs/spec.md §15 (Design System & UI Direction — "Screens: ... Progress ..."), §5.15 (Time
// Reclaimed Counter — "compute on-device: hours of blocked-app time avoided during locks. Show
// lifetime 'Time Reclaimed: 41h 20m' on the Progress tab and in the widget."), §5.17 (Trophy Case &
// Cosmetics — "Badges for milestones (first earned unlock, 7/30/100-day streaks, 1,000g protein
// week, 50 gym sessions)."), §8 (Retention Psychology Rules — streaks "should feel protective, not
// fragile"), §5.14 (Weekly Report Card — reused here as an in-app `RecapCard`, not the 9:16
// `ShareCard` export, which is Session 8/11's job per docs/spec.md §17 rows 8/11).
//
// Reads `LockSession` / `Streak` / `Badge` / `Recap` / `Goal` directly via `@Query` — all Session
// 1's frozen models (`Core/Sources/Core/Models`, read in full before writing this file). This
// screen is read-only: it never mutates a `Streak`/`Badge`/`LockSession` row itself (`StreakEngine`
// and `LockEngineManager` — both system contracts — own that), so there is nothing here that needs
// to go through an engine or an App Intent.
//
// "Time Reclaimed" is computed on-device from local `LockSession` rows, per spec §5.15's explicit
// instruction ("Because Screen Time data can't leave the device, compute on-device") — summing
// every ended session's `endedAt - startedAt` duration. This is a lifetime, all-local aggregate;
// there is no pre-aggregated column for it anywhere in Session 1's Data Model (spec §13), so
// summing the full `LockSession` history client-side is this session's scope-appropriate approach
// (flagged in this task's `decisions`: a real product would pre-aggregate this over time instead of
// re-summing full history on every appearance).
//
// ASSUMED API — `Copy.progress.*` / `Copy.badges.*` / `Copy.common.*` (`Core/Sources/Core/Copy`,
// not owned by this session). Follows the exact precedent `App/ZANO/Features/LockSetup/
// LockSetupView.swift` already set (read in full before writing this file): reference `Copy.
// <feature>.*` by name and list every assumed member here.
//
//   Copy.progress.screenTitle: String
//   Copy.progress.timeReclaimedTitle: String                          // "Time Reclaimed"
//   Copy.progress.streakSectionTitle: String                          // "Streak"
//   Copy.progress.streakBestLabel(best: Int) -> String                // "Best: 21"
//   Copy.progress.streakFreezesLabel(freezesLeft: Int) -> String      // "2 freezes left"
//   Copy.progress.badgesSectionTitle: String                          // "Trophy Case"
//   Copy.progress.badgesEmptyMessage: String
//   Copy.progress.recapSectionTitle: String                           // "This Week"
//   Copy.progress.recapEmptyMessage: String
//   Copy.progress.weekLabel(weekStart: Date) -> String                // "Week of Mar 3"
//   Copy.progress.goalsCompletedLabel(completed: Int, planned: Int) -> String
//   Copy.progress.timeReclaimedLabel(duration: String) -> String      // "6h 40m reclaimed"
//   Copy.progress.bestDayLabel(day: String) -> String                 // "Best day: Thursday"
//   Copy.progress.rankMovementLabel(delta: Int) -> String
//   Copy.progress.unknownGoalLabel: String                            // fallback when a recap's
//                                                                      // goal id no longer exists
//   Copy.badges.title(forKey: String) -> String                       // per Badge.swift's own doc
//                                                                      // comment: badge display
//                                                                      // copy lives in Copy, keyed
//                                                                      // by the stable `Badge.key`.
//   Copy.badges.earnedOnLabel(date: Date) -> String                   // "Earned Mar 3"
//   Copy.common.ok: String                                            // already assumed by
//                                                                      // LockSetupView.swift
//
// Badge icon (SF Symbol) mapping is kept as small, file-scoped reference data — identifiers, not
// copy, matching how `Core/Sources/Core/UI/Components/GoalRow.swift`'s `icon` parameter is a plain
// string rather than routed through `Copy` (see that file's own doc comments).

import SwiftUI
import SwiftData
import Core

/// Shadows `SwiftUI.ProgressView` (the spinner control) by name within this module — see the file
/// header for why that's safe (local-module shadowing, no ambiguity, this file never uses the
/// system spinner).
struct ProgressView: View {
    @Query(sort: \LockSession.startedAt) private var allLockSessions: [LockSession]
    @Query private var streaks: [Streak]
    @Query(sort: \Badge.earnedAt, order: .reverse) private var badges: [Badge]
    @Query(sort: \Recap.weekStart, order: .reverse) private var recaps: [Recap]
    @Query private var allGoals: [Goal]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                timeReclaimedCard
                streakSection
                badgesSection
                if let recap = recaps.first {
                    recapSection(recap)
                } else {
                    recapEmptyState
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.progress.screenTitle)
    }

    // MARK: - Time Reclaimed (spec §5.15)

    private var timeReclaimedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(Copy.progress.timeReclaimedTitle)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Text(formatDuration(minutes: lifetimeReclaimedMinutes))
                .font(Theme.Typography.numeralLarge())
                .foregroundStyle(Theme.Colors.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var lifetimeReclaimedMinutes: Int {
        allLockSessions.reduce(0) { total, session in
            guard let endedAt = session.endedAt else { return total }
            let minutes = Int(endedAt.timeIntervalSince(session.startedAt) / 60)
            return total + max(0, minutes)
        }
    }

    // MARK: - Streak (spec §8)

    private var currentStreak: Streak? { streaks.first }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(Copy.progress.streakSectionTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
                StreakPill(count: currentStreak?.current ?? 0)
            }

            StreakHistoryGrid(earnedDays: earnedDays)

            HStack(spacing: Theme.Spacing.md) {
                Text(Copy.progress.streakBestLabel(best: currentStreak?.best ?? 0))
                Text(Copy.progress.streakFreezesLabel(freezesLeft: currentStreak?.freezesLeft ?? 0))
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    /// The set of calendar days (local midnight) that had at least one earned unlock — the exact
    /// definition `Models/Streak.swift`'s own doc comment gives for what counts a day toward the
    /// streak: "A streak counts days with at least one *earned* unlock." Filters only on the
    /// non-relationship `endedAt != nil` fact via `@Query`'s already-fetched rows, then checks
    /// `unlockKind == .earned` in plain Swift — same conservative predicate/filter split
    /// `LockEngineManager.isGoalVerified` already established, since this session has no
    /// Mac/compiler available to verify `#Predicate`'s handling of enum equality.
    private var earnedDays: Set<Date> {
        let calendar = Calendar.current
        let earnedEndDates = allLockSessions.compactMap { session -> Date? in
            guard session.unlockKind == .earned, let endedAt = session.endedAt else { return nil }
            return calendar.startOfDay(for: endedAt)
        }
        return Set(earnedEndDates)
    }

    // MARK: - Badges / Trophy Case (spec §5.17)

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.progress.badgesSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            if badges.isEmpty {
                Text(Copy.progress.badgesEmptyMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84), spacing: Theme.Spacing.sm)],
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(badges) { badge in
                        BadgeTile(badge: badge)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    // MARK: - Weekly Report Card (spec §5.14)

    private func recapSection(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.progress.recapSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            RecapCard(
                weekLabel: Copy.progress.weekLabel(weekStart: recap.weekStart),
                rankLabel: recap.stats.rankMovement.map { Copy.progress.rankMovementLabel(delta: $0) },
                insightText: recap.text,
                ringItems: recapRingItems(for: recap),
                completionLabel: Copy.progress.goalsCompletedLabel(
                    completed: recap.stats.goalsCompleted,
                    planned: recap.stats.goalsPlanned
                ),
                timeReclaimedLabel: Copy.progress.timeReclaimedLabel(
                    duration: formatDuration(minutes: recap.stats.timeReclaimedMinutes)
                ),
                bestDayLabel: recap.stats.bestDay.map { Copy.progress.bestDayLabel(day: $0) },
                streak: recap.stats.streak
            )
        }
    }

    private var recapEmptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.progress.recapSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.progress.recapEmptyMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func recapRingItems(for recap: Recap) -> [RingClusterItem] {
        recap.stats.goalCompletionRings.compactMap { key, progress -> RingClusterItem? in
            guard let goalID = UUID(uuidString: key) else { return nil }
            let goal = allGoals.first { $0.id == goalID }
            return RingClusterItem(
                id: goalID,
                title: goal?.title ?? Copy.progress.unknownGoalLabel,
                progress: progress,
                color: goal.map { Theme.Colors.Ring.color(for: $0.type) } ?? Theme.Colors.muted
            )
        }
        .sorted { $0.title < $1.title }
    }

    // MARK: - Formatting

    private func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        guard hours > 0 else { return "\(mins)m" }
        return "\(hours)h \(mins)m"
    }
}

// MARK: - File-scoped supporting views

/// A 4-week (28-day), 7-column grid of small squares — accent when that day had an earned unlock,
/// muted surface otherwise — a lightweight "streak calendar" complementing `StreakPill`'s single
/// number with recent history at a glance.
private struct StreakHistoryGrid: View {
    let earnedDays: Set<Date>

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<28).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(earnedDays.contains(day) ? Theme.Colors.accent : Theme.Colors.surface2)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(earnedDays.intersection(Set(days)).count) of \(days.count)"))
    }
}

/// One badge tile in the Trophy Case grid.
private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: ProgressBadgeIconMap.systemImage(forKey: badge.key))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Text(Copy.badges.title(forKey: badge.key))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Copy.badges.title(forKey: badge.key)), \(Copy.badges.earnedOnLabel(date: badge.earnedAt))"))
    }
}

/// Small, non-voiced reference data (SF Symbol identifiers only — see this file's header comment
/// for why badge *titles* still route through `Copy.badges`, unlike these icon names).
private enum ProgressBadgeIconMap {
    /// Fixed in this batch's cross-check: the only badge-awarding code that actually runs in this
    /// codebase today (`Core/Sources/Core/Retention/StreakEngine.swift`'s `awardComebackBadge`,
    /// `ComebackMode.swift`'s `awardChallengeCompleteBadge`) keys comeback badges **per occurrence**
    /// — `"comeback_<yyyy-MM-dd>"` / `"comeback_challenge_<date>"` — not the single static
    /// `"comeback"` key `Models/Badge.swift`'s doc comment uses only as a shorthand example. Matched
    /// by prefix below so every real comeback badge actually resolves an icon instead of silently
    /// falling through to the generic default every time.
    static func systemImage(forKey key: String) -> String {
        if key.hasPrefix("comeback_challenge") { return "flag.checkered.circle.fill" }
        if key.hasPrefix("comeback") { return "arrow.uturn.forward.circle.fill" }
        switch key {
        case "first_earned_unlock": return "star.circle.fill"
        case "streak_7": return "flame"
        case "streak_14", "streak_30": return "flame.fill"
        case "streak_100": return "crown.fill"
        case "streak_365": return "trophy.fill"
        case "protein_1000g_week": return "fork.knife.circle.fill"
        case "gym_50_sessions": return "dumbbell.fill"
        default: return "rosette"
        }
    }
}

#Preview {
    NavigationStack {
        ProgressView()
    }
    .modelContainer(for: [LockSession.self, Streak.self, Badge.self, Recap.self, Goal.self], inMemory: true)
}
