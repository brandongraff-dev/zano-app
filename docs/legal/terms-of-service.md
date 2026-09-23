# ZANO Terms of Service

> **DRAFT — needs review by a lawyer before this ships; written by an AI agent from the product
> spec, not legal advice.** Every bracketed `[ ]` placeholder below (legal entity name, governing
> law/jurisdiction, arbitration clause if desired, final pricing) must be confirmed, and the whole
> document reviewed by qualified counsel, before this is linked from the App Store listing or the
> app's paywall. Source: `docs/spec.md` §21 (Monetization & Paywall) and §24 (Safety, Legal & App
> Review), and the actual subscription/emergency-unlock implementation in this repo as of the date
> below.

**Last updated:** September 22, 2026 (draft — not yet published)

These Terms of Service ("Terms") govern your use of the ZANO iOS app, its widgets, extensions, and
Apple Watch companion app (together, "ZANO," "the app," "the Service"), operated by
**[Legal Entity Name]** ("we," "us," "our"). By downloading, installing, or using ZANO, you agree to
these Terms. If you don't agree, don't use the app.

---

## 1. Eligibility

You must be at least **17 years old** to use ZANO (matching its App Store age rating), or the
minimum age of digital consent in your jurisdiction if that's higher. ZANO is not directed at
children under 13, and we do not knowingly allow anyone under 13 to create an account.

## 2. What ZANO is (and isn't)

ZANO shields apps you choose on your phone until you complete goals you've configured (workouts,
focus sessions, protein, water, sleep, and others — see `docs/spec.md` §3). You agree that:

- **ZANO is a motivation and accountability tool, not a medical device, fitness professional, or
  healthcare provider.** Nothing in the app is medical advice. Consult a physician before starting
  any new exercise, nutrition, or sleep program, especially if you have an existing health
  condition.
- **We make no health-outcome claims and none should be inferred.** ZANO does not promise weight
  loss, cure any condition, or guarantee any health result — see §24 of the product spec's
  "Content/claims" rule, which this product is built to follow. Any marketing language referring to
  "consistency," "focus," or "discipline" describes behavior, not medical outcomes.
- **ZANO's goals are additive only.** We do not offer, and will not add, calorie-restriction,
  weight-target, or fasting-window features. If a feature like that ever appears to be present,
  it's a bug, not an intended product decision — please report it.
- **The Sunrise Alarm and Bedtime Gate are not a substitute for a reliable primary alarm.** On
  devices/OS versions where ZANO uses scheduled local notifications rather than Apple's AlarmKit
  (see `docs/spec.md` §5.10), the alarm can be weaker than a dedicated alarm clock — silent mode,
  Do Not Disturb changes, or an OS update can affect delivery. **We do not guarantee ZANO will wake
  you up.** Keep a standard backup alarm, especially for anything time-critical (a flight, an exam,
  a medication schedule).

## 3. Emergency access — never trapped

- **Phone calls and Emergency SOS are never affected by ZANO's shields.** This is an Apple platform
  guarantee for apps built on FamilyControls, and ZANO relies on it rather than trying to override
  it.
- **Every lock ZANO applies has an in-app Emergency Unlock**: a 60-second hold-to-confirm gesture
  that ends the active lock immediately, without completing your goals. You may optionally spend a
  streak freeze (if available) to avoid a streak penalty, or accept the penalty — your choice, shown
  before you confirm.
- The Sunrise Alarm has its own escape hatch — a 60-second hold plus an "I'm not home" option — that
  silences the alarm unconditionally if you genuinely can't reach the dismiss tag.
- **You agree that Emergency Unlock exists precisely so you are never without access to your device
  in an emergency, and that using it is always your choice, with no penalty beyond what's disclosed
  in-app at the time.**

## 4. Subscriptions & billing

### 4.1 Plans

- **Free:** one goal, one lock set, manual/NFC-triggered locks, the basic widget, one streak freeze
  per week — usable indefinitely at no cost.
- **ZANO Pro:** unlimited goals and lock sets, scheduled locks, the adaptive difficulty engine, Earn
  Mode, photo-based protein logging, weekly recaps, squads/duels, three streak freezes, and
  cosmetics. Pricing is shown in the app and may be one of: a monthly subscription, an annual
  subscription (typically discounted vs. monthly), or — while offered — a one-time lifetime
  purchase. **Exact current prices are shown at the paywall inside the app and in App Store
  Connect's pricing, which control over any number written here.**
- We may run price experiments across users and change prices for new subscribers at any time;
  existing subscribers keep the price they agreed to per Apple's standard subscription-price-change
  notification rules.

### 4.2 Free trial

New Pro subscriptions may include an introductory free-trial period (its exact length is shown
before you start it). **We send a reminder before the trial ends and before you're charged.** If you
don't cancel before the trial ends, your subscription auto-renews at the plan's regular price via
your Apple ID.

### 4.3 Auto-renewal, cancellation & refunds

- All subscriptions are billed through **Apple's In-App Purchase system** and auto-renew unless
  cancelled at least 24 hours before the current period ends.
- **Manage or cancel your subscription any time** in iOS Settings → [your name] → Subscriptions, or
  via the link the app provides to that same screen. We do not process cancellations directly — only
  Apple can, since Apple holds your billing relationship.
- **Refunds are handled by Apple**, per Apple Media Services Terms and Conditions, not by us. We
  cannot issue refunds directly for App Store purchases.
- Your payment method, billing address, and full purchase history are held and processed by Apple —
  we never see or store your card details.

### 4.4 Restore Purchases

If you reinstall ZANO or move to a new device, use the **"Restore Purchases"** control — always
visible on the paywall screen — to reactivate a subscription you've already paid for, without being
charged again. This calls Apple's restore-purchases flow directly.

### 4.5 What we will never sell

Consistent with `docs/spec.md` §21: **we will never sell unlocks, streak restores, or anything that
lets money bypass a goal.** Cosmetics (themes, ring styles, shield backgrounds, coach-voice packs)
may be purchased or earned, but never grant an advantage over completing your actual goals. If a
future "charity stakes" feature (pledging a donation if you miss a goal) ships, it will only ever
route through a compliant third-party payment/charity provider — **we will never offer
peer-to-peer money stakes between users**, which would raise gambling/money-transmission concerns we
are not licensed for and do not intend to become licensed for.

## 5. Physical products

Tag packs, Lock Cards, shakers, and other physical merchandise referenced in the app (see
`docs/spec.md` §25) are sold through **our separate storefront (e.g. Shopify/TikTok Shop —
confirm final channel)**, not through Apple's In-App Purchase system. Purchasing physical goods is
governed by that storefront's own terms of sale, shipping policy, and returns policy, not by these
Terms — we'll link to them from Settings → Gear before you check out. Physical-product purchases are
never required to use any feature of the ZANO app itself.

## 6. Your content

- **Meal photos, custom goal notes, and any other content you create in ZANO remain yours.** You
  grant us a limited license to store and process that content solely to provide the Service to you
  (e.g. sending a meal photo to a vision AI model to estimate protein, as described in the Privacy
  Policy) — we do not use your content to train third-party foundation models beyond that per-request
  estimation call, and we do not publish your content publicly without your explicit action (e.g.
  choosing to share a Weekly Report Card image).
- **Squad/Duel content** (taunts, nudges) you send to other members is visible to those members per
  the feature's design; keep it friendly — see §7 below.
- You're responsible for what you upload. Don't upload anything illegal, someone else's private
  information without consent, or anything that infringes another person's rights.

## 7. Acceptable use

You agree not to:

- Attempt to defeat ZANO's verification/anti-cheat logic to falsely mark goals complete (e.g.
  automating fake HealthKit workouts, spoofing location, or scripting NFC taps) in a way intended to
  deceive yourself or a Squad/Duel opponent about your real progress — the point of the friction is
  honesty with yourself, and gaming it defeats the product's purpose (see `docs/spec.md` §3's
  verification philosophy).
- Use Squad, Duel, or Gym Home Turf features to harass, bully, or send abusive content to another
  user.
- Reverse-engineer, decompile, or attempt to extract FamilyControls tokens or other users' data from
  the app.
- Resell, sublicense, or use ZANO to build a competing product.
- Use ZANO in any way that violates Apple's App Store Review Guidelines or your local law.

We may suspend or terminate accounts that violate this section.

## 8. Disclaimers & limitation of liability

**[Standard SaaS/consumer-app disclaimer language — a lawyer should finalize this section's exact
wording for the target jurisdiction(s); the structure below is a placeholder, not final text.]**

TO THE MAXIMUM EXTENT PERMITTED BY LAW, ZANO IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT
WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT GEOFENCE DETECTION, HEALTHKIT VERIFICATION,
NFC READING, OR THE SUNRISE ALARM WILL FUNCTION WITHOUT INTERRUPTION OR ERROR — SEE §2's ALARM
DISCLAIMER ABOVE SPECIFICALLY. TO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR TOTAL LIABILITY FOR ANY
CLAIM RELATING TO THE SERVICE IS LIMITED TO THE AMOUNT YOU PAID US IN THE 12 MONTHS BEFORE THE CLAIM
AROSE, OR **[$100 / a fixed placeholder amount]**, WHICHEVER IS GREATER. NOTHING IN THESE TERMS
LIMITS LIABILITY THAT CANNOT BE LIMITED UNDER APPLICABLE LAW.

## 9. Termination

You may stop using ZANO and delete your account at any time (Settings → Account → Delete Account).
We may suspend or terminate your access if you violate §7, or if required by law. Sections that by
their nature should survive termination (§4.5, §6, §8, §10, §11) do.

## 10. Governing law & disputes

**[Placeholder — pick a real jurisdiction once the legal entity is registered, e.g. "the laws of the
State of Delaware, without regard to conflict-of-laws principles," and decide whether to include an
arbitration/class-action-waiver clause. This is a material legal decision, not something to leave to
an AI draft.]**

## 11. Apple as a third-party beneficiary

These Terms are between you and us, not Apple. Apple has no obligation to furnish any maintenance or
support for ZANO. In the event of any failure of ZANO to conform to any applicable warranty, you may
notify Apple, and Apple will refund the purchase price (if any) for the app to you; to the maximum
extent permitted by law, Apple has no other warranty obligation with respect to ZANO. Apple is not
responsible for addressing any claims by you relating to ZANO, including product-liability claims,
claims that ZANO fails to conform to legal or regulatory requirements, and claims arising under
consumer protection or similar legislation. Apple is not responsible for the investigation, defense,
settlement, or discharge of any third-party claim that ZANO or your possession/use of it infringes
that third party's intellectual property rights. You agree to comply with any applicable third-party
terms when using ZANO (e.g. your wireless data service agreement). Apple, and Apple's subsidiaries,
are third-party beneficiaries of these Terms, and upon your acceptance, Apple has the right (and will
be deemed to have accepted the right) to enforce these Terms against you as a third-party
beneficiary.

## 12. Changes to these Terms

We may update these Terms from time to time. If we make material changes, we'll notify you in the
app before they take effect. Continuing to use ZANO after changes take effect means you accept the
updated Terms.

## 13. Contact

**[Legal Entity Name]**
**[registered address]**
**[support@zano.app]**

---

*This document was drafted by an AI coding agent from `docs/spec.md` §21/§24 and the app's actual
RevenueCat/emergency-unlock/Sunrise-Alarm implementation as of September 22, 2026, to save a human
the first pass. It is a starting point for legal review, not a substitute for it — §10 in particular
(governing law) requires a human legal decision, not an AI guess.*
