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

// PREMIUM PASS (2026-09-24, docs/design/premium-ui-plan.md, "light is earned"; Spotify chrome +
// Nike numerals). Visual only — every `@Query` and derivation rule above is unchanged:
//   - Backdrop: `.zanoAmbient(.progress(x))` where x = earned days in the last 7 / 7 (`.neutral` with
//     no earned day, or under Reduce Transparency), replacing the flat `background` fill: the page
//     itself gets brighter the more of the week was earned.
//   - Hero: `zanoHero` (the one elevated surface), the lifetime total as an 88pt compressed numeral
//     in the accent (reclaimed time IS the earned reward), a "last 7 days" context line, and bars
//     where a day with an earned unlock is accent and every other day is `track`. Day 1 shows what
//     the number will count and how to start it, not a muted "0m".
//   - Section headers are sentence-case headlines in `text` (no tracked caps); only the hero keeps
//     a small muted eyebrow.
//   - Streak: "14 days" as a 48pt condensed numeral. With no earned day yet the calendar collapses
//     to the current week under a guidance line, instead of 28 grey cells.

// PLAYFUL PASS (2026-10-03, visual direction v2 second pass; founder: "make it more playful").
// Visual only — every `@Query`, derivation rule, hook and analytics event above is unchanged:
//   - Hero = an arcade score: the lifetime number, a "+16h 15m in 7 days" chip, and the week as
//     candy-coloured pills (goal-ring hues, earned days only) that spring up once
//     (`ProgressCandyBars`, Components/ProgressArcade.swift). The how-it-counts sentence and the
//     first-week "what shows up here" list moved into an info button.
//   - Streak = an ember flame + score numeral with best/freezes as chips, and the calendar as a
//     sticker grid: earned days are tilted ember stickers with a flame (`ProgressStickerCell`).
//   - Rank = a collectible hexagon medal (`RankMedal`, RankCard.swift).
//   - Trophy Case = a shelf with badges standing on it; the whole card is the link.
//   - The Gym Home Turf link is removed from this screen (the leaderboard is hidden for v1; the
//     `GymLeaderboardView` code and its copy stay for later).
//   - iPhone SE (320pt): streak chips and rank footer re-flow onto their own rows instead of
//     squeezing the numerals.

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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The recap currently being turned into a share card (`WeeklyRecapShareView`), or `nil`.
    @State private var sharingRecap: Recap?

    // Ranks, seasons, monthly challenge (spec §5.9), all computed locally by `SeasonsAndRanks`.
    @State private var rankStatus: SeasonsAndRanks.RankStatus?
    @State private var placementDaysLeft = 0
    @State private var challengeProgress: SeasonsAndRanks.MonthlyChallengeProgress?

    var body: some View {
        ScrollView {
            // 24pt between sections; inside a section the label row (44pt, text centred) leaves ~14pt
            // to its card and far more to the section above, so each label groups with the card it
            // names and the groups read as groups without divider lines (better-layout 2).
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                timeReclaimedHero
                // The weekly boss and perfect days (gamification, 2026-10-04).
                ScrollMonsterSection()
                streakSection
                rankSection
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
        .zanoAmbient(ambientState)
        .scrollContentBackground(.hidden)
        .navigationTitle(Copy.progress.screenTitle)
        .pageBuddy(.analyzing)
        .onAppear {
            Analytics.shared.capture(event: "progress_viewed")
        }
        // Re-runs when a badge lands (e.g. the season badge this very call banks).
        .task(id: badges.count) { await refreshRank() }
        .sheet(item: $sharingRecap) { recap in
            WeeklyRecapShareView(
                recap: recap,
                goalTitles: Dictionary(allGoals.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
                onDismiss: { sharingRecap = nil }
            )
        }
    }

    /// "Light is earned": the page warms with the share of the last 7 days that had an earned
    /// unlock. Static (a function of data, never animated on its own).
    private var ambientState: ZanoAmbientState {
        let earnedThisWeek = last7DaysReclaim.filter(\.isEarned).count
        guard !reduceTransparency, earnedThisWeek > 0 else { return .neutral }
        return .progress(Double(earnedThisWeek) / 7)
    }

    // MARK: - Time Reclaimed (spec §5.15)

    /// The screen's hero and its one elevated surface: the lifetime number at 88pt compressed in
    /// the accent (reclaimed time is earned), a "last 7 days" line, and the 7-day strip. Before the
    /// first finished lock it explains what will be counted instead of shouting a grey "0m".
    private var timeReclaimedHero: some View {
        let minutes = lifetimeReclaimedMinutes
        let hasHistory = minutes > 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            heroHeader(hasHistory: hasHistory)

            if hasHistory {
                NumeralText(Copy.progress.duration(minutes: minutes), size: .hero, color: Theme.Colors.accent)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .animation(reduceMotion ? nil : Theme.Motion.springPop, value: minutes)
                    // "4 hours 10 minutes", not "4h 10m" (which VoiceOver reads as letters).
                    .accessibilityLabel(Copy.progress.spokenDuration(minutes: minutes))
                weekLine
            } else {
                // Day 1: the number is an honest, quiet 0 (muted, not accent: nothing is earned
                // yet), and the line under it says what fills it.
                NumeralText(Copy.progress.duration(minutes: 0), size: .hero, color: Theme.Colors.muted)
                    .accessibilityHidden(true)
                Text(Copy.progress.timeReclaimedEmptyMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            heroChart
                .padding(.top, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoHero(radius: Theme.Radius.large, tint: hasHistory ? Theme.Colors.accent : nil, active: hasHistory)
    }

    private func heroHeader(hasHistory: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "clock.arrow.circlepath")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(hasHistory ? Theme.Colors.accent : Theme.Colors.muted)
                .accessibilityHidden(true)
            ProgressEyebrow(text: Copy.progress.timeReclaimedTitle)
            Spacer(minLength: 0)
            ZanoInfoButton(
                Copy.progress.timeReclaimedInfo,
                accessibilityLabel: Copy.progress.timeReclaimedInfoAccessibilityLabel
            )
        }
    }

    /// "+16h 15m in 7 days" as a chip (a score delta), or the quiet sentence when the week is empty.
    @ViewBuilder
    private var weekLine: some View {
        let weekMinutes = last7DaysReclaim.reduce(0) { $0 + $1.minutes }
        if weekMinutes > 0 {
            ZanoGlassChip(
                Copy.progress.last7DaysChip(duration: Copy.progress.duration(minutes: weekMinutes)),
                systemImage: "arrow.up.right",
                tint: Theme.Colors.Ring.steps
            )
            .accessibilityLabel(Copy.progress.last7DaysReclaimedLabel(duration: Copy.progress.spokenDuration(minutes: weekMinutes)))
        } else {
            Text(Copy.progress.last7DaysEmptyLabel)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// No lock has ever ended: seven bars of nothing would read as a broken chart, so the strip
    /// becomes the week ahead (today first). Otherwise the candy week.
    @ViewBuilder
    private var heroChart: some View {
        if hasEndedLock {
            ProgressCandyBars(bars: last7DaysReclaim.map(\.candyBar), accessibilityText: last7DaysAccessibilityText)
        } else {
            ProgressFirstWeekDots(startingAt: Calendar.current.startOfDay(for: .now))
        }
    }

    /// Any lock has ever ended (however it ended). `false` is the first-week state.
    private var hasEndedLock: Bool {
        allLockSessions.contains { $0.endedAt != nil }
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
        let earned = earnedDays
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).reversed().compactMap { offset -> ProgressDayReclaim? in
            guard let shifted = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            // Back to local midnight: across a DST change the shifted date lands at 23:00/01:00 and
            // would miss its `minutesByDay`/`earnedDays` key.
            let day = calendar.startOfDay(for: shifted)
            let weekdayIndex = calendar.component(.weekday, from: day) - 1
            return ProgressDayReclaim(
                day: day,
                minutes: minutesByDay[day] ?? 0,
                isToday: offset == 0,
                isEarned: earned.contains(day),
                initial: symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "",
                weekdayIndex: weekdayIndex
            )
        }
    }

    /// Data only (no sentence), spoken: "45 minutes, 0 minutes, 1 hour 10 minutes, ..." oldest to
    /// newest.
    private var last7DaysAccessibilityText: String {
        last7DaysReclaim.map { Copy.progress.spokenDuration(minutes: $0.minutes) }.joined(separator: ", ")
    }

    // MARK: - Streak (spec §8)

    private var currentStreak: Streak? { streaks.first }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionLabel(text: Copy.progress.streakSectionTitle)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                streakHeader
                let earned = earnedDays
                if earned.isEmpty {
                    // Day 1: one week of cells (today outlined) under a line that says what lights
                    // them, instead of four rows of grey.
                    Text(Copy.progress.streakEmptyMessage)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ProgressStreakGrid(earnedDays: earned, weeks: earned.isEmpty ? 1 : 4)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(radius: Theme.Radius.medium, tint: (currentStreak?.current ?? 0) > 0 ? Theme.Colors.ember : nil)
        }
    }

    /// The streak as a score: an ember flame that bounces when the count moves, the count in the
    /// score face, and best + freezes as chips on their own row (they used to sit in a trailing
    /// column that squeezed the number on iPhone SE). Frozen-day state isn't recorded per day in
    /// `Streak`, so nothing here pretends to show it.
    private var streakHeader: some View {
        let current = currentStreak?.current ?? 0
        let best = currentStreak?.best ?? 0
        let freezesLeft = currentStreak?.freezesLeft ?? 0
        let bestLabel = Copy.progress.streakBestLabel(best: best)
        let freezesLabel = Copy.progress.streakFreezesLabel(freezesLeft: freezesLeft)
        // Before the first earned day the header reads "Day 1", not a grey "0 days": today is the
        // first day of the streak, it just hasn't been earned yet.
        let isDayOne = current == 0 && earnedDays.isEmpty

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                streakFlame(isLit: current > 0, current: current)
                streakCount(current: current, isDayOne: isDayOne)
                Spacer(minLength: 0)
            }
            streakChips(bestLabel: bestLabel, freezesLabel: freezesLabel)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isDayOne
                ? "\(Copy.progress.streakDayOneAccessibility) \(freezesLabel)"
                : "\(Copy.progress.streakSectionTitle) \(current). \(bestLabel). \(freezesLabel)"
        )
    }

    private func streakFlame(isLit: Bool, current: Int) -> some View {
        Image(systemName: isLit ? "flame.fill" : "flame")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(isLit ? Theme.Colors.ember : Theme.Colors.muted)
            .frame(width: 56, height: 56)
            .background(Theme.Colors.ember.opacity(isLit ? 0.18 : 0.06), in: Circle())
            .symbolEffect(.bounce, value: current)
    }

    @ViewBuilder
    private func streakCount(current: Int, isDayOne: Bool) -> some View {
        if isDayOne {
            Text(Copy.progress.streakDayOne)
                .font(Theme.Typography.score(size: 36))
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            NumeralText(
                Copy.progress.streakValue(days: current),
                size: .large,
                color: current > 0 ? Theme.Colors.text : Theme.Colors.muted
            )
            .contentTransition(.numericText(value: Double(current)))
        }
    }

    private func streakChips(bestLabel: String, freezesLabel: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ZanoGlassChip(bestLabel, systemImage: "trophy.fill", tint: Theme.Colors.Ring.sunriseAlarm)
                // Freeze = the water hue + snowflake, the same "protected" vocabulary `StreakPill`
                // uses for a frozen day.
                ZanoGlassChip(freezesLabel, systemImage: "snowflake", tint: Theme.Colors.Ring.water)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ZanoGlassChip(bestLabel, systemImage: "trophy.fill", tint: Theme.Colors.Ring.sunriseAlarm)
                ZanoGlassChip(freezesLabel, systemImage: "snowflake", tint: Theme.Colors.Ring.water)
            }
        }
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

    // MARK: - Rank, season, monthly challenge, Gym Home Turf (spec §5.8, §5.9)

    /// Everything here is local (no network): rank and challenge from `SeasonsAndRanks`. The Gym
    /// Home Turf link that used to close this section is gone for v1 (leaderboard hidden); the
    /// `GymLeaderboardView` screen itself is kept.
    @ViewBuilder
    private var rankSection: some View {
        if let rankStatus {
            VStack(alignment: .leading, spacing: 0) {
                ProgressSectionLabel(text: Copy.progress.rankSectionTitle)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    RankCard(status: rankStatus, placementDaysLeft: placementDaysLeft)
                    if let challengeProgress {
                        MonthlyChallengeCard(progress: challengeProgress)
                    }
                    SeasonBadgeRow(badges: badges, season: rankStatus.season, currentRank: rankStatus.rank)
                }
            }
        }
    }

    /// Banks any finished season's / cleared month's badge (idempotent), then reads the live
    /// rank and challenge. Nothing else in the app calls the two award methods yet, so Progress
    /// opening is their call site.
    private func refreshRank() async {
        let engine = SeasonsAndRanks.shared
        await engine.awardPastSeasonBadgeIfNeeded()
        await engine.awardMonthlyChallengeBadgeIfComplete()
        rankStatus = await engine.currentRank()
        placementDaysLeft = engine.placementDaysRemaining()
        challengeProgress = await engine.monthlyChallengeProgress()
    }

    // MARK: - Badges / Trophy Case (spec §5.17)

    /// The Trophy Case entry as a shelf (`ProgressTrophyShelf`): the whole card is the link into
    /// the full Trophy Case. Up to four badges stand on it, earned first, then the spec §5.17
    /// milestones not yet earned as locked silhouettes, so it is never empty.
    private var badgesSection: some View {
        let earnedKeys = Set(badges.map(\.key))
        let milestones = TrophyMilestone.milestoneKeys
        let earnedMilestones = milestones.filter { earnedKeys.contains($0) }.count
        return NavigationLink {
            TrophyCaseView()
        } label: {
            ProgressTrophyShelf(
                title: Copy.progress.badgesSectionTitle,
                countText: Copy.progress.trophyShelfCount(earned: earnedMilestones, total: milestones.count),
                items: trophyEntries.map { ProgressShelfItem(id: $0.id, key: $0.key, isEarned: $0.isEarned) }
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.progress.trophyShelfAccessibility(earned: earnedMilestones, total: milestones.count))
        .accessibilityHint(badges.isEmpty ? Copy.progress.badgesEmptyMessage : Copy.progress.trophyShelfHint)
        .accessibilityAddTraits(.isButton)
    }

    /// Earned badges first (every one, including per-occurrence `comeback_*` keys — nothing earned
    /// is hidden), then any of the spec §5.17 milestones the user has not earned, in spec order.
    private var trophyEntries: [ProgressTrophyEntry] {
        var entries = badges.map {
            ProgressTrophyEntry(id: "earned-\($0.id.uuidString)", key: $0.key, earnedAt: $0.earnedAt)
        }
        let earnedKeys = Set(badges.map(\.key))
        for key in TrophyMilestone.milestoneKeys where !earnedKeys.contains(key) {
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
                    duration: Copy.progress.duration(minutes: recap.stats.timeReclaimedMinutes)
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

    /// Nothing to show yet: a recessed well (the "not yet" surface) rather than a raised card, so
    /// an empty week reads as a placeholder, not a broken card.
    private var recapEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionLabel(text: Copy.progress.recapSectionTitle)

            HStack(spacing: Theme.Spacing.sm) {
                // Buddy everywhere (2026-10-03): no recap yet, so the buddy naps.
                StoredBuddySprite(pose: .sleepy, size: 48)

                Text(Copy.progress.recapEmptyMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoWell(radius: Theme.Radius.medium)
        }
    }

    /// A handful of rings keep each goal's own hue (a legend the eye can learn). Past
    /// `ProgressMetrics.denseRecapRingCount` the row switches to the one-accent scheme instead —
    /// done = `accent`, not done = `textSecondary` — because a fifth and sixth hue turn a legend
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
                color = progress >= 1 ? Theme.Colors.accent : Theme.Colors.textSecondary
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
}

// MARK: - Screen-local primitives
//
// What the shared design system does not express: this screen's section labels, the first-week dots,
// the calendar-aligned streak grid. The candy bars, sticker cells, rank medal and trophy shelf live in
// Components/ProgressArcade.swift. Everything else (cards, numerals, badges, press
// feedback, the secondary button) is `Core`'s — see the CONSOLIDATION PASS note in this file's header.

private enum ProgressMetrics {
    /// More recap rings than this and the row drops per-goal hues for the one-accent scheme.
    static let denseRecapRingCount = 4
    /// First-week dots: diameter.
    static let firstWeekDotDiameter: CGFloat = 22
}

/// The hero's small sentence-case label ("Time reclaimed") in the shared eyebrow style. It is a
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
            // Spotify-style section header: a sentence-case headline in `text`, not tracked caps.
            Text(text)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
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
    /// At least one earned unlock ended this day (the streak's own day rule).
    let isEarned: Bool
    /// Localized very-short weekday symbol ("M", "T", ...) from `Calendar`, not copy.
    let initial: String
    /// `Calendar.component(.weekday) - 1` (0 = Sunday): picks the day's candy colour.
    let weekdayIndex: Int

    var id: Date { day }

    var candyBar: ProgressCandyBar {
        ProgressCandyBar(
            id: day,
            minutes: minutes,
            isToday: isToday,
            isEarned: isEarned,
            initial: initial,
            weekdayIndex: weekdayIndex
        )
    }
}

/// The first week, before any lock has ended: seven dots starting today (outlined in blue, with a
/// soft wash) and running into the six days ahead (empty hairline rings), weekday initials under them, and
/// "Your first week starts today" above. Static; one VoiceOver sentence for the whole row.
private struct ProgressFirstWeekDots: View {
    let startingAt: Date

    private var days: [(day: Date, initial: String)] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).compactMap { offset in
            guard let shifted = calendar.date(byAdding: .day, value: offset, to: startingAt) else { return nil }
            let day = calendar.startOfDay(for: shifted)
            let index = calendar.component(.weekday, from: day) - 1
            return (day, symbols.indices.contains(index) ? symbols[index] : "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.progress.firstWeekStartsToday)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, entry in
                    VStack(spacing: Theme.Spacing.xxs) {
                        dot(isToday: index == 0)
                        Text(entry.initial)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(index == 0 ? Theme.Colors.text : Theme.Colors.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.progress.firstWeekDotsAccessibility)
    }

    @ViewBuilder
    private func dot(isToday: Bool) -> some View {
        let size = ProgressMetrics.firstWeekDotDiameter
        if isToday {
            Circle()
                .fill(Theme.Colors.accentWash)
                .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: Theme.Metrics.selectedStroke))
                .frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth)
                .frame(width: size, height: size)
        }
    }
}

/// A 4-week, calendar-aligned streak grid: weekday header, four Monday-to-Sunday (locale first
/// weekday) rows ending with the current week. Earned days are an `accentWash` cell with a check; the
/// streak's head (the latest earned day, if it's today or yesterday) is the one solid accent cell
/// with a static glow; today is outlined; empty past days are a visible `track`; the rest of the
/// current week is an empty hairline outline. Replaces 28 rolling same-size squares with no weekday labels
/// and 1.08:1 empty days.
private struct ProgressStreakGrid: View {
    let earnedDays: Set<Date>
    /// Rows shown, ending with the current week: 4 normally, 1 on day 1 (see `streakSection`).
    var weeks = 4

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs),
        count: 7
    )

    /// `weeks * 7` consecutive local-midnight days: the current week plus the ones before it.
    private var days: [Date] {
        let cal = calendar
        let rows = max(1, weeks)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = cal.date(byAdding: .weekOfYear, value: -(rows - 1), to: weekStart) else { return [] }
        // `startOfDay` again: adding days across a DST change can land at 23:00/01:00, which would
        // never equal an `earnedDays` entry.
        return (0..<(rows * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
            .map { cal.startOfDay(for: $0) }
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

    private func kind(for day: Date, headDay: Date?, today: Date) -> ProgressStickerCell.Kind {
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

            LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    ProgressStickerCell(kind: kind(for: day, headDay: headDay, today: today), index: index)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        // "12 of 28 days earned": days with an earned unlock out of the days shown so far.
        .accessibilityLabel(Text(Copy.progress.streakCalendarAccessibilityLabel(earned: earnedCount, total: counted.count)))
    }
}

/// One entry in the trophy strip: an earned badge (with its date) or a milestone not yet earned.
private struct ProgressTrophyEntry: Identifiable {
    let id: String
    let key: String
    let earnedAt: Date?

    var isEarned: Bool { earnedAt != nil }
}

#Preview {
    NavigationStack {
        ProgressView()
    }
    .modelContainer(for: [LockSession.self, Streak.self, Badge.self, Recap.self, Goal.self], inMemory: true)
}
