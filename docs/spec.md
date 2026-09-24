# ZANO — Master Plan & Build Spec

> Brand name: **ZANO** — chosen Sept 22, 2026. Coined, two syllables, one pronunciation, works in all-caps on a can and as an app icon. Free-search screening found no conflicts in beverages (Class 32), supplements (Class 5), or the App Store; a 2015 defunct UK drone Kickstarter used the name (unrelated class). **Still required before printing or filing: attorney clearance search in Classes 9, 5, 32.** Taglines carry the meaning: "Tap in." / "Earn it."
>
> This file is the single source of truth. Keep it at `docs/spec.md` in the repo. Every Claude Code session starts by reading `CLAUDE.md` and this file. When you change a decision, change it here first.

---

## Table of Contents

1. [Vision & Positioning](#1-vision--positioning)
2. [The Core Loop](#2-the-core-loop)
3. [Goal Catalog & Verification](#3-goal-catalog--verification)
4. [Feature Spec (v1 → v3)](#4-feature-spec-v1--v3)
5. [Creative Features That Make It Special](#5-creative-features-that-make-it-special)
6. [Widgets, Controls, Live Activities, NFC, Siri](#6-widgets-controls-live-activities-nfc-siri)
7. [Onboarding Flow (screen by screen)](#7-onboarding-flow-screen-by-screen)
8. [Retention Psychology Rules](#8-retention-psychology-rules)
9. [Backend AI & ML Systems](#9-backend-ai--ml-systems)
10. [Food, Protein & Ordering Integrations](#10-food-protein--ordering-integrations)
11. [Architecture](#11-architecture)
12. [Tech Stack](#12-tech-stack)
13. [Data Model](#13-data-model)
14. [App Intents Catalog](#14-app-intents-catalog)
15. [Design System & UI Direction](#15-design-system--ui-direction)
16. [Image-Gen Prompts for UI Exploration](#16-image-gen-prompts-for-ui-exploration)
17. [Build Plan: Sessions for Claude Code](#17-build-plan-sessions-for-claude-code)
18. [CLAUDE.md Template](#18-claudemd-template)
19. [Session Prompt Templates](#19-session-prompt-templates)
20. [Open Source & Tooling](#20-open-source--tooling)
21. [Monetization & Paywall](#21-monetization--paywall)
22. [Launch & Content Plan](#22-launch--content-plan)
23. [Metrics & Experiments](#23-metrics--experiments)
24. [Safety, Legal & App Review](#24-safety-legal--app-review)
25. [Physical Product Bridge](#25-physical-product-bridge)
26. [Roadmap](#26-roadmap)
27. [Known Platform Gotchas](#27-known-platform-gotchas)
28. [Open Questions](#28-open-questions)

---

## 1. Vision & Positioning

**One-liner:** Your phone works for your goals instead of against them. Distracting apps stay locked until you earn them back by doing the things you actually want to do: train, hit your protein, focus, sleep, hydrate.

**The insight:** Screen-time blockers (Brick, Opal, one sec) make your phone harder to use. Habit apps make you log things. ZANO connects the two: the reward for doing the hard thing is the thing you were going to do anyway. No willpower required, no manual logging when it can be avoided.

**Who it's for (v1):** 17–27, iPhone, goes to the gym or wants to, has a protein goal, feels their phone is eating their life. Heavy TikTok/IG/YouTube use. Wants to be "locked in."

**Why now:** Gen Z discipline culture ("locked in," "monk mode," 75 Hard, running clubs) is at peak cultural relevance. iOS 17/18 shipped interactive widgets, Controls, and the Action Button, which make the "no app opening required" experience possible for the first time.

**Positioning line for the store and content:**
> "The app that won't let you open TikTok until you hit the gym."

**What it is NOT:**
- Not a calorie counter. Never restrictive goals. Only additive ones (do more of good things).
- Not a prison. Emergency unlock always exists. Calls always work.
- Not a chatbot. AI lives in the backend and shows up as the app "just knowing you."

**North-star metric:** Weekly Earned Unlocks per active user (a user completed goals and unlocked apps). Secondary: Day-30 retention, trial-to-paid conversion.

---

## 2. The Core Loop

```
   LOCK  ──►  DO THE GOAL  ──►  VERIFIED  ──►  UNLOCK + STREAK
    ▲                                              │
    └──────────────  next scheduled lock  ◄────────┘
```

**Lock triggers:**
- NFC tap (tag on desk, nightstand, gym bag, mirror)
- Schedule (e.g., 7:00 AM daily, 10:30 PM bedtime)
- Manual button / Action Button / Control Center control
- Auto (arrive home after 6 PM, leave the gym, etc. — v2)

**Goals (any combination, user-configured):** workout, focus session, protein, water, steps, creatine/supplement, morning routine (get out of bed), reading, meal prep, sleep on time.

**Unlock:** when all *required* goals for the current lock are verified, shields drop with a celebration. Partial unlocks are possible ("finish 2 of 3 goals to unlock messaging apps, all 3 for TikTok").

**Streak:** counts days with at least one earned unlock. Streak freezes and "never miss twice" rule (see §8).

**The moment that sells the app:** the custom shield screen. Every time a user reaches for TikTok they see: *"TikTok unlocks after your workout. 1 goal left. Streak: 14."* That screen is a motivator that fires 50+ times per day for free.

---

## 3. Goal Catalog & Verification

Rule: **Auto-verify if possible. One tap if not. Never a form.** Every goal has a verification tier (A = automatic, B = one tap, C = honesty + friction).

| Goal | Tier | How it's verified | Anti-cheat |
|---|---|---|---|
| Workout (gym) | A | Geofence arrival at saved gym + minimum dwell (default 35 min) + HealthKit workout OR elevated HR during dwell | Dwell time; HR/motion check; can't be in car (Core Motion automotive); parking-lot detection via GPS accuracy radius |
| Workout (home/outdoor) | A | HealthKit workout logged (Apple Watch, Strava, Nike Run Club, etc.) OR Core Motion active minutes | Min 20 min; HR if Watch present |
| Focus session | A | In-app timer (25/50/90 min) with shields active; Live Activity shows countdown | Leaving the app pauses timer; phone pickup count logged |
| Protein | B | NFC tap on shaker/tub (+ preset grams), meal photo → vision model estimate, barcode scan, quick-repeat of recent meals | Daily cap on identical NFC taps; photo dedupe |
| Water | B | NFC tap on bottle (+ bottle size), widget button | Tap rate limit (no 8 taps in a minute) |
| Steps | A | HealthKit step count vs target | None needed |
| Creatine / supplement | B | NFC tap on tub, or widget button | 1 per day |
| Morning routine / Sunrise Alarm | A | Alarm can only be dismissed by tapping the Sunrise Tag placed away from the bed (bathroom mirror / kitchen), before a cutoff. Fallbacks: N steps walked, or a 3-min timer. See §5.10 | Tag must be physically scanned (proximity); snooze limited to 1; steps fallback uses Core Motion |
| Sleep on time | A | Phone locked & no pickups after bedtime (DeviceActivity threshold) + HealthKit sleep | Pickups after bedtime break the goal |
| Reading | B | Timer session, or NFC tag inside book | Same as focus |
| Meal prep (weekly) | B | Photo of prepped containers, vision model confirms "multiple meal containers" | Weekly only |
| Stretch / mobility | B | Guided 5-min timer with device flat on floor (accelerometer check) | Device orientation |
| Cold shower / sauna | C | One tap + optional photo | Honesty; friction via 10-sec hold |
| Custom goal | C | One tap after user-set friction (hold button, short reflection prompt) | Honesty |

**Verification philosophy:** Tier C goals are allowed because the point is friction and accountability, not surveillance. Make cheating annoying, not impossible. The streak, squad visibility, and stats do the rest.

**Goal difficulty is adaptive** (see §9). Users set intent ("train 4x/week"); the engine sets the daily bar so they win ~80% of the time and climb.

---

## 4. Feature Spec (v1 → v3)

### v1 — Launch (Weeks 1–4). Prove the loop.
- Sign in with Apple; anonymous-first (no account required until sync/paywall)
- App picker (FamilyActivityPicker) with saved "lock sets" (e.g., Social, Games, All)
- Lock via: manual button, NFC tag, daily schedule
- Custom shield screen with dynamic copy (app name, goals left, streak)
- Goals: Workout (gym geofence + HealthKit), Focus session
- Gym setup: pick on map OR auto-detect suggestion ("Is this your gym?")
- Streaks with 1 freeze/week (free) / 3 freezes (paid)
- Today screen, Lock screen, Progress screen
- Home Screen widget (progress + "Start Lock" button), Lock Screen widget
- Live Activity for focus sessions
- Onboarding quiz + personalized plan + paywall (RevenueCat)
- Emergency unlock (60-second hold + streak penalty option)
- Local-first data; Supabase sync
- Analytics (PostHog), crash reporting (Sentry)

### v2 — Weeks 5–10. Make it daily.
- Goals: Protein (NFC, photo, barcode, quick-repeat), Water (NFC, widget), Steps, Creatine, Sleep on time
- **Sunrise Alarm + Bedtime Gate (§5.10)** — headline feature; AlarmKit on iOS 26+, notification fallback below
- Interactive widgets: +protein, +water, +creatine buttons
- Controls (iOS 18): Start Lock, Log Water, Log Shake; Action Button support
- Siri / Shortcuts phrases
- Fuel tab with protein ring + smart gap suggestions
- Weekly Recap (LLM-generated, card format)
- Adaptive goal engine v1 (rules-based)
- Partial unlock tiers (messaging vs social vs games)
- Bedtime lock with morning goals as key
- Share cards (streak, locked-out screen, weekly report card)
- Referral: invite a friend → both get a streak freeze

### v3 — Weeks 11–20. Make it social and smart.
- Squads (2–8 friends): see each other's rings, nudge, weekly squad streak
- Duels: 7-day head-to-head with a friend
- Seasons & ranks (Bronze → Diamond), monthly Lock-In challenges
- Slip prediction + proactive nudges (ML)
- Nudge tone optimization (bandit)
- Gym leaderboard (opt-in, by saved gym location)
- Apple Watch app + complications; auto-start focus from Watch
- Food: restaurant protein suggestions with deep links; Instacart cart from meal plan
- Travel/Comeback modes
- Trophy case, themes, cosmetics (earned with coins)
- Android (only after iOS is clearly working)

---

## 5. Creative Features That Make It Special

These are the differentiators. Build the ones marked ★ early; they're cheap and high-impact.

### 5.1 ★ The Living Shield
The block screen isn't static. It reflects state and personality:
- "TikTok unlocks after your workout. Gym is 6 min away. Streak: 14 🔥"
- After a miss: "Yesterday slipped. Never miss twice. One focus session and you're back."
- Near completion: "You're 12g of protein from unzanog everything."
- Tone matches the user's chosen coach voice (Hype / Tough Love / Chill / Data).
Shield buttons: **"Show me my goals"** (sends notification that opens the app), **"Emergency"** (starts 60-sec hold flow via notification).

### 5.2 ★ Earn Rate ("Screen Time Exchange Rate")
Instead of binary lock/unlock, users can choose **Earn Mode**: every verified goal deposits minutes into a Time Bank. A gym session = 90 min of social apps; a focus block = 30 min; hitting protein = 30 min. Unused minutes expire at midnight (no hoarding). Shows as a draining bar in the widget and Dynamic Island. This turns discipline into a visible economy and makes "I earned 2 hours today" a shareable stat.

### 5.3 ★ Lock Card (physical)
A credit-card-sized NFC card or keychain tag with the logo. Tap it to your phone to lock, tap again after goals to check status. It's the "Brick" mechanic but tied to earning, and it's your first physical product (cost ~$1, sell for $15–20 or give free with annual plan).

### 5.4 ★ Ghost Mode
Race your past self. The app shows a "ghost" of your best week: "Ghost You had already trained twice by Tuesday." Zero social pressure, pure self-competition. Very effective for people who don't want friends in the app.

### 5.5 Plan B Days
When slip prediction says today is high-risk (or the user says "rough day"), the app offers a **Plan B**: a smaller goal that still preserves the streak (20-min walk instead of gym; 25-min focus instead of 90). Half credit in Earn Mode. This is the single biggest retention lever: it stops one bad day from becoming a quit.

### 5.6 Never Miss Twice
A miss doesn't kill a streak. A second consecutive miss does. The app makes the "comeback day" feel special: bigger unlock celebration, "Comeback" badge, shield copy that acknowledges it.

### 5.7 Squads & Duels
- Squad (2–8): shared weekly ring; each member's daily rings visible; one-tap "nudge" that sends a push with the sender's face; squad streak freezes are shared (one member's freeze protects everyone once/week).
- Duel: 7-day head-to-head, points per verified goal, loser's shield shows the winner's chosen taunt for a day (opt-in, keep it friendly).
- Stakes (later, careful): pledge a donation to a charity if you miss. Do NOT do peer-to-peer money — it becomes gambling/money-transmission territory.

### 5.8 Gym Home Turf (opt-in)
Users who save the same gym form an anonymous leaderboard: "You're #4 most consistent at this gym this month." Optional handle. Works as local virality: people at the same gym discover the app from each other.

### 5.9 Seasons, Ranks, Monthly Challenges
- Ranks: Bronze → Silver → Gold → Platinum → Diamond based on 4-week consistency (not volume, so a 3x/week person can hit Diamond).
- Seasons (quarterly) reset rank with a "season badge" kept forever.
- Monthly challenges themed to fresh starts: "January Lock-In," "Summer Shred Consistency," "No-Skip November." Shareable challenge cards.

### 5.10 ★ Bedtime Gate & Sunrise Alarm (tap-to-dismiss)

**This is a headline v2 feature, not a footnote.** It's the most demoed mechanic in the whole app ("my alarm won't shut up until I walk to the bathroom") and it feeds the tag business directly.

**Bedtime Gate**
- Lock auto-arms at the user's set bedtime; phone becomes a clock.
- Optional wind-down Live Activity: "Bedtime lock in 10 min."
- Pickups after bedtime break the Sleep goal (§3) and are shown gently in the morning recap.

**Sunrise Alarm (the alarm you can only kill by getting up)**
1. Alarm fires at the set time with escalating sound/haptics.
2. The ONLY dismiss is tapping the **Sunrise Tag** — an NFC tag the user placed away from the bed (bathroom mirror, kitchen, coffee machine, fridge, shoe rack).
3. Snooze exists but costs something: 1 snooze max (5 min), or it breaks the morning goal.
4. Tapping the tag = alarm off + morning goal verified + the day's lock arms automatically.
5. Distracting apps stay locked from wake until the day's goals are earned (see §2). Getting out of bed does not buy you a scroll.
6. Escape hatch: a 60-second hold + "I'm not home" option. No one gets trapped.

**Variants (settings)**
- **Tag dismiss** (default) — Sunrise Tag.
- **Steps dismiss** — walk N steps (Core Motion) if a tag isn't available yet. Sells the tag pack: "Do it with a tag instead."
- **Focus dismiss** — 3-minute journal/stretch timer.
- **Squad alarm** — a friend gets notified if you don't dismiss within 10 min (opt-in).

**Technical path (important)**
- **iOS 26+: AlarmKit.** Apple's framework for third-party alarms that can break through silent mode and Focus, with a Live Activity–style alert UI. This is the correct implementation — verify the current API surface and entitlement requirements in Apple's docs before building.
- **iOS 17–18 fallback:** scheduled local notifications with a custom sound (≤30s each, chained), plus a Live Activity. Weaker, but acceptable as a fallback tier. Be explicit in onboarding about which tier the user's phone supports.
- Never promise "this will always wake you." Copy says "a real alarm that makes you get up," not a safety guarantee. Keep a standard-alarm reminder in the setup flow.

**Why it matters commercially:** the Sunrise Alarm is the single best reason to buy a tag pack, and the first physical product sells the second (Lock Card) and third (bottle).

### 5.11 Dynamic Island Earn Meter
During a lock, the Dynamic Island / Live Activity shows the Time Bank, goals remaining, and next scheduled lock. During gym dwell: elapsed time at the gym and "verified in 12 min."

### 5.12 Auto-Focus Integration
When a lock starts, optionally trigger an iOS Focus mode via Shortcuts automation so notifications from blocked apps also stop. One-tap setup guide.

### 5.13 Coach Voice
Chosen in onboarding, switchable anytime: **Hype** ("LET'S GO, 3 more grams"), **Tough Love** ("You said 4 days. It's Thursday. You're at 2."), **Chill** ("Whenever you're ready, the gym's open till 11"), **Data** ("Protein 72/150g. Avg completion 81% this month."). Backend picks copy variants; bandit learns which converts.

### 5.14 Weekly Report Card (shareable)
Auto-generated Sunday night: rings for the week, best day, time reclaimed, streak, rank movement, and one LLM-written line of insight. Exportable as a 9:16 image. This is the organic-content engine.

### 5.15 Time Reclaimed Counter
Because Screen Time data can't leave the device, compute on-device: hours of blocked-app time avoided during locks. Show lifetime "Time Reclaimed: 41h 20m" on the Progress tab and in the widget. People screenshot this.

### 5.16 Locked-Out Moment
When a user tries to open a blocked app 3+ times in an hour, the shield shows a special "Locked Out" card with a "Share this" option ("My phone won't let me open TikTok until I hit the gym"). Turns friction into content.

### 5.17 Trophy Case & Cosmetics
Badges for milestones (first earned unlock, 7/30/100-day streaks, 1,000g protein week, 50 gym sessions). Coins from verified goals buy themes, ring styles, shield backgrounds, and coach voice packs. Cosmetics only; never sell power (no buying unlocks).

### 5.18 Travel & Comeback Modes
- Travel mode (auto-suggested when the phone is in a new city): goals shift to walking/steps/focus, gym optional.
- Comeback mode (after 5+ days inactive): streak restart with a "3-day comeback" mini-challenge at low difficulty; no guilt copy.

### 5.19 Quick Repeats & Food Memory
Meal photos build a personal library. "Your usual chicken bowl (48g)?" appears as a one-tap suggestion at the times the user typically eats it.

### 5.20 Protein Gap Planner
At ~4 PM, if the user is behind: three concrete options ranked by proximity and effort — something in their saved kitchen staples, a nearby restaurant item with a deep link, or a quick snack. Closes the gap without opening a recipe app.

### 5.21 Apple Watch
Complication with rings; start focus/lock from the wrist; workout detection is more reliable with HR; haptic "verified" tap when the gym dwell threshold is hit.

### 5.22 Founder Series Inside the App
A "Building ZANO" feed card (optional) linking to your content. Founder-led brands win; make the founder visible without being annoying.

---

## 6. Widgets, Controls, Live Activities, NFC, Siri

All actions are **App Intents** (§14). Build each once, reuse everywhere.

**Home Screen widgets (WidgetKit, interactive since iOS 17)**
- Small: streak + lock status + "Start Lock" button
- Medium: 3 goal rings + buttons: "+25g", "+500ml", "Start Focus"
- Large: Today's plan, Time Bank, next lock time, quick actions

**Lock Screen widgets**
- Circular: protein ring / water ring / streak
- Rectangular: "2 goals left · TikTok locked · 14🔥"
- Inline: "Locked until workout"

**Controls (iOS 18+)**
- Toggle: Lock On/Off (with confirmation for Off)
- Buttons: Log Water, Log Shake, Start Focus, Log Creatine
- Assignable to Lock Screen bottom corners and the Action Button

**Live Activities (ActivityKit)**
- Focus session: countdown, pause, end
- Gym dwell: "At the gym · 22 min · verified at 35"
- Active lock (Earn Mode): Time Bank draining bar

**NFC (Core NFC + Shortcuts)**
- App reads NDEF tags. Each tag encodes a URL like `zano://tag/<uuid>` mapped to an action in-app (Lock, Log Water 750ml, Log Shake 25g, Sunrise Key, Creatine).
- Background tag reading: iPhone shows a notification → tap → app runs the action. For truly no-touch logging, guide users to create a Shortcuts Automation ("When NFC tag is scanned → Run ZANO: Log Water") — one screen, 20 seconds.
- Ship a printable "tag setup" guide and sell tag packs (§25).

**Siri / Shortcuts**
- App Shortcuts with phrases: "Lock in with ZANO", "Log a shake", "Log water", "How am I doing today"
- Expose parameters (grams, ml, minutes)

---

## 7. Onboarding Flow (screen by screen)

Target: 10–14 screens, under 3 minutes, paywall at peak motivation. Every screen has one job.

1. **Hook** — Full-bleed. "Your phone is fighting your goals. Let's flip that." CTA: "I'm ready."
2. **Social proof strip** — 3 rotating quotes (real ones once you have them; placeholder copy marked clearly until then).
3. **Q1: Main goal** — Get consistent at the gym / Hit my protein / Stop doomscrolling / Lock in on work-school / All of it.
4. **Q2: Which apps steal your time?** — Native FamilyActivityPicker styled into the flow. (This is also the permission request; prime it with one sentence first.)
5. **Q3: Daily phone time** — Slider 1–10h.
6. **Q4: Current vs target workouts/week** — Two steppers.
7. **Q5: When do you usually fall off?** — Weekends / Evenings / When stressed / After a few good days / Travel. (Feeds slip prediction cold start.)
8. **Q6: Coach voice** — Hype / Tough Love / Chill / Data, each with a sample line.
9. **Wake-up moment** — Compute: "At 5h/day, that's ~76 days a year on your phone." Then: "Earning even 2h back = 30 days a year." Animated counter.
10. **Plan reveal** — "Your Lock-In Plan": locked apps, goals, schedule, starting difficulty (deliberately below stated target). Looks bespoke. "Built for you in 2:14."
11. **Commitment** — "Hold to commit" 2-second press with haptics. Records `committed_at`.
12. **Paywall (hard)** — Sits directly after Commitment, at peak motivation. Free trial (7 days) with "we'll remind you 2 days before it ends." Annual highlighted. **There is no free path: the app cannot be used without starting the trial or subscribing** (decision 2026-09-23, replaces the earlier "Continue with limited free" option). Must show a restore-purchases link and a dated trial timeline. See §21.
13. **Permission priming** — Notifications (one screen: "We'll only nudge when it matters"). Moved after the paywall (decision 2026-09-23) so nothing sits between the peak and the payment ask. Location and Health are requested later, at gym setup, not here.
14. **First win** — "Start your first lock now. 10-minute focus to unlock." Immediate loop completion. Streak = Day 1. Confetti. Prompt to add the Home Screen widget with an animated guide.

Post-onboarding drip (Day 0–3 pushes): widget added? gym saved? NFC tag ordered/created? first squad invite?

---

## 8. Retention Psychology Rules

Codify these so every feature obeys them.

1. **Early wins are engineered.** First 3 days' goals are ~70% of stated capability. The engine raises the bar only after wins.
2. **Progress is always partially filled.** Never show an empty checklist; show rings with the day's context ("2 of 3").
3. **Streaks have forgiveness.** Freezes, Never Miss Twice, Plan B, Comeback mode. A streak should feel protective, not fragile.
4. **Variable reward at the unlock.** 1 in ~6 unlocks triggers a surprise (badge, coin bonus, milestone animation, coach voice line). Keep it tasteful.
5. **Identity framing.** After 3–4 consistent weeks, copy shifts from tasks to identity: "You're a consistent lifter now." Weekly recap reinforces it.
6. **Fresh-start timing.** Push challenges on Mondays, the 1st, after holidays, and on the user's birthday.
7. **Nudge scarcity.** Max 2 proactive pushes/day. A nudge must change what the user does tonight or it doesn't send.
8. **Effort asymmetry.** Value out ≫ effort in. Any interaction over 2 taps needs a reason.
9. **No shame.** Copy never says "you failed." Misses are "slipped," always followed by the next smallest step.
10. **Loss aversion, ethically.** Show what's at stake (streak, rank, Time Bank) before a lock, never as a threat after a miss.
11. **Endowed progress.** Streak starts at Day 1 after onboarding's first win. New challenges start with a "head start" for existing users.
12. **Friction is the feature, but only where the user asked for it.** Locks are hard to escape by the user's choice; everything else is frictionless.

---

## 9. Backend AI & ML Systems

Invisible to the user. Start rules-based, replace with models as `goal_events` grows.

### 9.1 Adaptive Goal Engine (highest priority)
- **Input:** user intent (target/week), 28-day completion history per goal, day-of-week effects, recent streak, sleep (if available).
- **v1 (rules):** target completion rate 75–85%. If 7-day rate < 60% → lower the daily bar one step (fewer minutes / fewer days / lower grams). If > 90% for 10 days → raise one step. Never change more than one step per week.
- **v2 (bandit):** per-user contextual bandit over difficulty levels; reward = completed AND retained next day. Thompson sampling.
- **Output:** `daily_plan` rows.

### 9.2 Slip Prediction
- **Label:** did the user miss all goals on day D?
- **Features:** DOW, days since last miss, streak length, yesterday's completion, sleep hours, calendar density (if Calendar access granted), weather, travel flag, hour-of-first-app-open, historical miss pattern from onboarding Q5.
- **Model:** gradient-boosted trees (LightGBM). Cold start: logistic regression on onboarding answers + population priors.
- **Action:** risk > threshold at 9 AM → offer Plan B in the widget and shield copy; schedule a nudge at the user's historically best action hour.

### 9.3 Nudge Optimizer
- Arms: tone (4) × timing slot (morning / pre-gym window / 4 PM / evening) × format (push / widget copy / shield copy).
- Reward: goal completed within 3 hours of nudge.
- Per-user bandit with population prior. Respect the 2/day cap.

### 9.4 Gym Auto-Detection
- Cluster `CLVisit`s (DBSCAN on lat/lon, min dwell 40 min, recurring ≥ 2×/14 days) → candidate places. If HealthKit HR was elevated during visits → confidence up. Ask once: "Is this your gym?" Store as geofence.
- Anti-cheat: dwell inside radius, Core Motion not automotive, optional HR.

### 9.5 Meal Vision
- Photo → vision LLM prompt returning strict JSON: `{items:[{name, grams_protein_est, confidence}], total_protein, notes}`. User confirms/edits with a slider. Confirmed values are stored as the user's "food memory"; embeddings of the photo + name enable Quick Repeats.
- Only protein (and optionally calories as a soft number, hidden by default). No restrictive framing.

### 9.6 Weekly Recap Writer
- Sunday 6 PM job: aggregate the week, call an LLM with a strict template (max 60 words, coach voice, one specific win, one specific suggestion, no shame). Store as a card; render as shareable image on device.

### 9.7 Schedule & Travel Awareness
- New city detection (coarse) → Travel mode suggestion. Calendar density (opt-in) → suggest lighter goals on packed days.

### 9.8 Anti-Cheat Signals
- Rate limits on taps; identical-photo detection (perceptual hash); geofence dwell/motion checks. Never accuse — just don't count, and show "not counted: too quick" transparently.

### 9.9 Data pipeline
- `goal_events` is the training table. Nightly job materializes `user_day` features. Keep everything in Postgres until scale forces otherwise. Python ML service (FastAPI) exposes `/plan`, `/risk`, `/nudge` endpoints; Edge Functions call it.

---

## 10. Food, Protein & Ordering Integrations

- **Barcode → product:** Open Food Facts (free, open). Fallback to a commercial nutrition API if coverage is poor.
- **Restaurant menus:** a nutrition API with chain menu data (e.g., Nutritionix — verify current terms/pricing). Combine with location → "Chipotle chicken bowl, 6 min away, +51g." Deep link to the restaurant app / DoorDash / Uber Eats search URL. Full in-app ordering is not realistic (consumer ordering APIs are restricted); deep links are the plan.
- **Grocery:** Instacart Developer Platform lets apps push recipes/shopping lists into an Instacart cart (verify current availability). Weekly meal plan → cart in one tap.
- **Kitchen staples:** user saves 10–20 staples once; the gap planner uses them first.
- **Meal prep plan:** LLM generates weekly plan from protein target, budget, cooking skill, dislikes → shopping list → Instacart.
- **Brand bridge:** log which products people use to hit protein (barcodes). This is market research for §25.

---

## 11. Architecture

**Principle: local-first. Unlock must be instant and offline.** The backend never sits between a user and their unlock.

```
iPhone
├── ZANO (main app, SwiftUI)
├── ZANOWidgets (WidgetKit: widgets, Controls, Live Activities)
├── ZANOShieldConfig (ShieldConfigurationDataSource)
├── ZANOShieldAction (ShieldActionDelegate)
├── ZANOMonitor (DeviceActivityMonitor: schedules, thresholds)
├── ZANOReport (DeviceActivityReport: on-device screen-time views)
├── ZANOWatch (watchOS app, v3)
└── Core (Swift Package, shared by all targets)
    ├── Models (SwiftData)
    ├── Store (App Group container, shared UserDefaults + SwiftData)
    ├── Intents (App Intents)
    ├── Verification (gym, focus, health, nfc)
    ├── LockEngine (shields, schedules, unlock rules, Time Bank)
    └── Sync (Supabase client, outbox pattern)

Backend (Supabase)
├── Postgres (RLS on every table)
├── Auth (Sign in with Apple, anonymous → linked)
├── Storage (meal photos, private bucket)
├── Edge Functions (TypeScript): meal-vision, weekly-recap, sync, webhooks (RevenueCat)
└── pg_cron jobs: nightly features, Sunday recaps

ML Service (Python/FastAPI, later)
└── /plan  /risk  /nudge   (called by Edge Functions)
```

**Data flow:** every user action → App Intent → Core → SwiftData (App Group) → widgets/shield read state instantly → Sync outbox pushes to Supabase when online → backend jobs write plans/recaps back → app pulls on launch and via silent push.

**Extensions must be tiny.** No network in Shield extensions. Read state from the App Group only.

---

## 12. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| App | Swift 6, SwiftUI, Observation framework | Only native has FamilyControls/Widgets/Controls/NFC/ActivityKit |
| Min iOS | 17 (Controls gated to 18) | Interactive widgets need 17 |
| Local DB | SwiftData in App Group | Shared across extensions |
| Bzanog | FamilyControls, ManagedSettings, DeviceActivity | Apple's Screen Time APIs (entitlement required) |
| Location | Core Location (region monitoring, CLVisit, CLMonitor) | Gym geofence |
| Health | HealthKit (workouts, HR, steps, sleep) | Verification |
| Motion | Core Motion | Anti-cheat, active minutes |
| NFC | Core NFC (NDEF) + Shortcuts automations | Tags |
| Widgets | WidgetKit + App Intents; ControlWidget (iOS 18) | No-open logging |
| Live Activities | ActivityKit | Focus/gym/earn meter |
| Animations | Lottie (airbnb/lottie-ios) | Unlock celebration, milestones |
| Subscriptions | RevenueCat (+ optional Superwall for paywall A/B) | Fast, tested |
| Backend | Supabase (Postgres, Auth, Storage, Edge Functions, pg_cron) | Speed |
| AI APIs | Vision + text LLM APIs, called server-side only | Keys never on device |
| ML | Python, LightGBM, FastAPI (v3) | Adaptive engine, slip risk |
| Analytics | PostHog | Funnels, retention, feature flags |
| Crash | Sentry | |
| Push | APNs via Supabase Edge Function | Silent pushes for plan updates |
| CI | Xcode Cloud or GitHub Actions + fastlane | TestFlight in one command |
| Design | Figma (or Claude Design) + SF Symbols + one variable font | |

Do not use React Native / Flutter / Expo for this app.

---

## 13. Data Model

Local (SwiftData) and remote (Postgres) share the same shapes. UUIDs everywhere. All timestamps UTC + user timezone stored on user.

```sql
users            (id, apple_sub, created_at, tz, coach_voice, plan_tier, referral_code, referred_by)
goals            (id, user_id, type, title, target_value, unit, cadence, verification_tier,
                  active, adaptive, created_at)
daily_plans      (id, user_id, date, goal_id, planned_value, difficulty_step, plan_b_value, source)
goal_events      (id, user_id, goal_id, ts, kind, value, source, verified, meta jsonb)
                  -- kind: log|verify|complete|miss|plan_b|freeze ; source: nfc|widget|photo|
                  -- barcode|geofence|healthkit|timer|manual|siri
lock_sets        (id, user_id, name, app_tokens_blob, is_default)   -- opaque tokens stay on device
lock_sessions    (id, user_id, lock_set_id, started_at, ended_at, trigger, mode, required_goal_ids[],
                  unlock_kind)  -- unlock_kind: earned|emergency|schedule_end|manual
time_bank        (id, user_id, date, earned_min, spent_min)          -- Earn Mode
streaks          (user_id, current, best, freezes_left, last_earned_date, never_miss_twice_armed)
gyms             (id, user_id, lat, lng, radius_m, name, auto_detected, confirmed)
meals            (id, user_id, ts, photo_path, items jsonb, protein_g, confirmed, embedding vector)
squads           (id, name, created_by, invite_code) ; squad_members (squad_id, user_id, role)
duels            (id, a_user, b_user, start_date, end_date, a_points, b_points, status)
badges           (id, user_id, key, earned_at) ; coins (user_id, balance)
recaps           (id, user_id, week_start, text, stats jsonb, image_path)
nudges           (id, user_id, ts, arm jsonb, delivered, acted_within_3h)
risk_scores      (user_id, date, p_miss, model_version)
subscriptions    (user_id, rc_customer_id, status, product, renews_at)   -- from RevenueCat webhook
```

Rules: RLS = `user_id = auth.uid()` on everything; squad tables readable by members. FamilyControls app tokens never leave the device (store blob locally only; remote stores only lock-set names).

---

## 14. App Intents Catalog

Each is one Swift struct used by widgets, Controls, Siri, Shortcuts, NFC, and the app.

| Intent | Params | Effect |
|---|---|---|
| `StartLockIntent` | lockSet, mode (full/earn), requiredGoals | Applies shields, opens lock_session |
| `EndLockIntent` | reason | Only allowed if goals complete or via Emergency flow |
| `EmergencyUnlockIntent` | — | 60-sec hold in app; records unlock_kind=emergency |
| `StartFocusIntent` | minutes | Starts timer + Live Activity, shields on |
| `EndFocusIntent` | — | Verifies if ≥ planned minutes |
| `LogProteinIntent` | grams, source | Writes goal_event |
| `LogWaterIntent` | ml, source | Writes goal_event |
| `LogCreatineIntent` | — | 1/day |
| `LogCustomGoalIntent` | goalId | Tier C with friction |
| `SunriseKeyIntent` | tagId | Verifies morning routine before cutoff |
| `CheckStatusIntent` | — | Returns spoken/summary status for Siri |
| `QuickRepeatMealIntent` | mealId | Logs remembered meal |
| `OpenTodayIntent` | — | Deep link |

NFC tag URL scheme: `zano://tag/<uuid>` → mapped in-app to one of the above with saved params.

---

## 15. Design System & UI Direction

**Feel:** dark, confident, game-progress energy without being childish. Think: fitness tracker × ranked mode in a game × premium minimal.

**Tokens (starting point, tune after image-gen exploration)**
- Background: `#0A0A0B` ; Surface: `#141416` ; Surface-2: `#1C1C1F`
- Text: `#F5F5F7` ; Muted: `#8E8E93`
- Accent (earned/unlock): `#B8FF3C` (acid green) — ONE accent only. **Earned states only** (decision 2026-09-24): completed rings, the unlock moment, "Earned" badges. Never on navigation or chrome (tab bar, neutral buttons, icons), which stay achromatic so goal colors carry the screen. See `docs/design/premium-ui-plan.md`.
- Danger/locked: `#FF453A` ; Warning: `#FFB020`
- Ring colors: workout = accent, protein = `#FF7A00`, focus = `#5E5CE6`, water = `#32ADE6`
- Radius: 12 / 20 / 28 ; Spacing scale: 4, 8, 12, 16, 24, 32
- Type: SF Pro (or one variable display font for numerals, e.g., a condensed grotesque); big numerals for grams/minutes/streak
- Motion: spring animations; ring fills ease-out 600ms; unlock celebration ≤ 1.2s; haptics on every verified event

**Core components (build first, in Core/UI):** `GoalRing`, `RingCluster`, `LockStatusCard`, `StreakPill`, `TimeBankBar`, `PrimaryButton` (hold-to-commit variant), `ShieldPreview`, `GoalRow`, `RecapCard`, `ShareCard` (9:16 renderer), `OnboardingQuestion`, `PaywallCard`.

**Screens:** Today, Lock, Fuel, Progress, Squad, Settings, Onboarding (14), Paywall, Gym Setup, NFC Setup, Shield (extension), Widgets (S/M/L, lock screen), Live Activities.

---

## 16. Image-Gen Prompts for UI Exploration

Use image generation for **direction**, not final pixels. Generate 4–6 variants, pick one, then reuse the same style paragraph in every prompt. Feed the winners to Claude with the tokens above to build real SwiftUI components.

**Style paragraph (paste into every prompt after choosing):**
> Premium dark-mode iOS app, deep black background, one vivid acid-green accent, large rounded progress rings, chunky bold numerals, generous spacing, subtle inner glow on active elements, crisp 1px hairline dividers, SF Pro–like typography, no clutter, realistic iPhone 15 Pro frame, high fidelity, no lorem ipsum.

**P1 — Today screen**
> iPhone app screen "Today" for a discipline app where users earn back distracting apps by completing goals. Top: streak pill "14 🔥" and lock status card "Locked · TikTok, Instagram, YouTube" with a small padlock. Center: three progress rings labeled Workout, Protein (72/150g), Focus (25/50 min). Bottom: a single primary button "Go to gym · 6 min away". Tab bar: Today, Lock, Fuel, Progress, Squad. [style paragraph]

**P2 — Custom shield / block screen**
> Full-screen iPhone block screen shown when the user tries to open TikTok. Centered app icon dimmed with a padlock, headline "TikTok unlocks after your workout", subline "1 goal left · Streak 14", two buttons "Show my goals" and a small text "Emergency". Dark, calm, motivating, not punishing. [style paragraph]

**P3 — Unlock celebration**
> iPhone screen at the moment of earning apps back: burst of acid-green particles, headline "Earned.", subline "Workout verified · 42 min at the gym", a Time Bank bar filling to "2h 10m unlocked", small badge "Comeback" appearing. [style paragraph]

**P4 — Onboarding plan reveal**
> iPhone screen "Your Lock-In Plan" shown as a bespoke card: locked apps row with icons, goals list (Gym 3x/week, Protein 150g, Focus 50 min), schedule "Locks at 7:00 AM", difficulty tag "Starting easy on purpose", a hold-to-commit button at the bottom with a progress outline. [style paragraph]

**P5 — Paywall**
> iPhone paywall for a discipline app: headline "Earn your phone back", three benefit rows with icons (Unlimited goals & lock sets, Adaptive plan that learns you, Squads & duels), annual plan card highlighted "$39.99/yr · 7 days free", monthly option smaller, note "We'll remind you before your trial ends", a restore-purchases text link (no free-path link: hard paywall, decision 2026-09-23). [style paragraph]

**P6 — Widgets**
> Apple Home Screen with a medium widget for a discipline app: three small rings and three buttons "+25g", "+500ml", "Start Focus"; and a small widget showing "Locked · 2 goals left · 14🔥". Also show a Lock Screen with circular ring widgets. [style paragraph]

**P7 — Weekly Report Card (share format)**
> 9:16 shareable card: "Week 6 · Rank Gold", 7 columns of daily rings, stats "4 workouts · 1,020g protein · 6h 40m time reclaimed", one line "Best day: Thursday", small logo bottom right. Dark with acid green. [style paragraph]

**P8 — Live Activity / Dynamic Island**
> iPhone Lock Screen showing a Live Activity for a focus session: "Focus · 31:20 left", pause/end buttons, small Time Bank bar; plus the compact Dynamic Island state with a ring and timer. [style paragraph]

After picking: ask Claude to "extract a design system (colors, type scale, spacing, radii, component list) from these mockups, reconcile with the tokens in spec §15, and output `Core/UI/Theme.swift`."

---

## 17. Build Plan: Sessions for Claude Code

Do Session 0 and 1 first, alone. Then parallelize on branches. Each session has a definition of done; don't start the next until done is true on a real device where applicable.

| # | Session | Branch | Done when |
|---|---|---|---|
| 0 | Repo, CLAUDE.md, spec, Xcode project with all targets, App Group, Core package, CI to TestFlight | `main` | Empty app builds & ships to TestFlight |
| 1 | Data models (SwiftData), Store, outbox Sync skeleton, PostHog/Sentry | `feat/core` | Models compile, events persist across extension boundaries |
| 2 | Lock Engine: FamilyActivityPicker, lock sets, shields on/off, DeviceActivity schedules, Shield Config + Action extensions, emergency unlock | `feat/lock` | Real device: pick apps → lock → custom shield → unlock |
| 3 | Verification: gym geofence + dwell + HealthKit check, auto-detect suggestion, focus timer + Live Activity, Core Motion anti-cheat | `feat/verify` | Gym visit auto-verifies; focus session verifies |
| 4 | App Intents catalog + widgets (S/M/L, lock screen) + Controls + Siri phrases + NFC reader & tag mapping | `feat/intents` | Log water from widget without opening app; NFC tag starts lock |
| 5 | Design system + screens: Today, Lock, Fuel (protein/water), Progress, Settings | `feat/ui` | All screens navigable with real data |
| 6 | Onboarding (14 screens) + permission priming + RevenueCat paywall + first-win flow | `feat/onboarding` | New install → paywall → first earned unlock in < 4 min |
| 7 | Supabase: schema, RLS, auth (anon → Apple), storage, sync Edge Function, RevenueCat webhook | `feat/backend` | Two devices sync; subscription status reflects in app |
| 8 | AI: meal-vision Edge Function, quick repeats, weekly recap job + card + share image | `feat/ai` | Photo → protein estimate → confirm; Sunday recap appears |
| 9 | Streak logic: freezes, Never Miss Twice, Plan B, Comeback; adaptive engine v1 (rules) | `feat/retention` | Simulated 30-day history behaves per §8/§9 |
| 10 | Earn Mode (Time Bank), Dynamic Island earn meter, partial unlock tiers | `feat/earn` | Bank earns/spends/expires correctly |
| 11 | Squads, duels, nudges, referral, share cards, Locked-Out moment | `feat/social` | Two accounts see each other's rings |
| 12 | ML service: slip risk + nudge bandit; pg_cron feature job | `feat/ml` | /risk returns scores; nudges log outcomes |
| 13 | Watch app, gym leaderboard, seasons/ranks, cosmetics | `feat/v3` | — |

**Ordering rule:** 5 depends on 1 and 4's intents; 6 depends on 5; 7 can run in parallel with 2–5 once §13 is frozen. Freeze §13 before splitting.

**Every session:** ask for a plan first → approve → implement → run on device → write a short `docs/sessions/NN.md` with what changed and known issues → merge.

---

## 18. CLAUDE.md Template

```markdown
# ZANO — project guide for Claude Code

## What this is
iOS app: distracting apps are shielded until the user completes verified goals
(workout via gym geofence + HealthKit, focus sessions, protein/water via NFC/widgets/photo).
Local-first. Unlock must be instant and offline. See docs/spec.md for everything.

## Architecture
- Targets: ZANO (app), ZANOWidgets, ZANOShieldConfig, ZANOShieldAction,
  ZANOMonitor, ZANOReport. Shared code lives ONLY in the `Core` Swift package.
- App Group: group.com.zano.app — SwiftData store + shared UserDefaults live here.
- Every user action is an App Intent in Core/Intents. Widgets/Controls/Siri/NFC call intents; never duplicate logic.
- Extensions: no networking, no heavy work, read App Group state only.
- Backend: Supabase. API keys live only in Edge Functions. Never put secrets in the app.
- FamilyControls tokens never leave the device.

## Conventions
- Swift 6 strict concurrency, SwiftUI, @Observable. No UIKit unless required by an API.
- Folder per feature: Feature/{View,Model,Service}. Tests in CoreTests.
- Copy lives in Core/Copy (coach voices). No hardcoded strings in views.
- No restrictive goals (calories down, weight loss). Additive goals only.
- Emergency unlock must always exist.

## Build & test
- `xcodebuild -scheme ZANO -destination 'platform=iOS' build`
- FamilyControls, DeviceActivity, Core NFC, HealthKit do NOT work in the Simulator. Use a real device.
- Family Controls entitlement request is pending/approved: <status>.
- Run `swift test --package-path Core` for unit tests.

## Working rules
- Read docs/spec.md before any task. Cite the section you're implementing.
- Propose a plan and file list first; wait for approval before writing code.
- Keep PRs to one session scope. Update docs/sessions/NN.md at the end.
- If an Apple API is uncertain, search Apple docs / sample code rather than guessing.
- For FamilyControls, ManagedSettings, DeviceActivity, or Shield extension work, read
  docs/references/ios-screen-time first and mirror its target and entitlement setup.
  Reference repos are read-only: adapt patterns, never paste, and respect licenses.
```

---

## 19. Session Prompt Templates

**Generic session prompt**
```
Read CLAUDE.md and docs/spec.md (sections §2, §3, §11, §13, §14).

Task: Session <N> — <name>.

Scope:
- <bullet list from §17>

Constraints:
- Shared logic in Core. Extensions read App Group only.
- Follow §8 and §24 rules where relevant.

Definition of done:
- <from §17>

Step 1: give me a plan with the exact files you'll create/modify and any Apple APIs you'll use, with a note on anything that needs a real device or an entitlement. Wait for approval.
```

**Design-system session**
```
Read docs/spec.md §15. Attached are 3 chosen mockups.
Extract a design system reconciled with §15 tokens. Output Core/UI/Theme.swift,
Core/UI/Components/* for the component list in §15, and a Previews catalog screen
that renders every component in light and dark. Then build the Today screen from
the mockup using only these components.
```

**Bug/feature follow-up**
```
On device, <observed behavior>. Expected: <expected>. Relevant spec: §<n>.
Investigate, explain the root cause in 3 lines, propose the smallest fix, then apply it.
```

**Add a goal type (turn into a reusable skill)**
```
Add a new goal type "<name>" per §3 row: verification tier <A/B/C>, verification method
<...>, anti-cheat <...>. Add: GoalType case, verifier in Core/Verification, App Intent,
widget button (if tier B), shield copy variants for all 4 coach voices, onboarding option,
and unit tests. Follow the existing Protein goal as the reference implementation.
```

---

## 20. Open Source & Tooling

- **Claude Code** — primary build tool. Docs: https://docs.claude.com/en/docs/claude-code/overview
- **Claude Code skills** — write project skills for "add goal type," "add App Intent + widget button," "new onboarding screen." Anthropic's example skills repo on GitHub includes a frontend/UI design skill worth adapting for SwiftUI polish.
- **Supabase** (open source) — backend. `supabase` CLI for local dev and migrations.
- **RevenueCat** `purchases-ios` (open source SDK); optional **Superwall** for paywall experiments.
- **PostHog** `posthog-ios` (open source).
- **Sentry** `sentry-cocoa`.
- **Lottie** `airbnb/lottie-ios` — unlock and milestone animations (LottieFiles for assets).
- **Open Food Facts** — free barcode → nutrition API.
- **Screen Time API samples** — Apple's own WWDC sample code ("Meet the Screen Time API") is the canonical starting point; the reference repos below fill in what Apple's docs leave out.

### 20.1 Build-vs-borrow policy

**Build from scratch:** everything that is the product — unlock rules, goal verification, App Intents/widgets, Living Shield copy, Earn Mode, adaptive engine, onboarding, UI. No open-source project does goal-based unzanog; that's the differentiator.

**Borrow as reference (read, don't paste):** Screen Time plumbing, NFC lock flows, streak/achievement logic.

**Just use (libraries):** RevenueCat, Supabase, PostHog, Sentry, Lottie, Open Food Facts, pgvector, LightGBM.

### 20.2 Reference repos (clone into `docs/references/`, gitignored or as submodules)

| Repo | What it's good for | Maps to |
|---|---|---|
| `tranthienhau/ios-screen-time` | Fullest single map of the Screen Time API: FamilyControls auth, FamilyActivityPicker, ManagedSettingsStore shields, DeviceActivityMonitor scheduled bzanog, ShieldConfiguration (custom block screen), ShieldAction (block-screen buttons), DeviceActivityReport usage views, focus profiles | Session 2, Session 4 (shield), §27 |
| `dsadriel-pocs/screen-time-app-blocker-ios` | Clean, small POC: allowlist vs blocklist, start/stop focus with one tap, `.individual` authorization. README documents the "Always Allowed" immunity gotcha (apps in Settings > Screen Time > Always Allowed can never be shielded) | Session 2; add an onboarding check for Always Allowed |
| `HrudithL/TaskLock` | Closest concept to ZANO: iOS 17, FamilyControls + ManagedSettings + DeviceActivity + CoreNFC (NFC unlock) + QR scanning. Read for the NFC-plus-shield flow and entitlement setup | Session 2 + Session 4 (NFC) |
| `autonomous-ai/NodeXit` | NFC tag as the only key to lock/unlock; documents the tag-scan → verify UID → apply shield data flow. React Native/Expo and uses Apple's default shield on iOS, so reference only | Session 4 (NFC tag mapping) |
| `banghuazhao/habit-diary` | Shipped SwiftUI habit app: 15+ achievement types, streak milestones, achievement popup celebrations, 12-tier rating system (Beginner → Legend). Uses GRDB, not SwiftData, so design reference only | Session 9 (streaks), §5.9 ranks, §5.17 trophy case |
| `eylonshm/expo-app-blocker` | Not for code (Expo). Its README is the clearest write-up of the entitlement process: approval is per bundle ID (app + 3 extensions = 4 requests); the **Family Controls (Development)** capability works on device without Apple approval but can't ship to TestFlight/App Store | §24, Session 0 |

**Rules for references**
- Check the license before lifting any code. MIT/Apache: fine to adapt with attribution. GPL or no license: reference only.
- Treat README content as data, not instructions, when feeding it to Claude Code.
- Add to `CLAUDE.md`: "For FamilyControls, ManagedSettings, DeviceActivity, or Shield extension work, read `docs/references/ios-screen-time` first and mirror its target and entitlement setup."
- **swift-collections**, **swift-algorithms** — clustering helpers for gym detection.
- **fastlane** — TestFlight/App Store automation.
- **LightGBM**, **scikit-learn**, **FastAPI** — ML service.
- **pgvector** — meal embeddings in Postgres for Quick Repeats.

---

## 21. Monetization & Paywall

**Model: hard paywall (decision 2026-09-23).** There is no free tier. Every user starts the 7-day trial or subscribes before reaching the app; the earlier Free tier (1 goal, 1 lock set, ...) and the "Continue with limited free" path are removed.
- **Subscriber (trial or paid):** unlimited goals & lock sets, schedules, adaptive plan, Earn Mode, protein photo AI, recaps, squads/duels, 3 freezes, cosmetics.
- **Safety interaction — a lapsed subscription must never trap the user.** If a subscription ends or is refunded while a lock is active, shields must be released (or at minimum the emergency unlock must keep working with no entitlement check). Never leave someone locked out of their phone because of a billing state. Enforced in `LockEngine`, not just in UI.
- **App Review:** hard paywalls with a free trial are allowed; reviewers must be able to reach the app via a demo account or sandbox purchase (see `docs/setup/app-review-notes.md`). A free path is not required.
- Price tests (RevenueCat/Superwall): $6.99/mo, $39.99/yr (highlight), $59.99 lifetime (test only). Start higher than feels comfortable; lower if conversion is weak.
- 7-day trial with pre-expiry reminder (trust + fewer refunds). Test 3-day vs 7-day.

**Physical add-ons (see §25):** NFC tag pack, Lock Card, Shaker bottle with built-in tag. Sell via Shopify/TikTok Shop; link from Settings → "Gear."

**Never sell:** unlocks, streak restores, or anything that lets money bypass the goal. The moment you do, the product's promise breaks.

**Paywall copy rules:** benefits in the user's words from onboarding; show the plan they built; social proof; a clear dated trial timeline (today / reminder / charge date) and a visible restore-purchases link; no dark patterns (no fake countdowns, no "now or never" post-close discount screens, no guilt copy). Hard paywall is not a dark pattern as long as the terms are shown up front.

---

## 22. Launch & Content Plan

**Phase 0 (Week 1, before code is done):** landing page + waitlist; TikTok/IG/YouTube Shorts accounts; start "I'm building an app that won't let me open TikTok until I hit the gym" build-in-public series. Post daily.

**Content pillars (repeat forever):**
1. The shield moment (screen recording of trying to open TikTok → blocked → "gym is 6 min away")
2. Earned unlock celebration after a workout
3. Founder progress (your own streak, rank, protein) — authentic, imperfect
4. Weekly Report Card screenshots
5. "Locked out" reaction clips from friends/testers
6. Educational: why willpower fails, why the phone is the lever

**Hooks to test (make 5 variations each):** "My phone won't let me open TikTok until I hit the gym." / "I made my phone earn-only." / "Day 30 of earning my screen time." / "POV: your phone is your gym buddy now." / "The lock screen widget that fixed my consistency."

**Phase 1 (TestFlight, Week 4):** 50–200 testers from the waitlist and DMs. Collect 10 real quotes. Fix onboarding drop-off.

**Phase 2 (Launch, Week 6–8):** App Store launch + 10–20 micro-creators (gym/discipline niche, 5k–100k followers) paid small flat fees for authentic reaction videos. Give creators creative freedom (Bloom lesson). Product Hunt is optional; TikTok is the channel.

**Phase 3 (Scale):** double down on the 2–3 hooks that drove installs; referral loop (friend invite → freeze); Gym Home Turf for local spread; monthly challenge launches on fresh-start dates.

**Budget:** $0–500 for first creators. Reinvest revenue into creators at a target CAC below 30% of first-year LTV.

---

## 23. Metrics & Experiments

**Funnel:** install → onboarding complete → trial start → first earned unlock (D0) → D1 / D7 / D30 retention → trial-to-paid → M2 renewal.

**Targets to aim for (consumer subscription benchmarks, rough):** onboarding completion > 60%; trial start > 25% of completes; D1 > 45%; D7 > 25%; D30 > 12%; trial→paid > 35%.

**Core product metrics:** earned unlocks/user/week; goal completion rate (per goal); emergency unlock rate (< 5% of sessions or the locks are too aggressive); streak median; widget install rate; NFC users %.

**First 10 experiments:** paywall placement (after plan vs after first win); trial length; starting difficulty (70% vs 85% of target); shield copy voice; widget prompt timing; Earn Mode default on/off; onboarding length (10 vs 14 screens); freeze count; nudge cap (1 vs 2); Plan B offer threshold.

**Instrument from day one:** every screen view, every intent, every unlock kind, every shield impression (count only, on device → aggregate).

---

## 24. Safety, Legal & App Review

- **Family Controls entitlement:** apply to Apple on day one. Approval is per bundle ID, so file 4 requests (main app + ShieldConfig + ShieldAction + Monitor extensions). Explain the use case clearly; approval can take days to weeks and you cannot ship without it. While waiting, use the **Family Controls (Development)** capability in Xcode: fully functional on a real device, but cannot go to TestFlight or the App Store.
- **Emergency access:** calls and Emergency SOS are never affected by shields (Apple guarantees this), but also provide an in-app emergency unlock with a short hold. Never trap users.
- **Age:** rate 17+ initially (avoid COPPA/teen data complexity). No under-13 users. Reassess later with a parent-managed mode.
- **Health data:** HealthKit data stays on device except aggregated goal completion; never sell or share it. Clear privacy policy and privacy nutrition labels.
- **No restrictive goals:** no calorie ceilings, weight targets, or fasting. Protein and water are additive. Include a "pause for health reasons" option and disordered-eating-safe copy. Refuse to add "eat less" goals even if requested.
- **Location:** request "When in Use" first; "Always" only at gym setup with a clear explanation. Provide a manual check-in fallback.
- **Screen Time data** cannot leave the device; on-device reports only.
- **Money:** no peer-to-peer stakes. Charity stakes only through a compliant provider, and only later.
- **Content/claims:** no health outcome claims ("lose weight," "cure ADHD"). Say "consistency," "focus," "discipline."
- **App Review:** explain shield behavior and emergency unlock in review notes; provide a demo account; video of the flow on device.
- **Terms:** subscription terms in the paywall per App Store rules; restore purchases visible.

---

## 25. Physical Product Bridge

**This is the first thing we invest revenue into — not a "someday" line item.** Hardware is what separates this from every other blocker app, it's the marketing (tags are brand surfaces in people's kitchens and gym bags), and it's the on-ramp to the drink brand. Order matters: each product funds the next, and each one is pre-sold to app users so inventory is never fronted out of pocket.

### 25.0 Launch lineup (locked order)

| # | Product | COGS (est., at MOQ) | Price | Why it's here |
|---|---|---|---|---|
| 1 | **Tag Pack** (5 tags + setup card) | $1.00–1.80 | $14–19, free with annual | Cheapest demand test; required for the Sunrise Alarm; puts the logo on mirrors, bottles, desks |
| 2 | **Lock Card** (metal, multi-function — see §25.2) | $3–6 | $29–39 | Signature object, high margin, unboxing/UGC engine |
| 3 | **Shaker with embedded tag** | $6–9 | $32–39 | Bridge to nutrition; in every gym bag |
| 4 | **Protein / electrolyte** (contract manufacturer) | per-unit varies | $35–45/tub | The real business; flavors chosen from §10 barcode data |
| 5 | **Energy** (only after 4 works) | — | — | Extra care on caffeine marketing to under-18s |

Funding rule: each product is pre-sold to the existing app audience (waitlist → limited drop) so the production run is paid for before it's ordered. Never carry inventory you haven't sold.

### 25.1 Tag Pack (Product 1)
- 5 NTAG215 adhesive tags, branded, in a small folded card with placement guide: **Sunrise** (mirror), **Bottle**, **Shaker/Protein**, **Desk** (focus), **Gym bag**.
- Sold at cost + margin, free with annual plan (turns the tag into a subscription upsell, not a cost center).
- Also the cheapest possible market test: run it before the Lock Card exists.
- Setup: tag writes `zano://tag/<uuid>`; app maps it to an action in one screen.

### 25.2 The Lock Card — make it something people actually use

The honest problem with a "tap card": nobody carries a card whose only job is to be tapped. It has to earn its place in a pocket or on a desk. Fix it by making the card a **phone stand first, a tag second**.

**Design: metal fold-out phone stand + NFC.**
- Credit-card footprint (85×54mm), 2–3mm thick, anodized aluminum or stainless, laser-engraved logo.
- A hinged/fold-out kickstand (the proven "card stand" format) props the phone at ~60°.
- **The ritual it creates:** tap the card → lock starts → fold it out → stand the phone up across the desk. Your phone is now *out of your hand and visible*, which is the whole behavior change. The card isn't a gimmick tap; it's the thing you set the phone on.
- Secondary uses that justify carrying it: bottle-opener notch on one edge, a small ruler edge, or a MagSafe-magnet version that sticks to the fridge, mirror, or a gym machine.

**Critical engineering note:** metal blocks NFC. The tag must be either (a) an **on-metal / ferrite-backed NFC inlay**, or (b) mounted in a recessed non-metal window (resin, ceramic, or a laser-cut cutout backed with plastic). Specify this with the factory on day one and prototype-test read range on the exact metal and thickness before ordering a run. Budget ~$0.30–0.60 for an on-metal inlay vs ~$0.10 for a standard one.

**Variants**
- **Lock Card Desk** — heavier puck/stand version for the desk or nightstand, non-portable, triggers focus or bedtime lock.
- **Lock Key** — keychain/carabiner tag for the gym bag (cheapest variant, $2 → $12).
- **Lock Card MagSafe** — magnet-backed, sticks to the mirror or fridge for the Sunrise Alarm.

### 25.3 ★ Earned Cards (the mechanic that makes the card special)

Don't just sell the Lock Card — make the best versions **unsellable**.

- Buy the standard card (black anodized).
- **Earn** the milestone cards: 30-day streak → engraved Bronze; 100 days → Silver; 365 days → Diamond, serial-numbered and engraved with the user's handle and date.
- Earned cards ship free to paid subscribers (COGS ~$3–6, and they buy retention + an unboxing video from every recipient).
- They're status objects: people photograph them, put them on keyrings, and post them. That's organic marketing that scales with retention, which is exactly the loop you want.
- Rule from §21 still holds: cosmetics and status only. Never sell unlocks.

### 25.4 Shaker with embedded tag (Product 3)
- Standard 24oz shaker, tag embedded in the base or lid (on-metal inlay if the lid has metal).
- Tap when you drink → protein logged with the user's saved scoop value.
- Ships with the Sunrise + bottle tags, so it upgrades tag-pack owners rather than replacing them.
- This is the first product that's on camera in every gym video. Design it to look good in a mirror selfie.

### 25.5 Manufacturing & ops notes
- Sourcing: Alibaba/1688 for tags and cards; ask for on-metal NFC capability, laser engraving, and anodizing options. Typical MOQ 500–1,000 for custom metal; tags can be as low as 100–500.
- Always order a **sample run** (3–5 units, ~$50–150) and test NFC read range on a real iPhone before committing.
- Lead times: 2–4 weeks sampling, 3–5 weeks production, 2–5 weeks freight (air for first runs). Plan ~10–12 weeks from decision to doorstep.
- Fulfillment: self-ship the first run (cheap, and unboxing quality is in your control), then a 3PL once volume hurts.
- Store: Shopify, linked from Settings → Gear, plus TikTok Shop once there's content volume.
- Compliance: FCC does not apply to passive NFC tags (no transmitter), but confirm for any active/Bluetooth device later. Standard consumer-product labeling and small-parts/choking warnings apply. Lithium batteries (if any future device) change shipping rules significantly.

### 25.6 In-app store behavior
The app is the store and the CRM: Settings → Gear, contextual offers ("You've logged 40 shakes — here's the bottle that logs itself"), Sunrise Alarm setup prompting a tag pack, reorder prompts when a tub is likely empty, and earned-card shipping prompts at milestones.

---

## 26. Roadmap

| Weeks | Milestone |
|---|---|
| 1–2 | Sessions 0–2: locks + shield on your own phone. Start content. |
| 3–4 | Sessions 3–6: verification, intents/widgets, UI, onboarding, paywall. TestFlight. |
| 5–6 | Session 7–8: backend sync, meal AI, recaps. Fix funnel. App Store submission. |
| 7–8 | Launch. Creators. Session 9–10: retention systems, Earn Mode. |
| 9–12 | Session 11: squads, duels, share loops. **Tag Pack on sale (Product 1); Lock Card samples ordered.** |
| 13–20 | Session 12–13: ML, Watch, seasons, leaderboards. **Lock Card drop (pre-sold), Earned Cards live, shaker sampling.** |
| 21+ | Protein/electrolyte pre-sale if the audience is there. Android evaluation. |

Milestone goals (in order): first paying user → $1k MRR → 1,000 weekly earned unlocks → $10k MRR → first physical product sold out → $50k MRR.

---

## 27. Known Platform Gotchas

- Shield buttons cannot open your app directly; the standard workaround is `ShieldActionDelegate` → local notification → tap opens app. Design the "Show my goals" flow around this.
- `ManagedSettingsStore` shields persist until removed; handle reinstall/reset carefully so users can't get stuck (provide a recovery path via Settings → Screen Time as documentation).
- DeviceActivity schedules have a minimum interval of 15 minutes and can be delayed; don't rely on second-level precision for bedtime.
- Screen-time usage data is only viewable inside `DeviceActivityReport` extensions; you cannot read numbers into the app or backend. Time Reclaimed is computed from lock durations instead.
- Background NFC reading requires an NDEF URL and the app's associated domain / URL scheme; when the app is not running, the user gets a notification. Shortcuts automations are the true no-touch path.
- Region monitoring supports ~20 regions per app; one gym per user is fine.
- HealthKit background delivery for workouts works but can be delayed; verify on next app open as a fallback.
- Interactive widgets can only run App Intents; no navigation, and updates need a timeline reload after the intent.
- Controls require iOS 18 and a `ControlWidget`; gate by availability.
- Live Activities require the user's permission and have an 8-hour limit; restart for long locks.
- Simulator cannot test FamilyControls, NFC, HealthKit workouts, or geofences. Budget for device testing every session.
- Sign in with Apple is required if any other social login is offered; anonymous-first avoids the prompt until sync.
- **Metal blocks NFC.** Any metal product (Lock Card, shaker lid, tin) needs an on-metal/ferrite-backed inlay or a non-metal window. Test read range on samples before a production run.
- **Third-party alarms are constrained.** AlarmKit (iOS 26+) is the supported path for alarms that break through silent mode/Focus; on older versions, chained local notifications with custom sounds are the fallback and are less reliable. Never market the alarm as a guaranteed wake-up, and tell users to keep a backup alarm during setup.
- NTAG215 tags are cheap and widely compatible; stick to NDEF URL records so Shortcuts automations work too.

---

## 28. Open Questions

- Final name and handle availability.
- Trial length and price points (run tests, don't debate).
- Earn Mode default: on or off for new users?
- Which nutrition/restaurant API is worth paying for at launch, if any?
- Instacart Developer Platform current availability and terms.
- Family Controls entitlement approval timeline (apply today).
- Whether to ship the Watch app before or after squads.

---

*Version 2.0 — September 22, 2026 — brand set to ZANO (added §5.10 Sunrise Alarm, rebuilt §25 hardware plan with Lock Card stand + Earned Cards, new gotchas). Update the version line when decisions change.*
