# Family Controls (Distribution) entitlement request

Status: **not filed.** Blocked on Apple Developer Program enrollment (`docs/setup/apple-developer.md`,
`docs/PROGRESS.md`). File this the day enrollment completes; approval can take days to weeks and
nothing can ship to TestFlight or the App Store without it (spec §24).

Sources: `project.yml` (bundle IDs, entitlements), each extension's sources (grepped 2026-10-02 for
`FamilyControls` / `ManagedSettings` / `ManagedSettingsUI` / `DeviceActivity` imports and calls),
`docs/spec.md` §2, §5.1, §11, §21, §24, §27.

**Unverified:** Apple's request form has moved and changed its fields before. The text below is
written so each section can be pasted into whatever free-text field the current form has ("describe
how your app uses the Family Controls framework" or similar). Check the live form and Apple's
current "Family Controls" documentation before filing; don't trust a hard-coded URL from this file.

---

## 1. Which bundle IDs need it

Bundle IDs come from `project.yml`: the app pins `PRODUCT_BUNDLE_IDENTIFIER: com.zano.app`; the
extensions use XcodeGen's derived `bundleIdPrefix + "." + target name`.

| Target | Bundle ID | Declares `com.apple.developer.family-controls` | Screen Time APIs it actually uses (grep) | Request? |
|---|---|---|---|---|
| ZANO (app) | `com.zano.app` | Yes | `FamilyControls` (`AuthorizationCenter.requestAuthorization(for: .individual)`, `FamilyActivityPicker`), `ManagedSettings` (`ManagedSettingsStore` via Core `LockEngineManager`), `DeviceActivity` (`DeviceActivityCenter` schedules via Core `LockScheduler`), `DeviceActivityReport` view | **Yes** |
| ZANOShieldConfig | `com.zano.app.ZANOShieldConfig` | Yes | `ManagedSettings`, `ManagedSettingsUI` (`ShieldConfigurationDataSource`) | **Yes** |
| ZANOShieldAction | `com.zano.app.ZANOShieldAction` | Yes | `ManagedSettings` (`ShieldActionDelegate`) | **Yes** |
| ZANOMonitor | `com.zano.app.ZANOMonitor` | Yes | `DeviceActivity` (`DeviceActivityMonitor`); shields/unshields via Core `ScheduledLockMonitor` → `ManagedSettingsStore` | **Yes** |
| ZANOReport | `com.zano.app.ZANOReport` | Yes | `DeviceActivity` (`DeviceActivityReportExtension` / `DeviceActivityReportScene`), `FamilyControls`, `ManagedSettings` | **Yes** (spec §24 guessed 4 requests; this repo has 5 targets using Screen Time APIs, and a report extension can't read data without the entitlement) |
| ZANOWidgets | `com.zano.app.ZANOWidgets` | No | None directly. **But see RISK below.** | No (unless the RISK is fixed by adding it) |
| ZANOWatch | `com.zano.app.watchkitapp` | No | None | No |
| ZANOUITests | `com.zano.app.ZANOUITests` | No | None | No |

**So: 5 bundle IDs.** `com.zano.app`, `com.zano.app.ZANOShieldConfig`,
`com.zano.app.ZANOShieldAction`, `com.zano.app.ZANOMonitor`, `com.zano.app.ZANOReport`.

Before filing, reconcile the extension IDs: `docs/sessions/00-repo-and-stack-setup.md` mentions
lowercase suffixes (`.shieldconfig`, ...) while `project.yml` generates `.ZANOShieldConfig`, ...
Whatever is registered in the portal and requested here must match what `xcodegen generate` produces
(`project.yml` already flags this). Bundle IDs are case-sensitive in the portal; pick one spelling
and keep it forever, because the approval is tied to it.

**RISK — Control Center "Start lock" runs shielding code in the widget extension.**
`Extensions/ZANOWidgets/Support/ZANOWidgetIntents.swift`: `ZANOLockControlIntent` is a plain
`AppIntent` defined in the widget extension, and its `perform()` calls
`StartLockIntent().perform()` directly. `StartLockIntent` is a `LiveActivityIntent` precisely so the
*system* runs it in the app process (which holds the entitlement), but calling `perform()` from
another intent's `perform()` runs it in the current process: the widget extension, which has no
Family Controls entitlement. The Control will most likely fail to shield anything (unverified,
needs a device). Fix options: (a) make `ZANOLockControlIntent` itself a `LiveActivityIntent` (or otherwise
an intent the system runs in the app process) so it runs in the app, or (b) add the entitlement to
ZANOWidgets and include `com.zano.app.ZANOWidgets` in this request. (a) is better: it keeps the
widget extension out of the request and matches CLAUDE.md's "extensions do no heavy work".

---

## 2. Text to paste — shared overview (use in every request, or once if the form takes all IDs)

> **App:** ZANO (`com.zano.app`), by [COMPANY LEGAL NAME]. Contact: [SUPPORT EMAIL]. Website:
> [WEBSITE].
>
> **What ZANO is:** a self-control app for individuals. The user chooses the apps that distract
> them (for example social media or games) and the goals they want to hit (a gym visit, a focus
> session, a step count, a protein or water target). ZANO keeps the chosen apps shielded until the
> user completes those goals, then removes the shield. It turns screen time into something the user
> earns by doing what they already said they want to do.
>
> **Authorization mode: individual, not parental.** ZANO calls
> `AuthorizationCenter.shared.requestAuthorization(for: .individual)`. The person using the iPhone is
> the person restricting their own apps, on their own device. ZANO has no child accounts, no
> guardian/child pairing, no Family Sharing dependency, and cannot be used to restrict or monitor
> anyone else.
>
> **How we use the frameworks:**
> - **FamilyControls:** `FamilyActivityPicker` so the user selects their own apps, categories and
>   websites. ZANO receives only opaque `ApplicationToken` / `ActivityCategoryToken` /
>   `WebDomainToken` values.
> - **ManagedSettings:** `ManagedSettingsStore` applies and removes shields on the user's selection
>   when a lock starts and when its goals are verified (or the user uses emergency unlock).
> - **ManagedSettingsUI:** a shield configuration extension draws ZANO's shield (what goal is left,
>   how close the user is) and a shield action extension handles its two buttons.
> - **DeviceActivity:** scheduled locks the user sets up (for example "every weekday 9:00–17:00", a
>   bedtime lock) and time-limited "spend windows" that re-shield apps automatically after a few
>   minutes; plus a `DeviceActivityReport` extension that shows the user their own screen time on
>   their own device.
>
> **Privacy:**
> - Tokens never leave the device. They are stored only in the app's App Group container on the
>   iPhone. They are never synced, uploaded, logged or sent to analytics. Our optional cloud sync
>   stores only the *name* the user gave a group of apps (for example "Social"), never which apps.
> - Screen Time usage data is never read into the app or sent anywhere. Usage charts are rendered
>   only inside Apple's `DeviceActivityReport` extension sandbox.
> - We do not sell, share or use any of this data for advertising or tracking. No ads, no ad or tracking
>   SDKs, no data brokers.
>
> **Safety — users can never be trapped:**
> - Phone calls and Emergency SOS are never blocked (system guarantee).
> - Every lock has an in-app emergency unlock that needs no goal: a press-and-hold control on the
>   Lock tab, also reachable from the shield's "Emergency unlock" button. It ends the lock and
>   removes all shields immediately.
> - If the user's subscription lapses or is refunded during a lock, ZANO removes the shields before
>   showing anything else. A billing state can never keep someone locked out of their apps.
> - Users can turn off ZANO's Screen Time access at any time in iOS Settings.
>
> **Why we need distribution:** ZANO is a consumer App Store app. We have built and tested it with the
> Family Controls (Development) capability and need the Distribution entitlement to ship it through
> TestFlight and the App Store.

## 3. Per-bundle-ID text

Paste the overview above plus the matching paragraph below into each request (or into the
"extensions" field if the form lists them together).

### `com.zano.app` — main app

> The containing app. It requests individual authorization, presents `FamilyActivityPicker` so the
> user picks their own apps, saves the selection (tokens) in its App Group on device, applies and
> removes shields with `ManagedSettingsStore` when a lock starts and ends, registers the user's lock
> schedules with `DeviceActivityCenter`, and hosts the `DeviceActivityReport` view for the user's own
> on-device screen-time summary. It also contains the always-available emergency unlock.

### `com.zano.app.ZANOShieldConfig` — Shield Configuration extension

> A `ShieldConfigurationDataSource` that customises the shield shown when the user opens one of their
> own locked apps: the ZANO mark, which goal is still open (for example "Gym session, 2 goals left"),
> and two buttons, "Show my goals" and "Emergency unlock". It only reads a small amount of state from
> the App Group (goal names and progress). No networking, no data leaves the device.

### `com.zano.app.ZANOShieldAction` — Shield Action extension

> A `ShieldActionDelegate` that handles the shield's buttons. Because a shield action cannot open the
> containing app directly, each button posts a local notification that opens ZANO on the right
> screen: the user's goals, or the emergency-unlock control. It never removes shields by itself and
> never sends data off the device.

### `com.zano.app.ZANOMonitor` — Device Activity Monitor extension

> A `DeviceActivityMonitor` that runs the user's own schedules: when a scheduled lock's interval
> starts it shields the selected apps, when it ends it removes the shield, and when a short
> user-requested "spend window" (minutes the user earned by completing goals) ends, it puts the
> shield back. It reads and writes App Group state only. No networking.

### `com.zano.app.ZANOReport` — Device Activity Report extension

> A `DeviceActivityReportExtension` that shows the user their own screen time for today (total,
> time in their locked apps, pickups, top apps) inside the ZANO app. The data stays inside the
> report extension's sandbox as Apple designed; it is never copied to the app, stored, or sent
> anywhere.

---

## 4. How to file

1. **Enroll** in the Apple Developer Program (individual or organization; organization if you want
   [COMPANY LEGAL NAME] as the seller name on the store; converting later is possible but slow).
2. **Register the identifiers** in Certificates, Identifiers & Profiles: the 5 bundle IDs above plus
   `com.zano.app.ZANOWidgets` (and `com.zano.app.watchkitapp` when the watch app ships). Turn on
   App Groups (`group.com.zano.app`) for all of them; HealthKit (with Background Delivery) and NFC
   Tag Reading for `com.zano.app`.
3. **Request the entitlement.** Find Apple's current "Family Controls (Distribution)" request page
   (search developer.apple.com for "Family Controls entitlement"; the account holder must submit
   it). Submit for `com.zano.app` and each of the 4 extensions, using §2 + §3 above. If the form
   only takes the app, say in the text that the shield configuration, shield action, device
   activity monitor and device activity report extensions need it too, and list their IDs.
4. **When approved:** the "Family Controls (Distribution)" capability becomes available for those
   identifiers. Enable it on each identifier, regenerate provisioning profiles (or let automatic
   signing / `fastlane match` do it), run `xcodegen generate`, and archive. Record the request date
   and approval date in `docs/setup/apple-developer.md`, `docs/PROGRESS.md` and the "Family
   Controls entitlement request status" line in `CLAUDE.md`.
5. **If Apple asks questions or rejects:** answer with the individual-use framing (§2). The usual
   reason for pushback is an app that looks like parental-control or employee monitoring; ZANO is
   neither. Offer a short screen recording of: picker → lock → shield → emergency unlock.

## 5. While waiting

- **Develop and test on a real device with Family Controls (Development).** In Xcode, add the
  "Family Controls" capability with the Development variant to the app and the 4 extensions (the
  generated project gets `com.apple.developer.family-controls` from `project.yml`; the development
  provisioning profile must include it). It works fully on a device; it just can't go to TestFlight
  or the App Store. Requires a Mac + iPhone; the CI Simulator can't run FamilyControls at all
  (spec §27).
- **Device checks to run while waiting** (they're also what App Review will do):
  picker → first-win 2-minute lock → shield appears → session verifies → shield lifts; a scheduled
  lock firing via ZANOMonitor; shield buttons → notification → correct screen; emergency unlock
  from the Lock tab and from the shield path; the Screen Time report rendering; the Control Center
  "Start lock" control (see the RISK in §1).
- **Everything else for submission can proceed:** App Store Connect record, IAP products,
  subscription group, listing (`docs/launch/app-store-listing.md`). A TestFlight build is *not*
  possible before approval (the app target declares the entitlement), so plan internal testing on
  development-signed devices until then.
- **Prepare the review assets:** `docs/launch/review-notes.md` and the demo recording.
