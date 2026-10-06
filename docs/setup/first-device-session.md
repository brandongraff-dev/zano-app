# First real-device session — checklist

Everything in the app compiles and `Core`'s unit tests pass in CI, but **no session has been
verified on a device** (see `docs/PROGRESS.md`). This is the checklist for the first time ZANO runs
on a real iPhone. It follows the order that finds the most expensive problems earliest.

Definitions of done come from `docs/spec.md` §17. Platform constraints are in §27.

## 0. Before you sit down

- [ ] Mac with current Xcode, and an iPhone on a recent iOS (iOS 18+ to exercise Controls; iOS 26+
      for AlarmKit). Note the exact iOS and Xcode versions in the session doc.
- [ ] `docs/setup/mac-setup.md` steps 1–3 done (xcodegen, extension identifiers cross-checked
      against fresh Xcode templates).
- [ ] Apple ID signed into Xcode. **Family Controls (Development)** capability attached to `ZANO`,
      `ZANOShieldConfig`, `ZANOShieldAction`, `ZANOMonitor`, `ZANOReport` (works without paid
      enrollment on a device).
- [ ] App Group `group.com.zano.app` provisioned for the app and all 5 extensions.
- [ ] A spare NFC tag (NTAG215, NDEF URL record) and, if available, an Apple Watch.
- [ ] Know where you are: gym location saved or a place you can walk away from for the geofence test.
- [ ] **Have a way out.** Before locking anything, confirm you can remove shields from
      Settings → Screen Time (spec §27), in case the in-app emergency unlock misbehaves.

## 1. Build and launch (target: 30 min)

- [ ] `xcodegen generate`, build `ZANO` scheme to the device.
- [ ] **First fix: the Swift 6 actor-boundary issue** flagged in `docs/PROGRESS.md` (non-`Sendable`
      `@Model` types crossing actors). Decide `@MainActor` vs `Sendable` DTOs deliberately with real
      compiler output; don't patch blind.
- [ ] Every extension target embeds and signs. Check the build log for embedded-binary warnings.
- [ ] App launches, SwiftData store opens in the App Group container (not the app sandbox).
- [ ] Sentry/PostHog disabled or pointed at test projects (no accounts exist yet).

## 2. Lock Engine — Session 2 done-when: pick apps → lock → custom shield → unlock

- [ ] Authorization prompt for Family Controls appears and succeeds.
- [ ] `FamilyActivityPicker` opens; pick 1–2 apps, a category, and (if supported) a website; save as a
      lock set.
- [ ] Start a lock manually → picked apps show the **ZANO shield**, not the system one.
- [ ] Shield shows living copy (app name, goals left, streak) — `ZANOShieldConfig` reads App Group state.
- [ ] "Show me my goals" button → local notification → tap opens the app (§27 workaround).
- [ ] "Emergency" button → 60-second hold flow → shield removed → streak penalty applied as configured.
- [ ] End lock normally → shields removed on all picked apps.
- [ ] **Recovery:** kill the app mid-lock, reboot, reinstall. Shields must be removable (in-app or
      via Settings → Screen Time). Record exactly what happens.
- [ ] DeviceActivity schedule: create a lock schedule ≥15 min out; confirm `ZANOMonitor` fires and
      applies/removes shields (§27: expect delay, not second precision).
- [ ] Memory: extensions don't get killed (watch Console for jetsam on shield render).

## 3. Verification — Session 3 done-when: gym visit auto-verifies; focus session verifies

- [ ] Location permission flow: When-In-Use → Always (the Always-Allowed onboarding check, §20.2).
- [ ] Gym geofence: save a gym, arrive, dwell past the minimum (use a short test dwell), confirm the goal
      verifies. Verify the **automotive Core Motion** guard blocks a drive-by.
- [ ] HealthKit: permission sheet, read a workout (log one on Watch/phone), confirm verification path.
      Background delivery may lag — confirm the "verify on next open" fallback works (§27).
- [ ] Focus session: start 25-min (use a short test length), Live Activity appears with countdown,
      leaving the app pauses the timer, completion verifies the goal and shows the unlock celebration.
- [ ] Steps goal verifies from HealthKit step count.

## 4. Intents, widgets, NFC — Session 4 done-when: log water from widget; NFC tag starts lock

- [ ] Home + Lock Screen widgets install and show real data.
- [ ] Interactive widget buttons (+water, +protein, +creatine) log without opening the app and the
      widget reloads after the intent (§27 timeline reload).
- [ ] Controls (iOS 18): Start Lock and Log Water appear in Control Center; Action Button mapping works.
- [ ] Siri phrases and Shortcuts actions resolve.
- [ ] NFC: write a tag, tap it with the app closed → notification → lock starts. Also test a Shortcuts
      automation for the true no-touch path (§27).
- [ ] Unlock-on-goal: complete a goal and confirm shields drop **instantly and offline** (airplane
      mode on). This is the core product promise.

## 5. Core loop in one sitting — the "first win" test

Do this cold, as a new user would, with a stopwatch:
- [ ] Fresh install → onboarding → (paywall stubbed) → pick apps → first earned unlock.
      Target from Session 6: **under 4 minutes**.
- [ ] Note every point where you hesitated or got confused.

## 6. Earn Mode, Bedtime, Alarm (second pass, if time allows)

- [ ] Earn Mode: goal deposits minutes, Dynamic Island meter drains, partial unlock tiers behave.
- [ ] Bedtime Gate: schedule applies on time (±15 min tolerance).
- [ ] Sunrise Alarm: AlarmKit on iOS 26+ breaks through silent/Focus; notification fallback on older
      iOS. Keep a backup alarm — never rely on it for a real wake-up yet (§27).

## 7. Watch (separate pass — least-verified slice)

- [ ] Watch app installs, complications render, wrist controls and haptics work.
- [ ] Zero watchOS SDK verification so far: expect compile/runtime surprises. Log them, don't block
      the rest of the session on them.

## 8. Wrap-up (mandatory per `CLAUDE.md` reporting protocol)

- [ ] Write `docs/sessions/14-first-device-run.md` from `docs/sessions/TEMPLATE.md`: iOS/Xcode
      versions, what passed, what failed with exact errors, what was never reached.
- [ ] Update each affected row in `docs/PROGRESS.md`. Only mark a session `Done` if its §17
      done-when was actually met on this device; otherwise leave `Scaffolded — Unverified` and
      say what is still open.
- [ ] Update the "Current environment status" block in `CLAUDE.md` (Mac/device now available).
- [ ] Commit fixes per session, not in one bundle.

## Things that cannot be verified on this first run

Supabase sync (no project), RevenueCat paywall (no account), TestFlight/App Store (no enrollment),
nudge bandit/slip risk (needs real data), anything needing the 4 Family Controls *distribution*
entitlements (Development capability is enough for device testing only).
