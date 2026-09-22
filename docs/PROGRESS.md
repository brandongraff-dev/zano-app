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
| 1 | Data models (SwiftData), Store, outbox Sync skeleton, PostHog/Sentry | `feat/core` | §13 | Not Started | — | — |
| 2 | Lock Engine: FamilyActivityPicker, lock sets, shields on/off, DeviceActivity schedules, Shield Config + Action extensions, emergency unlock | `feat/lock` | §2, §6, §24 | Not Started | — | — |
| 3 | Verification: gym geofence + dwell + HealthKit, auto-detect, focus timer + Live Activity, Core Motion anti-cheat | `feat/verify` | §3, §9.4 | Not Started | — | — |
| 4 | App Intents catalog + widgets (S/M/L, lock screen) + Controls + Siri + NFC reader/mapping | `feat/intents` | §6, §14 | Not Started | — | — |
| 5 | Design system + screens: Today, Lock, Fuel, Progress, Settings | `feat/ui` | §15 | Not Started | — | — |
| 6 | Onboarding (14 screens) + permission priming + RevenueCat paywall + first-win flow | `feat/onboarding` | §7, §21 | Not Started | — | — |
| 7 | Supabase: schema, RLS, auth (anon → Apple), storage, sync Edge Function, RevenueCat webhook | `feat/backend` | §11, §13 | Not Started | — | — |
| 8 | AI: meal-vision Edge Function, quick repeats, weekly recap job + card + share image | `feat/ai` | §9.5, §9.6, §5.14 | Not Started | — | — |
| 9 | Streak logic: freezes, Never Miss Twice, Plan B, Comeback; adaptive engine v1 (rules) | `feat/retention` | §5.5, §5.6, §8, §9.1 | Not Started | — | — |
| 10 | Earn Mode (Time Bank), Dynamic Island earn meter, partial unlock tiers | `feat/earn` | §5.2, §5.11 | Not Started | — | — |
| 11 | Squads, duels, nudges, referral, share cards, Locked-Out moment | `feat/social` | §5.7, §5.16, §9.3 | Not Started | — | — |
| 12 | ML service: slip risk + nudge bandit; pg_cron feature job | `feat/ml` | §9.2, §9.3, §9.9 | Not Started | — | — |
| 13 | Watch app, gym leaderboard, seasons/ranks, cosmetics | `feat/v3` | §5.8, §5.9, §5.17, §5.21 | Not Started | — | — |

**Ordering rule (spec §17):** Session 5 depends on 1 and 4's intents; 6 depends on 5; 7 can run in
parallel with 2–5 once §13 (data model) is frozen. Session 0 froze §13 as-written — see session doc.

## Physical product track (`docs/spec.md` §25 — separate from app sessions, starts once revenue exists)

| Product | Status | Note |
|---|---|---|
| Tag Pack | Not Started | Earliest hardware milestone — Weeks 9-12 per roadmap §26 |
| Lock Card | Not Started | Weeks 13-20 |
| Shaker | Not Started | Weeks 13-20 |
| Protein/electrolyte | Not Started | Week 21+ |
