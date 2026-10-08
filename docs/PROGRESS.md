# ZANO — Progress Board

**Read this before starting any session.** It is more current than your memory of a past
conversation. Every agent updates their own row after every coding task — see `CLAUDE.md`
"Reporting protocol." Status meanings:

- `Not Started` — nothing built yet
- `In Progress` — actively being worked
- `Blocked` — can't proceed, blocker named below
- `Scaffolded — Unverified` — code/config written but the session's real definition-of-done
  (per `docs/spec.md` §17) hasn't been verified (usually: needs a Mac/device we don't have yet)
- `Compiles + tested in CI` — (added 2026-09-23) builds on a real Xcode toolchain for the iOS
  Simulator and its unit tests pass in GitHub Actions. Still NOT verified on a device, and anything
  needing FamilyControls / DeviceActivity / NFC / HealthKit workouts cannot run in the Simulator at
  all (spec §27) — so the session's device-level definition-of-done is still open.
- `Done` — definition-of-done met and verified

**Where things actually stand (2026-09-23):** the whole app — main target, all 5 extensions, and
`Core` — compiles on real Xcode, and `Core`'s 231 tests pass, on every push (GitHub Actions run
35934393207 was the first fully green run). Getting there took 12 CI rounds: ~41 → 12 → 4 → 8 → … → 0
compiler errors, plus 6 test failures (1 real bug, 5 wrong test assumptions). The per-session rows
below still say `Scaffolded — Unverified` because they describe device-level verification; treat
"compiles + unit tests pass" as the new floor for all of them.

## Environment & accounts

| Item | Status | Note |
|---|---|---|
| Mac (for Xcode) | ❌ Not available locally | GitHub Actions macOS runners act as the compiler/test host (see below) — a Mac is only needed for device testing and the Simulator UI. |
| GitHub + CI | ✅ Live | Private repo `brandongraff-dev/zano-app`; `.github/workflows/ci.yml` builds, tests, and screenshots the app in the iOS Simulator on every push. |
| Apple Developer Program | ❌ Not enrolled | Blocks Family Controls entitlement filing + TestFlight/App Store. See `docs/setup/apple-developer.md`. Local device testing works without it once a Mac+device exist (Family Controls Development capability). |
| Family Controls entitlement (4 requests) | ❌ Not filed | Needs Apple Developer enrollment first. Can take days–weeks once filed — file it the day enrollment completes. |
| Supabase project | ❌ Not created | Schema/migrations scaffolded locally in `backend/supabase/` ahead of time (Session 0). Needs `supabase` CLI + a project to actually run against. |
| RevenueCat account | ❌ Not created | Needed starting Session 6 (paywall). |
| PostHog account | ❌ Not created | Needed starting Session 1. |
| Sentry account | ❌ Not created | Needed starting Session 1. |
| Domain / App Store Connect listing | ❌ Not started | Needed before TestFlight. |

## Sessions (`docs/spec.md` §17)

| # | Session | Branch | Spec §§ | Status | Last updated | Session doc |
|---|---|---|---|---|---|---|
| 0 | Repo, CLAUDE.md, spec, Xcode project (all targets), App Group, Core package, CI to TestFlight | `main` | §11, §12, §17, §18, §24 | Scaffolded — Unverified | 2026-09-22 | [00-repo-and-stack-setup.md](sessions/00-repo-and-stack-setup.md) |
| 1 | Data models (SwiftData), Store, outbox Sync skeleton, PostHog/Sentry | `main` | §13 | Scaffolded — Unverified | 2026-09-22 | [01-foundation.md](sessions/01-foundation.md) |
| 2 | Lock Engine: FamilyActivityPicker, lock sets, shields on/off, DeviceActivity schedules, Shield Config + Action extensions, emergency unlock | `main` | §2, §6, §24 | Scaffolded — Unverified | 2026-09-22 | [02-lock-engine.md](sessions/02-lock-engine.md) |
| 3 | Verification: gym geofence + dwell + HealthKit, auto-detect, focus timer + Live Activity, Core Motion anti-cheat | `main` | §3, §9.4 | Scaffolded — Unverified | 2026-09-22 | [03-verification.md](sessions/03-verification.md) |
| 4 | App Intents catalog + widgets (S/M/L, lock screen) + Controls + Siri + NFC reader/mapping | `main` | §6, §14 | Scaffolded — Unverified | 2026-09-22 | [04-intents-widgets.md](sessions/04-intents-widgets.md) |
| 5 | Design system + screens: Today, Lock, Fuel, Progress, Settings | `main` | §15 | Scaffolded — Unverified | 2026-09-22 | [05-design-system.md](sessions/05-design-system.md) |
| 5b | Premium UI + UX pass: design system, ZANO Blue + dark base, living star (screen-time charge), glass tab bar, paywall v4, brand v2/v3, unlock moment, shield, widgets, recap story, onboarding, empty states | `claude/sharp-euler-npwt08` | §15, §16, §5.1, §5.15, §7, §21 | Scaffolded — Unverified on device (CI green: run 36053520709 / bc74bf4 — app, extensions, 231 Core tests, screenshot tour; device-only: Screen Time report, shield, widgets, haptics). Since then: NFC onboarding + build-out Waves 0–3 (gym setup/check-in, NFC tags, goals editor, lock schedules + Earn Mode spend, health pause, meal photos, Today suggestion cards, Squad tab, ranks/seasons/referrals/variable rewards). Retention pass 2026-10-02 (7-step onboarding with a real first win, Lock Screen/Control Center/StandBy widgets, milestone share moments, lock status + Time Bank borrow). Gaps closed 2026-09-28 (Plan B credit, travel mode, missed-day reconcile, per-hour locked-out tally, nudge scheduling, invite links); CI green incl. 300 Core tests and crash-free screenshot tour (run 36491066217). Backend-dependent parts run offline; device-only parts unverified | 2026-10-02 | [05b-premium-ui.md](sessions/05b-premium-ui.md) |
| 5c | Visual direction v2: aurora ink canvas, glass system, score/rounded type, five-tab glass bar (Squad hidden), Today + Lock redesign; passes 2–3 (playful, restraint); light mode; buddies (9 pickable 48px pixel-art mascots with 8 charge faces, app icon per buddy, levels + earned gear) | `main` | §15, §16, §5.1, §24 | Scaffolded — Unverified on device. CI green through ac0a36b (run 37159734871: build incl. extensions, Core tests incl. BuddyTests, screenshot tour with light pass, buddy-picker, buddy-gear, buddy-brick-today). Done in CI: light mode, buddy picker (onboarding step 2 + Settings), buddy replaces the star app-wide, 8 charge faces, buddy everywhere (shield icon, focus Live Activity, notification images, empty states, NFC toast, launch screen), alternate app icon per buddy, levels + gear (party hat/shades/beanie/crown, earned only) with Today toast, Summer Strong rename. Device-only: shield/report/widgets/Live Activity/notification images, icon switching alert, haptics | 2026-10-04 | [05c-visual-v2.md](sessions/05c-visual-v2.md) |
| 6 | Onboarding (14 screens; 15 since the 2026-09-24 NFC tags screen) + permission priming + RevenueCat paywall + first-win flow | `main` | §7, §21 | Scaffolded — Unverified | 2026-09-22 | [06-onboarding.md](sessions/06-onboarding.md) |
| 7 | Supabase: schema, RLS, auth (anon → Apple), storage, sync Edge Function, RevenueCat webhook | `main` | §11, §13 | Scaffolded — Unverified (partial: sync client wiring to the app still open) | 2026-09-22 | [07-backend.md](sessions/07-backend.md) |
| 8 | AI: meal-vision Edge Function, quick repeats, weekly recap job + card + share image | `main` | §9.5, §9.6, §5.14 | Scaffolded — Unverified | 2026-09-22 | [08-ai.md](sessions/08-ai.md) |
| 9 | Streak logic: freezes, Never Miss Twice, Plan B, Comeback; adaptive engine v1 (rules) | `main` | §5.5, §5.6, §8, §9.1 | Scaffolded — Unverified | 2026-09-22 | [09-retention.md](sessions/09-retention.md) |
| 10 | Earn Mode (Time Bank), Dynamic Island earn meter, partial unlock tiers | `main` | §5.2, §5.11 | Scaffolded — Unverified | 2026-09-22 | [10-earn-mode.md](sessions/10-earn-mode.md) |
| 11 | Squads, duels, nudges, referral, share cards, Locked-Out moment | `main` | §5.7, §5.16, §9.3 | Scaffolded — Unverified | 2026-09-22 | [11-social.md](sessions/11-social.md) |
| 12 | ML service: slip risk + nudge bandit; pg_cron feature job | `main` | §9.2, §9.3, §9.9 | Scaffolded — Unverified (nudge bandit itself still needs real delivered/acted data, see session doc) | 2026-09-22 | [12-ml-service.md](sessions/12-ml-service.md) |
| 13 | Watch app, gym leaderboard, seasons/ranks, cosmetics | `main`, `claude/sharp-euler-npwt08` (13b) | §5.8, §5.9, §5.17, §5.21 | Scaffolded — Unverified on device. ZANOWatch now compiles in CI (run 37253141845): buddy with pose/gear/level, weekly boss page, celebration haptic, phone→watch sync of buddy/XP/boss. Not embedded/paired yet; complication target not built; needs Mac + paired Watch | 2026-10-05 | [13-v3-slices.md](sessions/13-v3-slices.md), [13b-watch-app.md](sessions/13b-watch-app.md) |
| 14 | Landing page redesign (light glass, screenshots, buddy) | `claude/gracious-johnson-tl2jf4` | §22, §5.13 | Done (static page, checked in headless Chromium desktop + mobile) | 2026-10-05 | [14-landing-redesign.md](sessions/14-landing-redesign.md) |
| 15 | Buddy emotions (10 activity faces x 9 buddies) + Buddy Closet (108 cosmetics: skins, hats, eyewear, neckwear, back items, backdrops) | `claude/quirky-wozniak-bf8h1v` | §5.17, §15, §24 | Compiles + Core tests pass in CI (run 105, 2026-10-06). Art checked as rendered sheets; Faces mapped (`BuddyPose(goal:moment:)`) but not yet switched on by Today/Fuel/Focus. Widgets/shield do not wear outfits yet. | 2026-10-05 | [15-buddy-emotions-closet.md](sessions/15-buddy-emotions-closet.md) |
| 16 | Age rating 13+ and the Family Link design (docs only) | `claude/quirky-wozniak-bf8h1v` | §24, §5.23 | Done (documents). Needs counsel review before submission; no code yet | 2026-10-05 | [16-age-13-and-family-link.md](sessions/16-age-13-and-family-link.md) |
| 17 | Work-hours focus lock: calendar meetings and focus blocks lock apps, learns which events to lock | `claude/quirky-wozniak-bf8h1v` | §5.24, §9.7, §24 | Compiles + Core tests pass in CI (run 105, 2026-10-06). Planner, learning memory, monitor hand-off and Settings screen written; not yet compiled. Asks only inside Settings (no Today card or notification yet); no background refresh | 2026-10-05 | [17-focus-lock.md](sessions/17-focus-lock.md) |
| 18 | Sleep wind-down check-in and on-device insights | `claude/quirky-wozniak-bf8h1v` | §5.25 | Compiles + Core tests pass in CI (run 105, 2026-10-06). Compiles only after CI | 2026-10-05 | [18-sleep-wind-down.md](sessions/18-sleep-wind-down.md) |
| 19 | Smart unlock rules by context (3 rules, suggester) | `claude/quirky-wozniak-bf8h1v` | §5.26 | Compiles + Core tests pass in CI (run 105, 2026-10-06). Whole-app only; monitor boundary needs a device | 2026-10-05 | [19-context-rules.md](sessions/19-context-rules.md) |
| 20 | Workout auto-unlock observer (Health/Strava via Health) and Year in Review | `claude/quirky-wozniak-bf8h1v` | §5.1, §5.21 | Compiles + Core tests pass in CI (run 105, 2026-10-06). No direct Strava link | 2026-10-05 | [20-health-observer-year-recap.md](sessions/20-health-observer-year-recap.md) |
| 21 | Earned It video clip with the chosen buddy | `claude/quirky-wozniak-bf8h1v` | §5.27 | Compiles + Core tests pass in CI (run 105, 2026-10-06).  | 2026-10-05 | [21-earned-it-clip.md](sessions/21-earned-it-clip.md) |
| 22 | Starter plans (goal templates) | `claude/quirky-wozniak-bf8h1v` | §5.28 | Compiles + Core tests pass in CI (run 105, 2026-10-06).  | 2026-10-05 | [22-goal-templates.md](sessions/22-goal-templates.md) |
| 23 | Family Link: parent tasks, view-once photo proof | `claude/quirky-wozniak-bf8h1v` | §5.23, §24 | Compiles + tests pass in CI (run 105). Not live: no Supabase project/Auth wired, no Apple enrollment; screen shows not-available | 2026-10-05 | [23-family-link.md](sessions/23-family-link.md) |
| 24 | Buddy faces on Today goal tiles; focus-lock question card on Today | `claude/quirky-wozniak-bf8h1v` | §5.17, §5.24 | Compiles + Core tests pass in CI (run 112). Look in the Simulator unchecked | 2026-10-06 | [24-buddy-faces-focus-ask.md](sessions/24-buddy-faces-focus-ask.md) |
| 25 | Focus break coach (Pomodoro-style rest nudge after focus blocks) | `claude/quirky-wozniak-bf8h1v` | §5.29 | Compiles + Core tests pass in CI (run 112). Look in the Simulator unchecked | 2026-10-06 | [25-break-coach.md](sessions/25-break-coach.md) |
| 26 | Launch prep: privacy/permission text fixes, hide unfinished features, Supabase setup guide, final checklist | `claude/quirky-wozniak-bf8h1v` | §24, launch docs | Compiles + Core tests pass in CI (runs 114, 115). Geofence without background location needs a device | 2026-10-06 | [26-launch-prep.md](sessions/26-launch-prep.md) |
| 27 | Planner: Apple-style calendar, tasks, reminders and event alerts | `claude/quirky-wozniak-bf8h1v` | §5.30 | Compiles + Core tests pass in CI (run 118). Notifications and the event editor need a device | 2026-10-06 | [27-planner.md](sessions/27-planner.md) |
| 28 | Sharing: share sheets for tasks and days (works now) and Household shared tasks (hidden until backend/sign-in) | `claude/quirky-wozniak-bf8h1v` | §5.31 | Scaffolded — Unverified. Awaiting CI; Household blocked on Supabase project and sign-in | 2026-10-06 | [28-household-sharing.md](sessions/28-household-sharing.md) |
| 29 | Cal (calendar character), fire/ice streak buddy, a small buddy on each tab | `claude/quirky-wozniak-bf8h1v` | §5.17a | Scaffolded — Unverified. Art checked as sheets; Swift awaits CI | 2026-10-06 | [29-page-companions.md](sessions/29-page-companions.md) |
| 30 | Onboarding character pass: buddies act out all 8 steps, Cal on the plan and paywall, CI clips | `claude/peaceful-cannon-w0thfg` | §7, §5.17a | Scaffolded — Unverified. Awaiting CI compile + clips; tap reactions need a device | 2026-10-06 | [30-onboarding-characters.md](sessions/30-onboarding-characters.md) |
| 31 | Tone down the blue: near-neutral canvas/surfaces/greys, softer accent and aurora (dark + light) | `claude/sweet-mayer-a9hzwo` | §15 | Compiles + tested in CI (run 37540966066); screenshots approved by the user. Device check still open | 2026-10-07 | [31-tone-down-blue.md](sessions/31-tone-down-blue.md) |
| 32 | Sunrise Alarm redesign: sun character (10 moods), Apple-style wake moment, repeat days / sound picker / backup alarm, time-of-day icon, clock + time wheel fixes | `claude/sunrise-redesign` | §5.10, §15 | Scaffolded — Unverified. Compiles and Core tests pass in CI (runs 141, 142 green on merged head 783775a); screenshots read. Device-only: amber Scan button (no NFC in Simulator), sound quality/playback, AlarmKit custom-sound file location, repeat/backup alarms actually firing, haptics, animation feel | 2026-10-07 | [32-sunrise-redesign.md](sessions/32-sunrise-redesign.md) |
| 33 | Privacy/Terms page generator with placeholder guard; Support page | `claude/dazzling-hypatia-ed6q5d` | §24, §22 | Support page Done (checked in headless Chromium). Privacy/Terms blocked on lawyer-approved text: the generator refuses to publish while 82 placeholders remain | 2026-10-08 | [33-legal-support-pages.md](sessions/33-legal-support-pages.md) |
| 34 | Sign in with Apple + Supabase auth; backend features switch on with keys; delete account; build keys passed to xcodebuild | `claude/dazzling-hypatia-ed6q5d` | §11, §13, §5.23, §5.31 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Needs a Supabase project, the Apple provider, keys in Codemagic/GitHub secrets, a device. Squad and referrals stay hidden (no server side yet) | 2026-10-08 | [34-apple-sign-in.md](sessions/34-apple-sign-in.md) |
| 35 | Time Bank widget (Home small/medium, Lock Screen, StandBy) | `claude/dazzling-hypatia-ed6q5d` | §5.2, §5.11, §14 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Widget look and refresh need a Simulator home screen/device | 2026-10-08 | [35-time-bank-widget.md](sessions/35-time-bank-widget.md) |
| 36 | Buddy moods on Fuel and Focus (incl. Focus Live Activity end state); outfit checks for widgets/shield | `claude/dazzling-hypatia-ed6q5d` | §5.17, §5.17a | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Live Activity, widgets and shield need a device | 2026-10-08 | [36-buddy-moods-outfits.md](sessions/36-buddy-moods-outfits.md) |
| 37 | Weekly recap: rank movement vs last week; time apps stayed locked + reached-for counts | `claude/dazzling-hypatia-ed6q5d` | §5.14, §5.21 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Attempt counts need a device | 2026-10-08 | [37-weekly-rank-time-saved.md](sessions/37-weekly-rank-time-saved.md) |
| 38 | Bedtime gate armed by DeviceActivityMonitor with the app closed | `claude/dazzling-hypatia-ed6q5d` | §2, §6, §27 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). DeviceActivity needs a device; known issue: bedtime locks can be earned by the previous day's goals (lock engine) | 2026-10-08 | [38-bedtime-gate-monitor.md](sessions/38-bedtime-gate-monitor.md) |
| 39 | Watch app embedded in the iPhone app (opt-in ZANO_EMBED_WATCH) + streak complication | `claude/dazzling-hypatia-ed6q5d` | §5.21 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Embedded build with the complication .appex also green in CI. Needs a paired Watch | 2026-10-08 | [39-watch-complication.md](sessions/39-watch-complication.md) |
| 40 | Direct Strava link (OAuth via Edge Functions, dedupe with Health) | `claude/dazzling-hypatia-ed6q5d` | §3, §5.1, §9.4 | Scaffolded — Unverified. Compiles + Core tests pass in CI (run 147, 2026-10-07). Needs Supabase + a Strava API app; official Strava button art is a founder to-do | 2026-10-08 | [40-strava.md](sessions/40-strava.md) |

**Ordering rule (spec §17):** Session 5 depends on 1 and 4's intents; 6 depends on 5; 7 can run in
parallel with 2–5 once §13 (data model) is frozen. Session 0 froze §13 as-written — see session doc.

**Branch note:** Sessions 1–13 above were all built directly on `main` by parallel background agents
(Workflow tool), not on individual `feat/*` branches as §17 originally assumed — that plan was written
for one human driving one session at a time. No git branch isolation was used; instead each agent got
an explicit non-overlapping file-ownership list so ~85 agents across three batches could write to the
same working tree concurrently without colliding. See `docs/sessions/*.md` for what each batch covered
and `docs/spec.md` §17's own ordering rule for why Foundation (Session 1 + parts of 7/8/12) had to fully
land before the other clusters started.

**§5 creative features built outside the session-per-number table:** Bedtime Gate & Sunrise Alarm
(§5.10 — headline v2 feature), Ghost Mode (§5.4), Trophy Case & Cosmetics (§5.17), Travel Mode (§5.18),
Auto-Focus Integration (§5.12), gym leaderboard (§5.8) and seasons/ranks (§5.9, normally Session 13) were
built as a dedicated follow-up batch once the core sessions' dependencies existed. See
[13-v3-slices.md](sessions/13-v3-slices.md) and [09-retention.md](sessions/09-retention.md) /
[03-verification.md](sessions/03-verification.md) addenda once that batch's completion is consolidated.

## Post-launch hardening: waves 4–6 (2026-09-22, ~50 more agents on top of the ~85 above)

Three more background batches closed the gaps found by auditing the finished build against every
spec section, in dependency order:

- **Wave 4** (23 agents): the remaining §3 goal verifiers (Steps, home/outdoor workout, stretch/
  mobility — all reusing the real `GoalType` cases, no invented duplicates), Open Food Facts barcode
  lookup, kitchen staples + protein gap planner (migration `0005`), meal-prep verifier + LLM plan
  generator, perceptual-hash photo dedupe (§9.8), calendar-density awareness (§9.7), the unlock
  celebration moment (§16 P3 — previously entirely missing), the Always-Allowed onboarding check
  (§20.2/§27 gotcha), draft privacy policy/ToS/App-Review notes (marked "needs real legal review"),
  ML-service↔Edge-Function wiring, real navigation links into previously-orphaned screens (Sunrise
  Alarm/Trophy Case/Cosmetics Shop from Settings), the §23 analytics instrumentation pass, a real
  `SyncBackend` wired to the sync Edge Function, and — critically — a dedicated repo-wide sweep that
  found and fixed 7 more instances of the exact "UI assumes a `Copy.<area>` namespace that was never
  built" bug class first caught in the Sunrise Alarm work.
- **Wave 5** (14 agents): substantial `CoreTests` coverage (the exact §9.1/§5.6 threshold tests
  flagged as needed), the Watch app upgraded from skeleton to real functionality, a real
  Thompson-sampling nudge bandit in `ml-service` (pytest-verified), onboarding drip + fresh-start
  scheduling, experiment flags, Gear contextual offers, a real `fastlane beta` lane wired into CI
  behind a safety gate, App Store listing copy, and research-backed guidance to prefer native SwiftUI
  over Lottie for the unlock-celebration/milestone moments specifically (Swift 6 concurrency gaps in
  `lottie-ios`) — reflected in `docs/dependencies.md`.
- **Wave 6** (11 agents): a research-and-audit pass (`docs/design/*.md`) followed by implementation,
  covering motion/accessibility on everything waves 4–5 weren't touching. Found and fixed a genuine
  reproducible bug (not just a style nit): `PrimaryButton`'s hold-to-commit gesture snapped its
  progress bar to 0 with no animation on the success path, duplicated in the Sunrise Alarm escape
  hatch. Found a systemic gap — **zero** uses of `accessibilityReduceMotion` anywhere in the repo
  before this wave — and added it across 16 files. Gave the Trophy Case's actual "unlock celebration"
  moment (previously zero animation) real motion.

**Cross-cutting item flagged independently by multiple agents across all three waves, not yet
resolved:** passing non-`Sendable` SwiftData `@Model` types (`Goal`, `GoalEvent`, etc.) across actor
boundaries under Swift 6 strict concurrency. This shows up anywhere a `@MainActor` service (most of
Retention/LockEngine) is called from a plain `actor` (most of Verification, for background
HealthKit/Location delivery). Every occurrence was left as-is with a clear comment rather than
guessed at, since the right fix (mark more of Core `@MainActor`, or introduce `Sendable` DTOs at
those boundaries) is an architecture decision worth making deliberately with real compiler feedback,
not patching blind. **This is the single highest-priority thing to resolve on the first real Mac
build**, before chasing anything else the compiler flags.

## Physical product track (`docs/spec.md` §25 — separate from app sessions, starts once revenue exists)

| Product | Status | Note |
|---|---|---|
| Tag Pack | Not Started | Earliest hardware milestone — Weeks 9-12 per roadmap §26 |
| Lock Card | Not Started | Weeks 13-20 |
| Shaker | Not Started | Weeks 13-20 |
| Protein/electrolyte | Not Started | Week 21+ |
