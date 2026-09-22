# ZANO — Build-in-Public & Launch Plan

Operational plan for `docs/spec.md` §22 (Launch & Content Plan), grounded in §1 (Vision &
Positioning). This is the "how" underneath the spec's "what" — week-by-week actions, message
templates, and a budget tracker. It does not change any product decision in the spec; if something
here conflicts with §22, the spec wins and this doc should be corrected.

**North-star metric (§1):** Weekly Earned Unlocks per active user. Every phase below should be read
as "does this move toward people earning unlocks," not just "does this get views." Secondary:
Day-30 retention, trial-to-paid conversion.

**Positioning line (§1):** "The app that won't let you open TikTok until you hit the gym."

**Reality check from `CLAUDE.md` / `docs/setup/windows-workflow.md`:** as of this writing there is
no Mac, the Apple Developer Program is not enrolled, and there is no `.xcodeproj` build yet.
TestFlight (Phase 1) and App Store submission (Phase 2) are hard-blocked on both of those. **Phase 0
does not depend on either** — it's audience-building and can run fully in parallel with app
development. Don't let Phase 1 dates slip the content cadence; decouple "days since we started
posting" from "days since Phase 0 began."

---

## Phase 0 — Week 1 (before code is done)

Goal: landing page + waitlist live, socials live, daily posting started. Per §22 this starts
**before the app is buildable** — it only needs the positioning line and the content pillars below.

### Checklist

**Manual user actions — these are accounts/signups a person has to do; no agent can create them:**

- [ ] Register/confirm the domain for the landing page (e.g. a `zano.app`-style domain).
- [ ] Create the waitlist landing page (e.g. Carrd, Framer, or a simple hosted page) with the
      positioning line as the headline and an email capture field.
- [ ] Connect the waitlist form to an email tool that can send a batch message later (e.g. a
      Google Form → Sheet, or a waitlist tool with built-in email export) — Phase 1 recruitment
      depends on being able to message everyone on this list at once.
- [ ] Create the TikTok account.
- [ ] Create the Instagram account (Reels).
- [ ] Create the YouTube channel (Shorts).
- [ ] Put the landing page link in all three bios.
- [ ] Decide who is on camera / whose voice this is (founder-led, per content pillar 3 below) —
      this is a one-time decision, not a per-post one.

**Agent-doable / content prep (can happen alongside the manual steps above):**

- [ ] Draft the first week of posts using the hooks list below (script beats, not full edits).
- [ ] Draft the waitlist confirmation email copy (what people get, what happens next, rough
      timeline).
- [ ] Set up a simple content calendar (even a markdown table or spreadsheet) so "post daily"
      survives someone being busy on a given day — batch-film when possible, schedule the posts.

### Content pillars (repeat forever, per §22)

1. The shield moment — screen recording of trying to open TikTok → blocked → "gym is 6 min away."
2. Earned unlock celebration after a workout.
3. Founder progress — your own streak, rank, protein. Authentic, imperfect > polished.
4. Weekly Report Card screenshots.
5. "Locked out" reaction clips from friends/testers.
6. Educational — why willpower fails, why the phone is the lever.

### Hooks to test (Week 1 batch — 5 variations each, per §22)

Post daily, rotate pillars so it's not the same beat every day. Starting hook set:

1. "My phone won't let me open TikTok until I hit the gym."
2. "I made my phone earn-only."
3. "Day 30 of earning my screen time." *(reframe as "Day 1" / "building this" for Week 1, since
   there's no 30-day streak yet — don't fabricate a streak that doesn't exist; film the real Day 1
   and let the number climb honestly in later posts.)*
4. "POV: your phone is your gym buddy now."
5. "The lock screen widget that fixed my consistency."

Track which of these gets the best watch-through / saves / comments in Week 1 — that early signal
feeds the Phase 3 hook-selection decision below, even though the real call happens post-launch.

---

## Phase 1 — Week 4: TestFlight tester recruitment

Goal (§22): 50–200 testers from the waitlist and DMs, 10 real quotes collected, onboarding
drop-off gets fixed from what testers hit.

**Dependency flag:** actually shipping a TestFlight build requires Apple Developer Program
enrollment (not done yet) and a Mac to archive/upload the build. If those are still blocked when
Week 4 arrives, recruitment messaging below can still go out on a delay — send it when the build is
truly about to land, not on a fixed calendar date, so testers don't go cold waiting.

### Recruitment message — waitlist email

Subject: `You're in — ZANO beta starts now`

```
Hey — you signed up for ZANO a few weeks ago ("the app that won't let you open TikTok until
you hit the gym"). It's ready for a first real test, and I want you in it.

What this is: an iPhone TestFlight beta. Rough edges expected — that's the point of testing
now instead of later.

What I need from you:
1. Install via this TestFlight link: [LINK]
2. Use it for real for a few days — set a goal, try to unlock an app, see what breaks
3. Reply to this email (or DM me) with what worked, what didn't, and one honest sentence
   about whether it actually got you to the gym / off your phone

Takes 10 minutes to set up, and I read every reply myself.

— [Founder name]
```

### Recruitment message — DM / social (shorter, for people who commented/engaged but aren't on
the waitlist)

```
Hey! Saw you [liked/commented on] the ZANO posts — it's ready for early testers on TestFlight.
Want in? It's free, takes 2 min to set up, and I'd love your honest take. Just need your email
or Apple ID to send the invite.
```

### Collecting the 10 quotes

- Ask for a quote explicitly once a tester has a few days of real use — don't ask on install day,
  the honest reaction (positive or negative) needs a real earned-unlock moment behind it.
- Suggested follow-up prompt once someone reports back: *"Mind if I quote that (first name only)
  on the landing page / in a post? No worries if not."* Always get explicit opt-in before using a
  name or clip publicly.
- Log responses somewhere durable (a simple sheet: name, quote, date, opted-in-to-share y/n) —
  this doc doesn't own that tracker, but Phase 1 execution should create one.
- Fix onboarding drop-off from what these 50–200 testers actually hit, not from guesses — this is
  the point of Phase 1 existing before Phase 2 spend.

---

## Phase 2 — Week 6–8: App Store launch + creator outreach

Goal (§22): App Store launch, 10–20 micro-creators (gym/discipline niche, 5k–100k followers) paid
flat fees for authentic reaction videos, creative freedom given per the Bloom lesson cited in spec.
TikTok is the channel; Product Hunt is optional.

**Same dependency flag as Phase 1** — App Store submission needs the Apple Developer Program
enrollment and a Mac build pipeline. Creator *outreach and negotiation* can start before that's
resolved (creators need lead time anyway); just don't promise a hard posting date until the App
Store listing is actually live.

### Creator outreach message template

Target: 5k–100k followers, gym/discipline/productivity niche, posts authentic reaction-style
content (not overly produced ads — that's the point of "creative freedom").

```
Hey [name] — love your [gym / discipline / productivity] content, especially [specific post —
reference something real, not generic flattery].

I'm the founder of ZANO, an iPhone app that locks distracting apps (TikTok, IG, etc.) until you
complete a real goal — gym session, protein target, focus block. Basically: your phone stops
working against you.

I'd love to send you early access and pay you a flat fee for an honest reaction video — good,
bad, or mixed, your call. I'm not going to script it or ask for approval rights on the final cut;
you know your audience better than I do. If it's not for you, no hard feelings and no post.

Fee: $[X] flat for one video, paid on posting (or half up front if that's easier for you).
Timeline: [posting window].

Want me to send the details / a TestFlight invite?
```

Notes for whoever sends these:
- Personalize the bracketed reference every time — a template that reads as a template gets
  ignored by exactly the creators worth working with.
- "Creative freedom" is not just a line in the DM — it means not sending a script, not requiring
  pre-approval of the final cut, and not asking for reshoots because the take wasn't flattering
  enough. That's the actual Bloom lesson the spec is citing.
- Negative or mixed reactions are still useful signal and still worth paying for, as long as
  they're honest — don't only pay for praise.

### Budget tracker — $0–500 initial creator spend

Target CAC stays below 30% of first-year LTV (§22) once this scales past the initial flat-fee
batch; for this first $500 the goal is signal and content, not a CAC calculation yet.

| # | Creator (handle) | Followers | Niche fit | Fee agreed | Paid (Y/N + date) | Content due | Posted (date + link) | Views | Installs / promo redemptions | Status | Running total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | Outreach sent | $0 |
| 2 | | | | | | | | | | | |
| 3 | | | | | | | | | | | |
| 4 | | | | | | | | | | | |
| 5 | | | | | | | | | | | |
| 6 | | | | | | | | | | | |
| 7 | | | | | | | | | | | |
| 8 | | | | | | | | | | | |
| 9 | | | | | | | | | | | |
| 10 | | | | | | | | | | | |

**How to use this table:**
- Add a row per creator contacted, even before a fee is agreed — it doubles as an outreach log.
- "Running total" is cumulative `Fee agreed` for everyone with `Paid = Y`, so it's always the true
  spend-to-date against the $500 cap, not the pipeline total.
- Track installs via a unique promo code or link-in-bio UTM per creator — without that, "which
  creator drove installs" is a guess, and that guess is exactly what Phase 3's hook/creator
  decisions need to not be.
- Status values: `Outreach sent` → `Negotiating` → `Confirmed` → `Content delivered` →
  `Posted` → `Paid`. Keep a row's status current so the $500 cap is easy to see at a glance.
- Stop new outreach once committed fees (not just posted content) hit $500, unless revenue from
  the launch is already funding the next batch (§22: "reinvest revenue into creators").

---

## Phase 3 — Scale

Goal (§22): double down on the 2–3 hooks that drove installs, launch the referral loop (friend
invite → freeze), push Gym Home Turf for local spread, launch monthly challenges on fresh-start
dates.

### Choosing the 2–3 hooks to double down on

Don't pick by gut feel or by which post the founder likes best — use the funnel data from §23:

1. Pull every posted hook (Phase 0's initial 5, plus whatever variations came out of Phase 0/1/2)
   and rank by **install rate per view** first, not raw views — a lower-view hook that converts
   better is worth more than a viral hook that doesn't convert.
2. Cross-check against **D1/D7 retention of the users each hook brought in** (§23 targets: D1 >
   45%, D7 > 25%). A hook that installs well but brings in users who churn by D1 is attracting the
   wrong audience, not a good hook to scale — this matters more than the install number alone.
3. Pick the top 2–3 by that combined read (install rate × D7 retention of that cohort), not by
   count of hooks tested. If only one hook clears the bar, scale one, don't force a third for
   symmetry.
4. Re-test the winning 2–3 with fresh variations (new footage, same core hook) rather than
   reposting the exact same clip — audiences fatigue on repeats faster than on a repeated idea.
5. Revisit this ranking on a cadence (e.g. every 2–4 weeks) rather than locking it in once —
   Phase 3 is "scale," not "set and forget."

### Referral loop timing (friend invite → freeze)

- Ship the referral loop once there's a retained cohort to refer *from* — referrals from users who
  haven't hit their own first earned unlock yet produce low-quality invites. Practically: gate the
  invite prompt behind the user's own D1 retention moment (first earned unlock), not behind
  account creation.
- "Freeze" as the referral reward ties directly to the core loop (spec §2/§8 retention psychology)
  — a friend joining should read as a tangible benefit (a day of grace) rather than a generic
  referral discount, consistent with the product's "earn, don't restrict" framing (§1).
- Don't launch the referral loop simultaneously with a new hook push — isolate the two changes so
  it's possible to tell which one moved the numbers.

### Gym Home Turf & monthly challenges

- Gym Home Turf (local spread mechanic — see spec for the feature's exact shape) is a Phase 3
  lever specifically for geographic density: it works best seeded in a small number of gyms/cities
  first rather than spread thin nationally, so early installs concentrate enough for the local
  effect to be visible.
- Monthly challenge launches should land on culturally "fresh start" dates (1st of the month, New
  Year, etc. — per §22) since that's when the target audience (§1: 17–27, "locked in" culture) is
  already primed to commit to something new. Plan challenge content a few days ahead of the date,
  not on the date itself.

---

## Open items / dependencies to watch

- Apple Developer Program enrollment and Mac availability gate Phases 1–2's actual ship dates
  (per `CLAUDE.md` current environment status) — Phase 0 content should not reference a specific
  TestFlight or App Store date until those are unblocked.
- The waitlist → email tool connection (Phase 0 checklist) is a hard dependency for Phase 1
  recruitment; if it's skipped in Week 1, Phase 1 has no list to message in Week 4.
- Promo codes / UTM links per creator (Phase 2 budget tracker) need to exist *before* the first
  creator posts, or Phase 3's hook-ranking data will be incomplete for that batch.
