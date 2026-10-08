# Session 13b — Watch app: buddy on the wrist, compiled in CI

- **Branch:** `claude/sharp-euler-npwt08`
- **Spec sections:** §5.21 (Apple Watch), §11 (architecture: ZANOWatch sibling target), §17 row 13
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-04
- **Last updated:** 2026-10-04

## Scope (copy from docs/spec.md §17 before starting — don't paraphrase from memory)

- §17 row 13: "Watch app, gym leaderboard, seasons/ranks, cosmetics" (done-when column: "—").
- §5.21: "Complication with rings; start focus/lock from the wrist; workout detection is more
  reliable with HR; haptic 'verified' tap when the gym dwell threshold is hit."
- This sub-session (founder: "lets develop the watch app"): make the existing Watch skeleton
  compile in CI, put the user's buddy (pose, gear, level) and the weekly Scroll Monster on the
  wrist, and extend the phone-to-watch sync with that state.

## Definition of done (copy from docs/spec.md §17)

- §17 gives none for row 13 ("—"). Working definition for this sub-session: the `ZANOWatch` scheme
  builds green in CI for the watchOS Simulator, the phone sends the buddy + boss state, and the
  watch shows it. Device behaviour (pairing, WatchConnectivity delivery, haptics, HealthKit) is
  out of reach without a Mac + paired Apple Watch.

## Log (append an entry after every coding task — newest at bottom)

### 2026-10-04 — Watch app v2: CI build, buddy, boss page, sync payload

- **Files touched:**
  - CI: `.github/workflows/ci.yml` (new "Build ZANOWatch (watchOS Simulator)" step → `watch.log`,
    included in the error summary and the uploaded logs), `codemagic.yaml` (same step,
    `ignore_failure`, status `watch-build-failed` when only the watch build fails),
    `scripts/ci/push-results.sh` (`watch.log` errors land in `ci-results/errors.txt`),
    `project.yml` (new `ZANOWatch` scheme; status note on the `ZANOWatch` target).
  - Art: `scripts/buddies/export_swift.py` (now also writes the watch file; `--sprites-only` skips
    the PNG outputs), `Watch/ZANOWatch/Generated/WatchBuddySprites.swift` (new, generated).
    `Core/Sources/Core/UI/Buddy/BuddySprites.swift` output is byte-identical (checked with
    `git diff`), and a full run left every PNG unchanged.
  - Phone: `Core/Sources/Core/Watch/WatchSyncManager.swift` (payload gains `buddy`, `buddyPose`,
    `buddyGear`, `level`, `levelFraction`, `earnedUnlocks`, `scrollMonster`; filled in the existing
    `buildSnapshot()`; no new sending path).
  - Watch: `WatchStateModels.swift` (matching optional fields + `WatchScrollMonsterSnapshot`,
    resolved accessors), `WatchStateStore.swift` (celebration: `isCelebrating` for 3 s + success
    haptic when a ring reaches 100% or `earnedUnlocks` goes up; one haptic per snapshot even when
    the gym threshold lands at the same time), `WatchConnectivityBridge.swift` and
    `WatchWorkoutSessionController.swift` (Swift 6 audit, below), `HapticsPlayer.swift`
    (`@MainActor`), `ContentView.swift` (vertical paging: Home / Boss / Gym),
    `HomeView.swift` (new), `BuddyViews.swift` (new: `WatchPixelImage`, `WatchProgressBar`,
    `BuddyHeroView`), `ScrollMonsterView.swift` (new), `TodayRingsView.swift` and
    `StartActionsView.swift` (now sections of Home, no own ScrollView/title; never-synced banner),
    `WatchCopy.swift` (buddy names, level, boss lines, HealthKit failure lines; unused tab titles
    removed), `WatchTheme.swift` (buddy signature colours mirrored from `Theme.BuddyColors`,
    ember + the boss HP colour rule from the phone's Progress tab).
- **What changed:**
  - Home page: the buddy at 72pt (3 px per sprite pixel on a 2x screen, `.interpolation(.none)`)
    in the pose Today's hero is in (`BuddyPose.heroStorageKey`), wearing its gear, on a soft glow
    in its signature colour, with its name, "Lv N" and a thin XP bar; then the goal rings, streak,
    lock badge, and the start actions (focus presets, start lock, hold-to-confirm emergency
    unlock). Ecstatic face + "Nice!" + a small bounce for 3 s on a win.
  - Boss page: this week's Scroll Monster (96pt sprite in its state/variant), HP bar (danger above
    half health, ember below, as on the phone), "N / M HP", days left, how-to or defeated line.
  - Gym page: unchanged dwell + "Track with HR" flow; the verified haptic still fires on the
    `isVerified` false→true edge.
  - Phone payload: computed in the coordinator's existing `buildSnapshot()` (main actor, has a
    `ModelContext`): `BuddyProgress.load(from:)` and `ScrollMonster.current(context:)`; buddy and
    gear from `Buddy.stored`/`BuddyGear.stored`; hero pose from the App Group key. Changes to
    those defaults already trigger a push through the existing `UserDefaults.didChangeNotification`
    observer.
- **Decisions made and why:**
  - Watch keeps its own generated copy of the art (`WatchBuddy`/`WatchBuddyPose`/`WatchBuddyGear`/
    `WatchMonsterState` mirror enums with identical raw values, `WatchPixels` with the same decoder
    and extended key alphabet). Core can't be linked on watchOS (UIKit, FamilyControls,
    ActivityKit), and both files come from the same in-memory sprite list in the script, so they
    can't drift.
  - Every new wire field is optional on the watch: the synthesized decoder reads a missing key as
    nil, so old phone builds and previously persisted snapshots still decode.
  - "Lock earned" is detected from `earnedUnlocks` going up rather than from `activeLock`
    disappearing, so an emergency unlock never triggers a celebration.
  - No celebration on the very first sync (a fresh watch would otherwise cheer every ring that
    was already full).
  - Swift 6: the old code captured `WCSession`/`[String: Any]`/`HKLiveWorkoutBuilder` into
    main-actor tasks and passed non-`@Sendable` closures formed in main-actor methods to
    WatchConnectivity/HealthKit completion handlers (inferred main-actor-isolated, which traps when
    called on a background queue). Now every delegate method extracts Sendable values first, every
    completion closure is explicitly `@Sendable` and reaches state through the singleton on the
    main actor, and the `@preconcurrency` conformances are gone. `HapticsPlayer` is `@MainActor`
    because `WKInterfaceDevice` is.
  - Vertical paging (`.tabViewStyle(.verticalPage)`, watchOS 10) with three pages instead of
    putting the boss under Home, so Home stays one glance.
  - Not embedded in ZANO yet: embedding changes the main iOS build, and only means something with
    signing + a paired device.
- **Known issues / TODOs left behind:**
  - The phone computes `BuddyProgress.load` and `ScrollMonster.current` on every snapshot build
    (every 15–60 s while a watch with the app is paired). Both fetch all `LockSession`s and
    `GoalEvent`s. Fine at current data sizes; cache per day if it shows up in profiling.
  - Complication: `ComplicationPlaceholder.swift` is still unregistered. A real watch complication
    needs a separate watchOS WidgetKit extension target embedded in ZANOWatch; not added (no new
    targets beyond what CI builds). Next step: add `ZANOWatchWidgets` (`type: app-extension`,
    `platform: watchOS`, `com.apple.widgetkit-extension`), move `GoalRingsComplication` there with
    a `@main WidgetBundle`, add a buddy face to `.accessoryCircular`, and have
    `WatchStateStore.apply` call `WidgetCenter.shared.reloadAllTimelines()`. The complication would
    also need the generated sprite file in that target's sources.
  - Perfect-day run isn't on the wrist (not in this scope).
- **Needs verification on:** CI first (the first real compile of the watch target with a watchOS
  SDK); then a Mac + paired Apple Watch for pairing, delivery, haptics, HealthKit, layout on
  41/45/49mm.

## Blockers

- No Mac / paired Apple Watch: pairing, embedding, WatchConnectivity delivery, haptics, HealthKit
  workouts and complications can only be checked on hardware.
- Apple Developer Program not enrolled: embedding the watch app in a signed ZANO build and
  installing it on a watch needs signing.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [x] `docs/PROGRESS.md` row updated to match this file's Status
- [x] No secrets committed (check `.gitignore` coverage if you added new config/env files)

## CI result (2026-10-05)

First watchOS compile (run 37240645584) failed on one error: `.accessibilityAction(perform:)` doesn't
exist; fixed to `.accessibilityAction(.default, fireEmergencyUnlock)`. Run 37253141845 on 32a7779 is
green end to end: iOS app, ZANOWatch (watchOS Simulator), Core tests, UI-test compile, screenshot tour.
Still device-only: pairing/embedding, WatchConnectivity delivery, haptics, wrist workout, complication.
