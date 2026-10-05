# Session 14 — Sunrise Alarm redesign (sun character, wake moment, layout)

- **Branch:** `claude/sunrise-redesign` (based on `claude/sharp-euler-npwt08`)
- **Spec sections:** §5.10 (Bedtime Gate & Sunrise Alarm), §15 (motion: "unlock celebration <= 1.2s", "haptics on every verified event")
- **Status:** Scaffolded — Unverified (needs a CI compile + screenshot read; none of it has run on a device)
- **Started:** 2026-10-05
- **Last updated:** 2026-10-05

## Scope

Presentation only on the Sunrise Alarm ringing and setup screens. Dismiss logic, the 60-second
escape hatch, VoiceOver actions, escalation phases, pulse loop and haptics are unchanged.

## Log

### 2026-10-05 — sun character, wake moment, layout

- **Files touched:** `App/ZANO/Features/SunriseAlarm/SunCharacter.swift` (new),
  `VerifiedCheck.swift` (new), `WakeMoment.swift` (new), `AlarmRingingView.swift`,
  `SunriseAlarmSetupView.swift`, `App/ZANO/ContentView.swift`, `App/ZANO/ScreenshotGallery.swift`,
  `Core/Sources/Core/Copy/SunriseAlarmScreenCopy.swift`, `.github/workflows/ci.yml`
- **What changed:**
  - **Sun character:** `SunMood` has ten moods (asleep, yawning, alarmed, frantic, grumpy,
    disappointed, hopeful, beaming, worried, sad) on the existing `RetroSun`. Ringing: yawning ->
    alarmed -> frantic by phase; grumpy / disappointed once the snooze is used; hopeful while scanning;
    worried during the escape hold; beaming on a verified dismiss; sad when the emergency exit is used.
    Setup: asleep beside the wake time. Decoration only (hidden from VoiceOver); still under Reduce Motion.
  - **Rising sun:** the sun sits on a horizon line above the clock and climbs a step per phase,
    instead of sitting behind the clock where its stripes crossed the digits.
  - **Wake moment:** Apple-style check (ring draws, check strokes in, one pop, success haptic, about 1.1s)
    then title and subtitle. The escape hatch gets a quieter "Alarm off." with a sad sun. Tap skips.
  - **Layout:** smaller tag target, quieter Snooze (secondary to Scan), clock no longer edge to edge.
  - **Setup:** the odd last dismiss tile spans the row (squad is hidden, which left 3 tiles in 2 columns);
    the sun moved from behind the wake time to beside it.
- **Decisions made and why:**
  - `WakeMoment` (small `@Observable`) keeps the full-screen cover up after `isRinging` goes false,
    because `ContentView` presents the cover purely from `isRinging`. One line changed in `ContentView`.
  - Subtitle says "Morning goal done" only; it does not claim the lock armed, since that was only
    confirmed for the tag path.
  - Check colour is `Ring.workout` (volt green) so it reads as "verified" and not as the sun.
- **Second pass (after the first CI screenshots, 2026-10-05):** fixed the "you're up" scrim (now
  near-opaque so the screen underneath no longer shows through), the sun's flat clipped edges (no halo
  disc when clipped to the horizon), the clock width (58pt), the yawning mouth sitting on the horizon
  (window 0.86, sink 0.20/0.09/0), the Scan button (amber `.warning` tint; it also looked dimmed in the
  simulator because NFC is unavailable there), the Snooze row hidden behind the dock fade (more bottom
  padding, tighter top and card padding), and the Save bar letting text show through (opaque local bar
  in the Sunrise folder; Core's shared `StickyActionBar` is unchanged). CI: `screens` input on
  `workflow_dispatch` for focused screenshot runs, a 35-minute step limit and a 150s limit per
  simulator command in the tour.
- **Known issues / TODOs left behind:**
  - Pending: collapse the tag help / troubleshooting on the setup screen; Save bar still lets text
    show behind it (Core `StickyActionBar`, not touched); a mood for the snooze moment itself (the cover
    closes on snooze as before).
  - The branch is based on `claude/sharp-euler-npwt08`; that branch conflicts with `main` in
    `LockStatusView.swift` and `PaywallView.swift` (unrelated to this work, not resolved here).
- **Needs verification on:** CI compile (never built), simulator screenshots (`alarm-ringing`,
  `wake-moment`, `sun-moods`, `sunrise-setup`), then a real device for haptics and the animation feel.
