# ZANO build-out plan (2026-09-24)

Source: read-only audit of spec §1–§28 vs the code (App/, Core/, Extensions/, Watch/). Nothing here
is built yet. "Engine" = Core logic; "UI" = user-facing screens.

## The blocker: the core loop isn't wired
Goals can be logged, but nothing turns "goal verified" into "apps unlock":
- Nothing ends a lock as **earned** (`LockEngineManager.endLock(.earned)` is only reached via an intent
  nothing calls; onboarding's first win is the only earned unlock).
- **Protein/water never count**: `isGoalVerified` accepts `.complete/.planB/.freeze`, but the log
  intents write `.verify` and nothing converts "target reached" into `.complete`.
- **Gym workouts never complete**: `GymVerifier` writes no `GoalEvent`.
- **Streaks and Time Bank** are never updated after onboarding.
- **ZANOMonitor** extension is empty: scheduled locks and Bedtime Gate pickups do nothing.

**P0-0 — GoalCompletionCoordinator (Core, M):** every intent/verifier calls it after writing an event;
it rolls `.verify` totals into one `.complete`, evaluates unlock eligibility → `endLock(.earned)` →
streak → Time Bank deposit (Earn Mode) → duel points. GymVerifier completion writes `.complete`
(`source: .geofence`). Tests in CoreTests.

## Feature map (UI status)
| Area | UI | Notes |
|---|---|---|
| Lock, lock sets, emergency unlock, shield | Done | |
| Earned unlock | Built, never triggered | needs P0-0 |
| Scheduled daily lock | None | monitor extension empty |
| **Gym setup** | Partial | "use current location" only — no address search / pin drop |
| **Geofence + dwell** | Partial | only via Today "Go"; no auto-arrival, no check-in screen, no Live Activity, lost if app killed |
| Location permission priming (Always) | None | Always asked silently |
| **Manual gym check-in fallback** | None | required by spec §24 |
| Home workout / steps (HealthKit) | None | verifiers exist, never started; no Health permission flow |
| **NFC scan + map** | Partial | Settings only; works only with pre-encoded tags |
| **NFC tag writing (blank tags)** | None | blank tags fail with a generic error |
| NFC tap confirmation / unmapped tag | None | background taps give no feedback; unmapped tag = dead end |
| Lock Card (tap to lock / status) | None | |
| Goals editor | Partial | only gym, focus, protein can be added |
| Meal photo → protein, meal prep, stretch | None | backend/verifiers exist, no UI |
| Earn Mode / Time Bank / partial tiers | Partial | display only |
| Plan B, travel, comeback, calendar | None / partial | engines exist, no UI |
| Nudges, health pause | None / explanation only | |
| Squads, duels, leaderboard, seasons, referrals | None | need Supabase live |
| Weekly recap | UI done | data only arrives via sync (not live) |
| Locked-out moment, Founder card, gear store | Built, unreachable/hidden | |

## Build waves (files don't overlap within a wave)
**Wave 0:** P0-0 coordinator.
**Wave 1 (P0):**
- A. Gym/location — `Features/GymSetup/` (address search + pin drop, permission primer, live check-in
  screen with dwell ring + Live Activity, manual check-in fallback), `GymPresenceService` (auto arrival).
- B. NFC — `Features/NFC/` (tags list out of Settings, write-a-blank-tag flow + `NFCWriter`, tap toast,
  unmapped-tag handler, Lock Card setup), new actions: start focus, gym check-in, custom goal, status.
- C. Goals — all additive types in the editor, per-type "how it's verified" + setup next step,
  HealthKit permission primer.
- D. Today — live steps/home-workout rows, gym row → check-in screen.
**Wave 2 (P1):** lock schedule editor + Earn Mode settings + real monitor extension; streak-protection
cards (Plan B, comeback, travel, calendar light day); meal photo capture; health pause + nudge settings.
**Wave 3 (P2, needs Supabase):** Squad tab (squads, duels, nudges); ranks/seasons/leaderboard; referrals,
locked-out card, variable reward; setup guides and post-onboarding checklist.

## New ideas (additive; emergency unlock untouched)
1. Gym Bag Tag check-in (tap starts dwell — works with bad GPS)
2. Tag Quest: place and tap all 5 pack tags in week 1 → badge + coins
3. Morning chain combo: Sunrise → water → creatine tags within 10 min → bonus minutes
4. "On my way" shield: "Gym in 6 min · you're on the way"
5. Rest-day planner that keeps the streak
6. Tag health panel: last tap per tag, "not seen in 5 days", reorder
7. Earned Lock Screen wallpaper that charges with the streak (coins)
8. Squad co-focus "Study Hall"
9. Witness for honor goals (bonus coins only)
10. Reflection + Plan B offer after an emergency unlock (never blocks it)
11. Heat-aware hydration bonus (opt-in)
12. Monthly Workout Wrapped heatmap poster
13. Lock Card desk mode (phone on card starts focus)
14. Watch double-tap logging
15. 8 PM protein "last mile" nudge when within 20 g
