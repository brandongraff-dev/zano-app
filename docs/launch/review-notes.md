# App Review notes and guideline pre-check (v1.0)

Status: **draft, 2026-10-02** (updated the same day for the conversion pass: RevenueCat linked,
paywall grace period, trial reminder, age rating 16+, squads hidden). Written against the code as of
today (7-step onboarding, hard paywall, 2-minute first win). It supersedes the walkthrough in `docs/setup/app-review-notes.md`,
which still describes the old 14/15-screen flow (paywall "screen 12", notifications "screen 13",
first win "screen 14"); update or retire that file so nobody pastes stale steps.

Sources: `docs/spec.md` §7, §21, §24, §27; `project.yml` (usage strings, background modes,
entitlements); `App/ZANO/Features/Onboarding/*`, `App/ZANO/Features/Lock/*`,
`App/ZANO/Features/GymSetup/*`, `Core/Sources/Core/Verification/*`,
`Core/Sources/Core/Monetization/*`, `Core/Sources/Core/Copy/*`, `App/ZANO/PrivacyInfo.xcprivacy`.

Everything here is **unverified on a device** (no Mac/iPhone yet; FamilyControls doesn't run in the
CI Simulator). Walk §2 on a real device before submitting and fix this file where reality differs.

Placeholders: `[COMPANY LEGAL NAME]`, `[SUPPORT EMAIL]`, `[WEBSITE]`, `[PRICE_*]`, `[VIDEO LINK]`.

---

## 1. Blockers to fix before the first submission

These are the RISK items (§6) that would very likely cause a rejection or make review impossible.
Details and the rest of the list are in §6.

1. **RISK (reduced 2026-10-02): RevenueCat is now linked, but needs its key, products and
   offering.** `purchases-ios` (5.x) is a dependency of Core and the app (`project.yml`,
   `Core/Package.swift`). The Release build reads `REVENUECAT_API_KEY` from Info.plist, which is
   empty in the repo and must be passed at build time. Without a key, or with no offering, the
   paywall offers "Continue for now" (the grace period, §3a), so a reviewer is never stuck, but they
   also can't buy anything. That is a 3.1.2/2.1 problem in its own right, so ship with a working key
   and sandbox-tested products.
2. **RISK: `UIBackgroundModes: location` is declared, but no feature needs continuous background
   location** (2.5.4).
3. **RISK: "goes live soon" / "coming soon" features are visible in the app** (2.1 / 2.3.1).
4. **RISK: privacy policy and terms URLs (`https://zano.app/...`) must resolve** before submission.

---

## 2. Five-minute reviewer path (what to verify yourself first)

Steps match `OnboardingFlowState.swift` (7 steps) and the Copy files.

1. **Install, open.** No account, no sign-in.
2. **Step 1–3: Hook → main goal → "What's your phone costing you?"** Any answers.
3. **Step 4: "Which apps steal your time?" → Choose apps.** iOS asks for Screen Time access
   (individual authorization), then Apple's app picker. Pick 1–2 apps that exist on the device
   (News, Stocks). Refusing is fine: "Continue without locking" lets the reviewer through, and the
   first win then runs as a plain 2-minute timer with no shield.
4. **Step 5: plan reveal → hold the button for 2 seconds** to commit.
5. **Step 6: paywall.** Yearly is pre-selected; its tile shows the billed amount ("$39.99/year"),
   with the per-month figure smaller under it. "Remind me before my trial ends" is ON; turning it
   on (or starting the trial with it on) asks for notifications once. "Start my 7-day free trial"
   with the sandbox account. Restore purchases, Terms and Privacy are on the same screen.
   - **If plans don't load** (offline, store error): "Try again" and **"Continue for now"**. The
     second one lets you into the app for 3 days without a trial (see §3a). Check it on device
     once, in Airplane Mode.
6. **Step 7: "Start your first lock now" → Start focus session.** iOS asks for notifications once
   (allow, see §3). A real 2-minute lock starts on the picked apps.
   - Go Home and open a picked app: **the ZANO shield appears.** Return to ZANO. (Leaving ZANO
     pauses the focus timer; it resumes when you come back. The screen says so.)
   - After 2 minutes: "Earned." The shield lifts, Day 1 streak, celebration.
7. **Emergency unlock.** Lock tab → "Start a lock now" → press and hold **"Hold to unlock in an
   emergency"** for 60 seconds (a countdown shows; letting go cancels). The lock ends and every app
   opens, no goal needed. Also reachable from the shield: tap "Emergency unlock" → tap the
   notification → same control.
8. **Manual gym check-in (no gym needed).** Today → Finish setup → "Set up your gym" (or Settings →
   Gym setup) → Add a gym → search any address or tap the map → save. Location permission is asked
   with an explanation first; "Allow While Using" is enough, and denying still works for this test.
   Then "Check in now" → "Can't verify? Check in manually" → hold "Hold to check in". The workout
   counts for today, marked as manual (one per day).
9. **Borrow minutes (Earn Mode / Time Bank).** On the Lock tab during a lock: "Need a few
   minutes?" → "Borrow 5 min from your Time Bank". Minutes are earned by finishing goals, so on a
   fresh install the bank may read empty ("finish a goal to earn minutes"). Finish a focus session
   first (Today, or the Start Focus control), then borrow. The lock comes back on its own when the
   minutes run out. **Verify on device** what a brand-new user's bank holds; if it is always 0 at
   this point, either drop this step from the notes or tell the reviewer the order.

## 3. "Notes for Review" text (paste into App Store Connect)

> ZANO is a self-control app: the user picks apps that distract them and goals they want to hit
> (focus session, gym visit, steps, protein, water). Their chosen apps are shielded with Apple's
> Screen Time frameworks (FamilyControls in **individual** mode, ManagedSettings, DeviceActivity)
> until the goals are done. No account or sign-in; everything starts on the device.
>
> **Please test on a real iPhone.** FamilyControls, NFC, geofencing and HealthKit workouts don't run
> in the Simulator.
>
> **Full loop in about 5 minutes**
> 1. Open ZANO and go through onboarding; any answers work.
> 2. At "Which apps steal your time?", tap Choose apps, allow Screen Time access, and pick 1–2 apps
>    (for example News). You can also tap "Continue without locking".
> 3. Hold the button on the plan screen for 2 seconds.
> 4. On the subscription screen, Yearly is pre-selected; start the 7-day free trial with your
>    sandbox account. Restore purchases, Terms and Privacy are on the same screen. If the plans ever
>    fail to load, tap "Continue for now": the app opens without a purchase and asks again later, so
>    the review is never blocked.
> 5. Tap "Start focus session" and allow notifications. A real 2-minute lock starts. Open one of the
>    apps you picked from the Home Screen: ZANO's shield appears. Return to ZANO (leaving pauses
>    the timer). After 2 minutes the session verifies, the shield lifts and a celebration plays.
>
> **Emergency unlock (nobody can be trapped)**
> - Calls and Emergency SOS are never blocked (system guarantee).
> - Every lock has an emergency unlock with no goal required: Lock tab → press and hold "Hold to
>   unlock in an emergency" for 60 seconds. Letting go cancels. The shield's "Emergency unlock"
>   button leads to the same control.
> - If a subscription lapses during a lock, ZANO removes the shields before showing the paywall.
>
> **Why the shield's buttons open ZANO through a notification:** a ShieldActionDelegate can't open
> the containing app directly, so "Show my goals" and "Emergency unlock" post a local notification;
> tapping it opens ZANO on the right screen. Please allow notifications when asked.
>
> **Without a gym or NFC tag:** Settings → Gym setup → Add a gym (search any address) → Check in now
> → "Can't verify? Check in manually" → hold. NFC tags and the Sunrise Alarm's NFC dismiss are
> optional; the alarm can be switched to Steps or a wake-up timer, and its ringing screen always has
> a 60-second "Emergency: turn off without verifying" hold.
>
> **Permissions, all asked in context with an explanation first:** Screen Time (onboarding, to block
> the chosen apps); Notifications (first lock, for shield buttons and reminders); Location (only when
> the user adds a gym: geofence around saved gyms only; "Always" only after an explanation, and
> manual check-in works without it); Health (only when the user adds a step, workout or sleep goal;
> read-only); Motion (workout anti-spoofing); Camera (barcode scanning and meal photos for protein
> logging); NFC (ZANO tags); Calendar (optional "go easier on busy days" setting). Nothing is used for
> advertising or tracking.
>
> **Screen Time data** never enters the app or leaves the device. The usage summary is drawn by
> Apple's DeviceActivityReport extension. App selections are opaque tokens stored only on the device.
>
> **Subscriptions:** auto-renewable, Monthly and Yearly (Yearly has a 7-day free trial). The paywall
> shows a dated trial timeline (today, reminder, billing date with the amount), the billed price as
> the largest price on each plan, the full terms next to the button, Restore purchases, Terms and
> Privacy. "Remind me before my trial ends" is an optional notification two days before billing; it
> does not change the plan or the price. If the store can't load plans, "Continue for now" opens the
> app for 3 days; the subscription screen comes back once that time is up and the store is
> reachable. Squads and leaderboards are not part of this version.
>
> **Known iOS behaviours:** DeviceActivity schedules have a 15-minute minimum and iOS may deliver
> them late, so scheduled locks aren't exact to the second. If ZANO is force-quit or reinstalled
> during a lock, the shield can persist; opening ZANO and using emergency unlock clears it.
>
> Demo video: [VIDEO LINK]. Contact: [SUPPORT EMAIL].

## 3a. Grace period and RevenueCat sandbox (for whoever submits)

**Grace period** (audit M2, founder decision 2026-10-02; `Core/Sources/Core/Monetization/
SubscriptionGate.swift`):

- Shown only when the paywall's plans fail to load: offline, no `REVENUECAT_API_KEY` in the build,
  no current offering, or a store error. "Continue for now" grants **3 days**; the app shows a soft
  "Finish starting your trial" banner that reopens the paywall.
- When the grace is over and the store answers "not subscribed", the paywall returns (any active
  lock is released first, as for a lapsed subscription). If the store still can't be reached, the
  app stays open (fail open, `EntitlementGate`). If plans fail again on that paywall, "Continue for
  now" grants **1 more day**. It is never offered when plans loaded, and nothing appears when a
  user closes or declines the paywall (spec §21: no post-close offers).
- Result for review: **no path leaves a reviewer stuck at the paywall.** The DEBUG-only
  `ZANOSkipPaywall` flag is unchanged (UI tests).

**RevenueCat sandbox checklist:**

- Key: the **public Apple SDK key** (`appl_...`) from the RevenueCat dashboard, passed as the
  `REVENUECAT_API_KEY` build setting (e.g. `xcodebuild ... REVENUECAT_API_KEY=appl_xxx` from a
  Codemagic/GitHub secret). Never commit it; `project.yml` keeps the setting empty.
- Dashboard: entitlement identifier **`pro`** (hard-coded in `RevenueCatManager.
  proEntitlementIdentifier`; a mismatch reads every user as not subscribed), one **current**
  offering with `$rc_annual` (7-day free-trial intro offer) and `$rc_monthly` packages mapped to
  the App Store Connect products (`app-store-listing.md` §10).
- Products must be "Ready to Submit" with the first build, and attached to the version, or the
  reviewer's sandbox purchase fails.
- Test on device with a Sandbox Apple Account (Settings → App Store → Sandbox Account): purchase
  the trial, Restore purchases on a reinstall, and let a sandbox trial expire (minutes, not days,
  in sandbox) to see the lapsed paywall and the lock release.
- The trial reminder is dated from RevenueCat's `expirationDate` when available. Sandbox
  accelerates subscriptions (a 1-week trial lasts minutes), so "2 days before the end" is already
  past and the reminder is skipped there; that is expected. The reminder can only be seen end to
  end with a real trial (TestFlight is also accelerated). What sandbox can show: the toggle's
  permission prompt, and that a sandbox purchase records the trial (no crash, no stray
  notification).

## 4. Permission and capability justifications

### Screen Time (FamilyControls / ManagedSettings / DeviceActivity)

Individual authorization (`requestAuthorization(for: .individual)`, four call sites: onboarding step
4, lock-set picker, Today's fix-access card, `LockHealthCheck`). Used to shield the user's own
selection during a lock, run the user's own schedules, and render an on-device usage report.
Entitlement request text: `docs/launch/family-controls-request.md`.

### HealthKit (read-only; nothing requests write access)

Asked per goal type, only when the user adds that goal (`HealthAuthorization.readTypes(for:)`):

| Data type | Read when | Used for | Code |
|---|---|---|---|
| Step count | Steps goal | Verifies the daily step target; background delivery so it verifies without opening the app | `StepsVerifier`, `HealthAuthorization` |
| Workouts | Gym or home/outdoor workout goal | Confirms a workout happened (home/outdoor) and corroborates gym dwell | `HomeWorkoutVerifier`, `GymVerifier` |
| Heart rate | Gym or home/outdoor workout goal | Anti-spoofing: elevated HR during the dwell/workout window ("Heart rate confirms") | `GymVerifier`, `GymAutoDetect`, `HomeWorkoutVerifier` |
| Sleep analysis | "Sleep on time" goal | Verifies the bedtime goal | `HealthAuthorization` |

- `NSHealthShareUsageDescription` ("steps, workouts, heart rate, and sleep") matches these four
  types. (The comment above it in `project.yml` says "nothing reads sleep"; that comment is out of
  date, the string is right.)
- Health data is used on device. Only "goal completed" results are eligible for sync (spec §24), and
  sync isn't live in 1.0. Not used for ads, not sold, not stored in iCloud by us.
- Guideline 2.5.1 wants HealthKit use made clear in the UI and marketing: the description names
  Apple Health; the Health prompt is preceded by an explanation.

### Location

- **When In Use** first, at gym setup only, after `LocationPermissionPrimer` explains why
  (`GymLocationServices.requestWhenInUse`). **Always** only after a second explanation ("Check in
  without opening the app"), and manual check-in is offered as the alternative.
- Used for: a `CLMonitor` circular geofence per saved, confirmed gym (dwell timer) and a one-shot
  "Use current location" to drop the gym pin. Travel Mode also samples the last known location on
  app launch to suggest pausing the gym goal when the user is far from home
  (`TravelMode.sampleLastKnownLocation`, `ContentView.swift`).
- No continuous tracking, no location history uploaded, no location sold or shared.

### NFC (`NFCReaderUsageDescription`, NDEF)

User-initiated scans of ZANO tags (or any NDEF tag the user programs) to log water/protein, start a
lock, check in, or dismiss the Sunrise Alarm. Never required: every tag action has an in-app or
widget equivalent.

### Camera

Barcode scanning (protein lookup) and meal photos for protein logging, user-initiated in Fuel. AI
photo estimates aren't live in 1.0 (the screen says "Photo estimates are coming soon"), see RISK 3.

### Motion (`NSMotionUsageDescription`)

`MotionAntiCheat` and the gym/home-workout/stretch verifiers check activity type during a workout
window so a phone left at the gym doesn't count.

### Calendar (`NSCalendarsFullAccessUsageDescription`)

Opt-in toggle on Today (`CalendarAwareness.optIn`): reads event density to soften goals on packed
days. Nothing is written; nothing leaves the device. Never asked unless the user turns it on.

### Notifications

Asked at most once by iOS, at the first of: turning on (or starting the trial with) the paywall's
"Remind me before my trial ends" toggle, the Start button on the first-win screen, or Today's
Finish setup "Turn on notifications" item (which opens the Settings app if it was refused). Used
for: shield button hand-off (the only way a shield action can open the app), the trial-ending
reminder ("What your trial earned you", two days before billing), and at most 2 nudges a day (spec
§8 rule 7). All local.

### Background modes (`UIBackgroundModes: [location]`)

`project.yml` declares only `location`, for the gym geofence. See **RISK 2**: region monitoring
(`CLMonitor`), visit monitoring and significant-change updates all relaunch the app without this
mode, so the declaration likely isn't needed and is a 2.5.4 rejection magnet. Background step
verification uses the HealthKit background-delivery entitlement, not a background mode (correct).

### Live Activities, AlarmKit, App Intents, widgets

`NSSupportsLiveActivities` for the focus timer and Bedtime/Sunrise activities; AlarmKit (iOS 26+)
for the Sunrise Alarm with a chained-notification fallback below 26; App Intents for Siri/Shortcuts,
widgets and Controls.

## 5. Guideline pre-check

| Guideline | Risk | How ZANO complies / what to do |
|---|---|---|
| **4.2 Minimum functionality** | Low | Native SwiftUI app with real device integrations (Screen Time shielding, geofence verification, HealthKit, NFC, Live Activities, widgets, Controls, Siri). Not a web wrapper. |
| **2.1 App completeness** | **High** | RevenueCat linked but needs key/products (RISK 1); "coming soon" features (RISK 3). The paywall's grace period keeps every build from dead-ending (§3a). Otherwise the full loop works offline with no account. |
| **5.1.1 Data collection & storage** | Medium | No account in 1.0, so no account-deletion requirement yet (5.1.1(v) applies the day Sign in with Apple ships with sync). Every permission is asked in context, with a purpose string, and refusing each one leaves a working path (continue without locking, manual check-in, one-tap logging). Privacy policy draft exists (`docs/launch/privacy-policy.md`), not yet reviewed or published (RISK 4, RISK 6). |
| **5.1.2 Data use and sharing / 5.1.3 Health** | Low | No ads, no tracking (`NSPrivacyTracking: false`), Health data not used for ads or sold, Screen Time data never leaves the device (by design of Apple's frameworks). |
| **2.5.4 Background services** | **High** | Only `location` declared; see RISK 2. |
| **2.5.1 / FamilyControls usage** | Medium | Individual mode, self-imposed only; entitlement must be approved for all 5 bundle IDs before upload. |
| **3.1.2 Subscriptions** | Medium | Hard paywall with free trial is allowed (spec §21); compliance depends on: price, length and auto-renew terms next to the CTA (done in `PaywallCopy.termsParagraph`), dated trial timeline (done), Restore (done), functional Terms + Privacy links in the app *and* in App Store Connect metadata (RISK 4), the trial shown only on the plan that has it (done: `selectedTrialDays`), no dark patterns (spec §21). See RISK 5 on paywall placement. Subscriptions must give ongoing value: adaptive plan, recaps, verification, Time Bank are ongoing. |
| **3.1.1 / 3.1.3(e) Physical goods** | Low | NFC tags / Lock Card are physical goods sold outside the app (Settings → Gear links to a web store), which is allowed. Make sure the link isn't a way to buy *digital* unlocks (spec §21 already forbids selling unlocks). The Gear store URL is a placeholder (`gear.zano.app`); hide the Gear entry until it resolves. |
| **1.4.1 Physical harm / health claims** | Low | Additive goals only (no calorie limits, weight targets, fasting; spec §24); no outcome claims in copy (grepped Copy for "addict", "detox", "ADHD", "lose weight", "cure": none). "Pause for health reasons" exists (`health-pause`). Workout goals are user-chosen, start below the stated target (spec §8 rule 1). |
| **1.4.1 / 2.5.x Safety of locks** | Low | Emergency unlock on every lock, calls/SOS unaffected, lapsed billing releases shields (`EntitlementGate`, `PaywallLockEscape`). |
| **1.2 User-generated content** | Low now / High later | Squads (names, nudges) aren't live. The release they go live needs report/block, a way to filter objectionable content and a contact, or it will be rejected. Nothing in the code does report/block yet. |
| **2.3 Accurate metadata** | Medium | Listing only names shipped features (`docs/launch/app-store-listing.md`); screenshots avoid third-party app names. |
| **2.4.1 iPad compatibility** | Medium | iPhone-only, but reviewers may run it on iPad in compatibility mode. FamilyControls individual mode works on iPadOS; NFC and some HealthKit features don't. Make sure no screen crashes or dead-ends when NFC/Health are unavailable (copy for both exists: "NFC isn't available on this iPhone", "Apple Health isn't available"). Test once on an iPad before submitting. |
| **4.5.4 Push / notifications** | Low | Notifications aren't required to use the app and aren't used for marketing without consent. |

## 6. RISK items found in the code

1. **RISK (was blocker; code side fixed 2026-10-02): purchases need a key and products.**
   `purchases-ios` is now linked (`project.yml`, `Core/Package.swift`) and the paywall no longer
   dead-ends: when plans can't load it offers the grace period (§3a). Still open, founder side:
   create the RevenueCat project (entitlement `pro`, current offering), the App Store Connect
   subscription group and products, pass `REVENUECAT_API_KEY` to the Release build, and test a
   sandbox purchase, restore and trial expiry on device. A build without a key gets through
   onboarding but can never sell, so don't submit one.
2. **RISK (likely rejection): `UIBackgroundModes: location` without a continuous-location
   feature.** The code uses `CLMonitor` geofences, a last-known-location read (Travel Mode) and a
   one-shot fetch; none needs the background mode (region monitoring relaunches a suspended or
   terminated app on its own). There's no `startUpdatingLocation` + `allowsBackgroundLocationUpdates`
   or `CLBackgroundActivitySession`. App Review often rejects under 2.5.4 with "declares location
   in UIBackgroundModes but we could not find features that require persistent location". Fix:
   remove the mode and confirm on device that gym arrivals still fire with the app terminated
   (unverified; the `project.yml` comment says the opposite, so test before deciding). If it must
   stay, the notes must name the exact feature and how to trigger it.
3. **RISK: "coming soon" features are reachable in 1.0.** Squad tab ("Squads go live soon", "Needs
   squads live"), gym leaderboard ("That isn't live yet"), referral redemption ("That isn't live
   yet"), meal-photo estimates ("Photo estimates are coming soon"), meal-prep photo checks. App
   Review rejects placeholder or "coming soon" features under 2.1/2.3.1. **Decision (founder,
   2026-10-02): squads and the leaderboard are hidden for v1.** Today's Finish setup no longer has a
   "Start a squad" item; confirm on the submitted build that the Squad tab and the leaderboard entry
   are gone too. Still to do: the referral entry and a plain "log your photo + grams" meal-photo
   flow without the "coming soon" line.
4. **RISK: privacy/terms URLs are placeholders.** `PaywallView` links `https://zano.app/privacy`;
   `SettingsCopy.termsOfUseURLString` is `https://zano.app/terms`; the privacy policy is an
   unreviewed draft with `[ ]` placeholders. App Store Connect requires a working Privacy Policy URL,
   and 3.1.2 requires working Terms/Privacy links in the app. Confirm the domain, publish both pages
   (current drafts: `docs/launch/privacy-policy.md`, `docs/launch/terms-of-use.md`), and enter them
   in App Store Connect.
5. **RISK (medium): hard paywall before any value.** The paywall is step 6; the first earned unlock
   is step 7, after payment. Apple allows this, and the paywall's disclosures are good, but it is the
   most common 3.1.2 friction point and the reviewer must use a sandbox purchase to see anything.
   Keep the notes explicit (done in §3). Spec §23 already lists "paywall after first win" as an
   experiment; that ordering would remove this risk entirely.
6. **RISK: privacy manifest / App Privacy label will be incomplete once SDKs are linked.**
   `App/ZANO/PrivacyInfo.xcprivacy` declares only Fitness (linked, app functionality). The moment
   PostHog (product interaction, identifiers) and Sentry (crash data, diagnostics) are linked, both
   the manifest and the App Store Connect questionnaire must add them; also account for Supabase
   sync (user ID, goal completions) when it ships, and barcode lookups sent to the barcode database.
   The SDKs ship their own manifests, but the app-level label is still yours. Per-data-type answers:
   `docs/launch/app-privacy-labels.md`.
7. **RISK: `NSLocationWhenInUseUsageDescription` doesn't cover Travel Mode.** The string says
   location verifies gym visits; Travel Mode also reads the last known location to detect travel.
   Fix the string, e.g. "ZANO uses your location to verify gym visits and notice when you're
   traveling, so you can earn your apps back." (5.1.1 asks that purpose strings name every use.)
8. **RISK (low): `NSHealthUpdateUsageDescription` describes a write that never happens.** "ZANO may
   save workouts you start from inside the app" but every `requestAuthorization` passes
   `toShare: []`. The prompt never shows, so it can't confuse a user, but a reviewer comparing
   strings to behaviour may ask. Either remove it (if the build doesn't trip the HealthKit
   purpose-string check without it, test that) or make it accurate.
9. **RISK (unverified key): `NSAlarmKitUsageDescription`.** `project.yml` marks the key name as a
   guess. If it's wrong, the AlarmKit authorization request on iOS 26 can crash or silently fail
   (Sunrise Alarm). Confirm against the iOS 26 SDK before submitting.
10. **RISK (low): `aps-environment: development` with no remote notifications.** All notifications
    are local; no `registerForRemoteNotifications`. Harmless if the App ID has Push enabled, but it
    adds a capability to configure and explain. Remove until remote push exists.
11. **RISK (functional): the Control Center / Action Button "Start lock" control probably can't
    shield.** `ZANOLockControlIntent` (widget extension) calls `StartLockIntent().perform()`
    in-process, so `ManagedSettingsStore` runs in an extension without the Family Controls
    entitlement. A reviewer who tries the control would see nothing happen (2.1). Details and fix:
    `docs/launch/family-controls-request.md` §1.
12. **RISK (copy/expectation): the emergency hold is 60 seconds.** Spec §24 says "a short hold";
    the code (`EmergencyUnlock.holdDuration = 60`) and copy say 60 seconds. That's defensible (it's a
    deliberate speed bump, and calls/SOS are never blocked) but a reviewer holding for 3 seconds will
    think it's broken. The notes now say 60 seconds explicitly; consider a shorter hold for 1.0 if
    review pushes back.
13. **RISK (metadata): third-party app names in demo data.** `DemoData.screenTime` and the
    `lockedout` screen use "Instagram"/"TikTok". Fine in CI, not in store screenshots (5.2.1 / 2.3.7).
    The screenshot plan says to swap them.
14. **RISK (process): the stale review-notes file.** `docs/setup/app-review-notes.md` describes the
    pre-2026-10-02 flow. Pasting it would send the reviewer looking for screens that no longer
    exist.

## 7. Submission checklist

- [ ] RISK 1–4 fixed; RISK 5–14 decided.
- [ ] Family Controls (Distribution) approved for all 5 bundle IDs (`family-controls-request.md`).
- [ ] Subscription group + Yearly (7-day intro trial) + Monthly created; IAP review screenshots
      attached; sandbox purchase works on device.
- [ ] Walk §2 on a real device from a fresh install, as someone who didn't build it; once more on an
      iPad in compatibility mode.
- [ ] Privacy Policy and Terms published at real URLs; App Privacy questionnaire matches the
      manifest and the policy.
- [ ] Age rating set to **16+** (founder decision 2026-10-02, `app-store-listing.md` §7).
- [ ] `REVENUECAT_API_KEY` passed to the Release build; RevenueCat entitlement `pro` and a current
      offering exist; the grace path ("Continue for now") checked once in Airplane Mode (§3a).
- [ ] Squad tab and gym leaderboard hidden in the submitted build (RISK 3).
- [ ] Demo video recorded (fresh install → picker → sandbox trial → first-win lock → shield →
      verified → new lock → 60-second emergency hold, uncut) and linked in §3.
- [ ] Review contact: name, phone, [SUPPORT EMAIL]. No demo account needed (no sign-in); say so in
      the "Sign-in required" field.
