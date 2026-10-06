# App Store Connect: App Privacy answers ("nutrition label")

> Written 2026-10-02 from a code audit. Every answer cites the file that justifies it. Re-audit
> this file whenever a service below is switched on. **The label must describe the binary you
> submit, not the roadmap.**

## 0. How to use this

Apple's definition: data is **collected** if it's transmitted off the device in a way that lets
you or your third-party partners access it for longer than needed to serve the request in real
time. Data processed only on device is **not** collected, even if it's very sensitive (Health,
Screen Time, calendar). SDKs you embed count as you.

This build has **two possible states**, so each answer below has two columns:

- **Today's build.** No third-party SDK is linked (`Core/Package.swift` has no dependencies, and
  `docs/dependencies.md` says "None are added"). PostHog, Sentry and RevenueCat are compiled out
  behind `#if canImport(...)` (`Core/Sources/Core/Analytics/Analytics.swift`,
  `Analytics/CrashReporting.swift`, `Monetization/RevenueCatManager.swift`). `SyncEngine` is
  never given a backend (no `setBackend` call in `App/`), and `MealVisionClient` stays
  unconfigured because there are no `SUPABASE_URL` / `SUPABASE_ANON_KEY` Info.plist keys
  (`project.yml`). The only live network calls are **Open Food Facts** barcode lookups
  (`Core/Sources/Core/Verification/BarcodeProteinLookup.swift`) and Apple system services.
- **Full launch config.** All of Supabase sync + auth, meal vision, RevenueCat, PostHog and
  Sentry are switched on, as the spec intends.

Answer the questionnaire for whichever state you **actually submit**. If you're between the two,
take each row's answer from the column of the service that's live.

> **Tip:** after linking the SDKs, use Xcode → Archive → right-click → **Generate Privacy Report**.
> It merges every SDK's `PrivacyInfo.xcprivacy` (PostHog, Sentry, RevenueCat and supabase-swift
> all ship one). Reconcile that report against this file before submitting.

**Tracking (ATT):** Answer **No** for every data type in both states. There's no IDFA, no
`ATTrackingManager`, no ad SDK and no data broker sharing (grep for `ATTrackingManager` /
`advertisingIdentifier` returns nothing). `NSPrivacyTracking` is `false` in all manifests, which
is correct. No `NSUserTrackingUsageDescription` is needed.

---

## 1. Answers by Apple data type

### Contact Info: Name, Email Address, Phone Number, Physical Address, Other

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **No** [CONFIRM IF SIGN IN WITH APPLE SHIPS: then Name + Email (relay) → Collected, Linked, App Functionality] |

Evidence: there's no `AuthenticationServices` import anywhere, and no sign-up or email field in
`App/`. `User.appleSub` (`Core/Sources/Core/Models/User.swift`) is an unused column. The support
link is a `mailto:` (`SettingsView.swift` `supportMailURL`), so it goes through Apple Mail and not
the app, and doesn't need to be declared. The website waitlist (`landing/index.html`) is outside
the app.

### Health & Fitness: Health

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes** (conservative) |
| Linked to user? | — | Yes |
| Tracking? | — | No |
| Purposes | — | App Functionality |

Evidence: HealthKit reads (step count, workouts, heart rate; sleep was dropped 2026-10-02) are in
`Core/Sources/Core/Verification/HealthAuthorization.swift`, `StepsVerifier.swift`,
`HomeWorkoutVerifier.swift`, `GymVerifier.swift` and `GymAutoDetect.swift`. They're all evaluated on
device. Once sync is live, `goal_events` rows with `source = 'healthkit'`, `value`, and `meta`
(heart-rate-corroborated flag) are synced (`backend/supabase/functions/sync/index.ts` allows
`goal_events: goal_id, ts, kind, value, source, verified, meta`). That's data derived from
HealthKit, so declare **Health** rather than relying on a "derived" argument. Do **not** add
Analytics as a purpose: no analytics event carries a HealthKit value (audited every
`Analytics.shared.capture` call. `health_primer_requested` sends only the permission *type
names*).

### Health & Fitness: Fitness

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes** |
| Linked to user? | — | Yes |
| Tracking? | — | No |
| Purposes | — | App Functionality, Analytics |

Evidence: synced goals and goal events (workouts, steps, gym dwell, focus minutes, protein, water,
creatine) go through `sync/index.ts` → `goals`, `goal_events`, `streaks`, `time_bank`. Analytics
events carry fitness values, for example `intent_log_protein {grams}`
(`Core/Sources/Core/Intents/LogProteinIntent.swift`), `intent_log_water {milliliters}`,
`intent_start_focus {minutes}`, and `fuel_barcode_scan_logged {protein_grams}`
(`App/ZANO/Features/Fuel/FuelView.swift`). That's why **Analytics** is a purpose here.
Note: `App/ZANO/PrivacyInfo.xcprivacy` already declares `NSPrivacyCollectedDataTypeFitness`
(linked, App Functionality). That's over-declared for today's build. It's harmless, but if you
submit today's build with "Data Not Collected", remove it so the manifest and label agree.

### Financial Info: Payment Info, Credit Info, Other

**No** in both states. Apple processes payment, and neither RevenueCat nor ZANO sees card data.

### Location: Precise Location

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **No**, *unless* gyms are synced. Then **Yes**, Linked, App Functionality |

Evidence: gym geofences use `CLMonitor` on device (`GymVerifier.swift`, default radius 150 m in
`Models/Gym.swift`). `CLVisit` clustering is on device (`GymAutoDetect.swift`). No client code
enqueues a `Gym` outbox event (only `Squad`, `SquadMember`, `Nudge`, `SquadSharedFreeze`, `Duel`
and `GymLeaderboardOptIn` are enqueued, in `Core/Sources/Core/Social/*`). **However**, the server
accepts `gyms.lat/lng` (`sync/index.ts` allowedColumns for `gyms`). If anyone later adds a Gym
enqueue, this answer becomes **Yes**. The location passed to Apple Maps (`FuelView.swift`
`openNearbyRestaurantSearch`) and Apple reverse geocoding (`TravelMode.swift`
`reverseGeocodeCityName`) go to Apple to serve a real-time request, so they aren't collected.

### Location: Coarse Location

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes, unless you disable GeoIP in PostHog** (and IP storage in Sentry) |
| Linked / Tracking / Purpose | — | Linked: Yes · Tracking: No · Analytics |

PostHog resolves the request IP to city/country by default. Apple counts IP-derived location as
Coarse Location. **Recommended:** turn on "Discard client IP data" in PostHog project settings and
"Prevent storing of IP addresses" in Sentry. Then answer **No**.

### Sensitive Info

**No.** Nothing about race, religion, sexual orientation, etc. is collected.

### Contacts

**No.** There's no `Contacts`/`CNContact` usage. Squad invites use share-sheet links and codes
(`SquadHomeView.swift` `ShareLink`, `UIPasteboard`).

### User Content: Photos or Videos

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes** |
| Linked | — | Yes |
| Tracking | — | No |
| Purposes | — | App Functionality |

Evidence: meal photos are saved locally to the App Group `MealPhotos/` folder
(`App/ZANO/Features/Fuel/MealPhoto/MealPhotoCapture.swift`). When configured, they're uploaded to
the private Supabase `meal-photos/<uid>/` bucket and analyzed by the `meal-vision` Edge Function,
which calls the Anthropic Messages API (`backend/supabase/functions/meal-vision/index.ts`,
`MealVisionClient.swift`, `MealPrepCaptureSheet.swift` `uploadMealPhoto`). Upload is skipped when
`MealVisionClient.isConfigured` is false (today).

### User Content: Emails or Text Messages, Audio Data, Gameplay Content, Customer Support

**No.**

### User Content: Other User Content

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes** |
| Linked / Tracking / Purposes | — | Yes · No · App Functionality |

Evidence: squad names and invite codes (`SquadManager.swift` `SquadSyncPayload`), gym leaderboard
handle (`GymLeaderboard.swift` `GymLeaderboardOptInSyncPayload.handle`), custom goal titles
(`goals.title` via sync), and lock-set names (`lock_sets.name`).

### Browsing History

**No.**

### Search History

**No**, but only if you remove the barcode from analytics (see §5, finding 6). Open Food Facts
lookups (`BarcodeProteinLookup.swift`) send only the barcode plus Apple's default request
metadata, with no user ID, to serve a real-time request. If the `barcode` property stays in
PostHog events, consider declaring it under Product Interaction (below) and say so in the
privacy policy.

### Identifiers: User ID

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **Yes** |
| Linked / Tracking / Purposes | — | Yes · No · App Functionality, Analytics |

Evidence: Supabase `auth.uid()` is the owner of every row (`backend/supabase/migrations/0001_init.sql`).
The RevenueCat app user ID, and the PostHog distinct ID once `Analytics.identify(userID:)` is wired
(it's never called today), also count.

### Identifiers: Device ID

| | Today | Full launch |
|---|---|---|
| Collected? | **No** | **[CONFIRM against each SDK's privacy manifest]**. Likely **No** |

ZANO never reads `identifierForVendor` or the IDFA (grep is clean). PostHog's anonymous ID and
Sentry's installation ID are random, app-scoped IDs. Answer as Apple's generated privacy report
says, based on the SDK manifests.

### Purchases: Purchase History

| | Today | Full launch |
|---|---|---|
| Collected? | **No** (RevenueCat not linked) | **Yes** |
| Linked / Tracking / Purposes | — | Yes · No · App Functionality (+ Analytics if you use RevenueCat charts or PostHog `paywall_*` events) |

Evidence: `RevenueCatManager.swift`; `backend/supabase/functions/revenuecat-webhook/index.ts` →
`subscriptions` table; `PaywallViewModel.swift` analytics `{package, granted_pro}`.

### Usage Data: Product Interaction

| | Today | Full launch |
|---|---|---|
| Collected? | **No** (PostHog compiled out) | **Yes** |
| Linked / Tracking / Purposes | — | Yes (conservative, since it's tied to the PostHog distinct ID) · No · Analytics, App Functionality (feature flags in `ExperimentFlags.swift`) |

Evidence: about 170 `Analytics.shared.capture` call sites across `App/ZANO/Features/**` and
`Core/Sources/Core/Intents/**`.

### Usage Data: Advertising Data, Other Usage Data

**No.**

### Diagnostics: Crash Data, Performance Data, Other Diagnostic Data

| | Today | Full launch |
|---|---|---|
| Crash Data | **No** | **Yes**: Linked = Yes if `CrashReporting.identify` is ever called, otherwise No · Tracking No · App Functionality |
| Performance Data | **No** | **No**, unless Sentry tracing (`tracesSampleRate`) is enabled. It isn't set in `CrashReporting.swift` |
| Other Diagnostic Data | **No** | [CONFIRM per Sentry manifest] |

### Surroundings / Body / Other Data

**No.** There's no ARKit, hand or head tracking, or environment scanning.

### "Data Not Collected" — the answer for today's build

If you submit **today's build exactly as it is in the repo**, the correct App Store Connect
answer is **"No, we do not collect data from this app."** The only off-device flow (barcode →
Open Food Facts) is a real-time lookup with no identifier. Also remove the Fitness entry from
`App/ZANO/PrivacyInfo.xcprivacy`. A hard paywall with no RevenueCat or StoreKit linked can't sell
anything, though, so in practice at least the RevenueCat column will apply at launch.

---

## 2. Summary table (full launch config)

| Data type | Collected | Linked | Tracking | Purposes |
|---|---|---|---|---|
| Health | Yes | Yes | No | App Functionality |
| Fitness | Yes | Yes | No | App Functionality, Analytics |
| Precise Location | No (Yes only if gym sync is added) | — | — | — |
| Coarse Location | No if PostHog GeoIP is off (else Yes · Analytics) | — | No | — |
| Photos or Videos | Yes | Yes | No | App Functionality |
| Other User Content | Yes | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality, Analytics |
| Purchase History | Yes | Yes | No | App Functionality |
| Product Interaction | Yes | Yes | No | Analytics, App Functionality |
| Crash Data | Yes | Yes/No (see above) | No | App Functionality |
| Everything else | No | | | |

## 3. `PrivacyInfo.xcprivacy` audit

| Target | Declares | Matches code? |
|---|---|---|
| `App/ZANO/PrivacyInfo.xcprivacy` | UserDefaults (CA92.1, 1C8F.1); collects Fitness | UserDefaults: correct. **Collected types are incomplete for launch.** Add Health, Photos or Videos, Other User Content, User ID (and Precise Location if gyms sync). PostHog, Sentry and RevenueCat declare their own SDK collection in their own manifests, but data the app itself sends to Supabase belongs in the app's manifest. For today's build, Fitness is over-declared |
| `Extensions/ZANOWidgets` | UserDefaults (CA92.1, 1C8F.1) | Correct |
| `Extensions/ZANOShieldConfig` | UserDefaults | Correct |
| `Extensions/ZANOShieldAction` | UserDefaults | Correct |
| `Extensions/ZANOReport` | UserDefaults | Correct |
| `Extensions/ZANOMonitor` | **Nothing** (`NSPrivacyAccessedAPITypes` is empty) | **Mismatch.** The monitor calls `ScheduledLockMonitor` (`Core/Sources/Core/LockEngine/LockScheduler.swift` line ~303 `UserDefaults(suiteName: AppGroup.identifier)`). Add the UserDefaults category with 1C8F.1 (+ CA92.1) |
| `Watch/ZANOWatch` | **No manifest file** | **Missing.** `WatchStateStore.swift` uses `UserDefaults`. Add a manifest before the Watch app is embedded and shipped (it isn't embedded yet, per `project.yml`) |

No other required-reason APIs were found: there are no file-timestamp, system-boot-time,
disk-space or active-keyboard calls (grep for `systemUptime`, `creationDate`,
`modificationDate`, `attributesOfItem`, `volumeAvailableCapacity` and `activeInputModes` is
clean).

## 4. Info.plist usage strings (`project.yml`)

| Key | Current string | Used by | Review verdict |
|---|---|---|---|
| `NSLocationWhenInUseUsageDescription` | "ZANO uses your location to verify gym visits so you can earn your apps back." | `GymLocationServices.swift`, `LocationPermissionPrimer.swift` | OK. Optional improvement: "…verify visits to gyms you save. Your location stays on your iPhone." (Also used by Travel Mode and nearby food search through the cached fix, which should be mentioned for completeness.) |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | "ZANO uses background location to verify gym visits even when the app isn't open." | `requestAlways()` in `GymLocationServices.swift`; `UIBackgroundModes: location` | OK. Suggested: "Allow 'Always' so ZANO can notice when you arrive at a gym you saved and check you in automatically, even when the app is closed. You can check in manually instead." Reviewers look for the benefit and the alternative |
| `NSHealthShareUsageDescription` | "ZANO reads your steps, workouts, and heart rate to verify goals automatically…" | `HealthAuthorization.swift` | **Fixed 2026-10-02:** sleep is no longer requested or mentioned. |
| `NSHealthUpdateUsageDescription` | "ZANO may save workouts you start from inside the app." | Nothing on iPhone (every request uses `toShare: []`) | Acceptable (never shown). Remove it if a reviewer asks; it's inaccurate for the iPhone app |
| `NFCReaderUsageDescription` | "ZANO reads ZANO tags to log actions like water, protein, or a lock/unlock." | `NFCReader.swift`, `NFCWriter.swift` | OK. It also **writes** tags (`NFCWriter`). Consider "reads and sets up ZANO tags…" |
| `NSCameraUsageDescription` | "ZANO uses the camera to scan food barcodes and photograph meals to log protein." | `MealPhotoCapture.swift`, VisionKit scanner in `FuelView.swift` | OK today. When meal vision goes live, add: "Meal photos you choose to analyze are sent securely to estimate protein." |
| `NSMotionUsageDescription` | "ZANO uses motion data to verify workouts and prevent goal spoofing." | `MotionAntiCheat.swift`, `GymVerifier.swift`, `HomeWorkoutVerifier.swift`, `SunriseAlarmManager.swift` (`CMPedometer`) | OK. Optionally mention the Sunrise Alarm step check |
| `NSCalendarsFullAccessUsageDescription` | "ZANO reads your calendar on this iPhone, never uploading it. It counts how busy your day is, and, only if you turn on Focus lock, uses meeting and focus-block times and titles to lock your apps while they run." | `CalendarAwareness.swift` (opt-in now triggered from `TodayView.swift` ~line 1909) | Good. Suggested addition: "It only counts events and never reads or uploads their details." The `project.yml` comment saying "nothing in the app calls that opt-in yet" is stale |
| `NSAlarmKitUsageDescription` | "ZANO schedules your Sunrise Alarm…" | `SunriseAlarmManager.swift` | String fine. **Key name is UNVERIFIED** (flagged in `project.yml`). Confirm it against the iOS 26 SDK |
| Watch `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` | "…heart rate and workouts on your wrist…" / "…save workouts you start from your wrist." | `WatchWorkoutSessionController.swift` (`toShare: [workoutType]`) | OK |

Not needed (checked): `NSPhotoLibraryUsageDescription` (`PhotosPicker` runs out of process),
`NSPhotoLibraryAddUsageDescription` (`ShareLink` only, no direct saves),
`NSUserTrackingUsageDescription`, `NSContactsUsageDescription`, `NSMicrophoneUsageDescription`.
Notifications need no plist string (requested in `Screen14FirstWin.swift`).

## 5. Privacy risks found during the audit (fix before launch)

1. **"Delete all my data" leaves meal photos behind.** `SettingsView.swift` `deleteAllData()`
   deletes SwiftData rows and the App Group defaults, but never removes the JPEG files in the App
   Group `MealPhotos/` folder (there's no `removeItem` anywhere in the code). Some
   `UserDefaults.standard` keys also survive (for example the squad cache in `SquadHomeModel.swift`,
   suggestion dismissals in `TodaySuggestion.swift`). The settings copy promises "Removes your goals,
   streaks, lock sets, gyms, tags, and history", which is accurate but doesn't mention photos.
2. **No server-side deletion or account deletion.** There's no `delete-account` Edge Function, and
   the delete-all code comment says "Remote (Supabase) rows are NOT deleted". Before sync goes live,
   add in-app account deletion (Guideline 5.1.1(v) once accounts exist; GDPR Art. 17). It needs
   to cover meal photos in Storage.
3. **The `lock_sets.app_tokens_blob bytea` column exists server-side** (`0001_init.sql`). The sync
   function correctly excludes it (allowedColumns `name, is_default`), and `LockSet.swift` documents
   that tokens never leave the device. Still, drop the column so a future change can't upload Family
   Controls tokens by accident. That would contradict the policy and Apple's Screen Time rules.
4. **The server would accept precise gym coordinates** (`gyms.lat/lng` in `sync/index.ts`). The
   client doesn't send them today. Decide on purpose whether gym location syncs, then update the
   label (Precise Location) and policy together.
5. **Sleep is requested from HealthKit but never read** (see §4).
6. **Analytics include product barcodes and nutrition amounts** (`FuelView.swift`
   `fuel_barcode_scan_*` `{barcode}`, `LogProteinIntent` `{grams}`). That's fine under Fitness →
   Analytics, but barcodes add little analytic value and reveal what someone eats. Recommend
   dropping `barcode`. Keep HealthKit values out of analytics entirely (true today).
7. **PostHog GeoIP / Sentry IP.** Turn both off, or declare Coarse Location.
8. **Analytics and crash user IDs.** `Analytics.identify` and `CrashReporting.identify` exist
   but are never called. If they get wired to the Supabase UID, keep the "Linked" answers as above.
   Never pass an email.
9. **`aps-environment` entitlement without remote notifications.** No
   `registerForRemoteNotifications` exists, so no push token is collected. That's harmless, but set
   it to `production` for release or remove it until silent push (spec §11) is built.
10. **Social features (when synced) need report/block** (Guideline 1.2) and a way to leave or delete
    a squad. Gym leaderboard matching across users needs some shared gym identity. How gyms would be
    matched without uploading location couldn't be determined from the code
    (`GymLeaderboardBackend.fetchParticipants(gymID:)` takes a per-user local UUID).
11. **Meal-vision provider configurability.** `ZANO_LLM_API_URL` can point anywhere. The policy
    names Anthropic. Keep them in sync.
12. **The ML service host** (`ml-service/`, called by `risk-check`) wasn't identified. The policy
    has a placeholder.

## 6. What couldn't be determined from code

- Hosting region of the Supabase project (no project exists), the ML service host, and Anthropic
  data-retention settings on the account.
- Exact data each third-party SDK collects. Their manifests aren't in the repo because the SDKs
  aren't linked.
- Final subscription products, prices and trial length (they live in App Store Connect and
  RevenueCat, not code). Spec §21 suggests $6.99/mo, $39.99/yr, and $59.99 lifetime (test only).
- Whether Sign in with Apple will ship (there's no code for it).
- How squad members are displayed to each other. `SquadMember` has no display-name field, so
  what other users see may change when the feature is finished.


## 7. Added 2026-10-06 (sessions 17-23): re-answer these when the features go live

- **Calendar (Focus lock):** event titles are read on the device and never leave it, so the label answer
  stays "Data Not Collected" for Calendar. The usage string was rewritten to say so.
- **Sleep:** read from Apple Health on request, kept on the device. Same: not collected.
- **Family Link (switched off in the build until Supabase and sign-in are live):** when on, a parent's and a
  teen's identifier, task text and one proof photo go to Supabase. Add **User ID**, **Other User Content**
  and **Photos or Videos** (linked to the person, not for tracking, purpose App Functionality) the same day
  it ships, and publish the privacy-policy row marked `[CONFIRM WHEN FAMILY LINK IS LIVE]`.
- **Background modes:** none declared since 2026-10-06 (location removed).
