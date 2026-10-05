# ZANO growth & background-ML research (2026-10-02)

Research only. This doc proposes and changes nothing in `docs/spec.md`. Where an idea touches a
spec decision (hard paywall, the ban on post-close discount screens, server-side ML in §9), it is
marked **needs founder decision**. Read alongside spec §7 (onboarding), §8 (retention rules),
§9 (ML), §21 (monetization), §23 (metrics) and `docs/design/buildout-plan.md`.

Labels used in this doc:
- **Effort:** S (≤2 days), M (≤1 week), L (>1 week or needs backend/device).
- **Verified:** I checked the API or the claim against a current source. **Unverified:** it comes
  from training memory or a secondary blog, so confirm it against Apple docs before you build.
- **Source quality:** primary sources are RevenueCat's or Adapty's own reports, peer-reviewed
  papers and Apple docs. Vendor blogs (Airbridge, Superwall marketing, ASO tools) are directional
  only.

---

## 1. Executive summary: top 10 ideas, ranked by impact ÷ effort

Ideas already in the spec are left out unless the research changes *how* they should be built.

| # | Idea | Effort | Expected impact | Why (evidence) |
|---|---|---|---|---|
| 1 | **Make the paywall's trial-reminder line a real toggle that asks for notification permission there and then.** Pre-select annual and make the billed amount the most prominent price. | S | Trial starts +10–20%, push opt-in roughly ×2, fewer refunds | Blinkist's timeline paywall moved push opt-in from 6% to 74%, trial starts +23% and complaints −55% ([Blinkist case](https://b2bpricinginsights.substack.com/p/4-min-read-how-blinkists-new-paywall)). Pre-selecting annual gives 69% annual vs 28% ([Adapty H&F](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/)). Apple guideline 3.1.2 requires the billed amount to be most conspicuous, and toggle paywalls are rejected from Jan 2026 ([RevenueCat](https://www.revenuecat.com/blog/growth/rip-toggle-paywall)). |
| 2 | **Add an "if-then plan" to Plan Reveal:** "If it's Mon/Wed/Fri 6 PM, then I go to the gym." It seeds the lock schedule, the nudge times and the slip-model cold start. | S | Goal completion ↑ (d≈0.65 in the literature). Better cold-start data for every model. | Implementation-intentions meta-analysis: 94 studies, d=0.65 ([Gollwitzer & Sheeran](https://www.socmot.uni-konstanz.de/sites/default/files/Gollwitzer_Oettingen_11_Planning_Goal_Striving.pdf)) |
| 3 | **Design the shield like one sec:** a short pause, then a big, easy "Close app" next to "Spend 5 min from Time Bank". Count dismissals as *reclaimed opens*. | S–M | Fewer emergency unlocks. A credible "Time Reclaimed" number. | one sec cut target-app opens by 57% over 6 weeks. The *option to dismiss* and the *delay* did the work; the deliberation message had no effect ([PNAS study](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409)). |
| 4 | **Put the adaptive goal engine and slip risk on-device, inside `Core`, from day one.** Use rules plus a hand-tuned logistic score, with no FastAPI dependency. | M | Protects D7/D30 (early wins). Works offline, before Supabase is live. | Spec §9 assumes a Python service. Supabase isn't live yet (buildout plan) and the logic is tiny. Doing it on-device keeps §8 rule 1 enforceable now. |
| 5 | **"What your trial earned you" card + push, 2 days before charge.** It shows unlocks earned, gym visits, hours reclaimed and streak. | S | Trial→paid ↑, refunds ↓ | Hard paywalls have about 70% higher refund rates (5.8% vs 3.4%) ([Airbridge, citing RevenueCat SOSA 2025](https://www.airbridge.io/en/blog/hard-paywall-vs-freemium-2026)). Early engagement drives trial conversion ([RevenueCat SOSA](https://saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps-how-115000-mobile-apps-deliver-16b-in-revenue-whats-working-whats-quietly-killing-growth)). |
| 6 | **Honest fallbacks when someone abandons the paywall or cancels Apple's purchase sheet:** offer monthly instead of annual, or a longer trial, with no fake timer. Also add Apple **win-back offers** (configured in App Store Connect, no code). | S | +10–25% revenue in vendor data | Superwall reports exit offers at 17% of revenue across 18 apps, and abandoned-transaction recovery at +25–40% ([Superwall](https://superwall.com/solutions/exit-offers), [transaction abandons](https://superwall.com/solutions/transaction-abandons)). Win-back offers launched in iOS 18 ([Apple ASC help](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/)). **Needs founder decision**: spec §21 bans "post-close discount screens"; a plan switch is not a discount. |
| 7 | **Use Apple's Foundation Models framework on-device for the weekly recap line and coach-line variants** (`@Generable` structured output). Fall back to templates on devices without Apple Intelligence. | M | Same recap feature without server LLM cost or data egress. Copy can be personalized per user. | Apple's on-device ~3B model offers guided generation and tool calling on iOS 26 ([overview](https://blakecrosley.com/blog/apple-foundation-models-framework), [createwithswift](https://createwithswift.com/exploring-the-foundation-models-framework/)) |
| 8 | **Time the rating prompt to peak moments:** after the 3rd earned unlock, the first gym-verified unlock, or a 7-day streak. Never after an emergency unlock, a slip or a paywall. | S | Higher rating → higher store conversion | Apple shows the prompt at most 3×/365 days. Fitness apps rate best right after a workout ([avanderlee](https://www.avanderlee.com/swift/skstorereviewcontroller-app-ratings/), [unstar](https://unstar.app/blog/when-to-ask-for-app-reviews-timing-strategies-2026)). |
| 9 | **Custom Product Pages, one per TikTok hook** (gym / doomscroll / study), plus a Product Page Optimization screenshot test | S (no code) | +5–25% store conversion on paid and creator traffic | Custom Product Page users saw lifts of up to 8.6%. Successful PPO tests run +10–25% ([MobileAction CPP report](https://www.mobileaction.co/report/2026-aso-report/custom-product-pages/), [Apple PPO](https://developer.apple.com/app-store/product-page-optimization)). |
| 10 | **On-device nudge-timing bandit:** Thompson sampling over the 4 slots in §9.3, keeping the 2/day cap, with forced copy rotation | M | Goal completion within 3h ↑. Push opt-outs ↓. | HeartSteps: a suggestion gave +14% steps in the next 30 min, but the effect **decayed over weeks** ([Klasnja 2019](https://pmc.ncbi.nlm.nih.gov/articles/PMC6401341/)). Google's PEARL RL arm (n=13,463) beat fixed rules ([PEARL](https://arxiv.org/abs/2508.10060v1)). |

Close runners-up: sleep-aware Plan B offers (HealthKit sleep), duplicate-photo anti-cheat with
Vision feature prints, and a "streak partner" ask at the first win (referee effect, §3.5).

**Strategic risk to revisit, not act on now:** Opal ran a hard paywall to $5M ARR, then plateaued.
Moving to freemium (3 free blocks/day) cut download→paid from 20% to 9% but doubled ARR to $10M+.
Students became two-thirds of DAU
([RevenueCat Sub Club, 2026](https://www.revenuecat.com/blog/growth/kenneth-schlenker-sub-club-podcast-2026)).
RevenueCat also reports that fitness apps giving *some value before the gate* see 1.5–2× trial→paid.
ZANO's hard paywall is a valid launch choice: 12.1% vs 2.2% download→paid and about 2× year-one LTV
([Airbridge/RevenueCat](https://www.airbridge.io/en/blog/hard-paywall-vs-freemium-2026)). Write down
now the trigger for re-testing it, for example installs flat for 8 weeks while organic share
traffic is rising.

---

## 2. Conversion playbook

### 2.1 Paywall placement & type
- **Keep the paywall in onboarding.** About 80% of trial starts happen on day 0 ([RevenueCat SOSA via SaaStr](https://saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps-how-115000-mobile-apps-deliver-16b-in-revenue-whats-working-whats-quietly-killing-growth)).
  The current placement, Commitment → Paywall, is right.
- **Value before the gate matters in fitness** (1.5–2× trial→paid). ZANO already engineers the
  wake-up counter, the plan reveal and the hold-to-commit step; these are the "value". Experiment 1
  in spec §23 (paywall after plan vs after first win) is the right first test. A middle variant
  worth adding: start the 10-minute first-win focus *before* the paywall, and show the paywall
  while it runs ("Your first unlock is in 8:42. Start your trial to keep it").
  **Unverified** whether App Review accepts that; the lock must still release if the user declines.
- **Onboarding length:** vendor data says 3–5 question screens before the paywall beats both 1–2
  and 6+ ([Airbridge](https://www.airbridge.io/en/blog/5-steps-app-onboarding-before-the-paywall);
  directional only). Cal AI runs a much longer quiz with stat cards between questions and does fine
  ([Superwall case](https://superwall.com/case-studies/cal-ai)). The rule that matters: every screen
  either personalizes the plan or raises the stakes. ZANO's Q1–Q6 plus the wake-up screen fits that.
  Note that spec §7's header says 7 steps but the list has 14 items. Reconcile the two before
  building analytics funnels.
- **Personalized plan reveal with a "building your plan" moment** is a near-universal pattern in
  quiz-to-paywall flows ([Lazyweb research](https://experiments.lazyweb.com/research/building-your-plan-loading-screen-prevalence.md)).
  Spec §7 step 10 already has it. Make the paywall headline quote the user's own Q1 answer.

### 2.2 Trial length
- RevenueCat 2026 medians: trials of 4 days or less convert at **25.5%**, 5–9 days at **37.4%**,
  17–32 days at **42.5%**. 55% of 3-day-trial cancellations happen on day 0
  ([RevenueCat 7-day trial](https://www.revenuecat.com/blog/growth/7-day-trial-subscription-app.md)).
- **Recommendation:** keep 7 days. ZANO's value shows up across a week (gym 3–4×/week, the first
  streak milestone, the first weekly recap), and a 3-day trial ends before the first recap. Before
  testing 3-day, test 7 vs 14 days. The one thing a 14-day trial adds is that the first Sunday
  recap lands *inside* it for everyone.

### 2.3 Pricing & plan display
- Health & Fitness has the highest share of annual subscribers (~67%) and annual subscribers have
  2.3× the 12-month LTV ([Adapty H&F](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/)).
  **Pre-select annual.**
- Comparable apps: Cal AI $29.99/yr with a 3-day trial ([Superwall case](https://superwall.com/case-studies/cal-ai));
  Jomo $29.99/yr freemium ([Jomo](https://jomo.so/pricing)); Ladder $29.99/mo
  ([Fortune](https://www.fortune.com/2024/12/10/strength-training-ladder-app-users-growth)).
  ZANO's $39.99/yr test anchor is reasonable.
- **Apple 3.1.2 compliance:** the billed amount must be the most conspicuous price. "$3.33/mo" may
  appear only smaller and below "$39.99/year". **No trial toggle**: Apple has rejected these since
  January 2026 ([RevenueCat](https://www.revenuecat.com/blog/growth/rip-toggle-paywall)).
- Use a remote-configured paywall (RevenueCat Paywalls or Superwall). Cal AI ran 123 experiments
  across 46 placements for +31% trial→paid ([Superwall](https://superwall.com/case-studies/cal-ai)).
  Experiment velocity is the real lever, not any single design.

### 2.4 Trial timeline + reminders + notification priming (combine them)
- Show a dated timeline: **Today** (full access), **Day 5** ("we'll remind you"), **Day 7** (charge date).
- **Change:** the "Remind me 2 days before" line becomes the moment the app asks for notification
  permission. The user has a selfish, concrete reason to say yes. This is where Blinkist's 6% → 74%
  opt-in came from. Spec §7 step 13 (permission priming after the paywall) can then shrink or go.
  This doesn't break the "nothing between peak and payment" rule, because the ask *is part of* the
  paywall.
- Benchmarks: iOS push opt-in is about 56% overall. Priming lifts it to 55–65%, and top-quartile
  apps reach 70–80% ([Pushwoosh](https://cdc.pushwoosh.com/blog/increase-push-notifications-opt-in), [Airship 2026](https://www.airship.com/mobile-app-push-notification-benchmarks-for-2026/)).
- **Day-5 "trial value" push and card** (idea #5): it lists the user's own numbers. With no wins
  yet, it offers Plan B, not guilt.

### 2.5 Exit, abandon and win-back (needs founder decision)
- **Two different moments:**
  1. *Exit:* the user closes the paywall without buying.
  2. *Transaction abandon:* the user tapped buy, then cancelled Apple's purchase sheet
     ([Superwall](https://superwall.com/solutions/transaction-abandons)).
- **Ethical offers that fit §21's no-dark-patterns rule:**
  - On exit, offer a "Prefer monthly?" plan switch.
  - On abandon, offer a "Want more time to decide? 14-day trial" variant.
  - Never a countdown, never "now or never", never guilt.
  - Spec §21 bans *post-close discount screens*. A plan switch or longer trial is not a discount,
    but confirm with the founder.
- Adapty 2026: 55.5% of eventual subscribers did *not* convert on day 0
  ([via Airbridge](https://www.airbridge.io/en/blog/what-happens-after-user-rejects-paywall)). A hard
  paywall gives decliners nothing to return to, which is another reason for the Day-1 and Day-3
  re-entry pushes. Those need notification permission, so ask on the paywall (§2.4) even if the
  user declines the trial.
- **Apple win-back offers** (StoreKit 2, iOS 18+) are configured in App Store Connect with eligibility
  rules. The App Store and Settings can merchandise them with no app code
  ([RevenueCat guide](https://www.revenuecat.com/blog/growth/guide-to-apple-win-back-offers.md)).
  This is zero-effort upside after launch. Annual subscribers who cancel rarely return
  ([9to5Mac 2026](https://9to5mac.com/2026/05/27/new-report-shows-annual-app-subscribers-rarely-return-after-they-cancel/)),
  so prevention matters more than win-back.
- **Never** sell streak restores or unlocks as save offers (§21).

### 2.6 Money-back / "streak guarantee"
- The App Store handles refunds, so an in-app money-back promise can't be enforced. An honest
  alternative: "Hit your plan 3 weeks out of 4 in your first month, or we extend you a month free."
  This could run through Apple offer codes or promotional offers. **Unverified** whether
  promotional-offer eligibility can be tied to in-app behavior without a server; a promotional
  offer signature needs a server, so it waits for Supabase Edge Functions. Effort M. Medium impact.
  Test it only after the basics.

### 2.7 App Store page
- Users decide in 7–10 seconds, mostly on the first two screenshots. Captioned benefit screenshots
  beat raw UI by 15–30% ([MWM glossary](https://mwm.ai/de/glossary/screenshots), directional).
- Screenshot 1 should be the shield moment ("TikTok locked · Gym is 6 min away"), the spec §22
  content pillar #1. Screenshot 2 is the earned unlock with confetti and the Time Bank.
- **Custom Product Pages:** one per creator hook (gym, doomscroll, students), deep-linked from each
  campaign ([Apple PPO](https://developer.apple.com/app-store/product-page-optimization)).
- A preview video showing the real lock → gym → unlock loop in 15s.

### 2.8 Ratings
- `requestReview` is capped at 3×/365 days and ignored when called from a button tap
  ([avanderlee](https://www.avanderlee.com/swift/skstorereviewcontroller-app-ratings/)).
- Triggers: the 3rd earned unlock, the first gym-verified unlock, or the Day-7 streak celebration.
- Suppress it within 24h of an emergency unlock, a slip, a paywall view or a billing event.

### 2.9 Referral & social loops
- Referees roughly double goal success. On stickK, success was 29% with no referee and no stakes,
  59% with a referee, and about 80% with a referee plus stakes
  ([Lund/LUSEM summary](https://www.lusem.lu.se/article/put-bet-it-self-funded-commitment-contracts-get-people-gym)).
  ZANO can't use money stakes (§21 forbids paying past the goal), but a *witness* is allowed
  (buildout idea #9).
- Duolingo: retention rises with each additional Friend Streak ([Duolingo blog](https://blog.duolingo.com/product-lessons-friend-streak/)).
  Streak Wager gave +14% D7 ([Econsultancy](https://econsultancy.com/six-a-b-tests-used-by-duolingo-to-tap-into-habit-forming-behaviour/)).
- **Ask for a "streak partner" right after the first win**, when motivation peaks. The invite link
  doubles as the referral (both get a freeze, spec v2). If Supabase isn't live, start with a
  Messages share and accept the partner later.
- **Keep share cards free and branded.** Strava moved Year in Sport behind its subscription in
  2025, which turned a viral surface into a perk
  ([report](https://tagteam.harvard.edu/hub_feeds/3415/feed_items/17132945/about)). ZANO's recap is
  for subscribers by definition, but the *exported image* must carry the hook and the App Store
  link (Custom Product Page).

### 2.10 Physical product tie-in
- Brick ($59 NFC puck) became an "aspirationally offline" status object and declines to share
  sales numbers ([SSENSE](https://www.ssense.com/en-ca/editorial/technology/how-brick-became-a-status-symbol-for-the-aspirationally-offline),
  [BizTimes](https://biztimes.com/germantown-startup-brick-can-help-you-temporarily-block-distractions-on-your-smartphone)).
  The lesson: the physical object is *marketing*. It is visible on desks and in videos.
- **Idea:** a "Founding Annual" bundle that includes a free Sunrise Tag shipped to annual buyers.
  It raises the annual mix and puts tags in homes, which seeds §25 sales. **Unverified against App
  Review 3.1.1/3.1.3:** giving a physical gift alongside an IAP subscription needs a guideline check
  and likely a web-redemption flow. Effort L (ops).

---

## 3. UX retention patterns: keeping people without punishing them

| Pattern | Evidence | ZANO application | Status in repo |
|---|---|---|---|
| **Pause + easy dismiss at the moment of temptation** | one sec: −57% opens. Dismiss option and delay worked; message did not ([PNAS](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409)) | Shield: 3–5s breath ring, then **"Close app"** as the primary button and "Use Time Bank (5 min)" as secondary. Spend less effort on clever shield copy and more on the delay and the dismiss. ShieldAction can only respond with `.close`/`.defer`/`.none`; deep-linking into the app from the shield is **not supported** (Unverified for iOS 26; check §27). | Shield exists; design change |
| **Count "attempts → closed" as wins** | Same study: 36% of attempts were abandoned | "You closed TikTok 14 times this week = ~2.1h reclaimed." Feeds §5.15. ShieldAction can increment an App Group counter (Unverified that ShieldConfiguration can write; ShieldAction is the safer place). | New counter |
| **Forgiving streaks** | Rigid streaks drive guilt and abandonment ([habitdoom summary of CHB 2021](https://habitdoom.com/blog/streak-anxiety-habit-trackers), secondary). Duolingo: streak investment → 40% lower daily churn ([Lenny's](https://lennysnewsletter.com/p/behind-the-product-duolingo-streaks)). | Already in §8 (freezes, Never Miss Twice, Plan B). Add a **weekly** streak ("4 of 4 weeks hit plan") beside the daily one, so one bad day never zeroes the identity metric. | Engines exist, UI pending |
| **If-then plans** | d=0.65 meta-analysis (above) | Plan Reveal step: pick days/time/place → becomes schedule + nudge prior | New |
| **Fresh-start timing** | Gym visits rise after Mondays, month starts and birthdays ([Dai, Milkman, Riis 2014](https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf)) | Already §8 rule 6. Also use for **Comeback mode**: offer the restart on the next Monday or 1st, not "now". | Partial |
| **Identity framing** | Habit literature; Duolingo's 7+ day streak cohort | §8 rule 5. Badge copy moves from "did a workout" to "lifter" at week 3–4. | Copy |
| **Variable reward at unlock** | Standard; keep tasteful | §8 rule 4 (1 in ~6). Prefer *informational* surprises ("Fastest earn this month") over coins. | Pending P2 |
| **Reclaimed-time framing over blocked-time framing** | Satisfaction rose in the one sec study | Lead with "earned / reclaimed", never "blocked X times". | Copy |
| **Tactile delight at milestones** | Opal's gem-cracking: "doesn't move a metric, builds affinity" ([RevenueCat](https://www.revenuecat.com/blog/growth/kenneth-schlenker-sub-club-podcast-2026)) | Earned-unlock haptic + Lock Card tap animation. Budget it once and don't A/B it to death. | Partial |
| **Schedule the locks at onboarding** | Opal: immediately scheduling work-hour blocks drove retention. Work hours beat evening blocks in A/B tests ([Speedinvest](https://speedinvest.com/blog/scaling-smart-how-opal-built-a-10m-arr-business-in-just-2-years), [RevenueCat](https://revenuecat.com/blog/growth/kenneth-schlenker-opal-sub-club-podcast)) | Plan Reveal should *pre-fill* a daily lock window from Q5 and the if-then plan. The monitor extension is currently empty (buildout plan), so this needs Wave 2. | Blocked on monitor |

---

## 4. Background ML/AI catalog (no chatbots)

### Platform constraints (read first)
- **Screen Time data cannot leave the DeviceActivityReport extension.** Its sandbox blocks network,
  App Group writes, files, the pasteboard and notifications. Apple calls this expected
  ([Apple forums 809823](https://developer.apple.com/forums/thread/809823),
  [736351](https://developer.apple.com/forums/thread/736351)). You can *render* insights inside the
  report view, but you can't learn from them in the app. **Verified** (forums, Apple staff).
- The **DeviceActivityMonitor** extension *can* write to the App Group. Threshold events
  (`eventDidReachThreshold`) are the only supported usage signal you can get out. They are known to
  fire early or twice, so treat them as a wake-up and validate
  ([forum 840907](https://developer.apple.com/forums/thread/840907), [727970](https://developer.apple.com/forums/thread/727970)).
  Extensions have about a 6 MB (monitor) to 15 MB memory budget, so no model inference there; just
  write events. **Verified as a pattern; exact limits Unverified.**
- **FamilyControls tokens are opaque.** The app never learns which bundle IDs a user picked.
  "Auto-categorizing apps" is impossible, and unnecessary because the picker already offers
  categories.
- **Background compute:** `BGProcessingTask` (with `requiresExternalPower`) is the place for
  overnight model updates. `BGContinuedProcessingTask` (iOS 26) is user-initiated only
  ([summary](https://playbooks.com/skills/charleswiltgen/axiom/axiom-background-processing)).
  **Verified** that the APIs exist.
- **Location (iOS 18+):** background events need `CLServiceSession(authorization: .always)` plus
  the capability plus Always authorization. A missing piece fails silently. Visit monitoring still
  works in the background ([summary](https://skills.sh/derklinke/codex-config/ios-core-location),
  [forum 757002](https://developer.apple.com/forums/thread/757002)). **Partially verified.**
- **Foundation Models (iOS 26):**
  - On-device ~3B LLM with a 4K context, `@Generable` guided generation and tool calling
    ([guide](https://www.atelier-socle.com/en/articles/foundation-models-api-guide)).
  - Requires an Apple-Intelligence-capable device (iPhone 15 Pro and later); always ship a
    template fallback.
  - **WWDC26** reportedly added image input and a second, larger on-device model for high-end
    devices ([Apple WWDC26 guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/),
    [Callstack](https://callstack.com/blog/on-device-ai-after-wwdc-2026-whats-new)). **Unverified:**
    which OS version and which devices. Check before relying on it for meal photos.

### Recommendation on architecture
Spec §9 plans server-side LightGBM and FastAPI. Given local-first, offline unlock and a backend that
isn't live, **build every model in §9 first as on-device Swift in `Core`** (rules, logistic
regression with hand-set or population-trained weights, Thompson sampling). These are a few hundred
lines and testable in CoreTests. Add the server only for population priors and weight training once
`goal_events` has volume. Then ship weights as a JSON blob and keep inference on-device. Ship
weights rather than a Core ML model: for ~15 features, plain Swift arithmetic is simpler than
`.mlmodel` packaging.

### Catalog

| # | Feature | What it does for the user | Data needed | On-device feasibility / frameworks | Privacy | Effort | Impact |
|---|---|---|---|---|---|---|---|
| A | **Adaptive difficulty** (spec §9.1) | Goals stay achievable (75–85% hit rate); early wins engineered | 28-day `GoalEvent` history, DOW, streak | Pure Swift in `Core`. v2 Thompson sampling over difficulty steps is also pure Swift. **Verified feasible.** | Nothing leaves device | M | High (D7/D30) |
| B | **Slip-risk score** (§9.2) | Offers Plan B *before* a bad day, in widget and shield copy | DOW, yesterday's completion, streak, days since miss, Q5 answers, sleep (HealthKit `sleepAnalysis`), first-unlock hour (app-side), travel flag | Logistic regression in Swift, scored by a morning `BGAppRefreshTask` or at first app/widget timeline refresh. Writes the risk to the App Group so the widget and shield read it. Calendar density via EventKit (opt-in). **Verified APIs**; refresh timing isn't guaranteed. | On-device | M | High |
| C | **Nudge timing & tone bandit** (§9.3) | Fewer, better-timed pushes | Nudge sent (slot, tone), goal completed within 3h | Thompson sampling with Beta priors per arm, in Swift. Schedule local notifications ahead (`UNCalendarNotificationTrigger`). Needs no server. HeartSteps shows decay, so rotate copy and keep the 2/day cap. | On-device | M | Medium-high |
| D | **Best lock-window suggestions** | "You hit your TikTok limit most days 9–11 PM. Lock then?" | Hourly threshold events from DeviceActivityMonitor (e.g. 15-min threshold per 2-hour interval) written to the App Group | Feasible but fiddly; thresholds are flaky. An alternative with no export: render the suggestion *inside* the DeviceActivityReport view (user sees it, app never does). **Partially verified.** | Usage stays on device; only "threshold hit in window X" is stored | L | Medium |
| E | **Gym auto-detection** (§9.4) | "Is this your gym?" without setup | `CLVisit`s, dwell, HealthKit workouts/HR | DBSCAN on a handful of visits is trivial in Swift. `CLLocationManager.startMonitoringVisits` plus `CLServiceSession` (iOS 18). Use HealthKit workouts overlapping the visit as the confidence boost. **Verified APIs**, reliability is device-dependent. | Location stays on device (spec says geofence only) | M | High: removes the #1 setup friction |
| F | **HealthKit workout as verifier** | Home or other-gym workouts count automatically | `HKWorkout` samples via `HKObserverQuery` + background delivery | Verified API. Watch auto-detected workouts appear once the user confirms them on the Watch. | On-device | S–M | High (fewer "it didn't count" moments) |
| G | **Sleep-aware mornings** | After a short night, the morning goal auto-offers Plan B or a gentler Sunrise variant | HealthKit `sleepAnalysis` (Watch or third-party) | Verified API. Read on alarm dismiss. | On-device, opt-in | S | Medium (no-shame rule §8.9) |
| H | **Weekly recap line + coach copy** (§9.6, §5.13) | Personal, specific, voice-matched copy | Week aggregates (numbers only) | Foundation Models `@Generable struct RecapLine { win, suggestion }` with strict length; template fallback. **Verified API (iOS 26).** Validate output against no-shame and no-restrictive-goal word lists before display. | Nothing leaves device (vs. spec's server LLM) | M | Medium; also cuts server cost |
| I | **Meal photo → protein** (§9.5) | Faster protein logging | Photo | Options: (1) server vision LLM (current plan); (2) Foundation Models image input, **only if the WWDC26 multimodal API is confirmed (Unverified)**; (3) Vision `VNClassifyImageRequest` labels + Food Memory lookup, a fast first guess with no grams (**Unverified** food-label coverage). Accuracy reality: GPT-4o/Claude ~36% MAPE on weight and energy, protein worse ([PMC study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12513282/)). **Always show a range and a confirm slider. Food Memory/Quick Repeats will carry most logs.** | Photos to server only with consent; on-device preferred | L | Medium |
| J | **Duplicate/cheat photo detection** (§9.8) | Fair squads and duels without accusations | Photo feature vectors | Vision `VNGenerateImageFeaturePrintRequest` + distance threshold against the last N meal photos. **Verified API** (iOS 13+). | On-device | S | Low-medium (protects social features) |
| K | **Motion sanity checks** (§9.8) | Gym dwell doesn't count while driving past | `CMMotionActivityManager` | Verified API. Query activity history for the dwell window. | On-device | S | Low-medium |
| L | **Disengagement → Comeback** | Detects drift early; offers a 3-day comeback on the next fresh-start date | App opens, widget taps, goal events | Simple rules (e.g. 3 days without a goal event or an open) in Core. Push only if notifications are on. | On-device | S | Medium |
| M | **Churn → save offer** | Before cancelling, suggest pausing or a lighter plan | StoreKit 2 `Transaction`/`Product.SubscriptionInfo.RenewalInfo` (willAutoRenew false) | Verified that `willAutoRenew` is visible on-device. The app can show an in-app "Want a lighter plan?" card when it flips. Win-back offers handle after-expiry. | On-device | S | Medium |
| N | **Smart Plan B threshold** | Plan B offered to the right people, not everyone | Slip-risk history, Plan B accept → complete | Extends B. Bandit over threshold values. | On-device | S after B | Medium |

Not recommended: on-device *training* with Create ML/`MLUpdateTask`. Per-user data is too small;
Bayesian updates of a few parameters (bandits, logistic with population priors) are the right
size.

---

## 5. Benchmarks (with sources)

| Metric | Value | Source |
|---|---|---|
| Download→paid, hard paywall vs freemium (median) | 12.1% vs 2.2% | [Airbridge citing RevenueCat SOSA 2025](https://www.airbridge.io/en/blog/hard-paywall-vs-freemium-2026) |
| Y1 LTV per payer, hard vs freemium | $49.30 vs $24.24 | same |
| Refund rate, hard vs freemium | 5.8% vs 3.4% | same |
| H&F trial start rate | 7.8% of installs (highest category) | same |
| Install→trial median / top decile | ~6.7% / 15%+ | [Adapty H&F](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/) |
| Trial→paid median | 25.5% (≤4d), 37.4% (5–9d), 42.5% (17–32d) | [RevenueCat 2026](https://www.revenuecat.com/blog/growth/7-day-trial-subscription-app.md) |
| Trial starts on day 0 | ~80% | [SaaStr on RevenueCat SOSA](https://saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps-how-115000-mobile-apps-deliver-16b-in-revenue-whats-working-whats-quietly-killing-growth) |
| Annual share in H&F / with annual preselected | ~67% / 69% vs 28% | [Adapty H&F](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/) |
| H&F first-renewal median | weekly 54%, monthly 57% (annual figure ambiguous in summary; check the source table) | [RevenueCat renewals](https://www.revenuecat.com/blog/growth/average-subscription-renewal-rates-by-app-category.md) |
| Opal | 20% → 9% download→paid after freemium; $5M → $10M+ ARR; 1M+ DAU | [RevenueCat Sub Club](https://www.revenuecat.com/blog/growth/kenneth-schlenker-sub-club-podcast-2026) |
| Cal AI | +31% trial→paid from 123 paywall experiments; $29.99/yr, 3-day trial | [Superwall](https://superwall.com/case-studies/cal-ai) |
| ClearSpace | ~$55k/mo, ~25k downloads/mo (third-party estimate) | [screensdesign](https://screensdesign.com/showcase/clearspace-reduce-screen-time) |
| Ladder | ~150k paid subs late 2024, $29.99/mo, 7-day no-card trial | [Fortune](https://www.fortune.com/2024/12/10/strength-training-ladder-app-users-growth) |
| Brick | $59 NFC puck; no sales disclosed | [SSENSE](https://www.ssense.com/en-ca/editorial/technology/how-brick-became-a-status-symbol-for-the-aspirationally-offline) |
| Push opt-in iOS | ~56% avg; 55–65% primed; 70–80% top quartile | [Pushwoosh](https://cdc.pushwoosh.com/blog/increase-push-notifications-opt-in), [Airship](https://www.airship.com/mobile-app-push-notification-benchmarks-for-2026/) |
| Blinkist timeline paywall | opt-in 6% → 74%, trial starts +23% | [case](https://b2bpricinginsights.substack.com/p/4-min-read-how-blinkists-new-paywall) |
| one sec friction | −57% target-app opens at 6 weeks (n=280) | [PNAS / PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409) |
| Exit offers | 17% of revenue (18 apps, vendor data) | [Superwall](https://superwall.com/solutions/exit-offers) |
| Duolingo Streak Wager | +14% D7 | [Econsultancy](https://econsultancy.com/six-a-b-tests-used-by-duolingo-to-tap-into-habit-forming-behaviour/) |
| HeartSteps nudges | +14% steps in 30 min, decaying over 6 weeks | [Klasnja 2019](https://pmc.ncbi.nlm.nih.gov/articles/PMC6401341/) |
| LLM food photo accuracy | ~36% MAPE weight/energy; protein worse | [PMC 2025](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12513282/) |

Spec §23 targets (trial→paid > 35%, D7 > 25%) fit these medians for a 7-day trial. Onboarding
completion > 60% is ambitious for a 14-screen flow with a hard paywall; instrument it per screen.

---

## 6. What NOT to do

1. **Don't try to export Screen Time data** from the report extension, or build "auto-categorize
   my apps". The sandbox forbids it and tokens are opaque. Any workaround risks App Review and user
   trust.
2. **Don't ship a trial toggle paywall,** or make the trial/per-month price more prominent than the
   billed amount (3.1.2, enforced since Jan 2026).
3. **No fake countdowns, "now or never" offers, or guilt copy** on paywalls or exit offers (§21).
   Plan switches and longer trials are fine; manufactured urgency is not.
4. **Never sell unlocks, streak restores or Time Bank minutes,** including as churn-save offers.
5. **No chatbot coach.** Use the LLM only for short, validated, templated copy (recap line, coach
   variant). Never let it generate goals; the additive-only rule (§24) must hold, so filter outputs.
6. **Don't present AI protein estimates as precise.** About 36%+ error is normal. Show a range and
   require one-tap confirmation; never let an unconfirmed estimate auto-complete a goal that
   unlocks apps.
7. **No all-or-nothing streaks.** Keep freezes, Plan B and weekly streaks, and never show "streak
   lost" without the next smallest step.
8. **Don't exceed 2 proactive pushes/day,** and don't send the same nudge copy repeatedly. Nudge
   effects decay (HeartSteps).
9. **Don't build the server ML pipeline (§9.9) before there is data.** On-device rules and bandits
   first; the server only provides priors.
10. **Don't run inference inside extensions** (memory limits, Jetsam). Extensions read precomputed
    values from the App Group.
11. **Don't let billing state touch lock release.** Emergency unlock and shield release on lapse
    must never check entitlements (§21). Save offers must never sit in front of the emergency unlock.
12. **Don't paywall the share image itself** (the Strava lesson). The exported card is acquisition.
13. **Don't ask for a rating** after an emergency unlock, a slip, a paywall view or on a button tap.
