# Session 37 — Weekly recap: rank movement + time apps stayed locked

- **Branch:** `worktree-agent-a9d97c9ceb070221c` (fast-forwarded to `origin/main` c586ea9 before starting)
- **Spec sections:** §5.14 (Weekly Report Card: "rank movement", "time reclaimed"), §5.15 (Time
  Reclaimed: on-device, Screen Time data can't leave the device), §5.9 (ranks, quarterly season
  reset), §5.16 (locked-out attempts), §5.13 (coach voices), §8 rule 9 (no shame), §24
- **Status:** Scaffolded — Unverified (no Swift toolchain here; awaiting CI build + Core tests)
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

- Fill `RecapStats.rankMovement` (already rendered by `RecapCard.rankLabel` and the recap story),
  comparing this week's rank with last week's without a fake drop at a new season.
- "Screen time saved this week": an honest on-device estimate from ZANO's own data, shown on the
  weekly recap card and in the share story/poster, compared with last week.
- Core unit tests for the week computations.

## Definition of done

- Rank movement and the time-locked summary appear on the recap card and share image for a week
  built on device; numbers are right across week, season and DST boundaries; CI green.

## Log

### 2026-10-07 — Rank movement, time apps stayed locked, tests

- **Files touched:**
  - `Core/Sources/Core/Retention/SeasonsAndRanks.swift` (modified): `weeklyRankMovement(weekStart:calendar:)`,
    pure `rankMovementDays(weekStart:calendar:)` and `rankMovement(from:to:)`, sync `rankStatus(asOf:)`
    behind `currentRank(asOf:)`. Removed the stale "nothing fills rankMovement" TODO and header note.
  - `Core/Sources/Core/Retention/WeeklyRecapBuilder.swift` (modified): summary gains `rankMovement`,
    `timeBankSpentMinutes`, `lockedAppAttempts` (all optional) and computed `appsLockedMinutes`;
    `Comparison` gains `appsLockedMinutesDelta`, `lockedAppAttemptsDelta` (optional);
    `RecapWeekInputs` gains `timeBankSpentMinutes`, `lockedAppAttempts` (defaulted); inputs read the
    week's `TimeBank` rows and the attempt tally; `stats(for:)` writes `rankMovement` and the
    net-of-spend minutes.
  - `Core/Sources/Core/LockEngine/LockedOutAttemptTracker.swift` (modified): per-local-day attempt
    tally in the same single App Group key (15 days kept) + `attempts(from:to:calendar:)`.
  - `Core/Sources/Core/Copy/WeeklyRecapCopy.swift` (modified): time-locked labels, vs-last-week line,
    reached/closed lines, poster pill, "not Apple Screen Time" footnote.
  - `Core/Sources/Core/UI/Components/RecapCard.swift` (modified): optional `timeSavedNotes` /
    `timeSavedFootnote`.
  - `App/ZANO/Features/Progress/ProgressView.swift` (modified): recap card uses the new label, notes
    and footnote; passes the stored summary to the share view.
  - `App/ZANO/Features/Share/WeeklyRecapShareView.swift`, `RecapStoryPages.swift`, `SharePoster.swift`
    (modified): optional `summary:` init parameter; time page eyebrow "Time your apps stayed
    locked" + vs-last-week / reached lines + footnote; poster hero caption "Apps stayed locked" and
    an optional third sticker "Reached for a locked app N×".
  - `Core/Tests/CoreTests/WeeklyRankTimeSavedTests.swift` (new).
- **What changed / decisions:**
  - **Rank movement is recomputed, not persisted.** Rank is derived live from `GoalEvent` history
    (`SeasonsAndRanks` header), so "rank as of last Sunday" reconstructs exactly from the same rows
    with the same goals' cadence on both sides. A stored snapshot would bake in whatever goals were
    active then, so adding a goal midweek would show movement no completion caused. Compared days:
    the Sunday before `weekStart` vs the week's Sunday (calendar `.day` math, DST-safe).
  - **No fake drops or climbs:** `nil` (nothing shown) when the two days are in different seasons
    (new season = reset, §5.9 / §8 rule 9), when either side is in placement (forced Bronze), when
    the account didn't exist on the previous Sunday, or with no local user. 0 shows "Holding steady"
    (existing copy).
  - **"Screen time saved" is named for what it counts.** Apple's Screen Time numbers are only
    readable inside the DeviceActivityReport extension, so the stat is "Time your apps stayed
    locked" = lock time (overlaps once, existing rule) minus Time Bank minutes spent opening apps
    that week, plus "Reached for a locked app N times, closed it M" (shield renders from
    `LockedOutAttemptTracker`'s new per-day tally; closes from `ReclaimedOpens`). A footnote says
    "Counted from your ZANO locks, not Apple Screen Time." No made-up minutes-per-attempt multiplier.
  - `RecapStats.timeReclaimedMinutes` is now net of Time Bank spend (those minutes the apps were
    open, so they weren't reclaimed). Same number as before when nothing was spent.
  - Attempt and close counts stay in the on-device `WeeklyRecapSummary` (App Group defaults), not
    the synced `RecapStats`: no SwiftData/Supabase schema change, and behavior counts don't leave the
    device. Only `rankMovement` (existing column) and the minutes go into the synced row.
  - Card/poster stat labels are not voiced (same as `Copy.progress`); the voiced part of the recap
    stays the coach line. Vs-last-week is stated as a fact ("40m less than last week"), no shame.
  - The `weekly-recap` Edge Function is untouched and not required: the recap is built locally by
    `WeeklyRecapBuilder` (already the case); the server job has no rank logic and doesn't need it.
- **Known issues / TODOs left behind:**
  - The per-day attempt tally starts when this ships; earlier weeks read 0 attempts (the old store
    kept only 24 hours of timestamps).
  - Shield renders are a proxy for "reached for a locked app": the system can re-render a shield
    (deduped within 10 s, existing rule), and a category shield counts once per render.
  - Rank movement uses the user's *current* active goals for both Sundays (same limitation the
    season badge already documents).
  - The poster's third sticker adds height; with a dense ring grid (5+ goals) check it still fits
    the 360x640 canvas in the screenshot tour.
  - `ScreenshotGallery`'s recap demo passes no summary (the summary's memberwise init is internal to
    Core), so the tour shows the new eyebrow/caption but not the vs-last-week/reached lines.
- **Needs verification on:** CI build (app + Core tests), screenshot tour (recap card, story time
  page, poster); a device for real shield attempt counts.

## Unsure to compile (check first if CI fails)

- `SeasonsAndRanks.swift`: `nonisolated static func rankMovement(from:to:)` reads `Rank.allCases`
  (nested enum in a `@MainActor` class; assumed nonisolated like `Rank.forConsistency`'s callers).
- `WeeklyRecapBuilder.swift`: new `#Predicate<TimeBank>` (mirrors `TimeBankEngine.fetchTimeBank`).
- `ProgressView.swift` `recapSection`: now `let` + `return VStack` inside a `some View` function.
- `RecapStoryPages.swift`: `@ViewBuilder private var timeDetails` in `RecapTimePage`.

## Definition-of-done check

- [ ] Every item in "Definition of done" above is actually true
- [ ] Verified in CI (build + Core tests) and in the screenshot tour
- [ ] `docs/PROGRESS.md` row updated (left to the orchestrator for this session)
- [x] No secrets committed

### 2026-10-08 — CI

- Merged into `claude/dazzling-hypatia-ed6q5d` with sessions 33-40. GitHub Actions run 147 (head 49a2e4c): the app with every extension, the Watch app, the embedded Watch build and the Core unit tests all pass. Device checks above still open.
