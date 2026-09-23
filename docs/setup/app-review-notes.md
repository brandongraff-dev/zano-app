# App Store review notes & demo account script

Status as of last update: **prepared ahead of submission.** Apple Developer Program enrollment is
not complete yet (see `docs/setup/apple-developer.md`), so there is no App Store Connect record and
no real demo account exists yet — this document is the script and checklist to execute once one
does. Update the placeholders below (credentials, video link) and paste the "Notes for Review" text
into App Store Connect when the real build is submitted. Source: `docs/spec.md` §24 ("App Review:
explain shield behavior and emergency unlock in review notes; provide a demo account; video of the
flow on device") plus the actual shield/emergency-unlock code in this repo, cited inline so this
stays accurate as that code changes — re-check the cited files before submitting if they've changed
since this was written.

This is operational/process documentation, not a legal document, so it carries no "DRAFT — needs a
lawyer" warning — but flag anything below you can't verify on a real device before submitting,
rather than presenting it to Apple as certain.

---

## 1. Why this document exists

ZANO shields apps using Apple's FamilyControls/ManagedSettings/DeviceActivity frameworks. Reviewers
testing a screen-time/parental-control-adjacent app need two things up front or they will
(reasonably) bounce the build:

1. **A way to actually see the shield and both its buttons work**, without needing their own gym,
   HealthKit history, or NFC tags.
2. **Explicit reassurance that no one can get trapped out of their own phone** — Apple's guidelines
   are strict about apps that restrict device functionality, and a reviewer who can't find the
   escape hatch in under a minute will assume there isn't one.

Everything below is written to make both of those obvious in under two minutes of testing.

## 2. Demo account script

### 2.1 Account

Create a dedicated Apple ID and Sign in with Apple identity for review purposes — do not reuse a
real user's account or the founder's personal device state.

- **Apple ID for review:** `[demo+applereview@zano.app — create once App Store Connect access
  exists; do not reuse a personal Apple ID]`
- **Password:** `[store in the team's password manager, not in this file, once created]`
- Sign in via Sign in with Apple when ZANO's onboarding prompts for it.

### 2.2 Pre-seed the account before submitting

So the reviewer never lands on an empty app with nothing to test, seed this account with:

1. **Onboarding completed** — coach voice set to **Hype** (the most legible tone for a first-time
   viewer unfamiliar with the product's voice system).
2. **One lock set** with 2–3 common apps shielded (e.g. a couple of pre-installed Apple apps like
   News or Stocks, since we can't assume the reviewer's device has TikTok/Instagram installed —
   pick apps guaranteed present on any reviewer's test device).
3. **One goal configured** on that lock set that's fast to complete on-camera without special
   hardware: a **Focus Session** (25-minute in-app timer, no HealthKit/location/NFC required — see
   `docs/spec.md` §3, verification tier A, "in-app timer... shields active"). Avoid seeding a
   Workout (Gym) or NFC-dependent goal as the *only* goal, since the reviewer has no gym geofence or
   physical tag and would get stuck unable to complete it — Focus Session is the one goal type a
   reviewer can finish start-to-finish with no external state.
4. **An existing streak** (e.g. 3–4 days) and **one completed goal in history**, so the Progress tab
   and Weekly Report Card aren't empty on first look.
5. **Pro entitlement active** on the demo account (via a RevenueCat sandbox/promotional entitlement,
   not a real purchase) so the reviewer can see Squads, Earn Mode, and photo-based protein logging
   without needing to complete a real purchase — see `docs/setup/apple-developer.md` /
   `docs/dependencies.md` for RevenueCat setup status.

### 2.3 What NOT to pre-seed

- Don't seed a gym/geofence — instead, rely on the manual check-in fallback (`docs/spec.md` §3) so
  the reviewer can complete a Workout goal without visiting a real location.
- Don't seed Screen Time data claims of any kind in the app's copy for the reviewer to see — there
  is none to show (see §5 below); if any UI text implies otherwise, that's a bug, flag it before
  submitting.

## 3. Step-by-step review walkthrough (what to put in "Notes for Review")

Paste (and adjust) the following into App Store Connect's **App Review → Notes** field:

> ZANO shields apps you choose (using Apple's FamilyControls/ManagedSettings/DeviceActivity
> frameworks) until you complete a goal you've configured — e.g. a focus session, a workout, or
> hitting a protein target. The demo account below is pre-configured with one shielded lock set and
> one Focus Session goal so you can see the full lock → shield → verify → unlock loop without
> needing a gym, wearable, or NFC tag.
>
> **To see the shield:**
> 1. Sign in with the demo account (credentials below).
> 2. On the Home tab, tap "Start Lock" on the pre-configured lock set.
> 3. Try to open one of the shielded apps (e.g. News). You'll see ZANO's custom shield screen
>    ("the Living Shield") instead of the app opening — this is Apple's `ShieldConfigurationDataSource`
>    rendering our copy, not a modification to the blocked app itself.
> 4. The shield has two buttons: **"Show my goals"** and **"Emergency."**
>
> **Why the shield buttons don't open the app directly:** Apple's `ShieldActionDelegate` API does
> not allow a shield's action buttons to open the host app directly. Both buttons instead post a
> local notification (scheduled ~1 second later, since the shield-action extension's process is
> short-lived); tapping that notification opens ZANO to the relevant screen. This is Apple's
> documented pattern for ShieldActionDelegate, not a bug or workaround we invented — see
> `Extensions/ZANOShieldAction/ShieldActionExtension.swift` in the submitted source if useful for
> your review.
>
> **Emergency unlock — how we guarantee no one is ever trapped:**
> - Phone calls and Emergency SOS are never affected by ZANO's shields — this is an Apple platform
>   guarantee for FamilyControls-based apps, not something our code has to implement.
> - Tapping "Emergency" on the shield posts a notification; tapping that notification opens ZANO
>   directly to a 60-second hold-to-confirm screen. Holding for the full 60 seconds ends the active
>   lock immediately, with no goal required — the shield drops right away. Releasing early cancels
>   with no penalty, so a user can't be punished for merely *attempting* to leave.
>   (`Core/Sources/Core/LockEngine/EmergencyUnlock.swift`, `EmergencyUnlockIntent.swift`.)
> - We ask whether to record a streak "miss" for using Emergency Unlock (since it means a goal
>   genuinely wasn't completed), but this is disclosed before confirming and never blocks the
>   unlock itself — the unlock always completes regardless of that choice.
> - To test: from the shield, tap Emergency → tap the resulting notification → hold the on-screen
>   button for 60 seconds → the shield drops.
>
> **HealthKit / Location / Motion permissions:** these are requested contextually (at gym setup for
> Location, not during onboarding) and are used only for automatic, on-device goal verification —
> e.g. detecting a completed workout so the user doesn't have to log it by hand. None of this data
> is shared, sold, or used for advertising. Full detail in our Privacy Policy
> (`docs/legal/privacy-policy.md` in the submitted source / linked from the app's Settings screen).
>
> **Screen Time data:** ZANO cannot and does not read your Screen Time usage data into the app or
> our backend — Apple's DeviceActivityReport extension only allows on-device display, by design.
> Anything ZANO shows about "time reclaimed" is computed from our own lock-session timestamps, not
> from Screen Time data.
>
> **Subscriptions:** ZANO uses standard Apple In-App Purchase auto-renewing subscriptions via
> RevenueCat, with a free trial and a visible "Restore Purchases" control on the paywall (Settings →
> Upgrade, or the onboarding paywall). No purchase is required to test the demo account above — Pro
> entitlement is already active on it.
>
> If anything above isn't behaving as described, please let us know which step and we'll follow up
> immediately — thank you for reviewing.

## 4. Demo account credentials (fill in before submitting)

| Field | Value |
|---|---|
| Apple ID (Sign in with Apple) | `[create at App Store Connect enrollment time]` |
| Password | `[team password manager — never commit here]` |
| In-app PIN/passcode (if ZANO adds one later) | `[n/a as of this writing]` |
| Notes | Pro entitlement granted via RevenueCat sandbox override, not a real purchase — see §2.2 |

## 5. Known platform behaviors worth flagging to a reviewer proactively

Pulled from `docs/spec.md` §27 (Known Platform Gotchas) — these are normal iOS/FamilyControls
behaviors, but a reviewer unfamiliar with the frameworks may read them as bugs if not told:

- Shield buttons opening the app via a notification tap (not directly) is expected — see §3 above.
- `ManagedSettingsStore` shields persist until explicitly removed; if the reviewer force-quits or
  reinstalls mid-review with a shield active, the shield may still show on next launch. A "Reset
  ZANO / remove all shields" path exists in Settings → Screen Time → [app] → Remove if this happens
  outside the app.
- DeviceActivity schedules have a 15-minute minimum interval and can be delayed by iOS — don't judge
  the Bedtime Gate's timing to the second.
- Simulator cannot run FamilyControls, Core NFC, HealthKit workouts, or geofences at all — **this
  app must be reviewed on a real device**, and should be marked as requiring one if App Store
  Connect offers that option.
- The Sunrise Alarm's tag-dismiss variant requires a physical NFC tag the reviewer won't have —
  the demo account is seeded with the **Focus Session** dismiss variant instead (a 3-minute
  in-app timer, no hardware needed) so the alarm flow is fully testable without one. If reviewing the
  Sunrise Alarm specifically, mention in your reply that the demo account is *not* on the default
  Tag-dismiss variant and why.
- On iOS versions before 26, the Sunrise Alarm runs on chained local notifications rather than
  AlarmKit; it may be audibly weaker than a dedicated alarm clock, which the in-app copy and our
  Terms of Service both disclose to the user — this is a known, intentional limitation of the
  fallback tier, not a bug.

## 6. Demo video (required alongside the notes above)

Record a single screen-recorded take on a real device, no cuts needed if the script below is
followed in order — App Store Connect accepts a video link/attachment alongside review notes, or
this can be hosted privately and linked here:

**Video link:** `[record once a real device + demo account exist; paste an unlisted link here —
e.g. a private Drive/Loom link, not a public one, since it shows account credentials on screen]`

**Script to record (~90–120 seconds):**

1. (0:00) Home tab, signed in as the demo account — show the existing streak and one shielded lock
   set.
2. (0:10) Tap "Start Lock." Show the Home Screen returning; briefly show the widget/Lock Screen
   status if visible.
3. (0:15) Try to open a shielded app (e.g. News) — show the Living Shield appearing instead, with
   its coach-voice copy and streak visible.
4. (0:25) Tap "Show my goals" — show the notification appearing, tap it, show it opening ZANO to the
   goals screen (demonstrating the ShieldActionDelegate → notification → app-open pattern from §3).
5. (0:35) Return to the shielded app, trigger the shield again, this time tap "Emergency" — show the
   notification, tap it, show the 60-second hold screen starting.
6. (0:45–1:45) Hold through the full 60 seconds (real time — don't cut this; a reviewer should see
   it's a genuine 60-second commitment, not a fake progress bar) — show the shield dropping and the
   app confirming "Unlocked early."
7. (1:50) Separately (can be a quick cut here, this part doesn't need to be continuous): show
   starting a fresh lock, completing the seeded Focus Session goal for real (or fast-forward/sped-up
   footage clearly labeled as such), and the unlock celebration when the goal is verified —
   demonstrating the *normal*, non-emergency path also works end-to-end.

## 7. Checklist before actually submitting

- [ ] Apple Developer Program enrollment complete (`docs/setup/apple-developer.md`)
- [ ] Family Controls entitlement approved for all 4 required bundle IDs (main app +
      ZANOShieldConfig + ZANOShieldAction + ZANOMonitor)
- [ ] Demo Apple ID created and credentials filled into §4 (in the team password manager, not this
      file in plaintext if this repo is ever made public)
- [ ] Demo account pre-seeded per §2.2, verified on a real device by someone who is not the person
      who set it up (fresh eyes catch "assumed but not actually seeded" gaps)
- [ ] Video recorded per §6 and linked
- [ ] Privacy Policy (`docs/legal/privacy-policy.md`) and Terms of Service
      (`docs/legal/terms-of-service.md`) finalized by a lawyer, published at real URLs, and those
      URLs entered in App Store Connect
- [ ] App Store Connect "App Privacy" nutrition-label questionnaire filled out to match the Privacy
      Policy exactly (HealthKit, Location, and any other declared data types)
- [ ] Re-read §3's "Notes for Review" text against whatever the shield/emergency-unlock code
      actually does at submission time — re-verify against `Extensions/ZANOShieldAction/
      ShieldActionExtension.swift`, `Core/Sources/Core/LockEngine/EmergencyUnlock.swift`, and
      `Core/Sources/Core/Intents/EmergencyUnlockIntent.swift`, since this document was written from
      those files as they existed on 2026-09-22 and any of them may have changed since
