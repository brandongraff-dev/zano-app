# Session 3 — Verification

- **Branch:** `main`
- **Spec sections:** §3 (goal catalog & verification), §9.4 (gym auto-detect), §9.8 (anti-cheat)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Verification" cluster (3 build agents + 1 harden agent).

## Scope

Gym geofence + dwell verification, gym auto-detection, focus-session verification + its Live
Activity, and shared Core Motion anti-cheat utilities.

## Files

- `Core/Sources/Core/Verification/GymVerifier.swift`, `GymAutoDetect.swift`
- `Core/Sources/Core/Verification/FocusSessionVerifier.swift`
- `Core/Sources/Core/Verification/MotionAntiCheat.swift`
- `Core/Sources/Core/LiveActivity/GymDwellActivityAttributes.swift`,
  `FocusActivityAttributes.swift`

## Decisions

- Gym dwell default threshold 35 min (§3), auto-detect clustering threshold 40 min dwell /
  recurring ≥2×/14 days (§9.4), both taken verbatim from spec rather than re-derived.
- `MotionAntiCheat` built as a small shared utility (`isLikelyAutomotive()`, a generic
  `TapRateLimiter`) rather than duplicated per-verifier, since both gym anti-cheat and future tap-
  based goals (protein/water/creatine) need the same rate-limiting shape.
- "Leaving the app pauses the focus timer" is left as an explicit TODO hook (likely `scenePhase`
  observation) for whichever UI code drives the timer screen, since that's a SwiftUI-layer concern
  outside this cluster's Core-only scope.

## Known issues

- HealthKit HR-during-dwell and Core Motion automotive detection are real API usage, unverified by
  a compiler. HealthKit workouts and Core Motion do not work in Simulator at all (§27) — device-only
  from day one.
- Note: §5.10's Bedtime Gate & Sunrise Alarm (also logically "verification") was **not** built in
  this cluster — it was significant enough to get its own dedicated batch. See
  `docs/sessions/13-v3-slices.md` (or its own doc once that batch is consolidated) rather than
  looking for it here.

## Needs verification on

Real device: geofence arrival/dwell timing accuracy, HealthKit HR read permission flow, Core
Motion automotive-vs-walking discrimination, Live Activity actually appearing on Dynamic
Island/Lock Screen.
