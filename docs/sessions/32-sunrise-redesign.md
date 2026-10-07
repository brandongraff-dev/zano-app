# Session 32 — Sunrise Alarm redesign (sun character, wake moment, layout)

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
### 2026-10-05 — repeat days, sound picker, backup alarm, time-of-day icon

- **Files touched:** `Core/Sources/Core/Verification/SunriseAlarmOptions.swift` (new),
  `SunriseAlarmManager.swift`, `Core/Sources/Core/Copy/SunriseAlarmScreenCopy.swift`,
  `Core/Tests/CoreTests/SunriseAlarmRepeatTests.swift` (new), `App/ZANO/Features/SunriseAlarm/
  AlarmOptionsViews.swift` (new), `TimeOfDay.swift` (new), `SunriseAlarmSetupView.swift`,
  `AlarmRingingView.swift`, `App/ZANO/Sounds/alarm-*.wav` (6 new), `scripts/generate-alarm-sounds.py`
  (new), `App/ZANO/ScreenshotGallery.swift`, `.github/workflows/ci.yml`
- **What changed:**
  - **Repeat days:** `Settings.repeatDays` (Calendar weekday numbers). The alarm rings on the checked
    days; none checked = "Never": it rings once, then switches itself off (Clock app behaviour). Saving
    the setup screen turns the alarm on again.
  - **Sound picker:** six synthesized wake-up tones (Daybreak, Chimes, Marimba, Pulse, Bells, Ripple),
    20s each, linear PCM WAV, volume rising over the clip. Used as the notification sound on the
    iOS 17-18 tier and passed to AlarmKit as `sound: .named(...)`. The Sound list previews each tone.
  - **Backup alarm:** optional plain second alarm 5/10/15 min after the Sunrise Alarm, on the same tier.
    A verified dismiss or the escape hatch cancels it (both end in `scheduleAlarm`, which cancels it first).
    Snooze leaves it in place. Off by default.
  - **UI:** Repeat / Sound / Backup rows and Repeat / Sound checkmark screens laid out like the iOS Clock
    app's alarm editor.
  - **Time of day:** `TimeOfDay` picks moon / sunrise / sun / sunset for the hour; shown on the wake-time
    card's badge and the ringing screen's "Wake up" chip.
- **Decisions made and why:**
  - `Settings` now has a custom `init(from:)` with `decodeIfPresent` for the new keys. Synthesized
    decoding would have thrown on every existing saved row and `currentSettings()` would have returned
    defaults, silently wiping people's alarms. A test covers it.
  - The backup uses its own notification prefix (`zano.sunriseBackup.`) so snooze, which cancels the
    main chain by prefix, does not cancel it.
  - Sounds are synthesized (no licensing, small, regenerable) rather than recorded; they have not been
    listened to on a device. They are placeholders in quality terms.
- **Unverified:** AlarmKit's `sound:` accepts `.named(String)` per Apple's docs, but those pages do not say
  where the file must live or its format limits; assumed main bundle, same as notification sounds. AlarmKit
  `stopIntent` default was not confirmed, so the backup passes the same intent the main alarm does. Neither
  has run on an iOS 26 device.
### 2026-10-06 — clock spacing and the always-visible time wheel

- **Files touched:** `AlarmRingingView.swift`, `SunriseAlarmSetupView.swift`
- **What changed:** the ringing clock uses its own proportional-digit copy of the score font
  (`Theme.Typography.score` forces fixed-width digits, which gave "11:39" a full-width slot for each
  "1"). The Sunrise setup screen now shows the time wheel straight away, like the Clock app's editor,
  with the label and the sleeping sun on one row above it; the bedtime card keeps tap-to-reveal.
- **Needs verification on:** Simulator screenshots (`alarm-ringing`, `sunrise-setup`).

- **Known issues / TODOs left behind:**
  - Pending: collapse the tag help / troubleshooting on the setup screen; Save bar still lets text
    show behind it (Core `StickyActionBar`, not touched); a mood for the snooze moment itself (the cover
    closes on snooze as before).
  - The branch is based on `claude/sharp-euler-npwt08`; that branch conflicts with `main` in
    `LockStatusView.swift` and `PaywallView.swift` (unrelated to this work, not resolved here).
- **Needs verification on:** CI compile (never built), simulator screenshots (`alarm-ringing`,
  `wake-moment`, `sun-moods`, `sunrise-setup`), then a real device for haptics and the animation feel.
