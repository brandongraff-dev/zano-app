# App Store review notes

Status: **prepared ahead of submission.** Apple Developer Program enrollment is not complete yet
(see `docs/setup/apple-developer.md`), so there is no App Store Connect record. This file is the
script to paste into App Store Connect → App Review Information → Notes when the first build is
submitted, plus the checklist to run first. Rewritten 2026-09-24 to match the flow the app actually
ships: there is **no account, no sign-in, and no pre-seeded demo account**. A reviewer installs the
app fresh and goes through the same onboarding a real user does.

Source: `docs/spec.md` §24 ("explain shield behavior and emergency unlock in review notes") and the
code cited inline. Re-check the cited files before submitting if they have changed since this date.

---

## 1. What a reviewer needs

ZANO shields apps with Apple's FamilyControls / ManagedSettings / DeviceActivity frameworks. A
reviewer needs two things within the first couple of minutes, or they will reasonably bounce the
build:

1. **To see the core loop work** (lock → shield → do the goal → unlock) without a gym, a wearable,
   HealthKit history or an NFC tag. Onboarding ends with a live 2-minute focus lock that does exactly
   this.
2. **To see that nobody can be trapped.** Every lock has a press-and-hold emergency unlock, visible
   on screen during the first lock, on the Lock tab during any lock, and reachable from the shield.

## 2. Reviewer walkthrough (the real flow)

Order and screens come from `App/ZANO/Features/Onboarding/OnboardingContainerView.swift`
(`screen(for:)`, screens 1–14).

1. **Fresh install, open ZANO.** No sign-in: all data is created on the device.
2. **Onboarding questions (screens 1–3).** Hook, social-proof screen, main goal. Any answers work.
3. **Screen Time permission and app selection (screen 4).** ZANO asks for Screen Time access
   (`AuthorizationCenter.requestAuthorization(for: .individual)`), then shows Apple's
   `FamilyActivityPicker`. Pick 1–2 apps that exist on the review device (for example News or
   Stocks). Apple draws this picker; ZANO only receives opaque tokens, which never leave the device.
4. **More questions, plan and commitment (screens 5–11).** Any answers work.
5. **Hard paywall (screen 12, `PaywallView.swift`).** There is no free tier. Start the free trial
   with the **sandbox Apple ID** on the review device; no real charge is made. Restore purchases,
   Terms and Privacy links are on the same screen.
6. **Notification permission (screen 13).** Allow or deny; either works. Notifications are how the
   shield's buttons reach the app (see §3).
7. **First win (screen 14, `Screen14FirstWin.swift`).** Tap **Start focus session**. This starts a
   real lock on the apps picked in step 3 plus a **2-minute** focus timer.
   - While it runs, open one of the picked apps from the Home Screen: ZANO's shield appears instead.
   - Wait out the 2 minutes, or come back to ZANO. The session verifies, the shield lifts and the
     unlock celebration plays. That is the full core loop.
8. **Emergency unlock.** Start a lock again (Lock tab → Start lock), then either:
   - on the Lock tab, press and hold **Hold to unlock in an emergency**, or
   - on the shield, tap **Emergency unlock**, then tap the notification that follows. It opens the
     Lock tab on the same hold control.

   The lock ends immediately, with no goal required. Letting go early cancels with no penalty.
   (During the onboarding first-win lock the same exit is the **Emergency unlock** bar on that
   screen, a 60-second hold.)

## 3. "Notes for Review" text (paste into App Store Connect)

> ZANO blocks apps the user chooses (Apple's FamilyControls, ManagedSettings and DeviceActivity
> frameworks) until they complete a goal they set, such as a focus session. There is no account or
> sign-in; everything starts on the device.
>
> **To test the full loop in about 5 minutes:**
> 1. Install and open ZANO. Go through onboarding; any answers work.
> 2. When asked, allow Screen Time access and pick 1–2 apps in Apple's app picker (for example
>    News).
> 3. On the subscription screen, start the free trial with your sandbox account. There is no free
>    tier, and Restore Purchases is on the same screen.
> 4. On the last screen, tap "Start focus session". This starts a real 2-minute lock. Open one of
>    the apps you picked: ZANO's shield appears instead of the app.
> 5. After 2 minutes the session verifies, the shield lifts and the app shows an unlock
>    celebration.
>
> **Why the shield's buttons open ZANO through a notification:** Apple's `ShieldActionDelegate`
> cannot open the containing app directly. Both shield buttons ("Show my goals", "Emergency
> unlock") post a local notification, and tapping it opens ZANO on the right screen. This is the
> documented pattern for shield actions, so please allow notifications when asked.
>
> **Emergency unlock — nobody can be trapped:**
> - Phone calls and Emergency SOS are never blocked. FamilyControls guarantees this.
> - Every lock has an emergency unlock: press and hold, and the lock ends immediately with no goal
>   required. It is on screen during the first lock in onboarding and on the Lock tab during any
>   lock, and the shield's "Emergency unlock" button leads to it. Letting go early cancels without
>   penalty.
> - To test: start a lock from the Lock tab, then press and hold "Hold to unlock in an emergency".
>
> **Permissions:** Screen Time (to block the chosen apps) and notifications are requested during
> onboarding. Location (gym check-ins), Health (steps, workouts, heart rate), Motion, Camera (food
> barcode scanning), NFC and Calendar are requested only when the user sets up the feature that
> needs them. They are used on the device to verify goals automatically. Nothing is used for
> advertising or tracking.
>
> **Screen Time data:** ZANO does not read Screen Time usage into the app or send it to a server.
> Usage charts are drawn by Apple's DeviceActivityReport extension, on the device only.
>
> **Subscriptions:** Standard auto-renewing In-App Purchase subscriptions with a 7-day free trial on
> the annual plan. The paywall shows the trial timeline and billing date, plus Restore Purchases,
> Terms and Privacy links.
>
> **Please review on a real device.** FamilyControls, NFC, geofencing and HealthKit workouts do not
> work in the Simulator.

## 4. Known platform behaviours to point out

From `docs/spec.md` §27. These are normal iOS behaviours that a reviewer new to these frameworks
could read as bugs:

- Shield buttons open the app through a notification, not directly (see §3).
- `ManagedSettingsStore` shields persist until removed. If the app is force-quit or reinstalled
  during a lock, the shield can still show. Opening ZANO and using Emergency unlock clears it.
- DeviceActivity schedules have a 15-minute minimum interval, and iOS can delay them. Scheduled
  locks (such as the Bedtime Gate) are not exact to the second.
- Sunrise Alarm: the default dismiss method needs a physical NFC tag. A reviewer can switch it to
  **Steps** or **Wake-up timer** in Settings → Sunrise Alarm. The ringing screen always has a
  60-second "Emergency: turn off without verifying" hold. On iOS versions before 26 the alarm uses
  chained local notifications instead of AlarmKit, which the setup screen says.

## 5. Demo video (optional but recommended)

One continuous screen recording on a real device, about 3 minutes, following §2: fresh install →
onboarding → Screen Time permission and picker → sandbox trial → first-win focus lock → shield on a
picked app → the lock ending → a new lock → emergency hold on the Lock tab, uncut. Upload it unlisted and
paste the link here:

**Video link:** `[record once a signed build runs on a device]`

## 6. Checklist before submitting

- [ ] Apple Developer Program enrollment complete (`docs/setup/apple-developer.md`).
- [ ] Family Controls (Distribution) entitlement approved for every bundle ID that needs it (main app
      + ZANOShieldConfig + ZANOShieldAction + ZANOMonitor, plus ZANOReport if Apple requires it).
- [ ] Subscription products created in App Store Connect and attached to the build. The sandbox
      purchase in step 5 of §2 works on a device.
- [ ] Walk through §2 on a real device, from a fresh install, as someone who didn't build it.
- [ ] Privacy Policy and Terms finalised, published at real URLs, and entered in App Store Connect.
      The paywall's Privacy link points to the real URL.
- [ ] App Privacy questionnaire in App Store Connect matches `App/ZANO/PrivacyInfo.xcprivacy` and the
      Privacy Policy.
- [ ] Re-read §3 against the code at submission time: `Extensions/ZANOShieldAction/
      ShieldActionExtension.swift`, `Core/Sources/Core/LockEngine/EmergencyUnlock.swift`,
      `Core/Sources/Core/Intents/EmergencyUnlockIntent.swift`,
      `App/ZANO/Features/Onboarding/Screen14FirstWin.swift`, `App/ZANO/Features/Lock/LockStatusView.swift`.
- [ ] Settle the emergency hold length. As of 2026-09-24 the Lock tab's hold is `PrimaryButton`'s
      `.holdToCommit` (about 2 seconds) while its copy (`Copy.lockStatus.emergencyUnlockHint`) and the
      onboarding first-win bar say 60 seconds. §2 and §3 above deliberately don't state a duration
      for the Lock tab until the two agree.
