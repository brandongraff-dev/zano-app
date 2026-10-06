# Final pre-submission checklist

Written 2026-10-06 after sessions 15-25. Order matters: the slow items (Apple enrollment, the Family Controls
entitlement, a lawyer) come first because they take days to weeks and everything else waits on them.
"You" means the founder: I cannot enroll, pay, sign, or hold a device from this environment.

Legend: **[YOU]** only you can do it · **[ME]** I can build it next · **[BOTH]** you provide something, I wire it.

## A. Start today (the slow ones)

1. **[YOU] Enroll in the Apple Developer Program** ($99/yr). An organization (company) needs a D-U-N-S
   number, which can take a couple of weeks; an individual enrolls in days but the App Store then shows your
   personal name as the seller. Decide first: see `docs/setup/apple-developer.md`.
2. **[YOU] File the Family Controls (Distribution) entitlement requests the day enrollment clears.** Five
   bundle IDs (app + ShieldConfig + ShieldAction + Monitor + Report). Paste-ready text:
   `docs/launch/family-controls-request.md`. **Nothing that shields apps can go to TestFlight or the App Store
   without this**, and approval can take days to weeks. This is the critical path.
3. **[YOU] Lawyer review** of `privacy-policy.md`, `terms-of-use.md` and the age answers (13+, teens use it
   alone, the optional parent link, health-adjacent sleep and workout data). Fill every `[PLACEHOLDER]`
   (company name, contact email, address, effective date, Supabase region).
4. **[YOU] Get a real iPhone and, ideally, borrow a Mac for a day.** The lock, shield, geofence, NFC,
   HealthKit and Live Activities have never run on a device. CI proves it compiles and the logic tests pass,
   nothing more. With the entitlement and a developer account, Codemagic can build and upload to TestFlight
   with no Mac (`codemagic.yaml`); a Mac is only for the first Xcode debugging session.

## B. Things I found in the code during this review (fixed 2026-10-06)

- The Calendar permission text and the privacy policy said ZANO never reads event titles. Focus lock now
  does (on the device only). Both rewritten; this was a 5.1.1 rejection risk.
- Visible "coming soon" / "go live soon" wording (2.1, 2.3.1): Photo estimates and Family Link text reworded;
  the Family Link row is hidden in Settings until it is live. Squads are already hidden.
- The unneeded background-location mode is removed (2.5.4). **You must test a real gym arrival on a device**;
  if the geofence stops waking the app, restore `UIBackgroundModes: location` and say why in the review notes.
- The privacy label doc has a new section 7 listing what to re-answer when Family Link goes live.

## C. Still open in the code (I can do these)

- **[ME] Build with the current Xcode.** CI uses whatever Xcode the runner has (16.x) and Codemagic uses
  "latest". Apple has been requiring the newest SDK for new uploads (an Xcode 26 / iOS 26 SDK requirement
  started in 2026 as far as I know; **check Apple's "Upload builds" page for the current rule**). Moving to
  Xcode 26 may surface new Swift errors; I would fix them in one pass.
- **[ME] Sign in with Apple + auth provider**, only if you want Supabase features in 1.0 (`supabase-setup.md`
  step 9). Not needed to submit.
- **[ME] Landing pages for `/privacy` and `/terms`.** The app links to `https://zano.app/privacy` and
  `/terms`, but `landing/` only has `index.html`. **Reviewers open these links and reject if they 404.** I
  will generate them from the markdown the moment the lawyer-approved text and placeholders exist (publishing
  the draft with its placeholders would be worse than a 404). You also need a support URL/email page.
- **[ME] A final accessibility pass** (VoiceOver labels on the new tiles and cards, Dynamic Type at the
  largest sizes, Reduce Motion) and a screenshot re-take for the App Store (new buddy faces and outfits).
- **[ME] Tidy the review notes** (`docs/launch/review-notes.md` still lists the old blockers) after the above.

## D. Accounts and keys

- **[BOTH] RevenueCat:** account, the app, products (monthly, yearly with a 7-day trial, lifetime), one
  offering, the public SDK key as `REVENUECAT_API_KEY` in Codemagic. Create the same products in App Store
  Connect, then sandbox-buy each one. Without a key the paywall only offers "Continue for now" (3 days), which
  reviewers can pass but which is not a business.
- **[YOU] App Store Connect:** create the app record (`com.zano.app`), name, subtitle, primary language,
  category, price tier, banking and tax forms (paid apps and subscriptions will not go live without them).
- **[YOU] Support and privacy email**, a domain mailbox, and `zano.app` DNS pointing at the landing site.
- Optional: PostHog and Sentry keys. If you add them, the privacy policy and labels must say so.

## E. App Store Connect page (copy is in `docs/launch/app-store-listing.md`)

- Description, keywords, promo text, What's New, screenshots (6.9" iPhone is the required set; take them on
  the Simulator with the CI tour, then regenerate after any visual change).
- **Age rating questionnaire:** answer honestly (no mature content; health/wellness topics; no user-generated
  public content). Expect 12+ or 13+ style results; do not game it.
- **App Privacy answers:** `docs/launch/app-privacy-labels.md`. They must match the privacy policy and each
  target's `PrivacyInfo.xcprivacy`.
- **Review notes:** `docs/launch/review-notes.md`. Include that **no login is needed**, how the shield works,
  a screen recording of the lock/earn/emergency-unlock loop on a real device, and a plain explanation of the
  Family Controls use (the person locks their own apps; no parental control resale).
- Export compliance: HTTPS only, already marked exempt in `project.yml`.

## F. Quality gate (use TestFlight, with outside testers for a week)

1. Install on a clean phone; walk the five-minute reviewer path in `review-notes.md` section 2.
2. Lock, earn, unlock; emergency unlock from the app and from the shield; kill the app mid-lock and reopen.
3. Gym geofence arrival and departure with the app closed; Health workout appearing while the app is closed.
4. A day on a real calendar (Focus lock asks, runs, ends; your emergency unlock teaches it to stop asking).
5. Airplane mode for the whole path: unlock must stay instant and offline.
6. Low battery, Low Power Mode, a phone restart during a lock (the shield must come back).
7. Subscription: buy, restore, cancel in sandbox; delete the app and reinstall.
8. Confirm no screen shows an emoji-only dead end, a "coming soon", or text cut off at large Dynamic Type.

## G. Product-safety statements to keep true (already enforced; re-check before every release)

- Additive goals only; no calorie-cutting, weight-loss or fasting goals (spec 24).
- Emergency unlock exists on every lock-type feature, including Focus lock and context rules.
- Sleep and health suggestions say they are not medical advice and never suggest a bedtime more than 30
  minutes earlier or push after a rough stretch.
- Under-18 users are never gated by a parent; the parent link is the teen's choice and the teen can leave.
- Photos: view-once, deleted 10 minutes after the open, never used for training, never shown to a third party.

## H. Day of submission

- Version and build numbers bumped, release notes written, "Manually release" selected so you choose the
  launch moment after approval.
- Submit with the Family Controls entitlement already approved (the build will not sign otherwise).
- Be ready to reply to App Review within a day. Common first-round questions: how the shield can be
  removed (emergency unlock, shown in the recording), why Screen Time access (own apps, own choice), and the
  health data uses.
