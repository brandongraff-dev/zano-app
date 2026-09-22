# ZANO — Progress Board

**Read this before starting any session.** It is more current than your memory of a past
conversation. Every agent updates their own row after every coding task — see `CLAUDE.md`
"Reporting protocol." Status meanings:

- `Not Started` — nothing built yet
- `In Progress` — actively being worked
- `Blocked` — can't proceed, blocker named below
- `Scaffolded — Unverified` — code/config written but the session's real definition-of-done
  (per `docs/spec.md` §17) hasn't been verified (usually: needs a Mac/device we don't have yet)
- `Done` — definition-of-done met and verified

## Environment & accounts

| Item | Status | Note |
|---|---|---|
| Mac (for Xcode) | ❌ Not available | Blocks all real builds/device testing. See `docs/setup/windows-workflow.md` for what proceeds anyway. |
| GitHub | ✅ Ready | Repo is local-only so far — push only when asked. |
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
| 6 | Onboarding (14 screens) + permission priming + RevenueCat paywall + first-win flow | `main` | §7, §21 | Scaffolded — Unverified | 2026-09-22 | [06-onboarding.md](sessions/06-onboarding.md) |
| 7 | Supabase: schema, RLS, auth (anon → Apple), storage, sync Edge Function, RevenueCat webhook | `main` | §11, §13 | Scaffolded — Unverified (partial: sync client wiring to the app still open) | 2026-09-22 | [07-backend.md](sessions/07-backend.md) |
| 8 | AI: meal-vision Edge Function, quick repeats, weekly recap job + card + share image | `main` | §9.5, §9.6, §5.14 | Scaffolded — Unverified | 2026-09-22 | [08-ai.md](sessions/08-ai.md) |
| 9 | Streak logic: freezes, Never Miss Twice, Plan B, Comeback; adaptive engine v1 (rules) | `main` | §5.5, §5.6, §8, §9.1 | Scaffolded — Unverified | 2026-09-22 | [09-retention.md](sessions/09-retention.md) |
| 10 | Earn Mode (Time Bank), Dynamic Island earn meter, partial unlock tiers | `main` | §5.2, §5.11 | Scaffolded — Unverified | 2026-09-22 | [10-earn-mode.md](sessions/10-earn-mode.md) |
| 11 | Squads, duels, nudges, referral, share cards, Locked-Out moment | `main` | §5.7, §5.16, §9.3 | Scaffolded — Unverified | 2026-09-22 | [11-social.md](sessions/11-social.md) |
| 12 | ML service: slip risk + nudge bandit; pg_cron feature job | `main` | §9.2, §9.3, §9.9 | In Progress (skeleton + tests passing; real feature job/training pipeline landing now) | 2026-09-22 | [12-ml-service.md](sessions/12-ml-service.md) |
| 13 | Watch app, gym leaderboard, seasons/ranks, cosmetics | `main` | §5.8, §5.9, §5.17, §5.21 | In Progress (build agents landing now, not yet hardened/consolidated) | 2026-09-22 | [13-v3-slices.md](sessions/13-v3-slices.md) |

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

## Physical product track (`docs/spec.md` §25 — separate from app sessions, starts once revenue exists)

| Product | Status | Note |
|---|---|---|
| Tag Pack | Not Started | Earliest hardware milestone — Weeks 9-12 per roadmap §26 |
| Lock Card | Not Started | Weeks 13-20 |
| Shaker | Not Started | Weeks 13-20 |
| Protein/electrolyte | Not Started | Week 21+ |
