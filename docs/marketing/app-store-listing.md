# ZANO — App Store Connect Listing (v1.0 Draft)

Source: `docs/spec.md` §1 (Vision & Positioning), §21 (Monetization & Paywall), §22 (Launch &
Content Plan), scoped to the **v1 feature set** in §4 (workout via gym geofence + HealthKit, focus
sessions, manual/NFC/schedule locking, streaks, widgets, Live Activity, emergency unlock). This
draft does **not** advertise v2/v3 goals (protein, water, squads, adaptive engine beyond the basic
plan) because they aren't shipped yet — App Review checks that the listing matches what the build
actually does, and overclaiming risks rejection or a bad first-run impression. Re-draft the
description once those ship.

Field limits below are Apple's real App Store Connect limits as of this writing; see the
**Uncertain / verify before submission** section at the bottom for anything that should be
double-checked against the current App Store Connect UI (no Mac/App Store Connect access to verify
live in this environment).

---

## App Name (30 characters)

**Recommended:**
> **Zano: Earn Screen Time** — 22/30

**Alternates:**
- "Zano: Lock In, Earn It" — 22/30
- "Zano - Screen Time You Earn" — 27/30

Rationale: Name is the single highest-weighted field for App Store search. "Earn" and "Screen Time"
are both high-intent search terms and match the core mechanic (§2 core loop) without repeating what
the subtitle already covers.

---

## Subtitle (30 characters)

**Recommended:**
> **App blocker for gym & focus** — 27/30

**Alternates:**
- "Locks apps until you train" — 26/30
- "Earn your scroll time" — 21/30

Rationale: Adds "app blocker," "gym," and "focus" — the category term people actually search, plus
the two v1 goal types — without repeating "earn," "screen," or "time" from the Name field (repeating
a word across Name/Subtitle/Keywords wastes character budget; each word only needs to appear once
across all three to be indexed).

---

## Promotional Text (170 characters)

Can be changed anytime without a new build/review — use it for what's true *this week* (a new
feature, a trial offer), not evergreen copy.

**Recommended (evergreen, safe for launch day):**
> "Distracting apps stay locked until you train or focus. Earn every unlock — no willpower, no
> calorie counting, just consistency." — 127/170

**Alternates:**
- "The app that won't let you open TikTok until you hit the gym. Lock your apps, earn them back by
  training or focusing. No willpower needed." — 138/170
- "Zano is live. Lock TikTok, Instagram, and games until you've trained or focused. Try Zano Pro
  free for 7 days." — 110/170 (best for launch-week, CTA-forward; swap to the evergreen one once
  the initial spike settles)

---

## Description (4000 characters)

**2,294/4,000 characters.**

```
The app that won't let you open TikTok until you hit the gym.

Zano locks the apps you can't stop opening — TikTok, Instagram, YouTube, games, whatever pulls you
in — until you've done the thing you actually wanted to do today. Finish a workout or a focus
session, and your apps unlock. Skip it, and they stay locked.

This isn't a calorie counter, and it isn't a habit tracker that makes you log every little thing by
hand. It's not a prison either: calls and Emergency SOS always work, and a built-in emergency unlock
means you're never actually stuck.

HOW IT WORKS
1. Pick the apps to lock — a "lock set" like Social, Games, or your own mix.
2. Set a goal: a gym workout (we check your location and Apple Health, so there's nothing to log) or
   a focus session (an honest in-app timer with your shields up).
3. Lock with a tap, an NFC tag, or a daily schedule.
4. Do the goal. Verification happens automatically, or with one tap — never a form.
5. Unlock, with a streak-building celebration.

Every time you reach for a locked app, the shield screen tells you exactly what's standing between
you and it, and how close you are. That's the moment that keeps people coming back.

WHAT YOU GET
- Real verification, not an honor system: gym geofence + HealthKit for workouts, a real timer for
  focus sessions
- Lock via manual button, NFC tag, or a daily schedule
- Home Screen and Lock Screen widgets, plus a Live Activity for focus sessions
- Streaks with a weekly freeze, so one bad day doesn't erase your progress
- Local-first — your data lives on your phone first; sync is optional

FREE
1 goal, 1 lock set, manual or NFC locking, a basic widget, and a streak freeze every week. Enough to
actually try the loop.

ZANO PRO
Unlimited goals and lock sets, scheduled locks, an adaptive plan that adjusts to how you're really
doing, and 3 streak freezes a week. 7-day free trial.

Zano never sells unlocks or streak restores. The moment money can buy your way past a goal you
didn't do, the whole thing stops meaning anything. Your Health and location data stay on your
device — we only ever see whether a goal was completed, never the details.

Built for anyone who's tired of "just have more willpower" advice and wants their phone to actually
hold them to what they said they wanted to do.
```

Notes on this draft:
- Mentions TikTok/Instagram/YouTube by name as examples of "apps people lock," which matches how
  comparable blocker apps (Opal, One Sec, Freedom) describe compatibility today. Flagged below for a
  trademark sanity check before submission — nothing here claims affiliation or endorsement.
- Deliberately avoids "digital detox," "addiction," or any outcome claim ("focus better," "lose the
  scroll habit") in the visible description per spec §24 (no health outcome claims — "consistency,"
  "focus," "discipline" only). "Digital detox" appears only in the hidden Keywords field below.
- Pricing is described by tier only (Free / Pro), not by dollar amount — §21 marks the $6.99/$39.99/
  $59.99 figures as price-test starting points, not locked prices; keeping numbers out of the
  description means this copy doesn't go stale when the price test moves.

---

## Keywords (100 characters, comma-separated)

**Recommended:**
> `habit tracker,workout,discipline,streak,self control,nfc,digital detox,accountability,willpower,lock` — 100/100

**Alternate (drop "lock," add nothing — leaves 4 chars unused, safer if "lock" is judged too close
to the Subtitle's implicit meaning):**
> `habit tracker,workout,discipline,streak,self control,nfc,digital detox,accountability,motivation` — 96/100

Rationale: no spaces after commas (saves characters; Apple's algorithm doesn't need them), no
plurals (Apple auto-matches plural/singular), and nothing that already appears in Name ("Zano,"
"Earn," "Screen," "Time") or Subtitle ("App," "Blocker," "Gym," "Focus") — repeating an already-
indexed word here just burns the 100-character budget for no extra reach.

---

## "What's New" — 3 candidate hooks for the v1.0 release

Apple's release-notes field allows up to 4000 characters; these are three different angles on the
same launch, sized like a real first-release note (300–450 characters). Pick one, or A/B across
regions if Product Page Optimization is set up later.

**A — Feature-led (safest, most literal):**
```
Welcome to Zano — v1.0.
Lock your distracting apps. Earn them back with a real workout or focus session — no manual
logging, no checkboxes. We verify with your gym location, Apple Health, and an honest focus timer.
- Lock via button, NFC tag, or daily schedule
- Home Screen + Lock Screen widgets
- Streaks with a weekly freeze
Emergency unlock always available. This is day one — tell us what to build next.
```
(408 characters)

**B — Story/positioning-led:**
```
The app that won't let you open TikTok until you hit the gym is here.
Willpower doesn't work, and habit trackers just make you do more work to open your phone less. So
we made the phone do the work: lock the apps that eat your day, unlock them by training or focusing
for real.
v1 covers workouts and focus sessions — protein, water, and sleep goals are next. Try the loop and
tell us what to build.
```
(399 characters)

**C — Direct/benefit-led:**
```
Your phone, working for your goals instead of against them.
v1.0 is live: pick the apps to lock, set a workout or focus goal, and earn your unlocks with a
streak to keep. Free to start — Zano Pro adds unlimited goals, schedules, and an adaptive plan, with
a 7-day trial.
No calorie counting. No restriction. Just consistency.
```
(325 characters)

Recommendation: **A** for the actual v1.0 submission (most literal, lowest App-Review-mismatch
risk since it only names shipped features); **B** is the strongest for the TikTok/build-in-public
audience from §22 if that same copy is reused in a launch-day social post pinned to the App Store
link.

---

## Bonus — adjacent App Store Connect fields (not explicitly requested, included since they're
part of the same submission and cheap to draft now)

### Category & age rating
- **Primary category:** Health & Fitness (matches the workout-verification core loop).
- **Secondary category:** Productivity (matches the focus-session / app-blocking angle) — reasonable
  alternative: Lifestyle.
- **Age rating:** spec §24 says "rate 17+ initially." Apple's age-rating system changed in 2025 to a
  new band set (4+ / 9+ / 13+ / 16+ / 18+ replacing the old 4+/9+/12+/17+ scale) — flagged below,
  needs a fresh pass through the actual App Store Connect age-rating questionnaire since "17+" may
  no longer be a selectable option by the time this ships.

### In-App Purchase / Subscription display metadata
Per §21's three price-test tiers (Display Name ≤ 30 chars, Description ≤ 45 chars — flagged below as
worth confirming against the live App Store Connect form):

| Product | Display Name | Description |
|---|---|---|
| Monthly | `Zano Pro Monthly` (16/30) | `Unlimited goals, schedules & plans` (34/45) |
| Annual (highlight per §21) | `Zano Pro Yearly` (15/30) | `Best value. Full Zano Pro, yearly.` (34/45) |
| Lifetime (test only) | `Zano Pro Lifetime` (17/30) | `One payment. Zano Pro, forever.` (31/45) |

### Screenshot caption ideas (first 3 — these carry the most weight before a scroll)
1. `Locked until you've trained. No exceptions.` — the shield moment (content pillar 1, §22).
2. `One tap after your workout. Unlocked.` — the celebration (content pillar 2, §22).
3. `Lock what pulls you in. NFC, schedule, or a button.` — setup flexibility.

---

## Uncertain / verify before submission

Flagging per CLAUDE.md's "search or flag, don't guess" rule — none of this was checked against a
live App Store Connect account (no Mac/App Store Connect access in this environment):

1. **IAP Display Name / Description limits (30 / 45 chars)** — this matches Apple's documented
   limits as of recent memory, but Apple has adjusted App Store Connect field limits before without
   much notice. Re-check the live form before entering these.
2. **Age rating questionnaire** — Apple rolled out a revamped age-rating system (new bands,
   different questionnaire) in 2025; whether "17+" still maps cleanly the way spec §24 assumes needs
   a fresh run through the actual questionnaire, not an assumption from this draft.
3. **Trademark mentions (TikTok, Instagram, YouTube)** in the description — common in this app
   category, but worth a quick legal sanity check alongside whatever `docs/legal/*` is doing in
   parallel (out of scope for this file — that path is owned by a concurrent workflow this run).
4. **Category choice (Health & Fitness vs. Productivity as primary)** — a judgment call based on
   spec §1/§4, not a rule; worth deciding deliberately rather than defaulting, since primary category
   affects charts and featuring eligibility.
5. **Pricing figures are placeholders** per spec §21 ("price tests... start higher than feels
   comfortable; lower if conversion is weak") — the IAP table above uses tier names, not dollar
   amounts, on purpose so it doesn't need updating when the price test moves.
