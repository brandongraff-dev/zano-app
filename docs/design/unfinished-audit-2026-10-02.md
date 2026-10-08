# Unfinished-features audit — 2026-10-02

Read-only audit of the repo (commit 3ed14a4). Severity: **Blocker** / Should-fix / Post-launch.
"Needs" = founder (keys, accounts, decision) or code.

## Blockers
| # | Item | Needs |
|---|---|---|
| M1 | RevenueCat SDK isn't a dependency (no SPM package, no key) → paywall can't load → a Release build can't finish onboarding (the skip is DEBUG-only). | Founder (RevenueCat, products, key) + code |
| M2 | Offline first launch hits the same paywall dead end. | Decision (offline grace vs block) + code |
| L1 | A scheduled lock started by the monitor while the app is closed only becomes a `LockSession` when the app opens; background goal events (gym geofence, NFC, widget, Siri) can't end it. Onboarding promises "apps open the second your last goal verifies". | Code |
| L2 | "Sleep on time" goal can be picked but nothing ever completes it — as a required goal it traps the lock (emergency unlock only). | Code (hide or build) |
| V1 | Sunrise Alarm rings once; it's never rescheduled after firing. | Code |
| G1 | Privacy / terms / support URLs are placeholders; paywall Terms link (Apple EULA) and Settings (zano.app/terms) disagree. | Founder |
| G2 | Apple Developer + Family Controls for **5** bundle IDs (app, ShieldConfig, ShieldAction, Monitor, Report); no `DEVELOPMENT_TEAM`. | Founder |
| W2 | No device pass yet (shields, NFC, geofence, Live Activities, AlarmKit, Control Center, StandBy). | Founder (device, Mac) |

## Should-fix before launch
- **L3/L4/L5** Focus sessions: in-memory only (Siri/NFC-started sessions never verify), leaving the app doesn't pause the timer, Live Activity "End" doesn't end.
- **L6** Steps / home-workout verification only runs from Today (observer not registered at launch).
- **V2/V3** Bedtime wind-down and Sunrise ringing Live Activities have no widget configuration; bedtime "no pickups" not implemented.
- **S2** Squad tab is entirely "goes live soon" (decision: hide for v1 or build backend). Same for cosmetics shop (**M4**: purchases change nothing).
- **M3** Paywall promises a trial reminder that's never scheduled.
- **N1** Sunday "weekly recap is ready" nudge links to an always-empty recap (no on-device recap builder).
- **N2** Notification permission only asked on the first-win Start; "Do it later" means the shield's Emergency button notification silently fails.
- **N5** Delete all my data doesn't stop DeviceActivity schedules, pending notifications or the AlarmKit alarm.
- **W1** No SwiftData `VersionedSchema` / migration plan; a failed store open silently falls back to in-memory.
- **X1** Analytics/crash reporting are no-ops; spec funnel events (`app_launched`, `lock_started`, `goal_completed`, `trial_started`, onboarding steps) aren't captured.
- **X4** UI tests are compiled, never run.
- **S9** Landing-page waitlist keys are placeholders.

## Post-launch
Adaptive engine beyond protein/water (L7), EndFocusIntent (L8), GymAutoDetect + motion anti-cheat (L9), AI meal photo / meal-prep vision / protein gap tiers 2–3 (V4–V6), sync + auth (S1), duels/referrals/leaderboard backends (S3–S5), squad push (S6), unused Edge Functions/cron (S7), RevenueCat webhook identity (S8), gear store / Founder Series (M5/M6), onboarding drip + fresh-start nudges (N3/N4), Watch app (A1), experiments (X2), ML service (X3), ~200 unused Copy constants and stale TODOs.

## Fixed since the audit (2026-10-02)
- Control Center lock control now runs in the app's process (`LockControlIntent`, a `LiveActivityIntent`).
- Health sleep read removed; meal photos deleted with "Delete all my data"; barcodes out of analytics; ZANOMonitor privacy manifest declares UserDefaults; location string mentions travel mode.
