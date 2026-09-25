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
| 5b | Premium UI + UX pass: design system, ZANO Blue + dark base, living star (screen-time charge), glass tab bar, paywall v4, brand v2/v3, unlock moment, shield, widgets, recap story, onboarding, empty states | `claude/sharp-euler-npwt08` | §15, §16, §5.1, §5.15, §7, §21 | Scaffolded — Unverified on device (CI green: run 36053520709 / bc74bf4 — app, extensions, 231 Core tests, screenshot tour; device-only: Screen Time report, shield, widgets, haptics). Since then: NFC onboarding + build-out Waves 0–3 (gym setup/check-in, NFC tags, goals editor, lock schedules + Earn Mode spend, health pause, meal photos, Today suggestion cards, Squad tab, ranks/seasons/referrals/variable rewards). Wave 1 CI green (run 36078947162); Waves 2–3 compiling in CI. Backend-dependent parts run offline; device-only parts unverified | 2026-09-25 | [05b-premium-ui.md](sessions/05b-premium-ui.md) |
| 6 | Onboarding (14 screens; 15 since the 2026-09-24 NFC tags screen) + permission priming + RevenueCat paywall + first-win flow | `main` | §7, §21 | Scaffolded — Unverified | 2026-09-22 | [06-onboarding.md](sessions/06-onboarding.md) |
| 7 | Supabase: schema, RLS, auth (anon → Apple), storage, sync Edge Function, RevenueCat webhook | `main` | §11, §13 | Scaffolded — Unverified (partial: sync client wiring to the app still open) | 2026-09-22 | [07-backend.md](sessions/07-backend.md) |
| 8 | AI: meal-vision Edge Function, quick repeats, weekly recap job + card + share image | `main` | §9.5, §9.6, §5.14 | Scaffolded — Unverified | 2026-09-22 | [08-ai.md](sessions/08-ai.md) |
| 9 | Streak logic: freezes, Never Miss Twice, Plan B, Comeback; adaptive engine v1 (rules) | `main` | §5.5, §5.6, §8, §9.1 | Scaffolded — Unverified | 2026-09-22 | [09-retention.md](sessions/09-retention.md) |
| 10 | Earn Mode (Time Bank), Dynamic Island earn meter, partial unlock tiers | `main` | §5.2, §5.11 | Scaffolded — Unverified | 2026-09-22 | [10-earn-mode.md](sessions/10-earn-mode.md) |
| 11 | Squads, duels, nudges, referral, share cards, Locked-Out moment | `main` | §5.7, §5.16, §9.3 | Scaffolded — Unverified | 2026-09-22 | [11-social.md](sessions/11-social.md) |
| 12 | ML service: slip risk + nudge bandit; pg_cron feature job | `main` | §9.2, §9.3, §9.9 | Scaffolded — Unverified (nudge bandit itself still needs real delivered/acted data, see session doc) | 2026-09-22 | [12-ml-service.md](sessions/12-ml-service.md) |
| 13 | Watch app, gym leaderboard, seasons/ranks, cosmetics | `main` | §5.8, §5.9, §5.17, §5.21 | Scaffolded — Unverified (Watch upgraded from skeleton to real complications/wrist controls/haptics in wave 5 — still the least-verified slice, zero watchOS SDK to check against) | 2026-09-22 | [13-v3-slices.md](sessions/13-v3-slices.md) |

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
