# Session 38 — Bedtime Gate runs while the app is closed

- **Branch:** `worktree-agent-a54d2a51cf2634ca3` (based on `origin/main` c586ea9)
- **Spec sections:** §5.10 (Bedtime Gate: "Lock auto-arms at the user's set bedtime"), §2 (lock triggers: schedule, "10:30 PM bedtime"), §4 v2 ("Bedtime lock with morning goals as key"), §6, §11 (extensions are tiny, App Group only), §24 (emergency unlock, health pause), §27 (DeviceActivity: 15-minute minimum, callbacks can be late, no Simulator)
- **Status:** Scaffolded — Unverified (not compiled yet; DeviceActivity does not run in the Simulator, so the monitor path needs a real device)
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

`BedtimeGateManager` said the gate only caught up when the app was opened. In fact `ScheduledLockMonitor` already shielded at bedtime (sessions 2E/17), but with gaps: it used the default lock set and `.full` instead of the gate's own settings, the registration ran bedtime to 23:59 (so the foreground catch-up missed every after-midnight open), the catch-up was never called, a bedtime lock with no goals could only end by emergency unlock, and the monitor and app could disagree about whether a night was already armed. This session:

1. Registers a bedtime-to-wake DeviceActivity window (usually crossing midnight), following `LockScheduler.register`'s pattern and naming (`com.zano.app.bedtimeGate`, or `.d<weekday>` per night when some nights are off).
2. Handles `intervalDidStart`/`intervalDidEnd` for those names in `ScheduledLockMonitor` (the extension stays a thin shim), from App Group state only.
3. Confirms the emergency unlock covers it (below).
4. Keeps the foreground catch-up as a backstop, wired into `ContentView`, idempotent with the monitor.
5. Adds Core tests for the schedule computation.

## Definition of done

- Real device: set a bedtime a few minutes ahead, close the app, apps shield at bedtime; open the app, the lock appears as a normal session and the 60-second emergency unlock ends it; nothing re-arms that night.
- Real device: with no active goals, the bedtime lock lifts at wake time; with goals, it stays until they're earned.
- CI: compiles; `BedtimeGateScheduleTests` pass.

## Log

### 2026-10-07 — Night window, monitor start/end, one decision per night, foreground backstop

- **Files touched:**
  - new `Core/Sources/Core/Verification/BedtimeGateSchedule.swift`: `BedtimeGateActivity` (names), `BedtimeGateSchedule` (pure night math + DeviceActivity windows), `BedtimeGateWindow`, `BedtimeGateSharedState` (nonisolated App Group state: advanced settings, per-night record, registration signature)
  - new `Core/Tests/CoreTests/BedtimeGateScheduleTests.swift`
  - `Core/Sources/Core/Verification/BedtimeGateManager.swift`: `nights` on `BedtimeGateAdvancedSettings` (backward-compatible decoding); `rearmDailySchedule` registers the night windows; new `syncDailySchedule`, `adoptMonitorArmedLock`, `finishArming`; `autoArmBedtimeLock`/`evaluateOnForeground` rewritten around the night window; removed the `DeviceActivityName.zanoBedtimeGate` extension and the private armed-today helpers; header TODO replaced
  - `Core/Sources/Core/LockEngine/LockScheduler.swift`: `ScheduledLockMonitor.bedtimeNightDidStart`/`bedtimeNightDidEnd`; `arm` returns whether it shielded; `.bedtime` hand-off calls `adoptMonitorArmedLock`
  - `Core/Sources/Core/Verification/SunriseAlarmManager.swift`: `nonisolated static func storedSettings()` (`nil` if never set up)
  - `Extensions/ZANOMonitor/DeviceActivityMonitorExtension.swift`: header comment only (it already forwards to `ScheduledLockMonitor`)
  - `App/ZANO/ContentView.swift`: calls `BedtimeGateManager.shared.evaluateOnForeground()` right after `LockScheduler.shared.reconcile()`
  - `App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift`: stale header comment only
- **What changed:**
  - **Window.** Bedtime to wake time from the shared `SunriseAlarmManager.Settings` row, at least 15 minutes (§27). One daily repeating registration under the original name (so existing installs are replaced in place), or one weekly registration per night with the end on the next weekday when the night crosses midnight. Nights are keyed by the weekday bedtime falls on.
  - **Start (monitor).** Reads only App Group `UserDefaults`: settings, advanced settings, lock-set mirrors. Skips if the gate is off or never set up, during a health pause (existing guard), or if this night is already decided. If another lock is running it doesn't stack and marks the night decided. Otherwise it shields the gate's lock set (`advanced.lockSetID ?? defaultLockSetID`) in the gate's mode and leaves a `.bedtime` pending record.
  - **Hand-off (app).** `adoptMonitorArmedLock` starts a real `LockSession` with the monitor's lock set, mode and start time (previously it re-resolved everything and started at "now"). If the gate was turned off since, or nothing can be resolved, it returns `nil` and `removeShieldIfNoActiveLock` lifts the shield, as before.
  - **End (wake time).** A bedtime lock with goals keeps going: morning goals are its key (§4 v2, §5.10 step 5). This matches the old behaviour. A lock with nothing to earn (no active goals, or only ones that can't gate a lock) ends at wake time. Before this change only the emergency unlock could end it. The app marks such a session as owned by its night's window (`ScheduleOwnedLock`, the same mechanism focus windows use). For a pending lock, the monitor uses the goal count it has. If the night is already over when the app adopts it, the lock ends right away, recorded at wake time. A stray end callback in mid-night (iOS can end the interval when a schedule is re-registered) is ignored by `isNightOver`.
  - **Idempotency.** One record per night (`BedtimeGateSharedState.hasArmed/markArmed`, the existing `lastArmedDay` key now holding the night's start). The monitor, the hand-off and the foreground catch-up all check it. They never double-arm, and nothing re-arms a night after an emergency unlock. The catch-up also defers to an unadopted pending record and to any running lock. Overlapping sources are reconciled the same way as before: `arm` never stacks on `activeLockSessionID`/`pendingStart`, the app never starts a bedtime lock over an active session, and context rules and spend windows are untouched.
  - **Foreground backstop.** `evaluateOnForeground` now runs on every foreground, after reconcile. It re-registers only when the saved settings no longer match the stored signature or the registrations are missing, which also migrates installs off the old bedtime-to-23:59 window. It arms if `now` is inside an undecided night, including after midnight. It does nothing for someone who never set the feature up: `Settings.enabled` defaults to `true`, so reading `currentSettings()` here would have armed a 22:30 lock nobody asked for.
- **Emergency unlock (item 3), confirmed by reading the code:** the shield's secondary button posts a notification into the app (`ShieldActionExtension`). Opening the app runs `reconcile`, which adopts the pending record into a `LockSession`. `EmergencyUnlockIntent.perform` also calls `adoptPendingScheduledLock()` first. The Lock tab's 60-second hold then ends it via `LockEngineManager.emergencyUnlock`. If adoption fails, `removeShieldIfNoActiveLock` lifts the shield. If the store can't open, `liftAllShieldsForRecovery` still exists. No new escape hatch was added and none was needed.
- **Decisions made and why:**
  - **One crossing-midnight window, not two.** Bedtime-to-wake is the honest "night" and lets the after-midnight catch-up and the wake-time end work. It fails safe: if iOS never delivers the end, behaviour is the old one, where the lock continues until goals are earned or the emergency unlock is used.
  - **`nights` added to `BedtimeGateAdvancedSettings`, with no UI.** The brief asked for disabled-day handling and this blob is where the gate's no-UI settings already live. Spec §5.10 names no day picker, so it defaults to every night and nothing in the app changes it yet.
  - **The night is marked only when the monitor actually shields, or when another lock already holds the night.** If the lock-set mirror is missing, the app's backstop, which can read SwiftData, still gets a chance.
- **Known issues / TODOs left behind:**
  - **Unverified API:** a repeating `DeviceActivitySchedule` whose `intervalEnd` is earlier than `intervalStart` (crossing midnight), and weekly windows whose start and end weekdays differ. No Apple doc confirms either. One developer forum report says threshold events misbehave across midnight; this feature uses no thresholds. If the device shows the end never firing, split into two windows (bedtime to 23:59, 00:00 to wake).
  - **Unverified:** whether `stopMonitoring` delivers `intervalDidEnd` (some reports say it does). `isNightOver` guards against it either way.
  - **Pre-existing, not fixed (outside this session's scope):** `LockEngineManager.isGoalVerified` counts goal events since the start of the calendar day the session *started*. A bedtime lock started at 22:30 is therefore earnable by goals already done earlier that day, so the next goal event (or a manual end once eligible) can lift it before morning. "Morning goals as key" needs eligibility for bedtime locks to count from the night's start or the next morning. That is a LockEngine decision worth making on purpose.
  - The pending lock's wake-time goal count comes from `LockEngineSharedState.activeGoalCount`, which includes goals that can't gate a lock (e.g. Sleep on time). Such a pending lock stays shielded past wake until the app opens. Adoption then ends it at once, recorded at wake time.
  - `Settings.enabled` is shared with the wake alarm. A one-time ("Never" repeat) alarm switches itself off after ringing, which now also stops the gate on the next foreground sync. It already stopped the hand-off before this change.
  - Pickup-after-bedtime detection (`eventDidReachThreshold`) is still not wired. Unchanged and out of scope.
  - "Next lock" (`SharedDefaults.nextScheduledLockAt`) still lists lock schedules only, not bedtime.
- **Needs verification on:** CI (compile + `BedtimeGateScheduleTests`); **real device** for everything DeviceActivity/ManagedSettings: monitor start at bedtime with the app killed, the wake-time end, the weekly crossing windows, and the emergency unlock of a monitor-armed bedtime lock.

## Blockers

- No Mac or device here; CI is the compiler. DeviceActivity doesn't run in the Simulator (§27). The Family Controls entitlement is not filed (Apple Developer enrollment pending); device testing needs the Development capability.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinating session, per instructions)
- [x] No secrets committed
