# ZANO Terms of Use

> **DRAFT FOR LAWYER REVIEW. This is not legal advice.** An AI agent wrote it on 2026-10-02 from
> the product spec and an audit of the code. A qualified attorney licensed in [STATE] must review it
> before it's published at `[WEBSITE]/terms`. That URL is already linked from Settings
> (`Core/Sources/Core/Copy/SettingsCopy.swift`).
>
> **Decide one thing before publishing.** The paywall's "Terms" link
> (`App/ZANO/Features/Onboarding/PaywallView.swift`) currently points to **Apple's standard EULA**,
> while Settings points to `zano.app/terms`. Pick one of these:
> (a) Use these Terms as a **custom EULA**. Paste them into App Store Connect → App Information →
> License Agreement, and point both in-app links at `[WEBSITE]/terms`. Apple's minimum EULA terms are
> already included in §15.
> (b) Keep Apple's standard EULA as the license, publish these as supplemental Terms of Use, and say
> so in the App Store description.
> Either way, Guideline 3.1.2 requires a working Terms/EULA link **in the app binary and in the App
> Store metadata** (description or EULA field).
>
> Older draft: `docs/legal/terms-of-service.md`. This file supersedes it.

**Effective date:** [EFFECTIVE DATE]

These Terms of Use ("Terms") are an agreement between you and **[COMPANY LEGAL NAME]**, a [STATE]
limited liability company ("ZANO", "we", "us"). They govern your use of the ZANO iPhone app, its
widgets and extensions, and (when released) the Apple Watch app (together, the "App"). By
downloading or using the App, you agree to these Terms and to our Privacy Policy at
[WEBSITE]/privacy. If you don't agree, don't use the App.

## 1. What ZANO does

ZANO helps you build habits by blocking apps you choose until you complete goals you set, such as
a workout, a focus session, steps, protein or water. ZANO uses Apple's Screen Time, Health,
Location, Motion and NFC features **on your device** to do this.

## 2. Eligibility

You must be **at least 13 years old** to use ZANO (or the age of digital consent where you live, if
higher). If you're under the age of majority where you live, you confirm that a parent or guardian
has reviewed and agreed to these Terms. You can use ZANO entirely on your own. A parent can link to a
teen's account only if the teen accepts, and ZANO does not replace Apple's Screen Time or Family
Sharing controls and isn't designed to manage another person's device.
[CONFIRM: keep in sync with Privacy Policy §9 and the App Store age rating.]

## 3. Subscriptions, free trials and payments

> These items are required by App Review Guideline 3.1.2. The paywall already shows the
> title, length, price and auto-renew/cancel wording (`PaywallCopy.termsParagraph`). This section
> must match the products configured in App Store Connect exactly.

- **Subscription required.** The App's core features need an active subscription or free
  trial. Current offers: **ZANO Pro Monthly**, [PRICE]/month; **ZANO Pro Annual**, [PRICE]/year;
  [CONFIRM: **ZANO Pro Lifetime**, [PRICE] one-time purchase, if offered]. Prices are shown in your
  local currency in the App before you buy and may vary by region.
- **Free trial.** Eligible new subscribers may get a free trial of [TRIAL LENGTH]. If you don't
  cancel at least **24 hours before the trial ends**, it converts automatically to a paid
  subscription, and your Apple ID is charged the price shown. Any unused part of a free trial is
  forfeited when you buy a subscription. Trial eligibility is decided by Apple.
- **Auto-renewal.** Payment is charged to your Apple ID account when you confirm the purchase (or
  when the trial ends). Subscriptions **renew automatically** for the same period and price unless
  you turn off auto-renew at least **24 hours before the end of the current period**. Your account
  is charged for renewal within 24 hours before the current period ends.
- **How to cancel.** Go to **Settings → [your name] → Subscriptions → ZANO** on your iPhone, or open
  **Settings → Manage subscription** in ZANO. Cancelling stops future renewals, and you keep access
  until the end of the period you paid for. **Deleting the App doesn't cancel your subscription.**
- **Refunds.** All purchases are processed by Apple. Refund requests go to Apple at
  reportaproblem.apple.com and follow Apple's policies. We can't issue refunds directly.
- **Price changes.** If we change a subscription price, Apple will notify you in advance and, where
  required, ask for your consent before the new price applies.
- **Restore purchases.** Use "Restore purchases" in the App to recover a subscription on a new
  device signed in with the same Apple ID.
- **Referral or promotional rewards** (for example free Pro time for inviting a friend) have no cash
  value, can't be transferred, and may be changed or ended at any time. [CONFIRM final referral
  terms.]

## 4. License

Subject to these Terms, we grant you a personal, non-exclusive, non-transferable, revocable license
to use the App on Apple devices that you own or control, as permitted by Apple's Usage Rules in
the App Store Terms of Service. You may not copy, modify, reverse engineer (except where the law
allows it), resell, rent, or create derivative works of the App, or use it to build a competing
product. We and our licensors own all rights in the App, the ZANO name and logo, and all content we
provide.

## 5. Your content

You own the content you create in the App, such as goal names, squad names, your leaderboard
handle, and meal photos ("Your Content"). You give us a limited license to store, process and
display Your Content **only** to operate the features you use. For example, we show your squad name
to squad members and send a meal photo you submit for an AI protein estimate. We don't use Your
Content for advertising.

## 6. Acceptable use

You agree not to:

- use squad names, handles, nudges or any other social feature to harass, threaten, impersonate or
  demean anyone, or to post unlawful, hateful, sexual or infringing content;
- spoof or tamper with goal verification in ways that affect other users (for example, falsifying
  leaderboard or duel results);
- interfere with, overload, scrape or try to gain unauthorized access to the App or our servers;
- use the App on a device you don't own or control to restrict someone else's access to their apps;
- use the App in breach of any law, or Apple's terms.

We may remove content or suspend social features for anyone who breaks these rules.
[CONFIRM WHEN SOCIAL SYNC IS LIVE: add a report/block mechanism in the App and describe it here.
App Review Guideline 1.2 requires one for user-generated content that other users can see.]

## 7. Health and safety disclaimer

**ZANO isn't a medical device and doesn't give medical, nutritional, fitness or mental-health
advice.** Goals, suggestions, recaps, plans and AI estimates are for general motivation only.

- **Talk to a doctor** before starting a new exercise, nutrition or supplement routine (including
  protein or creatine goals), especially if you're pregnant, have a medical condition, or take
  medication.
- **ZANO only supports additive goals**, things you *do* (move, focus, drink water, eat protein).
  It doesn't support, and won't add, calorie limits, weight-loss targets or fasting goals. If you
  have or are recovering from an eating disorder, please talk to a professional before using any
  nutrition tracking. You can turn on **Health Pause** at any time to stop goals and scheduled locks
  without losing your streak.
- **Stop exercising and get help** if you feel pain, dizziness or shortness of breath. Never push
  through an injury to "earn" your apps back.
- **AI estimates can be wrong.** Protein estimates from photos, barcodes or databases are
  approximations. Check and edit them.
- **Don't use ZANO while driving** or in any situation where looking at your phone is unsafe.

## 8. App blocking: how it works and its limits

- **iOS enforces the blocking, not ZANO.** ZANO asks Apple's Screen Time system to show a block
  screen over the apps you choose. You can always end a lock with **Emergency Unlock** (a 60-second
  hold in the App), and you can revoke ZANO's Screen Time access or delete the App in iOS Settings at
  any time, which removes the blocks.
- **Calls and Emergency SOS are never blocked.** Apple guarantees this. Don't rely on ZANO's blocking
  in any situation where you might need access to a particular app for safety, work, medical or
  legal reasons. Add those apps to your always-allowed list or don't block them.
- **No guarantee.** Blocking depends on Apple's frameworks, your iOS version, Screen Time settings,
  device state and permissions, which may change or fail without warning. Location, Health, NFC
  and motion checks can be delayed or inaccurate. **We don't guarantee that any app will be
  blocked, that any goal will be verified, or that ZANO will change your behavior.** A missed
  verification or a lost streak isn't a defect we're liable for. You can log many goals manually,
  and we'll do our best to correct verification bugs once we know about them.

## 9. Third-party services and hardware

The App relies on Apple services and on third-party services such as Open Food Facts and
[CONFIRM WHEN LIVE: Supabase, RevenueCat, PostHog, Sentry, Anthropic], each under its own terms.
We aren't responsible for third-party services, websites (for example Apple Maps links or
restaurant deep links), or their availability. ZANO NFC tags and other physical products are sold
under separate terms of sale. [CONFIRM: link the store terms when gear sales open.]

## 10. Changes to the App and these Terms

We may add, change or remove features at any time. If we make a material change to these Terms,
we'll tell you in the App or by other reasonable means before it takes effect. If you keep using
the App after that, you accept the new Terms. If you don't agree, stop using the App and cancel
your subscription.

## 11. Termination

You can stop using ZANO at any time: cancel your subscription through Apple, then use Settings →
Delete all my data and delete the App. We may suspend or end your access if you materially breach
these Terms, if the law requires it, or if we discontinue the App. If we discontinue the App,
we'll give reasonable notice where we can. Sections 4–5 (ownership), 7–8, 12–14 and 16 survive
termination.

## 12. Disclaimer of warranties

TO THE FULLEST EXTENT PERMITTED BY LAW, THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT
WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED. THESE INCLUDE IMPLIED WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY AND NON-INFRINGEMENT. WE DON'T WARRANT
THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE OR SECURE, THAT ANY APP WILL BE BLOCKED OR UNBLOCKED
AT A PARTICULAR TIME, OR THAT GOAL VERIFICATION OR AI ESTIMATES WILL BE ACCURATE. Some jurisdictions
don't allow certain disclaimers, so some of these may not apply to you.

## 13. Limitation of liability

TO THE FULLEST EXTENT PERMITTED BY LAW, ZANO AND ITS MEMBERS, MANAGERS, EMPLOYEES AND CONTRACTORS
WON'T BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY OR PUNITIVE DAMAGES.
THIS INCLUDES LOST PROFITS, DATA, OPPORTUNITIES, STREAKS OR ACCESS TO APPS OR CONTENT, AND ANY
INJURY FROM EXERCISE OR DIET ACTIVITIES YOU CHOOSE TO DO. OUR TOTAL LIABILITY FOR ANY CLAIM RELATED
TO THE APP IS LIMITED TO THE GREATER OF (A) THE AMOUNT YOU PAID FOR THE APP IN THE 12 MONTHS
BEFORE THE CLAIM, OR (B) US $50. Nothing in these Terms limits liability that can't be limited by
law, such as liability for death or personal injury caused by negligence (where that rule applies)
or fraud, or your statutory consumer rights.

## 14. Indemnity

You agree to indemnify and hold harmless ZANO from claims arising out of Your Content or your
breach of these Terms, to the extent permitted by law.

## 15. Apple-required terms (minimum EULA terms)

- These Terms are between you and ZANO only, **not Apple**. Apple isn't responsible for the App or
  its content.
- Apple has **no obligation to provide maintenance or support** for the App.
- If the App fails to conform to any applicable warranty, you may notify Apple, and Apple will refund
  the purchase price (if any) for the App. To the maximum extent permitted by law, Apple has no
  other warranty obligation for the App.
- ZANO, not Apple, is responsible for addressing any claims relating to the App or your use of it,
  including product liability claims, claims that the App fails to meet legal or regulatory
  requirements, and consumer protection, privacy or similar claims.
- If a third party claims the App infringes their intellectual property, ZANO, not Apple, is
  responsible for investigating, defending, settling and discharging that claim.
- You represent that you're not located in a country subject to a U.S. Government embargo or
  designated as "terrorist supporting", and that you're not on any U.S. Government list of
  prohibited or restricted parties.
- **Apple and its subsidiaries are third-party beneficiaries** of these Terms and may enforce them
  against you.
- Questions, complaints or claims about the App go to us (see §17).

## 16. Governing law and disputes

These Terms are governed by the laws of the State of **[STATE]**, USA, without regard to its
conflict-of-law rules. Disputes will be resolved in the state or federal courts located in
[COUNTY], [STATE], and you and we consent to their jurisdiction. If you're a consumer in the EU,
UK or another country whose law gives you the right to sue in your home courts or under your home
law, nothing here takes that right away.
[CONFIRM with counsel: whether to add binding individual arbitration and a class-action waiver,
and a small-claims carve-out. These are common in U.S. consumer apps but have specific notice
requirements.]

## 17. Contact

**[COMPANY LEGAL NAME]**
[REGISTERED ADDRESS], [STATE]
[CONTACT EMAIL] · [WEBSITE]

## 18. Miscellaneous

These Terms and the Privacy Policy are the entire agreement between you and us about the App. If
any provision is unenforceable, the rest stays in effect. If we don't enforce a provision, that
doesn't waive it. You may not assign these Terms without our consent. We may assign them in
connection with a merger, acquisition or sale of assets.
