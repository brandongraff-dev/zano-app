# Session 29 — Cal and the page companions

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.17a (new), §5.30 (Planner)
- **Status:** Scaffolded — Unverified (not yet compiled in CI). The art was checked as rendered sheets
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06

- **Files touched:** `scripts/buddies/{face,cal,export_swift}.py` (five new faces and props; new calendar character; export), regenerated `BuddySprites.swift` and the watch's `WatchBuddySprites.swift`; new `Core/Sources/Core/UI/Buddy/Cal.swift` (`CalPose`, `CalSprite`, `pageBuddy`); `Buddy.swift` (new `BuddyPose` cases); `StreakPill.swift` (the buddy replaces the flame icon); `TodayView.swift`, `PlannerView.swift` (Cal); `FuelView`, `ProgressView`, `SettingsView`, `LockStatusView` (`pageBuddy`); `ScreenshotGallery` and `ci.yml` (`characters` screen); `BuddyTests`; `docs/spec.md`.
- **What changed:** Cal in four moods (idle, happy with a check, sleepy, alarm); buddy faces `blaze` (glowing ember eyes, a happy smile), `frozen` (ice eyes), `guarding` (padlock), `tinkering` (hammer), `analyzing` (bar chart) for all nine buddies; the streak pill is now the user's own buddy with fire or ice eyes; a small buddy in each tab's navigation bar. Also fixed in the Planner: day dots now centre under the date, tasks keep their checkbox on the left.
- **Decisions:** one generator for everything so the characters stay one family; Cal is not one of the nine buddies (it is the calendar's own mascot); the tab buddies are decorative and 34 pt so they stay subtle; the streak pill grew to fit a 34 pt face.
- **Known issues / not done:** the streak face is small in the pill (full body at 34 pt); widgets and the Live Activity still show their own streak icon; the watch has the new poses in its data but no screen uses them; Cal is not on the watch or in widgets.
- **Needs verification on:** CI compile and `BuddyTests`; the `characters` and Today screenshots.
