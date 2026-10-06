# Session 30 — Onboarding character pass

- **Branch:** `claude/peaceful-cannon-w0thfg` (built on `claude/quirky-wozniak-bf8h1v`, which has the 8-step flow and session 29's characters)
- **Spec sections:** §7 (onboarding flow), §5.17a (buddies / Cal), §21 (paywall rules, kept as they were)
- **Status:** Compiles + tested in CI (run 37482275783: app, watch, Core tests, UI test build, tour and clips all green, no crashes). The tap reactions are still unverified (they need a device or the Simulator UI)
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06 — buddies act out every onboarding step

- **Files touched:** `App/ZANO/Features/Onboarding/{OnboardingPlayKit,Screen1Hook,Screen3MainGoal,ScreenYourWhy,Screen4AppSelection,Screen10PlanReveal,PaywallView,Screen14FirstWin}.swift`, `App/ZANO/Features/Buddy/BuddyPickerView.swift`, `.github/workflows/ci.yml`.
- **What changed (founder ask: "fun, with super good and cool animations"):**
  - PlayKit: `OnboardingBuddyActor`, a buddy in a pose that hops (Core's `zanoMascot` jump, plus an optional burst) every time its pose changes. `OnboardingGuideStar` takes a `pose`. `OnboardingChargeButton` reports its charge (`onChargeChange`).
  - 1 Hook: the buddy runs in from the left with hops, two crewmates (one cozy, one hype) pop up beside it, then it acts out Lock it / Earn it / Get it back (guarding, lifting, ecstatic) as each sticker lands one at a time, and settles happy.
  - 2 Buddy picker: picking spins the hero round to the new buddy, which cheers and then settles; the picked tile cheers and hops; the other tiles bob out of step with each other; "Team up" is ecstatic, with a burst and a success haptic, then moves on after 0.55s.
  - 3 Main goal: the guide acts out the answer (lifting, eating, guarding, focused, flexing); "All of it" fires a confetti `CelebrationBurst`.
  - 4 Your why: a buddy in the counter card's corner whose face matches the hours (happy, meh, sad, drained); once the count-up finishes, the "+N days back" sticker bounces and the buddy cheers.
  - 5 Apps: the guide guards with a padlock, then blazes once apps are picked; the picked app tiles drop in one after another.
  - 6 Plan: the build beat's buddy tinkers with a hammer, hops at each checked row, then turns proud; Cal sits on the schedule row; during the hold the guide lifts, then blazes past 70%, then turns ecstatic on commit.
  - 7 Paywall: the hero sleeps until the padlock pops, then goes ecstatic and settles happy; the timeline nodes light up in turn; the reminder node is Cal (happy while the reminder is on, asleep when it's off). Prices, dates, terms and the CTA are unchanged.
  - 8 First win: the buddy dozes in the ring (sleepy motion); on start it yawns for about 1.4s, then focuses.
  - CI: records a ~6s clip of each onboarding step from launch (`shots/clip-onboarding-N.mp4`).
- **Decisions:** no new libraries and no new copy. Every motion goes through Core's existing mascot, burst and spring tokens. Reduce Motion: the faces still change and nothing moves. The CTAs work from the first frame on every step; the only added wait is 0.55s after "Team up".
- **Known issues / not done:** the clips only show each screen's intro (CI can't tap), so the tap reactions (picker, goal, apps, hold) need a device or the Simulator UI. There is no conversion data yet: PostHog isn't set up, so we can't compare drop-off per step before and after.
- **Needs verification on:** CI compile; the clips and screenshots (layout of the hook's crew row and the corner buddy on Your why, especially on the SE); a device for the haptics.

### 2026-10-06 — first CI clips reviewed

- **Result:** run 37482275783 passed (build, watch, Core tests, UI test build, screenshot tour, 8 clips, no crash reports). The screenshots show the crew on the Hook, Cal on the plan and the paywall, and the corner buddy on Your why; the SE layout still fits.
- **Fixed:** the Hook hero's hop (Core's leap is 0.42 of the size, ~54pt at 128pt) reached the wordmark. It now hops at half height (`OnboardingBuddyActor.hopScale`).
- **CI:** clips now record ~10s instead of 6s, because the launch splash took the first ~4s of each.
