# ZANO Privacy Policy

> **DRAFT FOR LAWYER REVIEW. This is not legal advice.** An AI agent wrote it on 2026-10-02 from an
> audit of the actual code in this repo. It does not rely on the product spec alone. The internal
> notes in `> blockquotes` and every `[CONFIRM …]` marker must be resolved and deleted before
> publishing at `[WEBSITE]/privacy`. That is the URL the app already links to
> (`Core/Sources/Core/Copy/SettingsCopy.swift`, `App/ZANO/Features/Onboarding/PaywallView.swift`).
>
> **How to read the markers:**
> - `[CONFIRM WHEN <SERVICE> IS LIVE]` means the code for this data flow exists but is switched off
>   in today's build, because there's no account, API key, or SDK yet. If the service is still off
>   on launch day, **delete that sentence or row**. Don't publish a description of data you don't
>   collect, and don't leave out data you do collect.
> - `[COMPANY LEGAL NAME]`, `[STATE]`, `[CONTACT EMAIL]`, `[WEBSITE]` and `[EFFECTIVE DATE]` are
>   business placeholders.
> - This policy must match the App Store Connect privacy answers in
>   `docs/launch/app-privacy-labels.md`. If you change one, change the other.
>
> This version supersedes the earlier draft at `docs/legal/privacy-policy.md`. That draft describes
> Sign in with Apple and server sync as if they were live, and neither exists in the code today.

**Effective date:** [EFFECTIVE DATE]
**Applies to:** the ZANO iPhone app and its widgets, Screen Time extensions and (when released) the
Apple Watch app. In this policy, "ZANO", "we", "us" and "our" mean **[COMPANY LEGAL NAME]**, a
[STATE] limited liability company.

---

## 1. The short version

- **ZANO is local-first.** Your goals, streaks, lock sets, gyms, NFC tag setup and history are
  stored on your iPhone, in storage shared only between ZANO's own app and extensions.
- **The apps you block stay private.** Apple's Screen Time system only gives ZANO opaque tokens for
  the apps and websites you pick. ZANO can't see which apps they are, and the tokens never leave
  your iPhone.
- **Apple Health data stays on your iPhone.** ZANO reads steps, workouts, heart rate and (for the
  sleep goal) sleep so it can check your goals automatically. We never upload raw Health data, never
  use it for advertising and never sell it. [CONFIRM WHEN SUPABASE SYNC IS LIVE: only the *result*
  of a goal check, such as "steps goal met, 10,240 steps", is backed up to our servers.]
- **Location is only used for gyms you choose to set up.** It's checked against your saved gyms on
  your device. You can always check in manually instead.
- **We don't sell your data, and we don't track you** across other companies' apps or websites.
  ZANO contains no advertising.

## 2. What we collect and why

The table covers every feature that touches personal data. "On device" means the data never
leaves your iPhone (or your paired Apple Watch). "Leaves device" names who receives it.

| Feature | Data | Why | Where it goes | Your choice |
|---|---|---|---|---|
| **Goals, streaks, lock history** | Goals you set, when you completed or missed them, focus-session lengths, Time Bank minutes, emergency unlocks, streaks, badges | To run the app: unlock your apps when you earn it and show your progress | On device. [CONFIRM WHEN SUPABASE SYNC IS LIVE: backed up to our servers (Supabase) so it survives a reinstall or new phone.] | Required for the app to work |
| **App blocking (Screen Time)** | Opaque Apple tokens for the apps, categories and websites you choose to block, plus your lock-set *names* | To show Apple's block screen until you earn access | Tokens: **on device only, always**. [CONFIRM WHEN SUPABASE SYNC IS LIVE: lock-set names (for example "Social") may be backed up. Tokens are never sent.] | Required for blocking. You can revoke Screen Time access in iOS Settings at any time |
| **Apple Health** | Read only: step count, workouts, heart rate, sleep analysis. Each is requested only when you add a goal that needs it | To verify step, workout, gym and sleep goals automatically | Raw Health data: **on device only**. [CONFIRM WHEN SUPABASE SYNC IS LIVE: the goal result and the number it was checked against (for example step total, workout minutes, "heart rate was elevated: yes/no") is backed up.] | Optional. Every goal can also be logged another way. Manage in iOS Settings → Health → Data Access |
| **Gym location** | The map location and radius (150 m by default) of gyms you save or confirm. Arrival and departure at those gyms. Your visit history, used only on-device to suggest a likely gym ("Is this your gym?") | To verify gym workouts automatically | **On device.** Geofence checks run on your iPhone through Apple's location services. [CONFIRM WHEN SUPABASE SYNC IS LIVE: if gym sync is turned on, the saved gym coordinates are backed up. Today's app does not send them.] | Optional. "When In Use" is asked for at gym setup, and "Always" only if you want automatic check-in. Manual check-in works without location |
| **Travel detection** | The last location your iPhone already knows (ZANO never starts a new location request for this), reduced to a "home area" and a distance from it | To suggest Travel Mode when you're away from home, so your goals adapt | On device. To show a city name, the coordinates are sent to **Apple's** reverse-geocoding service | Only works if you've already granted location for gyms |
| **Nearby food search** | Your last known location, if you've already granted it | To bias a "high-protein food nearby" search | Handed to **Apple Maps** when you tap the button. ZANO stores nothing | Only when you tap it |
| **Motion & Fitness** | Activity type (for example walking or driving) and, for the Sunrise Alarm, step counts | Anti-cheat: a gym visit doesn't count while you're driving, and the alarm can require you to get up and walk | On device only | Optional, through the iOS permission prompt |
| **Calendar** (opt-in) | The **number** of timed events on a day (busy-day check). If you turn on **Focus lock**: the start and end time, title and whether other people are invited, for events in the next two days, and a one-way fingerprint of an event title to remember your yes or no. Never location or notes | To go easier on your goals on packed days, and, only with Focus lock on, to lock your apps during meetings and focus blocks you choose | On device only; never uploaded | Off unless you turn it on. Revoke anytime in iOS Settings |
| **Sleep wind-down** (opt-in) | Your morning "how did you sleep" answers, the hours you slept (read from Apple Health if you allow it), and when you picked up the phone after bedtime | To show how your habits relate to your sleep and suggest a bedtime at most 30 minutes earlier | On device only; never uploaded; one button deletes it | Off unless you turn it on |
| **Family Link** (opt-in) `[CONFIRM WHEN FAMILY LINK IS LIVE]` | A parent and a teen's account IDs, the tasks a parent sets, hand-in times and, if a parent asks for proof, one photo | To let a parent set tasks and a teen hand them in | Stored on our servers (**Supabase**, `[SUPABASE REGION]`). The photo is private, can be opened once by the parent, and is deleted 10 minutes after that, or 24 hours after upload if never opened. Never used to train models or shown to anyone else | Teen must accept the link and can leave any time |
| **NFC tags** | Which ZANO tag you tapped and what you mapped it to (for example "water, 500 ml") | One-tap logging and lock/unlock | On device only | Optional |
| **Meal photos** | Photos you take or pick to log a meal or meal prep | To estimate protein and suggest quick repeats of meals you eat often | Saved on your device. [CONFIRM WHEN MEAL VISION IS LIVE: the photo is uploaded to a private storage folder only your account can access (Supabase). Our server then sends it to our AI provider (**Anthropic**, Claude API) for a protein estimate, and you confirm or edit the number.] | Optional. Manual entry always works |
| **Barcode scan** | The barcode number of a food product you scan | To look up protein per serving | Sent to **Open Food Facts** (a public, non-profit food database) along with your device's IP address and a generic app identifier. No account or user ID is sent | Optional |
| **Squads, duels, nudges, referrals, gym leaderboard** | Squad name, invite code, membership, nudges you send or receive, duel scores, referral codes, and for the leaderboard the display handle you choose | Social features you choose to join | On device in today's app. [CONFIRM WHEN SUPABASE SYNC IS LIVE: sent to our servers and visible to the other members of that squad, duel or leaderboard.] | Optional. The gym leaderboard is opt-in, and you can leave it anytime |
| **Notifications** | None collected | Reminders, alarms and "you're locked out" taps | All notifications are scheduled on your device. ZANO doesn't currently use push notifications | Manage in iOS Settings |
| **Subscriptions** | [CONFIRM WHEN REVENUECAT IS LIVE: an anonymous purchaser ID, the products you bought, and trial/renewal status] | To unlock paid features and restore purchases | Apple processes payment. We never see your card details. [CONFIRM WHEN REVENUECAT IS LIVE: **RevenueCat** manages subscription status for us.] | Required to subscribe |
| **Product analytics** | [CONFIRM WHEN POSTHOG IS LIVE: which screens you view and which features you use (for example "goal added: steps", "protein logged: 30 g", "focus started: 25 min"), a random app-generated ID, device model, OS version, app version] | To understand which features help people and to fix confusing flows | [CONFIRM WHEN POSTHOG IS LIVE: **PostHog**.] Never includes Health data, blocked-app identities, precise location or photos | [CONFIRM: describe the in-app opt-out if one is added] |
| **Crash reports** | [CONFIRM WHEN SENTRY IS LIVE: crash logs, device model, OS and app version, and a random app ID] | To find and fix crashes | [CONFIRM WHEN SENTRY IS LIVE: **Sentry**.] | — |
| **Weekly recap & coaching** | [CONFIRM WHEN WEEKLY RECAP IS LIVE: your week's goal stats] | To write your Sunday recap line | [CONFIRM WHEN WEEKLY RECAP IS LIVE: our server sends aggregate weekly stats (no name, no Health samples, no photos) to **Anthropic** to draft the line.] | [CONFIRM] |
| **Support email** | Whatever you choose to include when you email us | To help you | Our email provider [CONFIRM PROVIDER] | Optional |

**We do not collect:** your name, email address or phone number inside the app (there's no
sign-up form); contacts; microphone audio; browsing history; the identity of the apps you block;
advertising identifiers (IDFA); or payment card details.

> Internal note: the marketing website's waitlist form (`landing/index.html`) collects email
> addresses into a Supabase `waitlist_signups` table. If the website shares this policy, add a
> "Website" row: email, purpose = launch announcement, retention, and unsubscribe.

## 3. Accounts

[CONFIRM WHEN SUPABASE AUTH IS LIVE: The first time ZANO connects to our servers, it creates an
anonymous account identified only by a random ID. You don't give us an email or password.
[CONFIRM IF SIGN IN WITH APPLE SHIPS: you can link Sign in with Apple to keep your data across
devices. If you choose to share your name or email through Apple, we store only what Apple
passes to us. If you use "Hide My Email", we only see Apple's relay address.]]

> Internal note: today's code has no account system at all. There's no Sign in with Apple and no
> Supabase Auth client. If the app ships like that, replace this section with: "ZANO doesn't
> require or offer an account."

## 4. What stays on your device

These **never leave your iPhone**, in today's build or in any planned feature:

- Screen Time / Family Controls app, category and website tokens, and any Screen Time usage
  numbers. Apple's frameworks keep these on the device, and ZANO's on-device usage report runs
  inside an Apple-sandboxed extension that can't send data out.
- Raw Apple Health samples: individual heart-rate readings, step samples, workout routes and sleep
  stages.
- Calendar event details.
- Motion activity data.
- NFC tag mappings.
- Your visit history for gym auto-detection.

ZANO's widgets, Lock Screen controls, Live Activities and Screen Time extensions read your data
from storage shared only among ZANO's own components on your iPhone. They don't connect to the
internet.

**iCloud:** ZANO doesn't store your data, including Health data, in iCloud. If you use iCloud
device backups, Apple may include ZANO's on-device data in your encrypted device backup, as it
does for all apps. Health data is handled by Apple under Apple's own rules.

## 5. Who we share data with

We don't sell personal information, and we don't share it for cross-context behavioral
advertising. We only share data with these service providers ("processors"), which act on our
instructions:

| Provider | What they receive | Purpose | Status |
|---|---|---|---|
| **Apple** | Health and location processing on device; reverse-geocoding requests; payments | Platform services | Live |
| **Open Food Facts** (Open Food Facts association, France) | Scanned barcode numbers, IP address | Food database lookup | Live |
| **Supabase, Inc.** | Account ID, synced goal/streak/social data, meal photos | Database, storage and server functions. Region: [SUPABASE REGION] | [CONFIRM WHEN SUPABASE IS LIVE] |
| **Anthropic, PBC** (Claude API) | Meal photos you submit for analysis; aggregate weekly stats for recaps | AI protein estimate and recap text. Under Anthropic's commercial API terms, API inputs are not used to train models [CONFIRM current Anthropic data-retention terms] | [CONFIRM WHEN MEAL VISION / RECAP IS LIVE; confirm the provider if `ZANO_LLM_API_URL` points elsewhere] |
| **RevenueCat, Inc.** | Anonymous purchaser ID, purchase and subscription status | Subscription management | [CONFIRM WHEN REVENUECAT IS LIVE] |
| **PostHog, Inc.** | Pseudonymous usage events (see §2) | Product analytics. [CONFIRM: disable IP capture/GeoIP in PostHog project settings] | [CONFIRM WHEN POSTHOG IS LIVE] |
| **Functional Software, Inc. (Sentry)** | Crash and error reports | Crash reporting | [CONFIRM WHEN SENTRY IS LIVE] |
| **[ML SERVICE HOST]** | Pseudonymous per-user goal history features | Predicting days you're likely to slip so the app can offer an easier "Plan B" | [CONFIRM WHEN ML SERVICE IS LIVE] |

**Other users:** if you join a squad, duel or the gym leaderboard, the other participants see what
that feature shows them. That includes your handle or squad role, nudges, duel points and
consistency score. They never see your Health data, location or blocked apps.
[CONFIRM WHEN SOCIAL SYNC IS LIVE]

We may also disclose information if the law requires it, to protect someone's safety, or as part
of a merger or acquisition (and we'll notify you if that happens).

## 6. Health data commitments

In line with Apple's App Review Guideline 5.1.3 and the HealthKit terms:

- Health data is used **only** to verify your goals and show your progress.
- It's never used for advertising, marketing or data mining, never sold, and never shared with
  data brokers.
- Raw Health data is never stored on our servers or in iCloud.
- ZANO never writes false or inaccurate data to Apple Health. The iPhone app doesn't write to
  Health at all. [CONFIRM WHEN WATCH APP SHIPS: the Watch app saves workouts you start from your
  wrist to Apple Health.]
- Product analytics never include Health values.

## 7. How long we keep data

| Data | How long |
|---|---|
| On-device data | Until you use **Settings → Delete all my data** or delete the app |
| Server data (synced goals, social data) | [CONFIRM WHEN SUPABASE IS LIVE: for as long as your account exists. Deleted within [30] days of a deletion request. Backups roll off within [N] days] |
| Meal photos on our servers | [CONFIRM WHEN MEAL VISION IS LIVE: until you delete them or your account, or [PROPOSAL: 90 days], whichever comes first] |
| Analytics events | [CONFIRM WHEN POSTHOG IS LIVE: [N] months] |
| Crash reports | [CONFIRM WHEN SENTRY IS LIVE: [90] days] |
| Subscription records | As long as required for tax, accounting and App Store dispute purposes [CONFIRM: typically up to 7 years] |
| Support emails | [N] months after the conversation ends |

## 8. Your choices and rights

**Everyone, everywhere, can:**

- **Delete your on-device data in the app:** Settings → **Delete all my data**. This ends any active
  lock (so you're never left blocked), removes your goals, streaks, lock sets, gyms, tags and history
  from your iPhone, and resets the app.
  > Internal note: before launch, make this also delete the meal-photo files on the device (see
  > the audit findings in `app-privacy-labels.md` §5). Don't publish the word "photos" here until
  > it does.
- **Delete server data:** [CONFIRM WHEN SUPABASE IS LIVE: Settings → Delete account. This removes
  your server data and meal photos.] Until that exists, email [CONTACT EMAIL] and we'll delete it
  within 30 days.
- **Get a copy of your data:** email [CONTACT EMAIL]. ZANO doesn't have a self-serve export yet.
- **Withdraw permissions** (Health, Location, Calendar, Motion, Camera, Notifications, Screen Time)
  at any time in iOS Settings. Features that depend on them fall back to manual logging.
- **Cancel your subscription** in Settings → [your name] → Subscriptions. Deleting the app doesn't
  cancel it.

**EEA, UK and Switzerland (GDPR):** you have the right to access, correct, delete, restrict or object
to processing of your data, to data portability, and to withdraw consent at any time. We rely on:
*performance of our contract with you* to run the app; your *explicit consent* (given through
iOS permission prompts) for Health data (special-category data under Article 9), location, calendar
and photos; and our *legitimate interests* in keeping the app secure and working, for crash reports
and [CONFIRM: analytics, or consent if an in-app opt-in is used]. You can complain to your local
data protection authority. Our providers may process data in the United States. Where required,
transfers rely on the EU Standard Contractual Clauses or the EU-U.S. Data Privacy Framework
[CONFIRM per provider].
[CONFIRM: EU/UK representative under Art. 27, if required.]

**California (CCPA/CPRA) and other U.S. states with privacy laws:** you have the right to know,
access, correct and delete personal information, and to opt out of sale or sharing. **We don't sell
or share personal information** (as those laws define it), and we don't use sensitive personal
information (including health and precise location data) for anything other than providing the
features you asked for. We won't discriminate against you for exercising your rights. Categories
collected in the past 12 months: identifiers (random app/account IDs); commercial information
(subscription status); internet or network activity (in-app usage); geolocation (gym locations,
kept on device); sensitive personal information (health and fitness data, kept on device);
audio/visual (meal photos); inferences (likely-slip predictions). [CONFIRM per live service.]
**Washington My Health My Data Act / Nevada:** ZANO's consumer health data is collected only to
provide the service you requested, and is never sold. [CONFIRM with counsel whether a separate
Consumer Health Data Privacy Policy link is required.]

To exercise any right, email **[CONTACT EMAIL]**. We'll verify the request and respond within 30
days (45 days under CCPA).

## 9. Children

ZANO is not for young children. You must be **at least 13 years old** to use ZANO (or the age of
digital consent where you live, if higher). We don't knowingly collect personal information from
anyone under 13. People aged 13 to 17 use ZANO on their own: no public profile, no behavioural
advertising, and no sale or sharing of personal data. A parent can link only if the teen accepts. If you believe a child has given us data,
email [CONTACT EMAIL] and we'll delete it.

> Internal note on the age (founder decision 2026-10-05): **13+**, replacing 16+. Under 13 stays out
> (COPPA). Teens 13-17 use the app on their own, so teen defaults apply to every under-18 user. In EU
> countries where the age of digital consent is above 13 (up to 16) the minimum is that local age, as
> the Terms say. [UNVERIFIED: counsel must review this, and check the live App Store Connect age
> questionnaire.] Keep the Terms of Use (§2) and this section in sync.

## 10. Security

- All traffic between the app and our servers or providers uses HTTPS (TLS).
- [CONFIRM WHEN SUPABASE IS LIVE: every database table and the meal-photo storage bucket enforce
  row-level security, so an account can only read its own rows and photos. API secret keys live
  only on our server, never in the app.]
- Meal photos on your device are stored with iOS Data Protection.
- No method of storage or transmission is 100% secure. If a breach affects your data, we'll notify
  you and regulators as the law requires.

## 11. Changes to this policy

If we make a material change, such as starting to send a new type of data off your device, we'll
update this page and the date at the top, and tell you in the app before the change takes effect.
If the law requires it, we'll ask for your consent again.

## 12. Contact

**[COMPANY LEGAL NAME]**
[REGISTERED ADDRESS], [STATE]
Email: **[CONTACT EMAIL]**
Website: [WEBSITE]

> Internal note: the app currently shows `support@zano.app` (`SettingsCopy.supportEmail`) and links
> `https://zano.app/privacy` and `https://zano.app/terms`. Make sure those mailboxes and pages exist,
> or update the copy.
