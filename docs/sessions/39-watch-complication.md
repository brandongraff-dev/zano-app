# Session 39 — Watch app bundled with the phone app + streak complication

- **Branch:** `worktree-agent-a46179a9caee9ddb7` (rebased onto `origin/main` before starting)
- **Spec sections:** §5.21 (Apple Watch: "complication with rings"), §11 (ZANOWatch as a sibling
  target), §27 (extensions are short-lived and memory-limited). The brief also cited §5.8/§5.9;
  those are Gym Home Turf and Seasons/Ranks and have nothing to do with this work, so they are not
  implemented here.
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

- Embed `ZANOWatch` in the `ZANO` iOS app (single-target SwiftUI watch app, "Embed Watch
  Content"), without putting the iOS Simulator CI build at risk.
- A watchOS WidgetKit complication extension showing the streak in `accessoryCircular`,
  `accessoryCorner`, `accessoryRectangular` and `accessoryInline`, fed by the snapshot the phone
  already syncs (session 13b), read from the watch's App Group, reloaded when it changes.
- CI: build the new target; check the embedded build without making it blocking.

## Definition of done

- §17 gives none for the watch (row 13: "—"). Working definition: `xcodegen generate` and the
  ZANOWatch scheme build green in CI with the new extension, the embedded build (opt-in) is green
  in CI's non-blocking step, and on a paired Apple Watch the complication shows the streak and
  updates after the phone syncs.

## Log

### 2026-10-07 — Embed switch, ZANOWatchComplications, timeline reloads, CI

- **Files touched:**
  - `project.yml` (modified): top-level `include:` of `project.watch-embed.yml`, gated by
    `enable: ${ZANO_EMBED_WATCH}`; `ZANOWatch` gains `Watch/Shared` in its sources and a
    `- target: ZANOWatchComplications` dependency; new `ZANOWatchComplications` target
    (`app-extension`, watchOS 10, `com.zano.app.watchkitapp.complications`,
    `com.apple.widgetkit-extension`, App Group entitlement, device family 4).
  - `project.watch-embed.yml` (new): adds `- target: ZANOWatch` / `embed: true` to ZANO.
  - `Watch/Shared/WatchAppGroup.swift` (new, compiled into both watch targets): App Group id,
    snapshot key, complication kind.
  - `Watch/ZANOWatchComplications/ZANOWatchComplicationsBundle.swift` (new, `@main`),
    `StreakComplication.swift` (new: provider, widget, four family views),
    `ComplicationSnapshot.swift` (new: decodes the subset it shows),
    `ComplicationCopy.swift` (new: `Copy.watchComplication`).
  - `Watch/ZANOWatch/WatchStateStore.swift` (modified): uses `WatchAppGroup`; after persisting
    a new snapshot, calls `WidgetCenter.shared.reloadTimelines(ofKind:)` when the streak, level,
    ring progress, first-sync state or day changed.
  - `Watch/ZANOWatch/ComplicationPlaceholder.swift` (modified, header note only).
  - `.github/workflows/ci.yml`, `codemagic.yaml`, `scripts/ci/push-results.sh` (modified): new
    last, non-blocking "Build ZANO with the watch app embedded" step → `embed.log`, included in
    the error summary / `ci-results` errors.txt and the uploaded logs; it also checks that
    `ZANO.app/Watch/ZANOWatch.app/PlugIns/ZANOWatchComplications.appex` exists. Watch-step
    comments updated.
- **What changed:**
  - Complication (`StreakComplication`, kind `com.zano.app.watch.complication.streak`):
    - circular: flame + streak number inside a capacity gauge of today's average ring progress
      (this is the spec's "complication with rings", in one ring);
    - corner: flame, with "N days" along the bezel (`.widgetLabel`);
    - rectangular: "N-day streak", a "Today" progress bar, "Buddy Lv N" when the phone sent a level;
    - inline: flame + "N-day streak".
    - Before the first sync it shows "–" / "Open ZANO on iPhone", never a made-up number. The
      watch-face gallery (`context.isPreview`) gets a sample (streak 12), as the iOS widgets do.
    - Timeline: the current entry plus one at local midnight (today's ring empties: a snapshot
      from an earlier day counts as nothing done), refresh after 30 min as a safety net.
  - Streak was already in the sync payload (`currentStreak`, from `SharedDefaults.currentStreak`
    in `WatchSyncManager.buildSnapshot()`), and so were `level`/`levelFraction`; no phone change.
- **Decisions made and why:**
  - **Embedding is opt-in** (`ZANO_EMBED_WATCH=YES xcodegen generate`). Embedding makes every
    ZANO build also build the watch app for the watchOS SDK; the main CI build, the UI-test
    compile and the screenshot tour stay exactly as before, and the fastlane `beta` lane (plain
    `xcodegen generate`, no watch bundle ids in match) can't break on it. CI checks the embedded
    variant in a separate non-blocking step that runs last, because it regenerates the project in
    place and overwrites `ZANO.app` after the screenshot tour has used it. Once that step is green
    a few runs in a row, the switch can be flipped to default-on (move the dependency into
    `project.yml`, delete the include, add the watch ids to fastlane).
  - How the gate works: XcodeGen only substitutes `${VAR}` when it's set; an unset variable stays
    the literal text, which `NSString.boolValue` reads as false, so the include is skipped. Read in
    XcodeGen's `Sources/ProjectSpec/SpecFile.swift` and `Docs/ProjectSpec.md` ("Include"); included
    arrays are appended, so ZANO's dependency list is the include's plus project.yml's.
  - XcodeGen puts a watchOS `application` dependency of an app target into an "Embed Watch Content"
    phase (`$(CONTENTS_FOLDER_PATH)/Watch`) and an `app-extension` dependency of the watch app
    into "Embed Foundation Extensions" (checked in `PBXProjGenerator.swift`), so no `copy:` override.
  - The extension does NOT compile `WatchStateModels.swift`: that type reaches the generated
    16k-line sprite file through its buddy accessors, and extensions are memory-limited (§27).
    `ComplicationSnapshot` decodes only `currentStreak`, `rings[].progress`, `level`,
    `levelFraction`, `updatedAt` from the same JSON; those names are the contract (documented in
    both files). The App Group id/key/kind live in one shared file.
  - Reloads only when something shown changed: the phone resends the snapshot every 15–60 s and
    watchOS budgets complication reloads.
  - **Strings:** Core can't be linked on watchOS (iOS-only frameworks; `Core/Package.swift` is
    `.iOS(.v17)` only), so, like the watch app's `WatchCopy.swift`, the extension keeps its copy
    locally as `Copy.watchComplication` in `ComplicationCopy.swift`. It can't reuse
    `WatchCopy.swift` because that references the generated buddy types. Voice-neutral.
  - **Buddy charge not shown:** the charge is computed from Screen Time inside the `ZANOReport`
    extension's sandbox; the app process (and so the sync payload) never sees it. Not cheap, so
    the rectangular face shows the buddy's level instead.
  - The rings complication in `ComplicationPlaceholder.swift` stays unregistered (moving it needs
    ring kinds + colours in the extension and it competes for the same families). Header updated.
- **Known issues / TODOs left behind:**
  - Nothing here has been compiled (no Mac). Availability checked against Apple's documentation
    data on 2026-10-07: `WidgetFamily.accessoryCorner` (watchOS 9, watchOS only),
    `widgetLabel(label:)` (watchOS 9), `.accessoryCircularCapacity` (watchOS 9),
    `AccessoryWidgetBackground` (WidgetKit, watchOS 9), `containerBackground(_:for:)` (watchOS 10),
    `WidgetCenter.reloadTimelines(ofKind:)` (watchOS 9). Swift 6 concurrency of the provider
    mirrors the CI-green iOS `ZANOHomeWidgetProvider` (synchronous read, completion called inline).
  - The streak shown is the last one the phone sent; if the phone hasn't synced for days, a
    broken streak still reads as the old number until the next sync.
  - `ZANO_EMBED_WATCH` isn't set by fastlane: TestFlight builds stay phone-only until watch
    bundle ids (`com.zano.app.watchkitapp`, `com.zano.app.watchkitapp.complications`) are
    registered and in match.
  - Generated `Info.plist`/`.entitlements` for the new target appear as untracked files after a
    local `xcodegen generate`, same as every other target.
- **Needs verification on:** CI (first compile of the extension; first embedded build), then a Mac
  + paired Apple Watch: install of the bundled watch app from the phone, complication in all four
  families on several faces (tinted and full-colour), reload after a phone sync, the midnight
  entry.

## Blockers

- No Mac / paired Apple Watch: installing the bundled app, complication rendering on real faces,
  and reload timing can only be checked on hardware.
- Apple Developer Program not enrolled: a signed build with the embedded watch app needs the two
  watch bundle ids registered.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinator)
- [x] No secrets committed (check `.gitignore` coverage if you added new config/env files)
