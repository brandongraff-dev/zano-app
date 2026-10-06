# Session 17 — Work-hours focus lock (calendar)

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.24 (new), §5.10 (Bedtime Gate, the sibling timed lock), §9.7 (calendar awareness), §24 (privacy, health pause, emergency unlock), §27 (DeviceActivity limits)
- **Status:** Compiles + Core unit tests pass in CI (run 105, 2026-10-06). Device and Simulator behaviour still unverified (see "Needs verification on")
- **Started / Last updated:** 2026-10-05

## Scope

Feature #1 of the founder's list (2026-10-05): lock distracting apps during calendar meetings and focus blocks, open them again when the block ends, learn which events the user wants locked. Features #3 (sleep wind-down) and #8 (context rules) are separate sessions.

## Log

### 2026-10-05 — Engine, learning memory, settings screen

- **Files touched:** new `Core/Sources/Core/FocusLock/{FocusLockModels,FocusLockPlanner,FocusLockStore,FocusLockCalendarSource,FocusLockScheduler}.swift`, `Core/Sources/Core/Copy/FocusLockCopy.swift`, `Core/Tests/CoreTests/FocusLockTests.swift`, `App/ZANO/Features/FocusLock/FocusLockSettingsView.swift`; edited `LockEngine/LockScheduler.swift` (new `.focus` source, monitor start/end, hand-off), `LockEngine/LockEngineManager.swift` (emergency unlock teaches the memory), `Copy/TodayCopy.swift` ("Locked · focus time" for a lock with no goals), `App/ZANO/ContentView.swift` (refresh on foreground), `Settings/SettingsView.swift` (row).
- **What changed:** a pure planner turns two days of events into at most 8 lock windows; each window is locked, asked about, or dropped by a small per-event memory (hash of the title; two yes = automatic, two no = stop asking, emergency unlock = a no). Windows are one-off DeviceActivity schedules under their own name prefix (`com.zano.app.focus.`) so saving a lock schedule never touches them. The monitor shields at the start; `LockScheduler.convert` makes a real `LockSession` with no required goals (the engine already treats that as a timed lock: it is never "earned"), owned by the window so only its end can end it.
- **Decisions:** reuse the existing schedule monitor and hand-off instead of a second lock path; trigger recorded as `.schedule` (no database change); ask-first by default so the feature can't surprise anyone; calendar permission is requested only from the Settings switch (the Info.plist usage string was already present).
- **Known issues / not done:**
  - No background refresh: a meeting added while the app is closed is picked up next time the app opens.
  - The "ask" questions only appear inside Settings > Focus lock; there is no Today card or notification yet.
  - DeviceActivity's 20-activity cap is unverified; the feature uses at most 8.
  - One-off schedules with full dates, `EKEvent.availability`/`attendees`/`isCurrentUser` are written from memory of the API.
  - The lock tab and Live Activity still say "0 goals" in places; only the Today status line was changed.
- **Needs verification on:** CI (compile, `FocusLockTests`); a real device for DeviceActivity one-off schedules, the monitor extension firing at the start and end, and Calendar permission.

## Blockers

- No Mac or device here; Family Controls needs the Apple Developer entitlement (not filed).
