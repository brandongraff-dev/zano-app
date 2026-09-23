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
//   Copy.trophyCase.lockedAccessibilityHint: String                   // "Not yet earned"
//   Copy.common.ok: String                                            // already assumed by
//                                                                      // LockSetupView.swift
//
// Badge icon (SF Symbol) mapping is kept as small, file-scoped reference data — identifiers, not
// copy, matching how `Core/Sources/Core/UI/Components/GoalRow.swift`'s `icon` parameter is a plain
// string rather than routed through `Copy` (see that file's own doc comments).
//
// Earlier task (orchestrator batch, 2026-09-22) confirmed two spec §5.15/§5.17 requirements and
// closed one real gap, all still true after the design pass below:
//
// 1. "Time Reclaimed" was already computed from real `LockSession` durations, not a placeholder —
//    `lifetimeReclaimedMinutes` below sums every *ended* session's `endedAt - startedAt` across the
//    full on-device history (no `unlockKind` filter, so an emergency-unlocked session still counts:
//    distracting apps were shielded for that whole span regardless of how the lock ended, which is
//    the actual thing spec §5.15 wants reclaimed). A currently-active lock's elapsed-so-far time is
//    intentionally *not* included — this is a `@Query`-driven counter that recomputes when a
//    `LockSession` row changes (i.e., when a lock ends), not a live-ticking timer; making the active
//    lock count would need a `Timer`/`.onReceive` tick to move the number while a lock is in
//    progress, which is real added scope this task didn't touch. Flagged, not fixed.
// 2. The Trophy Case section header is a `NavigationLink` into the full, dedicated Trophy Case
//    screen (`App/ZANO/Features/Trophy/TrophyCaseView.swift`, read, not owned).
//
// Also fires `Analytics.shared.capture(event: "progress_viewed")` on `.onAppear` (spec §23).
//
// DESIGN PASS (2026-09-23, docs/design/{competitive-research,2026-ios-trends,better-ui-findings,
// better-layout-findings,typography-color-findings,composition-audit}.md). Composition and visual
// treatment only — every `@Query`, the reclaimed-minutes sum, the earned-day rule, the recap
// mapping and the Trophy Case navigation are unchanged. What moved and why:
//   - One hero. Time Reclaimed (spec §5.15's payoff, the number people screenshot) is now a
//     72pt numeral with h/m units, on a large accent-washed card, with a 7-day bar strip beneath
//     it (the Opal "big number + one small chart" pattern, competitive-research 3.1/3.8) built from
//     the same `LockSession` rows. The other three sections are quieter `.medium` cards, so the
//     screen has an entry point instead of four identical slabs (composition-audit offender 10).
//   - Streak = a real number (`numeralLarge`, flame beside it), not a 17pt pill above a wall of
//     squares; best + freezes sit with it. The 28-day grid is calendar-aligned under a weekday
//     header, has a today marker and visible empty days, and reserves the solid accent for the
//     streak's head cell only (earned days are a calm accent tint + check). Before: 28 rolling
//     squares, no weekdays, empty days 1.08:1 on their card, earned days solid accent in bulk.
//   - Trophy strip: one horizontal row that bleeds to the card edge (the next tile peeks), earned
//     badges first, then the spec §5.17 milestones you have NOT earned yet as dimmed silhouettes of
//     their OWN glyph with a small lock — a new user sees what there is to win instead of a
//     paragraph. Badge icons drop the `.circle.fill` variants (a circle inside a circle).
//   - Section labels sit above their cards as small tracked caps, so "This Week" is no longer a
//     17pt heading over a 22pt card title (better-layout 1.7), and `chevron.right` became
//     `chevron.forward` (RTL).
//   - Cards get a top-lit 1pt edge (`surface` alone is 1.08:1 off `background`).
//   - The This Week card now has a "Share this" action that presents `WeeklyRecapShareView` (the
//     9:16 export). That screen already existed and documents this file as its presenter, but
//     nothing anywhere in the app navigated to it (composition-audit offender 6).
//   - Every animation is gated on `accessibilityReduceMotion`; there is no looping motion.
//
// CONSOLIDATION PASS (2026-09-23, later the same day). The pass above was written while `Theme` and
// the shared Core UI pieces were still being built in a parallel wave, so it carried file-scoped
// copies of them (`ProgressSurface`/`ProgressEdge`, `ProgressPressStyle`, `ProgressShareButton`,
// `ProgressDurationHero`, an inline eyebrow, `ProgressMetrics.minTapTarget`/`badge`). Those now exist
// for real, so this file uses them instead of re-implementing them:
//   - cards          -> `.zanoCard(radius:tint:active:)`. The hero passes `active: minutes > 0`: the
//                       lifetime total IS the earned reward, so it gets the design system's earned
//                       glow (nothing else on the screen does). `RecapCard` (Core) is itself a
//                       `zanoCard`, so it is used as-is (review pass: a redundant `zanoCard(fill:
//                       .clear)` wrapper that doubled its edge was removed).
//   - the hero number-> `NumeralText(size: .hero)`: 72pt heavy digits, quiet h/m units on the same
//                       baseline, Dynamic Type scaling and shrink-to-fit in one place. The streak
//                       count is `NumeralText(size: .large)` beside an `IconBadge` flame.
//   - share action   -> `PrimaryButton(style: .secondary)`.
//   - press/badges   -> `PressableStyle`, `IconBadge`.
//   - text/tokens    -> `zanoText(.eyebrow)`, `Theme.Typography.icon(_)`, `Theme.Metrics`,
//                       `Theme.Radius.inner(of:inset:)` for the streak-cell corner.
//   - fills          -> `accentWash` / `accentDim` for earned tiles and cells (`accent.opacity(0.16)`
//                       composites to a drab olive next to the real accent) and `track` for the
//                       empty half of the week bars and the unearned streak cells (the token exists
//                       for exactly that; the old 10% white was 1.3:1).
//   - recap rings    -> each ring now carries its goal's glyph (`goalIconName(for:)`, the shared
//                       goal-type -> SF Symbol mapping in `TodayView.swift`), and a recap with more
//                       than four rings uses the one-accent scheme instead of one hue per goal
//                       (2026-ios-trends 4.3, competitive-research 3.11.4).
// One layout fix along the way: the Trophy Case label is a 44pt link row while the other section
// labels were bare 28pt frames, so the label-to-card gap was ~14pt under one and ~8pt under the
// others. Every section now uses the same `minTapTarget`-tall label row (`ProgressSectionLabel`), so
// the gap is identical down the screen and each label reads as belonging to the card below it.
//

// ASSUMED API (design pass) — `Copy.share.shareButtonTitle` ("Share this", `ShareCopy.swift`) and
// `WeeklyRecapShareView(recap:goalTitles:rankTierLabel:onDismiss:)` (`Features/Share`), both read in
// full on disk before use. Not compiler-verified (no Mac).

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The recap currently being turned into a share card (`WeeklyRecapShareView`), or `nil`.
    @State private var sharingRecap: Recap?

    var body: some View {
        ScrollView {
            // 24pt between sections; inside a section the label row (44pt, text centred) leaves ~14pt
            // to its card and far more to the section above, so each label groups with the card it
            // names and the groups read as groups without divider lines (better-layout 2).
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                timeReclaimedHero
                streakSection
                badgesSection
                if let recap = recaps.first {
                    recapSection(recap)
                } else {
                    recapEmptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.progress.screenTitle)
        .onAppear {
            Analytics.shared.capture(event: "progress_viewed")
        }
        .sheet(item: $sharingRecap) { recap in
            WeeklyRecapShareView(
                recap: recap,
                goalTitles: Dictionary(allGoals.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
                onDismiss: { sharingRecap = nil }
            )
        }
    }

    // MARK: - Time Reclaimed (spec §5.15)

    /// The screen's hero: the lifetime number at 72pt with quiet h/m units, over a 7-day strip. Radius
    /// `.large`, an accent wash and — once there is anything reclaimed — the earned glow mark it as
    /// the lead; everything below is `.medium` and quieter.
    private var timeReclaimedHero: some View {
        let minutes = lifetimeReclaimedMinutes
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                ProgressEyebrow(text: Copy.progress.timeReclaimedTitle)
            }

            // Before the first finished lock the loudest thing on the screen would be a 72pt "0m":
            // it recedes to `muted` (and the card has no earned glow) until there is something
            // reclaimed to celebrate.
            NumeralText(
                formatDuration(minutes: minutes),
                size: .hero,
                color: minutes > 0 ? Theme.Colors.text : Theme.Colors.muted
            )
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: minutes)

            ProgressWeekBars(days: last7DaysReclaim, accessibilityText: last7DaysAccessibilityText)
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.large, tint: Theme.Colors.accent, active: minutes > 0)
    }

    private var lifetimeReclaimedMinutes: Int {
        allLockSessions.reduce(0) { total, session in
            guard let endedAt = session.endedAt else { return total }
            let minutes = Int(endedAt.timeIntervalSince(session.startedAt) / 60)
            return total + max(0, minutes)
        }
    }

    /// Minutes reclaimed per calendar day for the last 7 days (oldest first, today last), from the
    /// same ended-session durations as `lifetimeReclaimedMinutes`. A session counts toward the day it
    /// ENDED — the same day rule `earnedDays` uses — so a lock that runs past midnight lands whole
    /// on the morning it lifted rather than being split.
    private var last7DaysReclaim: [ProgressDayReclaim] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var minutesByDay: [Date: Int] = [:]
        for session in allLockSessions {
            guard let endedAt = session.endedAt else { continue }
            let minutes = max(0, Int(endedAt.timeIntervalSince(session.startedAt) / 60))
            minutesByDay[calendar.startOfDay(for: endedAt), default: 0] += minutes
        }
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).reversed().compactMap { offset -> ProgressDayReclaim? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekdayIndex = calendar.component(.weekday, from: day) - 1
            return ProgressDayReclaim(
                day: day,
                minutes: minutesByDay[day] ?? 0,
                isToday: offset == 0,
                initial: symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : ""
            )
        }
    }

    /// Data only (no sentence): "45m, 0m, 1h 10m, ..." oldest to newest.
    private var last7DaysAccessibilityText: String {
        last7DaysReclaim.map { formatDuration(minutes: $0.minutes) }.joined(separator: ", ")
    }

    // MARK: - Streak (spec §8)

    private var currentStreak: Streak? { streaks.first }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionLabel(text: Copy.progress.streakSectionTitle)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                streakHeader
                ProgressStreakGrid(earnedDays: earnedDays)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(radius: Theme.Radius.medium)
        }
    }

    /// The streak as a number: flame + `numeralLarge`, with best and freezes beside it (they belong
    /// with the number they summarise, not under a grid). The old `StreakPill` was a 17pt capsule;
    /// `RecapCard` still uses it, where it is chrome. Frozen-day state isn't recorded per day in
    /// `Streak`, so nothing here pretends to show it.
    private var streakHeader: some View {
        let current = currentStreak?.current ?? 0
        let best = currentStreak?.best ?? 0
        let freezesLeft = currentStreak?.freezesLeft ?? 0
        let bestLabel = Copy.progress.streakBestLabel(best: best)
        let freezesLabel = Copy.progress.streakFreezesLabel(freezesLeft: freezesLeft)

        return HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            // Lit while a streak is running, a muted outline when it is not — the disc swaps
            // flame <-> flame.fill and accent <-> muted on the shared icon-swap spring.
            IconBadge(
                systemName: current > 0 ? "flame.fill" : "flame",
                tint: current > 0 ? Theme.Colors.accent : Theme.Colors.muted
            )

            NumeralText("\(current)", size: .large, color: current > 0 ? Theme.Colors.text : Theme.Colors.muted)

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(bestLabel)
                HStack(spacing: Theme.Spacing.xxs) {
                    // Freeze = the water hue + snowflake, the same "protected" vocabulary
                    // `StreakPill` uses for a frozen day.
                    Image(systemName: "snowflake")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.Ring.water)
                        .accessibilityHidden(true)
                    Text(freezesLabel)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .multilineTextAlignment(.trailing)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Copy.progress.streakSectionTitle) \(current). \(bestLabel). \(freezesLabel)")
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

    /// The label doubles as a `NavigationLink` into the full, dedicated Trophy Case screen
    /// (`TrophyCaseView`). The strip below shows every earned badge (newest first) and then the
    /// spec §5.17 milestones not yet earned, so it is never empty and always says what is next.
    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                TrophyCaseView()
            } label: {
                ProgressSectionLabel(text: Copy.progress.badgesSectionTitle, showsChevron: true)
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if badges.isEmpty {
                    Text(Copy.progress.badgesEmptyMessage)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                // The scroller spans the whole card width (inset applied to its content), so tiles
                // slide under the card edge and the next one peeks — the cue that there's more.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ForEach(trophyEntries) { entry in
                            ProgressTrophyTile(entry: entry)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The strip scrolls edge to edge, so clip it to the card's own corner before the card
            // surface (and its edge) is drawn behind it — clipping after would cut the edge.
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .zanoCard(radius: Theme.Radius.medium)
        }
    }

    /// Earned badges first (every one, including per-occurrence `comeback_*` keys — nothing earned
    /// is hidden), then any of the spec §5.17 milestones the user has not earned, in spec order.
    private var trophyEntries: [ProgressTrophyEntry] {
        var entries = badges.map {
            ProgressTrophyEntry(id: "earned-\($0.id.uuidString)", key: $0.key, earnedAt: $0.earnedAt)
        }
        let earnedKeys = Set(badges.map(\.key))
        for key in ProgressBadgeIconMap.milestoneKeys where !earnedKeys.contains(key) {
            entries.append(ProgressTrophyEntry(id: "locked-\(key)", key: key, earnedAt: nil))
        }
        return entries
    }

    // MARK: - Weekly Report Card (spec §5.14)

    private func recapSection(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionLabel(text: Copy.progress.recapSectionTitle)

            // `RecapCard` (Core/UI) is already a `zanoCard` (surface, top-lit edge, radius 20), the
            // same recipe as every other card on this screen, so it is placed as-is. A second
            // `zanoCard(fill: .clear)` around it (what this call site used to do, back when the card
            // drew its own slab) stacked a second top-lit edge on the first and brightened the rim.
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

            // `WeeklyRecapShareView` (the 9:16 export) had no entry point anywhere in the app: the
            // recap it shares lives HERE, so this is where the way in belongs (composition-audit
            // offender 6). Secondary style on purpose — the hero stays the loudest thing on screen.
            PrimaryButton(
                title: Copy.share.shareButtonTitle,
                systemImage: "square.and.arrow.up",
                style: .secondary
            ) {
                Analytics.shared.capture(event: "progress_recap_share_opened")
                sharingRecap = recap
            }
            .padding(.top, Theme.Spacing.md)
        }
    }

    /// Nothing to show yet: a dashed outline (the "not yet" language) rather than a filled card,
    /// so an empty week reads as a placeholder, not a broken card.
    private var recapEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionLabel(text: Copy.progress.recapSectionTitle)

            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "calendar", tint: Theme.Colors.muted)

                Text(Copy.progress.recapEmptyMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(
                    Theme.Colors.hairlineStrong,
                    style: StrokeStyle(lineWidth: Theme.Metrics.edgeWidth, dash: [6, 5])
                )
            )
        }
    }

    /// A handful of rings keep each goal's own hue (a legend the eye can learn). Past
    /// `ProgressMetrics.denseRecapRingCount` the row switches to the one-accent scheme instead —
    /// done = `accent`, not done = a quiet `text` tint — because a fifth and sixth hue turn a legend
    /// into confetti and dilute the accent's one meaning ("earned"). Either way every ring carries
    /// its goal's glyph in the middle plus its title underneath, so nothing is told apart by hue
    /// alone (glyph-first rule; 18 of the 66 ring-hue pairs are not separable under colour-vision
    /// filters — 2026-ios-trends 4.3).
    private func recapRingItems(for recap: Recap) -> [RingClusterItem] {
        let isDense = recap.stats.goalCompletionRings.count > ProgressMetrics.denseRecapRingCount
        return recap.stats.goalCompletionRings.compactMap { key, progress -> RingClusterItem? in
            guard let goalID = UUID(uuidString: key) else { return nil }
            let goal = allGoals.first { $0.id == goalID }
            let color: Color
            if isDense {
                color = progress >= 1 ? Theme.Colors.accent : Theme.Colors.text.opacity(0.55)
            } else {
                color = goal.map { Theme.Colors.Ring.color(for: $0.type) } ?? Theme.Colors.muted
            }
            return RingClusterItem(
                id: goalID,
                title: goal?.title ?? Copy.progress.unknownGoalLabel,
                progress: progress,
                color: color,
                centerIcon: goal.map { goalIconName(for: $0.type) }
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

// MARK: - Screen-local primitives
//
// What the shared design system does not express: this screen's section labels, the 7-day bars, the
// calendar-aligned streak grid and the trophy strip. Everything else (cards, numerals, badges, press
// feedback, the secondary button) is `Core`'s — see the CONSOLIDATION PASS note in this file's header.

private enum ProgressMetrics {
    /// Trophy tile: circle diameter and tile width (wide enough for a two-line title at 13pt).
    static let trophyDiameter: CGFloat = 56
    static let trophyTileWidth: CGFloat = 84
    /// The small lock badge on a not-yet-earned trophy disc.
    static let lockBadgeDiameter: CGFloat = 20
    /// More recap rings than this and the row drops per-goal hues for the one-accent scheme.
    static let denseRecapRingCount = 4
    /// 7-day strip: bar width, and the tallest/shortest bar.
    static let barWidth: CGFloat = 22
    static let barMaxHeight: CGFloat = 52
    static let barMinHeight: CGFloat = 6
    /// Streak grid: cell aspect (wider than tall keeps four rows compact) and the concentric corner
    /// radius — a `.medium` card holding cells at `Spacing.md` inset (20 - 16 = 4).
    static let cellAspect: CGFloat = 1.4
    static let cellRadius: CGFloat = Theme.Radius.inner(of: Theme.Radius.medium, inset: Theme.Spacing.md)
}

/// Small tracked all-caps label ("TIME RECLAIMED", "STREAK") in the shared eyebrow style. It is a
/// heading for VoiceOver's rotor, not just decoration.
private struct ProgressEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .zanoText(.eyebrow)
            .foregroundStyle(Theme.Colors.muted)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The label row above a card. Every section's row is `minTapTarget` tall (the Trophy Case one is a
/// link, the others are not) so the label-to-card gap is identical down the whole screen: the text
/// sits centred in the row, 14pt clear of the card below and much further from the section above, so
/// it groups with the card it names.
private struct ProgressSectionLabel: View {
    let text: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ProgressEyebrow(text: text)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Theme.Metrics.minTapTarget)
        .contentShape(Rectangle())
    }
}

/// One day in the hero's 7-day strip.
private struct ProgressDayReclaim: Identifiable, Equatable {
    let day: Date
    let minutes: Int
    let isToday: Bool
    /// Localized very-short weekday symbol ("M", "T", ...) from `Calendar`, not copy.
    let initial: String

    var id: Date { day }
}

/// Seven bars, oldest to today, with weekday initials underneath. Today's bar is the accent; earlier
/// days are a quiet `text` tint; an empty day is a short `track` stub, so the strip reads as seven
/// days even before there is any data. Bar height is proportional to the busiest day in the window.
private struct ProgressWeekBars: View {
    let days: [ProgressDayReclaim]
    let accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxMinutes: Int { max(days.map(\.minutes).max() ?? 0, 1) }

    private func barHeight(for day: ProgressDayReclaim) -> CGFloat {
        guard day.minutes > 0 else { return ProgressMetrics.barMinHeight }
        let fraction = CGFloat(day.minutes) / CGFloat(maxMinutes)
        return max(ProgressMetrics.barMinHeight, fraction * ProgressMetrics.barMaxHeight)
    }

    private func barFill(for day: ProgressDayReclaim) -> Color {
        if day.minutes == 0 { return Theme.Colors.track }
        return day.isToday ? Theme.Colors.accent : Theme.Colors.text.opacity(0.30)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            ForEach(days) { day in
                VStack(spacing: Theme.Spacing.xxs) {
                    Capsule()
                        .fill(barFill(for: day))
                        .frame(width: ProgressMetrics.barWidth, height: barHeight(for: day))
                    Text(day.initial)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(day.isToday ? Theme.Colors.text : Theme.Colors.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: ProgressMetrics.barMaxHeight)
        .animation(reduceMotion ? nil : Theme.Motion.ringFill, value: days.map(\.minutes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// A 4-week, calendar-aligned streak grid: weekday header, four Monday-to-Sunday (locale first
/// weekday) rows ending with the current week. Earned days are an `accentWash` cell with a check; the
/// streak's head (the latest earned day, if it's today or yesterday) is the one solid accent cell
/// with a static glow; today is outlined; empty past days are a visible `track`; the rest of the
/// current week is a dashed outline. Replaces 28 rolling same-size squares with no weekday labels
/// and 1.08:1 empty days.
private struct ProgressStreakGrid: View {
    let earnedDays: Set<Date>

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xxs),
        count: 7
    )

    /// 28 consecutive local-midnight days: the current week plus the three before it.
    private var days: [Date] {
        let cal = calendar
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = cal.date(byAdding: .weekOfYear, value: -3, to: weekStart) else { return [] }
        return (0..<28).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    /// Localized very-short weekday symbols for the first row's columns, in locale week order.
    private func weekdayInitials(for days: [Date]) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return days.prefix(7).map { day in
            let index = calendar.component(.weekday, from: day) - 1
            return symbols.indices.contains(index) ? symbols[index] : ""
        }
    }

    private var headDay: Date? {
        let today = self.today
        guard let latest = earnedDays.filter({ $0 <= today }).max(),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              latest >= yesterday
        else { return nil }
        return latest
    }

    private func kind(for day: Date, headDay: Date?, today: Date) -> ProgressStreakCell.Kind {
        if day > today { return .future }
        if day == headDay { return .head }
        if earnedDays.contains(day) { return .earned }
        if day == today { return .today }
        return .missed
    }

    var body: some View {
        let days = self.days
        let today = self.today
        let headDay = self.headDay
        let counted = days.filter { $0 <= today }
        let earnedCount = counted.filter { earnedDays.contains($0) }.count

        VStack(spacing: Theme.Spacing.xs) {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xxs) {
                ForEach(Array(weekdayInitials(for: days).enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: Theme.Spacing.xxs) {
                ForEach(days, id: \.self) { day in
                    ProgressStreakCell(kind: kind(for: day, headDay: headDay, today: today))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        // "12 of 28 earned": days with an earned unlock out of the days shown so far. Reuses the
        // existing Copy shape instead of composing an "of" sentence in the view.
        .accessibilityLabel(Text(Copy.trophyCase.progressLabel(earned: earnedCount, total: counted.count)))
    }
}

/// One day cell in `ProgressStreakGrid`. Pure state -> paint; the glow is static (never animated).
/// Earned is the on-hue `accentWash` with an `accentDim` edge and an accent check; only the head cell
/// is the solid accent (with the `onFill` label colour, 16.4:1) — the brand's scarcest colour is
/// spent on one cell, not 28.
private struct ProgressStreakCell: View {
    enum Kind { case head, earned, today, missed, future }

    let kind: Kind

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ProgressMetrics.cellRadius, style: .continuous)
        shape
            .fill(fill)
            .overlay { cellEdge(shape) }
            .overlay {
                switch kind {
                case .head:
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.onFill)
                case .earned:
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.accent)
                case .today, .missed, .future:
                    EmptyView()
                }
            }
            .shadow(color: Theme.Colors.accent.opacity(kind == .head ? 0.45 : 0), radius: 8)
            .aspectRatio(ProgressMetrics.cellAspect, contentMode: .fit)
    }

    private var fill: Color {
        switch kind {
        case .head: Theme.Colors.accent
        case .earned: Theme.Colors.accentWash
        case .today, .missed: Theme.Colors.track
        case .future: Color.clear
        }
    }

    @ViewBuilder
    private func cellEdge(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .today:
            shape.strokeBorder(Theme.Colors.text.opacity(0.55), lineWidth: 1.5)
        case .earned:
            shape.strokeBorder(Theme.Colors.accentDim, lineWidth: Theme.Metrics.edgeWidth)
        case .future:
            shape.strokeBorder(Theme.Colors.hairline, style: StrokeStyle(lineWidth: Theme.Metrics.edgeWidth, dash: [2, 3]))
        case .head, .missed:
            EmptyView()
        }
    }
}

/// One entry in the trophy strip: an earned badge (with its date) or a milestone not yet earned.
private struct ProgressTrophyEntry: Identifiable {
    let id: String
    let key: String
    let earnedAt: Date?

    var isEarned: Bool { earnedAt != nil }
}

/// One tile in the trophy strip. Earned = accent glyph on an `accentWash` disc with an `accentDim`
/// edge and a soft static glow. Not earned = the milestone's OWN glyph in `muted` on a dim disc, with
/// a small lock badge — six identical padlocks say nothing, the actual silhouettes say what there is
/// to win. Title stays `muted` (5.6:1), not dimmed: the name of the thing to earn is the content.
private struct ProgressTrophyTile: View {
    let entry: ProgressTrophyEntry

    private var title: String { Copy.badges.title(forKey: entry.key) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: ProgressBadgeIconMap.systemImage(forKey: entry.key))
                    .font(.system(size: ProgressMetrics.trophyDiameter * 0.42, weight: .semibold))
                    .foregroundStyle(entry.isEarned ? Theme.Colors.accent : Theme.Colors.muted)
                    .frame(width: ProgressMetrics.trophyDiameter, height: ProgressMetrics.trophyDiameter)
                    .background(
                        entry.isEarned ? Theme.Colors.accentWash : Theme.Colors.hairline,
                        in: Circle()
                    )
                    .overlay {
                        if entry.isEarned {
                            Circle().strokeBorder(Theme.Colors.accentDim, lineWidth: Theme.Metrics.edgeWidth)
                        }
                    }
                    .shadow(color: Theme.Colors.accent.opacity(entry.isEarned ? 0.30 : 0), radius: 10)

                if !entry.isEarned {
                    Image(systemName: "lock.fill")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(width: ProgressMetrics.lockBadgeDiameter, height: ProgressMetrics.lockBadgeDiameter)
                        .background(Theme.Colors.surface2, in: Circle())
                        // A cutout ring in the card's own colour separates the badge from the disc.
                        .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
                }
            }

            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(entry.isEarned ? Theme.Colors.text : Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: ProgressMetrics.trophyTileWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        if let earnedAt = entry.earnedAt {
            return Text("\(title), \(Copy.badges.earnedOnLabel(date: earnedAt))")
        }
        return Text("\(title), \(Copy.trophyCase.lockedAccessibilityHint)")
    }
}

/// Small, non-voiced reference data (SF Symbol identifiers only — see this file's header comment
/// for why badge *titles* still route through `Copy.badges`, unlike these icon names).
private enum ProgressBadgeIconMap {
    /// The spec §5.17 milestone keys, in the order the spec lists them (mirrors
    /// `TrophyCaseView`'s own private list; kept here rather than shared because that file isn't
    /// owned by this screen). Drives the not-yet-earned tiles in the trophy strip.
    static let milestoneKeys = [
        "first_earned_unlock",
        "streak_7",
        "streak_30",
        "streak_100",
        "protein_1000g_week",
        "gym_50_sessions",
    ]

    /// Fixed in an earlier cross-check: the only badge-awarding code that actually runs in this
    /// codebase today (`Core/Sources/Core/Retention/StreakEngine.swift`'s `awardComebackBadge`,
    /// `ComebackMode.swift`'s `awardChallengeCompleteBadge`) keys comeback badges **per occurrence**
    /// — `"comeback_<yyyy-MM-dd>"` / `"comeback_challenge_<date>"` — not the single static
    /// `"comeback"` key `Models/Badge.swift`'s doc comment uses only as a shorthand example. Matched
    /// by prefix below so every real comeback badge actually resolves an icon instead of silently
    /// falling through to the generic default every time.
    ///
    /// Design pass: the `.circle.fill` variants are gone — these glyphs sit inside a disc already, and
    /// a circle inside a circle read as two competing shapes next to bare siblings like `dumbbell.fill`
    /// (better-ui ICO-09). SF Symbol names are from memory of the catalog; confirm each in the SF
    /// Symbols app on a Mac.
    static func systemImage(forKey key: String) -> String {
        if key.hasPrefix("comeback_challenge") { return "flag.checkered" }
        if key.hasPrefix("comeback") { return "arrow.uturn.forward" }
        switch key {
        case "first_earned_unlock": return "star.fill"
        case "streak_7": return "flame"
        case "streak_14", "streak_30": return "flame.fill"
        case "streak_100": return "crown.fill"
        case "streak_365": return "trophy.fill"
        case "protein_1000g_week": return "fork.knife"
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
