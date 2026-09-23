# ZANO Privacy Policy

> **DRAFT — needs review by a lawyer before this ships; written by an AI agent from the product
> spec, not legal advice.** Every bracketed `[ ]` placeholder below (legal entity name, governing
> jurisdiction, registered address, final contact addresses) must be filled in and the whole
> document reviewed by qualified counsel — and checked against the App Store Connect "App Privacy"
> nutrition-label questionnaire so the two match exactly — before this is linked from the App Store
> listing or the app itself. Nothing here has been reviewed by a lawyer. Source: `docs/spec.md`
> §24 (Safety, Legal & App Review) and the actual data flows implemented in this repo as of the
> date below — cited inline so a reviewer can verify each claim against real code, not just prose.

**Last updated:** September 22, 2026 (draft — not yet published)
**Applies to:** the ZANO iOS app, its widgets/extensions, and Watch companion app (together, "ZANO",
"the app", "we", "us").

---

## 1. Who we are

ZANO is published by **[Legal Entity Name — e.g. "Zano Labs LLC" or the founder's name as a sole
proprietor, whichever is actually registered with Apple as the seller of record]**, referred to
below as "ZANO," "we," "us," or "our." Our contact address for privacy questions is
**[privacy@zano.app — confirm this domain/mailbox actually exists before publishing]**. Our
registered business address is **[registered address, required in most jurisdictions for a privacy
policy to be valid]**.

If you have questions about this policy or how your data is handled, contact us at the address
above.

## 2. The short version

- ZANO is **local-first**. Most of what makes the app work — your shields, your lock sessions, your
  Health and Screen Time data — lives on your iPhone and is never uploaded anywhere.
- **Screen Time / Family Controls data cannot leave your device.** Apple's frameworks don't allow
  it, and we don't try to work around that.
- **HealthKit data stays on your device.** Only the fact that a goal was completed (not your
  underlying health data) syncs to our backend, so your streak and history are available if you
  reinstall or switch devices.
- **Location "Always" access is optional and requested only when you set up a gym**, not during
  onboarding, and only to detect gym arrival for automatic goal verification. You can decline it and
  use a manual check-in instead.
- **Meal photos are stored privately**, tied only to your account, used to estimate protein content,
  and never shared or made public.
- **We never sell your data.** Full stop.

The rest of this document explains all of that in detail.

## 3. Data we collect and how it's used

### 3.1 Account & identity

- **Sign in with Apple** (or an anonymous, on-device identity that can later be linked to Sign in
  with Apple) creates your account. We receive the opaque identifier Apple provides; if you choose
  to share your name or email through Sign in with Apple, we store only what you allow Apple to
  disclose.
- We do not require an email address or password to use ZANO.

### 3.2 Health data (HealthKit)

ZANO reads the following, with your permission, to automatically verify goals so you never have to
log them by hand:

- **Workouts** (type, duration, energy where available)
- **Heart rate** (to confirm effort during a workout and during gym dwell time)
- **Step count** (for the Steps goal and as an alarm-dismiss fallback)
- **Sleep analysis** (for the Sleep on Time goal)

The exact permission prompt you'll see (from `NSHealthShareUsageDescription`): *"ZANO reads
workouts, steps, and sleep to verify goals automatically, without you having to log them."* If you
start a workout from inside ZANO on Apple Watch, we may also write that workout back to Health
(`NSHealthUpdateUsageDescription`: *"ZANO may save workouts you start from inside the app."*).

**This data is read and evaluated on your device and is never uploaded in raw form.** What syncs to
our backend (so your account works across devices and your streak survives a reinstall) is limited
to: which goal was completed, when, and which verification method was used (e.g. "workout goal,
verified via HealthKit, 7:42 AM") — never the underlying heart-rate samples, sleep stages, or
workout routes themselves. We never sell or share HealthKit data with advertisers, data brokers, or
any third party, and we never use it for advertising.

You can revoke HealthKit access at any time in iOS Settings → Privacy & Security → Health → ZANO.
If you do, affected goals fall back to manual/one-tap verification rather than failing silently.

### 3.3 Location

ZANO uses location for one purpose: detecting when you've arrived at (and stayed at) your gym, so
your workout goal can verify itself without you opening the app.

- **"When in Use" is requested first**, at gym setup, not during onboarding. The prompt reads (from
  `NSLocationWhenInUseUsageDescription`): *"ZANO uses your location to verify gym visits so you can
  earn your apps back."*
- **"Always" access is only requested afterward, at that same gym-setup step, with an explanation of
  why** — background location lets the geofence detect arrival even when ZANO isn't open, since a
  gym visit you have to remember to open the app for defeats the point. The prompt reads (from
  `NSLocationAlwaysAndWhenInUseUsageDescription`): *"ZANO uses background location to verify gym
  visits even when the app isn't open."*
- If you decline "Always" or "When in Use" entirely, ZANO offers a **manual check-in fallback** so
  the Workout (Gym) goal is never unusable — see `docs/spec.md` §3.
- Location is evaluated as a geofence (region monitoring / `CLVisit`) on-device. We store the
  latitude/longitude/radius of gyms you've saved, tied to your account, so the geofence can be
  re-armed across devices. We do not store your continuous location history, and we do not use
  location for advertising or share it with data brokers.

### 3.4 Screen Time / Family Controls data

ZANO uses Apple's FamilyControls, ManagedSettings, and DeviceActivity frameworks to shield apps you
choose until your goals are verified.

- **Which apps you've selected to shield are represented as opaque tokens that iOS gives us — we
  never learn the actual app names/bundle IDs from those tokens, and Apple's frameworks do not
  allow that data to leave your device.** Only the *name you gave a lock set* (e.g. "Work Focus"),
  never the underlying app selection, is ever synced to our backend — and only so your lock-set
  names show up if you reinstall.
- **Screen Time usage data (how long you spent in which app) cannot leave your device — this is an
  Apple platform restriction, not a choice we're making.** It's viewable only inside an on-device
  `DeviceActivityReport` extension. We never receive it, cannot receive it, and don't ask Apple for
  an exception to that rule. Anything ZANO shows you about "time reclaimed" is computed entirely
  on-device from your own lock-session durations, not from raw Screen Time data.

### 3.5 NFC tags

If you use ZANO tags (or your own NFC tags) to log actions (start a lock, log water, dismiss the
Sunrise Alarm), we store the tag's opaque identifier and which action you mapped it to. Tags carry
no personal data and cannot be traced back to you by anyone who finds a lost tag.

### 3.6 Meal photos & protein estimates

If you use photo-based protein logging:

- Your photo is sent to a vision AI model (server-side, over an encrypted connection) to estimate
  protein content. You review and can edit the estimate before it's saved — we never log a number
  you didn't confirm.
- **Photos are stored in a private storage bucket tied only to your account.** They are not public,
  not searchable by other users, and not used to train third-party AI models beyond the one-time
  estimation call (see §4 for the vendor that call goes to). We keep photos so "Quick Repeats" can
  suggest your usual meals back to you; you can delete any saved meal (and its photo) from the app,
  which removes it from storage.
- We do not share meal photos with other users, even in Squads — squads and duels only ever see your
  aggregate goal completion, never your meal photos.

### 3.7 Motion data

Core Motion (step count, whether you're in a vehicle) is used only for anti-cheat checks (e.g.
confirming you're not "arriving at the gym" from inside a moving car) and for step-based goals and
alarm dismissal. It is evaluated on-device.

### 3.8 Usage analytics & crash reports

We use a product analytics provider and a crash-reporting provider (see §4) to understand which
screens are used and to fix bugs. These events are things like "screen viewed," "goal completed,"
"paywall shown" — counts and app behavior, not your health data, location history, or meal photos.
Crash reports may include device model, iOS version, and a stack trace; we configure our crash
reporter to exclude personal data where the tooling allows it.

### 3.9 Subscription status

If you subscribe to ZANO Pro, our subscription-billing provider (see §4) tells us your entitlement
status (active/expired, which plan) so the app can unlock Pro features. Apple handles your actual
payment details (card number, etc.) — we never see or store them.

### 3.10 Social features (Squads & Duels)

If you join a Squad or a Duel, the members you're connected with can see your daily goal-ring
progress, streak, and completion status for shared goals — not your meal photos, exact location, or
raw health data. You choose to join; leaving a squad stops sharing that data with its members going
forward.

## 4. Who we share data with

We do not sell your data to anyone, for any reason, ever.

We share limited data with the following categories of service providers, each acting on our
behalf and bound to use your data only to provide their service to us:

| Provider (role) | What they receive | Why |
|---|---|---|
| **Supabase** (database, auth, file storage, backend functions) | Account ID, goal-completion events, lock-set names, saved gym coordinates, meal photos, squad membership | Hosts our backend; Postgres row-level security restricts every table to your own account except what you explicitly share with a squad |
| **RevenueCat** (subscription management) | Anonymous purchaser ID, subscription/entitlement status | Manages App Store subscription state so Pro features unlock correctly |
| **[Vision/text LLM API provider(s) — name to be finalized]** | Meal photos (for protein estimation, one-time per photo), weekly summary statistics (for the Weekly Report Card's written line) | Powers Meal Vision (§9.5 of the spec) and the Weekly Recap Writer (§9.6); calls happen server-side, API keys never ship in the app |
| **PostHog** (product analytics) | Anonymized usage events, screen views, feature flags | Understand what's working, run A/B tests on onboarding/paywall copy |
| **Sentry** (crash reporting) | Crash stack traces, device/OS metadata | Fix bugs |
| **Apple** (Sign in with Apple, HealthKit, FamilyControls, APNs, App Store) | Whatever you choose to share via Sign in with Apple; push tokens for notifications; your purchase receipt for subscription validation | Platform services required to run the app at all |
| **Open Food Facts** (barcode lookups) | Barcode number only (not your identity) | Look up nutrition data for scanned products |

We do not use any of the above for their own advertising purposes, and none of them are permitted
to sell the data we send them.

We may disclose information if required by law, to protect the rights/safety of our users, or in
connection with a merger or acquisition of ZANO's business (in which case you'll be notified before
your data becomes subject to a different privacy policy).

## 5. Data retention & deletion

You can delete your account from within the app (Settings → Account → Delete Account) or by
emailing **[privacy@zano.app]**. Deleting your account:

- Removes your Supabase-hosted data (goal history, lock-set names, saved gyms, meal photos, squad
  membership) within **[30 days — confirm actual SLA once backend deletion jobs exist]**.
- Does **not** retroactively delete data already local to a device you've since wiped — deleting the
  app itself removes on-device data (SwiftData store, Health/Location caches) immediately.
- Cancels any active subscription's access to Pro features going forward, but does not automatically
  cancel App Store billing — cancel your subscription separately in Settings → Apple ID →
  Subscriptions, or see §5 ("Restore Purchases & Cancellation") of the Terms of Service.

We retain de-identified, aggregated analytics (e.g. "X% of users complete onboarding") after account
deletion, since it no longer identifies you.

## 6. Age requirement

ZANO is rated **17+** on the App Store and is not intended for children under 13. We do not
knowingly collect data from children under 13; if we learn we have, we will delete it. If you are
under the age required by your jurisdiction to consent to this policy on your own, please do not use
ZANO without a parent or guardian's involvement.

## 7. No restrictive health framing

ZANO's protein and water goals are **additive only** — we never set calorie ceilings, weight-loss
targets, or fasting windows, and any protein/water data you log is used only to track progress
toward a goal you set, never to calculate or suggest weight loss. See `docs/spec.md` §24.

## 8. Security

- Every Supabase table enforces row-level security (`user_id = auth.uid()`), so your data is only
  ever queryable by your own authenticated session (squad tables are additionally readable by squad
  members you've chosen to share progress with — see §3.10).
- FamilyControls app-selection tokens never leave your device — architecturally, not just by policy.
- Data in transit is encrypted (HTTPS/TLS). Meal photos and other files sit in a private storage
  bucket, not a public one.
- No system is perfectly secure; if we become aware of a breach affecting your data, we will notify
  you as required by applicable law.

## 9. International data transfers

**[Placeholder — depends on where Supabase/our sub-processors host data vs. where our users are
located; needs a real answer (e.g. Standard Contractual Clauses for EU users) once hosting regions
are finalized. Do not ship without filling this in if ZANO has EU/UK/Swiss users.]**

## 10. Your rights

Depending on where you live (e.g. under the CCPA in California, or the GDPR in the EU/UK), you may
have the right to access, correct, export, or delete your personal data, and to object to or
restrict certain processing. Most of these you can exercise directly in the app (Settings → Account
→ Export Data / Delete Account); for anything else, contact **[privacy@zano.app]**. We will not
discriminate against you for exercising these rights.

**[Placeholder — confirm final CCPA "Do Not Sell/Share My Personal Information" language is not
required given "we do not sell data" above, and add a GDPR legal-basis table if the app targets
EU/UK users at launch.]**

## 11. Changes to this policy

If we make material changes to this policy, we'll notify you in the app before the changes take
effect and update the "Last updated" date above.

## 12. Contact

**[Legal Entity Name]**
**[registered address]**
**[privacy@zano.app]**

---

*This document was drafted by an AI coding agent from `docs/spec.md` §24 and the app's actual
HealthKit/Location/FamilyControls/meal-photo implementation as of September 22, 2026, to save a
human the first pass. It is a starting point for legal review, not a substitute for it.*
