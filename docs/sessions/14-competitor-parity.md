# Session 14 — Competitor parity

- **Branch:** `claude/fervent-pasteur-0pz4ud`
- **Spec sections:** §5.23 (new), §3, §27
- **Status:** In Progress
- **Started:** 2026-10-06
- **Last updated:** 2026-10-06

## Scope

Close the gaps found against Opal, One Sec, ScreenZen, Brick and the fitness-unlock apps
(FitLock, StepBloc, Push Up Time, Limit Fit). Order agreed: 1 → 3 → 2 → 4 → 5.

1. Mindful Pass (pause before opening) — spec §5.23
2. Rep-based unlock (push-ups/squats via Vision pose) — not yet specced
3. Daily app time limits (DeviceActivity thresholds) — not yet specced
4. Focus score / usage insights (`ZANOReport`) — not yet specced
5. Strict mode — not yet specced; must keep Emergency Unlock (§24)

Not in scope: a Pomodoro timer (already covered by focus sessions).

## Definition of done

Each item: spec section written, Core logic unit-tested in CI, wired end to end, verified on a
device. Items 1, 3 and 5 depend on FamilyControls/DeviceActivity and cannot be verified without one.

## Log

### 2026-10-06 — Item 1, step 1: Mindful Pass policy logic

- **Files touched:** `docs/spec.md` (new §5.23), `Core/Sources/Core/LockEngine/MindfulPass.swift` (new),
  `Core/Tests/CoreTests/MindfulPassTests.swift` (new)
- **What changed:** Pure policy: escalating pause (10s +5s per pass used today, capped 45s), 15-min pass,
  daily cap of 5, same-day grant counting/pruning.
- **Decisions:** Pass length is 15 min because DeviceActivity's minimum interval is 15 min (§27).
  Passes never touch the streak/Time Bank/goals. Reached via notification deep link because shield
  buttons can't open the app (§27).
- **Known issues / TODOs left behind (the rest of item 1 is NOT done):**
  - The shield has only two buttons (Show goals / Emergency). Where "Pause and continue" goes is an
    open UX decision (replace one, route through the goals notification, or a notification action).
  - Not yet written: `zano://pause` deep link + `ShieldCopy.DeepLink`, in-app pause screen, copy
    (`Copy/MindfulPassCopy.swift`), persistence of grant timestamps (App Group), ManagedSettings
    lift + re-shield via `ZANOMonitor`, per-lock-set opt-in flag on `LockSet`.
- **Needs verification on:** CI (unit tests, not yet run) for the logic; real device for everything else.
