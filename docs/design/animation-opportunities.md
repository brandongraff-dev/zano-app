# Animation opportunities — Design System, LockSetup, Share, Trophy, Sunrise Alarm, Widgets

**Status:** Read-only survey. No Swift files were edited to produce this document. Every
recommendation below cites exact SwiftUI values, but **nothing was run, built, simulated, or
visually checked** — there is no Mac, Simulator, device, or Swift compiler in this environment.
Every claim about how something currently looks/feels is inferred by reading the SwiftUI source
(view hierarchy, modifiers, curve/duration constants), not from having seen it render. Treat every
"assessment" below as a code-review-level read, not a visual QA pass.

**Scope:** this task's safe working set only —
`Core/Sources/Core/UI/Theme.swift`,
`Core/Sources/Core/UI/Components/{GoalRing,RingCluster,LockStatusCard,StreakPill,TimeBankBar,PrimaryButton,ShieldPreview,GoalRow,RecapCard,ShareCard,GhostProgressBanner}.swift`,
`Core/Sources/Core/UI/PreviewCatalog.swift`,
`App/ZANO/Features/LockSetup/*.swift`, `App/ZANO/Features/Share/*.swift`,
`App/ZANO/Features/Trophy/*.swift`, `App/ZANO/Features/SunriseAlarm/*.swift`,
`Extensions/ZANOWidgets/**/*.swift` — plus `App/ZANO/Features/Today/TodayView.swift` and
`App/ZANO/Features/Fuel/FuelView.swift`, read **only** for context (owned by a concurrent wave;
not edited, findings there are marked deferred and not implemented).

Every recommendation is Gate-checked per the `find-animation-opportunities` skill (Frequency →
Purpose → Speed → Function) before being included; candidates that didn't survive the Gate are
listed in **Part 4 — Rejected candidates** instead of being smuggled in as suggestions. All curve/
duration values below either reuse an existing `Theme.Motion` token or propose a new one in the
same family — nothing invents an ad hoc hex/number outside that discipline (CLAUDE.md, spec §15).
This survey is consistent with `docs/design/animation-library-decision.md` (same directory,
already on disk): **no Lottie** — every recommendation below is native SwiftUI (`.animation`,
`withAnimation`, `symbolEffect`, `PhaseAnimator`/`KeyframeAnimator` where a sequence is proposed),
gated by `@Environment(\.accessibilityReduceMotion)`.

---

## Part 0 — Systemic finding (applies to every recommendation below)

**`grep -r "reduceMotion" .` across the entire repo returns zero matches.** Not one file — in the
safe set or anywhere else — reads `@Environment(\.accessibilityReduceMotion)`. Every spring,
`symbolEffect(.bounce)`, pulse loop, and hold-to-commit gesture in the design system currently
runs unconditionally.

This is the task brief's explicit hard rule ("Every animation must respect
`@Environment(\.accessibilityReduceMotion)` — never ship a spring/bounce/particle effect with no
reduced-motion fallback"), and today **nothing in the safe set meets it**, including the one
component (`StreakPill`) that already ships a `symbolEffect(.bounce)`. This isn't a per-component
nitpick — it's a prerequisite for every other recommendation in this document. Each row below
gives its own specific fallback, but the pattern is the same everywhere:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- Keep the *feedback* (color change, state change, haptic — haptics are unaffected by Reduce
  Motion and should carry more of the signal when animation is dialed back).
- Drop *overshoot/bounce* (spring `dampingFraction` < ~0.75, `symbolEffect(.bounce)`,
  scale-past-1.0 pulses) — swap for a plain `.easeOut` or `.easeInOut` of roughly the same total
  duration, landing directly on the end state with no overshoot.
- Drop *repeating/ambient* motion (pulse loops, breathing glows) — show a static midpoint or the
  final state instead of continuing to loop.
- Never drop feedback to literally nothing — Reduce Motion means "less motion," not "no signal."

---

## Part 1 — Sunrise Alarm ringing screen: assessment of the existing pulse

File: `App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift` (safe set, implementable this wave).
Assessed against spec §5.10 point 1 ("Alarm fires... with escalating sound/haptics") and the Apple
HIG motion principles this task cites (spring-based/physical, interruptible, reversible).

**What's already right — keep these:**

1. **Three-phase escalation** (`RingingPhase.waking` <20s → `.urgent` <60s → `.critical` 60s+),
   each pairing a tint color (`Theme.Colors.Ring.sunriseAlarm` → `.warning` → `.danger`) with a
   *shortening* pulse period (1.6s → 0.9s → 0.45s) and escalating haptic weight (none →
   `.impact(weight: .medium, intensity: 0.5)` → `.impact(weight: .heavy, intensity: 0.9)`). This
   is a genuinely good "escalating" mechanic — urgency = faster pulse + harder haptic — and maps
   directly onto spec §5.10 point 1. No change needed to this structure.
2. **`.easeInOut`, not a spring, for the ambient background pulse** (`runPulseLoop()`,
   line ~433: `withAnimation(.easeInOut(duration: phase.pulseDuration)) { isPulsing.toggle() }`).
   This is the *correct* curve choice for an ambient "breathing" glow — a spring would look
   bouncy/springy for a slow tint fade, which is the wrong physical metaphor for an alarm's ambient
   glow. Good restraint; don't change this to a spring.
3. **The clock stays legible** — `Text(now, format: .dateTime.hour().minute())` only scales
   `1.0 → 1.04`, a near-imperceptible amount, so the number a groggy user needs to read doesn't
   blur or shake. Good call (see refinement #2 below, though — this one detail is worth going
   further, not less far).

**Two concrete refinements, both in this same file:**

### 1. Missing reduced-motion fallback (critical — see Part 0)

This is the single highest-stakes instance of Part 0's systemic gap in the whole safe set: a
**full-screen, escalating, strobing background** (opacity `0.10 ↔ 0.32`, cycling every 0.45s at
the `.critical` phase) shown to a user who is, by construction, still in bed and not fully awake —
with zero way to reduce it even with iOS's Reduce Motion setting on. Given this app's own stated
principle ("no one gets trapped," an unconditional escape hatch), the ringing screen is exactly
the wrong place to skip this.

Recipe — keep the escalating *haptic* cadence exactly as-is (haptics aren't affected by Reduce
Motion and should carry more of the urgency signal when visuals are dialed back); replace the
looping opacity animation with a static, phase-colored tint:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// body:
phase.tint
    .opacity(reduceMotion ? 0.22 : (isPulsing ? 0.32 : 0.10))
    .ignoresSafeArea()

// runPulseLoop():
private func runPulseLoop() async {
    while !Task.isCancelled {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: phase.pulseDuration)) { isPulsing.toggle() }
        }
        if phase != .waking { pulseHapticTick += 1 }   // haptic cadence unchanged either way
        try? await Task.sleep(for: .seconds(phase.pulseDuration))
    }
}
```

`0.22` is the midpoint of the existing `0.10...0.32` range — same phase-tint color, same legibility,
just held still instead of pulsed. Also gate the header's own pulse-linked scale the same way (see
refinement #2 — recommend dropping it rather than conditionally keeping it).

### 2. Two different curves are keyed off the same boolean (minor, but worth fixing)

`isPulsing` drives *two* independent animations with *different* curves:

- Background tint: `.easeInOut(duration: phase.pulseDuration)` (0.45–1.6s depending on phase)
- Header clock scale (line ~183, `.scaleEffect(isPulsing ? 1.04 : 1.0)`): animated by
  `.animation(Theme.Motion.springStandard, value: isPulsing)` — a **spring** (response 0.35,
  damping 0.82), which settles on a completely different timeline (~0.4–0.5s, regardless of
  `phase.pulseDuration`) than the background it's supposedly pulsing in sync with.

At `.critical` phase (0.45s pulse period) these two are visibly out of phase with each other —
the background is cycling every 0.45s while the clock's spring is still settling from the
previous toggle. That reads as an incoherent "double pulse" rather than one coherent escalating
beat.

**Recommendation: stop scaling the clock at all.** The clock is the one piece of information this
screen must stay perfectly legible (a user deciding "do I have time to snooze" reads it under
stress) — a wobbling number actively works against that, and removing it doesn't lose any of the
escalation signal (color + background pulse + haptics already carry it). Delete the
`.scaleEffect(isPulsing ? 1.04 : 1.0)` and its `.animation(Theme.Motion.springStandard, value:
isPulsing)` from `header` entirely; let the eyebrow text color (`phase.tint`) and the background
pulse be the only two visual escalation channels, both driven by the one `.easeInOut` curve.

### Verdict for this screen

The escalation *design* is right and shouldn't be re-architected. The two fixes above are both
small, targeted, and don't touch the dismiss-variant logic, the escape hatch, or any of the
non-motion code. Priority: **P0** (the reduced-motion gap; this is the most safety-relevant
instance of Part 0 in the whole safe set) and **P2** (the curve-mismatch cleanup).

---

## Part 2 — Prioritized recommendations by component

All are implementable in this wave (safe set) unless marked **DEFERRED**.

| # | Component / File | Today | Gate (Frequency / Purpose) | Suggested motion (exact values) |
|---|---|---|---|---|
| 1 | **Sunrise Alarm pulse** — `SunriseAlarm/AlarmRingingView.swift` | Full-screen pulse + haptics, no reduced-motion path (see Part 1) | Rare (only while ringing) / State indication + safety | See Part 1's two recipes above. **P0.** |
| 2 | **PrimaryButton hold-to-commit — success path** — `Core/UI/Components/PrimaryButton.swift:169-173` | On successful commit, `holdProgress` and `isHolding` are reset with **no `withAnimation`** at all (unlike the cancel path in `endHold()`, which does wrap its reset in `Theme.Motion.springStandard`). The filled bar **teleports** back to empty the instant the 2s hold completes — a "teleporting state" bug on the app's single highest-stakes confirmation control. | Occasional (onboarding commit, emergency-style confirms) / Preventing a jarring change | Wrap the success reset the same way the cancel path already does, and give the 100% moment a brief settle instead of an instant vanish: `withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.72)) { holdProgress = 0 }` placed right after `action()` in `beginHoldIfNeeded()`'s completion branch (~line 171). If `action()` itself doesn't immediately dismiss/navigate away, also consider holding at `holdProgress == 1` for ~120ms before resetting, so the user actually sees "full" before it clears. |
| 3 | **PrimaryButton press feedback (`.standard`)** — `Core/UI/Components/PrimaryButton.swift:192-201` | `StandardPrimaryButtonStyle` scales to 0.97 / opacity 0.92 on press via `Theme.Motion.springStandard` (spring response 0.35, damping 0.82) — same curve used everywhere else in the design system for *state* changes, not press feedback specifically. Press budget per Apple HIG / this skill's own table is 100–160ms; response 0.35 settles noticeably slower than that. | Tens of times/day (every button tap, app-wide) / Feedback | Add a **dedicated, faster** token to `Theme.Motion` rather than reusing `springStandard` for presses: `public static let pressFeedback: Animation = .spring(response: 0.16, dampingFraction: 0.75)`. Use it in `StandardPrimaryButtonStyle` and the hold-to-commit's `isHolding` scale (both currently on `springStandard`). Reduced motion: swap to `.easeOut(duration: 0.1)` — same scale delta (0.97), no spring overshoot, still gives feedback (removing it entirely would violate "give feedback" — this is legitimate feedback at a subtle, high-frequency scale, not the kind of motion Reduce Motion is meant to suppress). |
| 4 | **GoalRing — reduced motion + completion beat** — `Core/UI/Components/GoalRing.swift:82-101` | Fill trim animates via `Theme.Motion.ringFill` (`.easeOut(duration: 0.6)`, spec-exact — do not change this curve) with no reduced-motion gate, and no distinct feedback when a ring actually *completes* (crosses 100%) beyond the linear fill arriving there. | Rings render on every high-frequency screen (Today/Fuel — deferred), but *completion* itself (crossing 100%) happens only a few times/day per ring / State indication + Feedback | (a) Gate the existing fill: `.animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: clampedProgress)` — keep the fill, just shorten it, since a progress fill is core information, not decoration. (b) Add an opt-in one-shot completion pulse driven by the *caller* crossing the 1.0 threshold (not inside `GoalRing` itself, which doesn't track history): `.scaleEffect(justCompleted && !reduceMotion ? 1.06 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.55), value: justCompleted)`, reset after ~250ms. Screen-level haptics (e.g. `TodayView`'s existing `.sensoryFeedback(.impact(weight: .light), trigger: completedGoalCount)`) already cover the haptic side on the one screen that's wired up today — this is a purely visual companion for wherever `GoalRing` is used standalone (e.g. `RecapCard`, `AlarmRingingView`'s steps/focus rings). |
| 5 | **RingCluster — opt-in entrance stagger** — `Core/UI/Components/RingCluster.swift` | `ForEach(items) { RingClusterCell(...) }` — cells appear with no entrance transition at all; on a first render, all N rings pop in simultaneously (or, more accurately, are just already there on first paint). | **Context-dependent — this is the one place Frequency cuts two different ways.** Today/Fuel show `RingCluster` tens of times/day (deferred screens; see Part 3) → *reject* a default-on stagger there. `RecapCard`/`ShareCard`/Trophy-adjacent occasional surfaces → occasional/weekly → *eligible*. | Add an **opt-in, default-`false`** parameter so the component itself stays safe for high-frequency callers while occasional callers (in this safe set: `RecapCard`) can turn it on: `public init(items:, ringSize: .medium, layout: .row, staggerAppearance: Bool = false)`. When `true`, wrap each `RingClusterCell` in `.opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.85)` set `true` in `.onAppear` after `Double(index) * 0.04` seconds (cap the stagger window at ~5 items / 200ms total), animated with `.spring(response: 0.4, dampingFraction: 0.75)`. Needs `ForEach(Array(items.enumerated()), id: \.element.id)` to get the index. Reduced motion: skip the per-item delay and scale — just `.opacity` fade over 150ms, no stagger, no scale. This also composes safely with `TodayView`'s existing fixed-`RingSlotID` pattern (see that file's own comment) — fixed identity is exactly what keeps an `.onAppear`-driven stagger from re-firing on every unrelated re-render. |
| 6 | **StreakPill — directional bounce + reduced motion** — `Core/UI/Components/StreakPill.swift:34-37` | `Image(systemName: isFrozen ? "snowflake" : "flame.fill")...symbolEffect(.bounce, value: count)` bounces on **any** change to `count` — including a streak *reset* (14 → 0), not just an increment. No reduced-motion gate (`symbolEffect` does not automatically respect Reduce Motion for custom triggers). | Roughly once/day (streak updates once daily) / Feedback + Delight | (a) Reduced motion: `.symbolEffect(reduceMotion ? .pulse.byLayer : .bounce, value: count)` or simplest, drop the effect entirely under reduce motion (`reduceMotion ? nil : .bounce` isn't directly expressible on `.symbolEffect`, so gate with an `if reduceMotion { Image(...) } else { Image(...).symbolEffect(.bounce, value: count) }` — the count change is still reflected via the `Text("\(count)")` redraw and the existing `accessibilityLabel`, so no information is lost, only the bounce). (b) Directional fix: only bounce on an *increase*. Track the delta with a small `@State private var bounceTrigger = 0` incremented only when `newCount > oldCount` via `.onChange(of: count) { old, new in if new > old { bounceTrigger += 1 } }`, and key the symbol effect off `bounceTrigger` instead of `count` directly — a streak breaking to 0 should not read as a celebratory bounce (spec §8's "no shame" principle is about copy, but the same spirit applies to motion). |
| 7 | **TimeBankBar — low-balance pulse + direction-aware fill** — `Core/UI/Components/TimeBankBar.swift:53-64` | Single `.animation(Theme.Motion.ringFill, value: fraction)` (ease-out 600ms) drives both *earning* (bar growing) and *draining* (bar shrinking as banked minutes are spent) with the same curve, and there's no distinct signal when the bank is nearly empty. | Occasional (crossing a low-balance threshold happens ~once per active lock session) / State indication | (a) **Low-balance pulse**, gated to fire once per threshold-crossing (not looping): when `remainingMinutes` crosses below a caller-relevant floor (suggest exposing a `isLow: Bool` computed at the call site, e.g. `remainingMinutes <= 5`), animate the fill's color from `Theme.Colors.accent` toward `Theme.Colors.warning` and pulse opacity `1.0 ↔ 0.7` three times: `.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true)`, triggered via `.onChange(of: isLow)` firing only on `false → true`. Reduced motion: skip the repeating pulse, just hold the warning color statically — the color change alone is the state signal. (b) **Direction-aware curve** (lower-confidence, optional): keep `Theme.Motion.ringFill` (spec-exact) for increases; for decreases, a shorter `.easeOut(duration: 0.3)` avoids a sluggish re-animation if `fraction` updates faster than 600ms apart during a live countdown. This is a refinement, not a defect — flag as **P3**, worth a second look once whichever engine feeds this bar's live cadence is confirmed. |
| 8 | **ShieldPreview — onboarding hero reveal** — `Core/UI/Components/ShieldPreview.swift` | Fully static: icon badge, lock overlay, headline/subline, buttons all render simultaneously with no entrance choreography, even though this is the single screen most responsible for explaining the core mechanic (P2 mockup, spec §16) at the highest-emotion moment (onboarding plan reveal). | Rare (onboarding once; occasional thereafter as a "preview my shield" screen) / Delight + spatial consistency (the lock "landing" on the app icon) | A restrained, single-beat hero reveal — **not** bouncy/cutesy, matching the mockup's own "calm, motivating, not punishing" framing: icon badge scale `0.8 → 1.0` + opacity `0 → 1`, `.spring(response: 0.45, dampingFraction: 0.7)`; the lock-circle overlay (`iconBadge`'s bottom-trailing `Circle`) delayed ~150ms behind it with the same spring, so it visually "arrives" onto the app icon a beat after; headline/subline fade + 8pt rise, `.easeOut(duration: 0.3)`, delayed ~250ms. Total sequence ≈500ms — within the modal/explanatory budget. Reduced motion: single 150ms opacity cross-fade for the whole card, no scale/translate/stagger. |
| 9 | **RecapCard reveal** — `Core/UI/Components/RecapCard.swift` | Static; the weekly ring cluster and the coach's one-line insight (`insightText`, the actual payoff of the whole weekly recap) appear simultaneously with no reveal order. | Occasional (weekly) / Delight + explanation | Turn on `RingCluster`'s new `staggerAppearance: true` (recommendation #5) here specifically — this is exactly the occasional-frequency context that flag exists for. Follow it with the insight box fading/rising in ~300ms *after* the rings settle: `.opacity(0 → 1).offset(y: 6 → 0)`, `.easeOut(duration: 0.25)`, `.delay(0.3)` (skip the delay chain entirely under reduced motion — show everything at once, no stagger). |
| 10 | **ShareCard reveal (call-site only, not `ShareCard.swift` itself)** — `App/ZANO/Features/Share/{WeeklyRecapShareView,LockedOutMomentView}.swift` | Both screens drop `ShareCard(content:)` into a `ScrollView` with no entrance transition when the sheet/moment is presented — most notable on `LockedOutMomentView`, which is explicitly an emotional "turn friction into content" beat (spec §5.16). | Occasional (weekly recap; Locked-Out fires at most once/hour, debounced) / Delight + preventing a jarring appearance | Animate the reveal **at the call site**, wrapping the `ShareCard(...)` instance each screen already constructs for on-screen display: scale `0.92 → 1.0` + opacity `0 → 1`, `.spring(response: 0.5, dampingFraction: 0.8)`, triggered `.onAppear`. **Important constraint:** do **not** add this animation inside `ShareCard.swift` itself — both screens also call `ShareCard.renderImage(content:)`, which constructs its own separate, off-screen `ShareCard` instance purely for `ImageRenderer.uiImage` capture; an animation baked into `ShareCard`'s own `body` risks being mid-flight when that separate off-screen instance is rasterized (though today the two instances are already fully decoupled — the render call builds a fresh, non-animated instance — so this is a constraint to preserve, not a bug to fix). Reduced motion: opacity-only fade, 150ms, no scale. |
| 11 | **Trophy Case badge unlock — reactive spring (future-proofing)** — `App/ZANO/Features/Trophy/TrophyCaseView.swift` (`TrophyTile`) | Every tile's locked/earned state (`isEarned`) is computed fresh from `badges.contains { $0.key == milestone.key }` on every `@Query` refresh, with **zero transition** — a tile currently just is or isn't earned; there's no animated "moment" if a badge's `Badge` row appears while this screen happens to be open. Per this file's own header comment, **no engine currently awards most of these six milestones yet** — so the actual celebratory instant (the moment a badge is earned) happens elsewhere (deferred — see Part 3), not on this screen today. | Rare (each milestone unlocks once, ever) / Delight | What's implementable *now*, with zero new state, is making this screen **reactive** so that whenever a future engine does insert a `Badge` row while Trophy Case happens to be open, it already animates correctly instead of needing a follow-up patch: wrap `TrophyTile`'s circle fill / icon in `.animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62), value: isEarned)`, add `.contentTransition(.symbolEffect(.replace))` to the `Image(systemName:)` swap (lock → milestone icon), and a one-shot expanding ring burst on the `false → true` edge only (guarded by a local `@State private var didCelebrate = false` per tile, or simpler: `.onChange(of: isEarned) { old, new in if new && !old { /* trigger */ } }`): a `Circle().stroke(Theme.Colors.accent, lineWidth: 2)` scaling `1.0 → 1.6` while fading `0.6 → 0` over `.easeOut(duration: 0.5)` — well inside `Theme.Motion.unlockCelebrationMaxDuration` (1.2s). Reduced motion: keep the color/icon crossfade (200ms `.easeOut`), skip the expanding ring burst. |
| 12 | **Coin balance — numeric transition** — `TrophyCaseView.swift` + `CosmeticsShopView.swift` (`CoinBalancePill`, both files, both safe set) | `Text("\(balance)")` redraws instantly on change; both files declare their own separate copy of `CoinBalancePill` (documented as intentional, non-shared). | Occasional (a purchase, or coins earned while the shop happens to be open) / State indication | Cheap, low-risk addition to both copies: `Text("\(balance)").contentTransition(.numericText(value: Double(balance)))` inside a `withAnimation(.easeOut(duration: 0.3))` when `balance` changes. `.numericText()` (iOS 16+) is a built-in, low-effort digit-roll — no reduced-motion gate strictly required (it's a subtle content transition, not a spring/bounce/particle per Part 0's own carve-out), but for consistency with this doc's own rule, wrap in `reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3)` rather than skipping it outright. |
| 13 | **Live Activity Time Bank bar** — `Extensions/ZANOWidgets/Support/ZANOWidgetComponents.swift` (`ZANOTimeBankBarView`, used by `ZANOEarnMeterLiveActivity.swift`) | The fill `Capsule` has no `.animation` modifier at all. | Occasional (content-state pushes while a lock is active) / State indication | ActivityKit does support simple animatable-property interpolation across `ContentState` pushes for Live Activities (per Apple's Live Activity update guidance) — unlike the Home/Lock Screen widgets (see Part 4, rejected), this is a Live Activity, so a cheap addition is reasonable: `.animation(.easeInOut(duration: 0.3), value: fraction)` on the fill `Capsule`. Low priority/low confidence given this can't be visually verified here — flag as **P3**, worth confirming on-device before relying on it. |

---

## Part 3 — Deferred (outside the safe set — noted, not implemented)

Per this task's rules, the following were spotted while reading `TodayView.swift`/`FuelView.swift`
**read-only, for context**, or elsewhere outside the safe file list. Not implemented; flagged here
so they aren't lost for the concurrent wave that owns those paths.

- **`TodayView.swift` / `FuelView.swift` — `RingCluster` default frequency.** Both screens are the
  app's daily-driver surfaces (tens of visits/day). Recommendation #5 above (opt-in
  `staggerAppearance`) was deliberately designed default-`false` specifically so these two screens
  are unaffected unless that concurrent wave opts in — flagged for their awareness, not
  recommended for them to turn on given the Gate's frequency verdict. **Deferred — owned by a
  concurrent wave.**
- **`TodayView.swift`'s celebration banner** (`celebrationBanner`, driven by `showCelebration` +
  `Theme.Motion.springCelebration`) already exists and looks reasonable from a read (spring
  response 0.45/damping 0.68, capped at `unlockCelebrationMaxDuration`), but — like everywhere
  else in the repo — has no `accessibilityReduceMotion` gate. Same Part 0 fallback pattern applies:
  swap the entrance spring for a shorter `.easeOut` and skip any overshoot. **Deferred — owned by a
  concurrent wave** (`TodayView.swift` is explicitly out of this task's safe set).
- **`FuelView.swift`'s `FuelQuickAddChip`** (line ~607) has `.animation(Theme.Motion.springStandard,
  value: title)` — animating on `value: title`, a string that never changes per button instance,
  which makes this `.animation` modifier a no-op as written (it likely was meant to animate press/
  selection state, not the static label). Not an animation-*opportunity* so much as a
  possibly-dead modifier worth a second look by whoever owns that file. **Deferred — owned by a
  concurrent wave**, flagged only so it isn't lost.
- **`Extensions/ZANOShieldConfig`, `App/ZANO/Features/Onboarding/*`, `Celebration/*`,
  `CelebrationBurst.swift`** — explicitly out of scope per this task's instructions (owned by other
  concurrent waves) and not read. `docs/design/animation-library-decision.md` (already on disk)
  covers the unlock-celebration/`CelebrationBurst.swift` research in depth; nothing added here
  duplicates or contradicts it.

---

## Part 4 — Rejected candidates

Per the skill's own discipline, candidates considered and deliberately **not** recommended:

- **Home Screen widget (`ZANOHomeWidget.swift`) / Lock Screen widget
  (`ZANOLockScreenWidget.swift`) content animations.** WidgetKit's `StaticConfiguration`/
  `TimelineProvider`-driven widgets are snapshotted between timeline entries — arbitrary
  `.animation()` modifiers on ring fills, bar fills, or button presses largely don't run reliably
  in this rendering model the way they do in-app or in a Live Activity. **Rejected: platform
  constraint, not a motion-design call.** (`ZANOGoalRingView`/`ZANOTimeBankBarView` in
  `ZANOWidgetComponents.swift` are shared with the Live Activity, where the recommendation above
  *does* apply — see row 13.)
- **`ZANOControls.swift` (iOS 18 Control Center toggles/buttons).** System-rendered chrome the app
  has essentially no control over the transition of; also inherently a "many times/day, instant
  action" surface (toggle Lock on/off, log water from Control Center) — squarely the "100+/day,
  never animate" tier even if it were technically animatable. **Rejected: Frequency Gate (never
  animate) + platform constraint.**
- **`AppPickerView.swift`'s `.familyActivityPicker` sheet presentation.** This is Apple's own
  system sheet (`FamilyActivityPicker`) — ZANO doesn't own its presentation transition at all.
  **Rejected: not this app's surface to animate.**
- **`LockSetupView.swift`'s list rows / swipe-to-delete.** Standard `List`/`.swipeActions` — this
  is exactly the "tens of times/day, admin-screen, functional list" case the skill's own Gate
  calls out for **no or only near-imperceptible motion**; SwiftUI's default `List` row insert/
  remove animation already covers this adequately. **Rejected: Function — a plain admin CRUD
  screen doesn't need bespoke motion, and SwiftUI's built-in list diffing already provides
  baseline continuity.**
- **`AlwaysAllowedWarningView.swift`'s appearance.** It's a conditionally-included banner the
  *caller* decides whether to show at all (per its own header comment) — any entrance motion
  belongs to whatever screen composes it in (LockSetup admin or onboarding), not to this file
  itself, and those callers are outside the safe set. **Rejected: not this file's surface to
  choreograph; would need to be decided by the composing screen.**
- **`SunriseAlarmSetupView.swift` / `BedtimeGateSetupView.swift` — the settings forms
  themselves.** Standard `Form`/`Section`/`DatePicker`/`Stepper` admin UI, visited occasionally
  (setup once, revisit rarely) but purely functional/information-dense (times, toggles, a tag
  list). **Rejected: Function — decoration on a settings form the user is trying to configure
  correctly hinders more than it helps; SwiftUI's default `Form` transitions are already
  appropriate here.**
- **Escalating audio/visual intensity beyond what Part 1 already covers** (e.g. a full-screen
  color-cycling strobe, screen-shake). Considered and rejected outright, not just gated behind
  Reduce Motion: spec §5.10 explicitly frames the Sunrise Alarm as "a real alarm that makes you
  get up," never promising more than that, and a screen-shake/strobe-style escalation would cross
  from "urgent" into genuinely disorienting or photosensitivity-risking territory for a
  full-screen, unavoidable UI. **Rejected: Function — motion intensity beyond Part 1's existing
  tint/haptic escalation actively hinders (safety), it doesn't help.**

---

## Part 5 — Verdict

This design system is already close to right in its restraint: most components (`LockStatusCard`,
`GhostProgressBanner`, `GoalRow`) already use `Theme.Motion.springStandard` correctly and sparingly
for real state changes, not decoration, and the one spec-mandated curve (`ringFill`, ease-out
600ms) is implemented exactly as specified everywhere it's used. The real gap isn't "too little
motion" or "too much motion" — it's that **every single animation in the safe set, without
exception, has no reduced-motion fallback** (Part 0), which is a correctness gap against this
task's own stated hard rule, not a taste question.

Highest-leverage single fix: **Part 1's Sunrise Alarm reduced-motion gap** — it's the one place in
this safe set where "no fallback" intersects with a full-screen, unavoidable, safety-adjacent
surface, not just a missed nicety. Second-highest: **row 2, `PrimaryButton`'s hold-to-commit
success-path teleport** — a real, findable bug (not just a missing enhancement) on the app's single
most consequential confirmation control. Everything else in Part 2 is additive polish, correctly
scoped to the occasional/rare frequency tiers where this skill's Gate says delight is actually
earned — Trophy Case (row 11) and ShieldPreview (row 8) in particular are the two places a
first-time or milestone user is most likely to remember the moment, and both are currently fully
static.
