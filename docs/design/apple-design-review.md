# Apple HIG motion/depth review — Theme + Core UI Components + LockSetup/Share/Trophy/SunriseAlarm/Widgets

**Status:** Read-only survey. No source files were changed by this task. Every recommendation
below is written for a future implementation pass to apply — this document itself is the
deliverable.

**Scope reviewed (exactly this run's safe working set, per CLAUDE.md's file-ownership rule):**
`Core/Sources/Core/UI/Theme.swift`; every file in `Core/Sources/Core/UI/Components/` that this
wave owns (`GoalRing`, `RingCluster`, `LockStatusCard`, `StreakPill`, `TimeBankBar`,
`PrimaryButton`, `ShieldPreview`, `GoalRow`, `RecapCard`, `ShareCard`, `GhostProgressBanner`);
`Core/Sources/Core/UI/PreviewCatalog.swift`; `App/ZANO/Features/LockSetup/*.swift`;
`App/ZANO/Features/Share/*.swift`; `App/ZANO/Features/Trophy/*.swift`;
`App/ZANO/Features/SunriseAlarm/*.swift`; `Extensions/ZANOWidgets/**/*.swift`. Every file in that
list was read in full before writing this document.

**Honesty about verification:** no Mac, Simulator, device, or Swift compiler exists in this
environment. Nothing below was built, run, or visually checked — every finding is a static read of
the Swift/SwiftUI source against Apple's Human Interface Guidelines motion principles (spring-based
over linear/ease, gesture interruptibility, translucent materials/depth, optical alignment,
reduced-motion fallbacks) and WCAG-style accessibility basics. Line numbers below are accurate as
of this read but will drift the moment a file is edited — treat them as pointers, not guarantees.

**How to use this document:** each finding names the exact file, the exact problem, and (where
applicable) exact replacement code — spring `response`/`dampingFraction` pairs, exact
`Theme.Motion`/`Theme.Colors` tokens to reuse, and exact `@Environment(\.accessibilityReduceMotion)`
gating patterns. Nothing here proposes a new dependency — `docs/design/animation-library-decision.md`
(already on disk) settled that native SwiftUI (`PhaseAnimator`, `KeyframeAnimator`, `symbolEffect`,
`.contentTransition`, `Canvas`/`TimelineView`) is the house style; every recommendation below stays
inside that native toolkit and inside `Theme`'s existing token families.

---

## 0. The one-line summary

The design system's *values* (colors, radii, spacing, type) are disciplined and spec-compliant —
zero drift found anywhere in the safe set, including the widget extension's independent
`ZANOWidgetColor.swift` fallback copy, which matches `Theme.swift` byte-for-byte in every hex
value. The *motion* layer is the gap: **`@Environment(\.accessibilityReduceMotion)` is read in
zero of the twelve Core UI Components and zero of the ten App/Features files in this safe set**,
several looping/continuous animations exist that HIG explicitly flags as reduced-motion risks
(`AlarmRingingView`'s full-screen pulsing tint chief among them), the one spec-mandated curve
(`Theme.Motion.ringFill = .easeOut(duration: 0.6)`) is linear-family rather than spring-based on
the app's single most-reused animated primitive (`GoalRing`, transitively used by `GoalRow`,
`RingCluster`, `RecapCard`, `ShareCard`, `AlarmRingingView`), and there is one **concrete,
reproducible gesture-interruption bug** in `PrimaryButton`'s hold-to-commit gesture that is also
independently duplicated (with the same bug) in `AlarmRingingView`'s escape hatch.

---

## 1. Cross-cutting finding: reduced-motion coverage (highest priority)

None of the following files import or read `@Environment(\.accessibilityReduceMotion)` today.
Every row below is a real `.animation(...)`/`withAnimation(...)`/`.symbolEffect(...)` call site
that will run at full motion regardless of the user's Reduce Motion setting:

| File | Call site | What moves |
|---|---|---|
| `GoalRing.swift:94` | `.animation(Theme.Motion.ringFill, value: clampedProgress)` | ring trim sweep |
| `LockStatusCard.swift:47` | `.animation(Theme.Motion.springStandard, value: isLocked)` | icon/color/padlock swap |
| `StreakPill.swift:37` | `.symbolEffect(.bounce, value: count)` | flame/snowflake bounce |
| `StreakPill.swift:48` | `.animation(Theme.Motion.springStandard, value: isFrozen)` | flame↔snowflake swap |
| `TimeBankBar.swift:61` | `.animation(Theme.Motion.ringFill, value: fraction)` | bar fill width |
| `PrimaryButton.swift:117` | `.animation(Theme.Motion.springStandard, value: isHolding)` | hold-to-commit scale/border |
| `PrimaryButton.swift:199` | `.animation(Theme.Motion.springStandard, value: configuration.isPressed)` | standard button press scale |
| `GhostProgressBanner.swift:70` | `.animation(Theme.Motion.springStandard, value: comparison)` | whole-row cross-fade |
| `SunriseAlarmSetupView.swift:230` | `withAnimation(Theme.Motion.springStandard) { settings.dismissVariant = variant }` | variant-row selection |
| `AlarmRingingView.swift:190` | `.animation(Theme.Motion.springStandard, value: isPulsing)` | header eyebrow/clock/headline |
| `AlarmRingingView.swift:405` | `.animation(Theme.Motion.springStandard, value: isHoldingEscapeHatch)` | escape-hatch scale |
| `AlarmRingingView.swift:433` | `withAnimation(.easeInOut(duration: phase.pulseDuration)) { isPulsing.toggle() }` inside an unbounded `while` loop | **full-screen background tint pulse + clock scale — see §5.1, this is the review's top finding** |

**Standard fix pattern to apply at every row above** (matches this codebase's existing
`@MainActor`/`@State` conventions):

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// wherever `Theme.Motion.springStandard` (or `.ringFill`) is passed directly to `.animation`/
// `withAnimation`, replace it with a nil-able variant so Reduce Motion snaps instead of animating:
.animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isLocked)
```

`nil` is deliberate, not `.easeInOut(duration: 0)`: passing `nil` to `.animation(_:value:)` fully
disables implicit animation for that value change (an instant, correct snap), whereas a
zero-duration animation still runs SwiftUI's animation machinery for no benefit. For state changes
that are themselves the *information* (a fill bar's width, a ring's progress) — not decorative — do
not remove the value change, only the interpolation; the fix above already does this correctly
since it snaps to the new value rather than hiding it.

Recommend adding one shared token to `Theme.Motion` so every call site pulls from the same place
instead of re-deriving `nil : Theme.Motion.springStandard` twenty times:

```swift
// Theme.swift, inside `enum Motion`
/// Convenience for call sites gating a spring behind `@Environment(\.accessibilityReduceMotion)`.
/// Returns `nil` (an instant snap) when `reduceMotion` is true, `springStandard` otherwise —
/// covers the majority case; call sites needing a different base curve (`.ringFill`,
/// `.springCelebration`) pass their own animation to the ternary directly instead of this helper.
public static func standard(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : springStandard
}
```

---

## 2. Cross-cutting finding: spring-based vs. linear/ease curves

Apple HIG's motion principle is explicit: *"Think of animation as a conversation... reach for
springs for anything a user can touch."* `Theme.Motion` already defines two good springs
(`springStandard`, `springCelebration`) but the app's single most-reused animated primitive uses a
duration-based ease curve instead:

```swift
// Theme.swift:181
public static let ringFill: Animation = .easeOut(duration: 0.6)
```

This is spec-exact text (`docs/spec.md` §15: *"ring fills ease-out 600ms"*), so this review is not
recommending silently overriding it — `Theme.swift`'s own header says spec §15 is authoritative and
hex/motion values shouldn't drift without updating the spec first. **Recommendation for the
implementation phase: propose a one-line spec §15 amendment** ("ring fills: critically-damped
spring, ~600ms settle" instead of "ease-out 600ms") and, once agreed, swap the token to:

```swift
public static let ringFill: Animation = .spring(response: 0.55, dampingFraction: 0.9)
```

`dampingFraction: 0.9` (not `1.0`) is deliberate: a ring filling toward a target value is a
"conversation," per HIG's framing, not a one-shot reveal — a hair under critically damped gives it
a barely-perceptible settle rather than a mechanical stop, without the overshoot that would read as
wrong on a progress indicator (HIG reserves overshoot for momentum-carrying, flick-driven
interactions, which a ring fill is not). `response: 0.55` keeps the settle time in the same ~600ms
neighborhood the spec's duration-based number targets, so this reads as a curve-family change, not
a pacing change — nothing about "how long it takes to fill" changes from the user's perspective.

This one token drives, transitively: `GoalRing` itself, `TimeBankBar`'s fill, and (via `GoalRing`)
`GoalRow`'s leading ring, `RingCluster`'s every cell, `RecapCard`'s embedded `RingCluster`,
`ShareCard`'s day-ring strip, and `AlarmRingingView`'s steps/focus/escape-hatch rings. Fixing it
once is the single highest-leverage change available in this entire safe set.

`Theme.Motion.springStandard` (`response: 0.35, dampingFraction: 0.82`) and `springCelebration`
(`response: 0.45, dampingFraction: 0.68`) are both already correctly spring-based and their damping
values are reasonable (0.82 for confident-but-controlled state flips, 0.68 for celebratory
overshoot) — no change recommended to either. One gap: there is no token for a **drag/gesture
response** spring (Apple's own shipped value for a directly-manipulated reposition is `damping 1.0,
response 0.4`, and for a drawer/sheet `damping 0.8, response 0.3` — see the Quick Reference table
in this review's source guidance). Recommend adding:

```swift
// Theme.swift, inside `enum Motion`
/// For 1:1 gesture-tracked motion the user's finger is actively driving (a hold-to-commit fill,
/// a future drag-to-dismiss sheet) — critically damped, no overshoot, snappier settle than
/// `springStandard` since a released gesture should feel like it "catches" immediately.
/// Apple's own shipped value for directly-manipulated repositioning (WWDC18 "Designing Fluid
/// Interfaces"): damping 1.0, response 0.4.
public static let springGesture: Animation = .spring(response: 0.4, dampingFraction: 1.0)
```

Recommend using this new token, not `springStandard`, for `PrimaryButton`'s hold-to-commit press
scale (`PrimaryButton.swift:117`) and `AlarmRingingView`'s escape-hatch scale
(`AlarmRingingView.swift:405`) once §3's interruption bug is also fixed there — both are directly
finger-driven, not a passive state flip, and HIG's own table puts finger-driven motion at
`dampingFraction: 1.0`, not `0.82`.

---

## 3. Gesture interruptibility — the hold-to-commit bug (and its duplicate)

This is the review's most concrete, reproducible finding, and the task brief specifically asked
"can a running animation be grabbed and redirected mid-flight?" — here the answer is: mostly yes,
with one specific broken case.

### 3.1 `PrimaryButton.swift`, `.holdToCommit` style

The good news first — `endHold()` (`PrimaryButton.swift:180-188`) is correctly interruptible:

```swift
private func endHold() {
    guard isHolding, holdProgress < 1 else { return }
    holdTask?.cancel()
    holdTask = nil
    isHolding = false
    withAnimation(Theme.Motion.springStandard) {
        holdProgress = 0
    }
}
```

A release-to-cancel starts a fresh spring from wherever `holdProgress` currently sits (SwiftUI's
implicit/explicit animation reads the live *presentation* value, not the pre-gesture target) —
exactly HIG's "always animate from the presentation value" rule, satisfied for free by SwiftUI's
animation system. No change needed here.

**The bug:** `beginHoldIfNeeded()` (`PrimaryButton.swift:145-175`) does not check whether a
cancel-spring from a *previous* release is still in flight before hard-resetting:

```swift
private func beginHoldIfNeeded() {
    guard isEnabled, !isHolding else { return }
    isHolding = true
    holdProgress = 0   // ← unanimated, hard reset
    ...
```

**Failure scenario:** user holds to ~40% (`holdProgress = 0.4`), releases early. `endHold()` starts
a `springStandard` animation retargeting `holdProgress` from 0.4 → 0 (that spring takes roughly
300–400ms to settle). If the user re-presses within that window — say 100ms in, while the
*presentation* value is still around 0.25 — `DragGesture.onChanged` fires `beginHoldIfNeeded()`
again, which sets `holdProgress = 0` with **no animation wrapper at all**. The fill bar visibly
snaps from ~0.25 to 0 in a single frame, then immediately starts climbing again — a hard,
un-physical pop exactly where HIG says the interface should instead read as one continuous,
redirectable gesture ("a user must be able to grab a moving element mid-flight and reverse it
without waiting for the animation to finish... never lock out input during a transition").

**Fix:** don't force `holdProgress` to a literal `0` on re-press; let the ascending tick loop
resume from whatever the presentation value already is, and stop fighting the in-flight release
spring:

```swift
private func beginHoldIfNeeded() {
    guard isEnabled, !isHolding else { return }
    isHolding = true
    // Do NOT hard-reset holdProgress here. If a previous release's cancel-spring is still
    // animating toward 0, snapping to 0 now creates a visible pop (see review notes). Cancel
    // that spring's effect on future frames by starting the ascending tick loop from whatever
    // `holdProgress` currently reads — worst case (re-press right as the spring finishes) this
    // is indistinguishable from starting at 0 anyway.
    let totalMs = max(1, Int(Theme.Motion.holdToCommitDuration * 1000))
    let tickMs = 50
    let startingMs = Int(holdProgress * Double(totalMs))

    holdTask?.cancel()
    holdTask = Task { @MainActor in
        var elapsedMs = startingMs
        var lastDecile = Int(holdProgress * 10)
        while elapsedMs < totalMs {
            try? await Task.sleep(for: .milliseconds(tickMs))
            if Task.isCancelled { return }
            elapsedMs += tickMs
            let progress = min(1, Double(elapsedMs) / Double(totalMs))
            holdProgress = progress
            let decile = Int(progress * 10)
            if decile != lastDecile {
                lastDecile = decile
                hapticTick += 1
            }
        }
        guard !Task.isCancelled else { return }
        commitTick += 1
        action()
        isHolding = false
        holdProgress = 0
    }
}
```

Secondary, lower-priority polish on the same mechanism: the fill's 50ms discrete ticks
(`PrimaryButton.swift:157-163`) set `holdProgress` directly with no `.animation` wrapper on the
fill `Rectangle` itself, so the bar advances in ~40 visible steps over the 2-second hold rather than
a continuous sweep. At 20Hz this is close to imperceptible, but for a more display-synced fill,
consider driving `holdProgress` from wall-clock elapsed time inside a `TimelineView(.animation)`
(or `.periodic`) instead of a `Task.sleep` loop — this also sidesteps `Task.sleep` scheduling
jitter and makes "resume from current value" in the fix above trivial (`elapsed = now -
startDate`, no `startingMs` bookkeeping needed). Not blocking; the `Task`-loop approach already
works, this is a "nicer" alternative if the implementation phase wants to also touch this file for
other reasons.

### 3.2 `AlarmRingingView.swift`, escape-hatch hold (same bug, independently duplicated)

`beginEscapeHatchHold()`/`endEscapeHatchHold()` (`AlarmRingingView.swift:548-586`) are, by the
file's own header comment, an intentional re-implementation of `PrimaryButton`'s hold mechanics
(justified: the escape hatch's visual is a `GoalRing`, which `PrimaryButton` doesn't support) — and
they carry the exact same bug:

```swift
private func beginEscapeHatchHold() {
    guard !isHoldingEscapeHatch else { return }
    isHoldingEscapeHatch = true
    holdProgress = 0   // ← same hard reset, same bug
    ...
```

Apply the identical fix (resume from the current `holdProgress` instead of forcing `0`). Because
this is the app's **safety-critical 60-second escape hatch** (spec §5.10 point 6 / §24: "no one
gets trapped"), a visual glitch here is a worse look than the same glitch on an onboarding
confirm button — recommend treating this as the higher-priority of the two identical fixes if only
one can be done first.

**Simplification note for the implementation phase** (not a correctness bug, but worth flagging
since the task's design principles include restraint/reuse): since this exact hold-progress state
machine now needs the identical interruption-safety fix in two places, consider extracting a small
shared helper — e.g. a `HoldToCommitProgress` `@Observable` type or view modifier owning
`holdProgress`/`isHolding`/the tick `Task`, parameterized over duration and an `onComplete`
closure — so `PrimaryButton.holdToCommitBody` and `AlarmRingingView.escapeHatchHoldControl` both
drive their own visual (rectangle fill vs. `GoalRing`) from one correctly-interruptible engine
instead of maintaining two copies of the same fix going forward. This is a "nice to have,"
flagged for whoever next touches either file — not blocking the immediate bug fix in both places.

---

## 4. Content-transition gaps (SF Symbol / numeral swaps that currently "pop")

Several components swap an `Image(systemName:)`'s string or a numeral `Text` in response to state
changes, wrapped in a generic `.animation(...)` at a parent level. SwiftUI does **not**
automatically interpolate between two different SF Symbol names or between two numeral strings —
without an explicit `.contentTransition(...)`, the symbol/number just replaces itself instantly
inside whatever cross-fade the parent's `.animation` provides for other properties (color, layout),
producing a visible "pop" at the exact spot the eye is drawn to.

| File | Where | Current | Recommended |
|---|---|---|---|
| `LockStatusCard.swift:67` | `Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")` | swaps with no content transition | add `.contentTransition(.symbolEffect(.replace))`, gated: `reduceMotion ? .contentTransition(.opacity) : .contentTransition(.symbolEffect(.replace))` |
| `StreakPill.swift:34` | `Image(systemName: isFrozen ? "snowflake" : "flame.fill")` | swaps with no content transition | same pattern as above |
| `GoalRow.swift:124-138` | `statusIndicator`'s three `Image(systemName:)` cases (pending/inProgress/complete) | swaps with no content transition | same pattern, plus see §6.3 for the missing haptic |
| `GhostProgressBanner.swift:139,143` | `scoreItem`'s numeral `Text("\(value)")` | plain text swap | `.contentTransition(.numericText(value: Double(value)))` — SwiftUI's built-in numeric content transition (an "odometer" roll), which honors Reduce Motion automatically with no extra gating code needed |
| `TrophyCaseView.swift:296` / `CosmeticsShopView.swift:308` (both `CoinBalancePill`, two separate `private` copies — see §6.4) | `Text("\(balance)")` | plain text swap | same `.contentTransition(.numericText(value:))` fix, applied to **both** copies independently since neither file can reach the other's `private` type |

`symbolEffect(.replace)` itself is a moderately strong motion effect (a morph/draw transition), so
the reduce-motion fallback above (`.opacity`) is not optional decoration — treat it the same as any
other §1 finding, not a nice-to-have.

---

## 5. `AlarmRingingView.swift` — dedicated section (highest-stakes screen in the safe set)

This file is both the most animation-dense screen reviewed and the one where getting reduced
motion wrong has the highest cost (it's a full-screen, `interactiveDismissDisabled()` alarm the
user cannot swipe away). Two findings beyond §1/§3 above:

### 5.1 The pulsing background tint is close to an explicit HIG anti-pattern

```swift
// AlarmRingingView.swift:431-441
private func runPulseLoop() async {
    while !Task.isCancelled {
        withAnimation(.easeInOut(duration: phase.pulseDuration)) {
            isPulsing.toggle()
        }
        if phase != .waking {
            pulseHapticTick += 1
        }
        try? await Task.sleep(for: .seconds(phase.pulseDuration))
    }
}
```

This drives a **full-viewport background tint** (`phase.tint.opacity(isPulsing ? 0.32 : 0.10)`,
`AlarmRingingView.swift:127-129`) that runs continuously for as long as the alarm rings, plus a
`1.04×` scale pulse on the clock numeral (`AlarmRingingView.swift:183`). HIG's reduced-motion
guidance names both patterns explicitly as things to avoid: *"avoid full-viewport moving
backgrounds, slow looping oscillations (near 0.2 Hz / one cycle per 5s)."* The `.waking` phase's
1.6s pulse period is ≈0.31 Hz — not the exact 0.2 Hz called out, but squarely in the same "slow
looping full-screen oscillation" family the guidance warns about, and it's the phase a user with
vestibular sensitivity is guaranteed to experience first, every single time the alarm fires.

**This is the single highest-priority fix in this entire review.** Recommended change:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private func runPulseLoop() async {
    guard !reduceMotion else { return }   // see runHapticEscalationLoop() below — haptics
                                           // still escalate even when the visual pulse doesn't
    while !Task.isCancelled {
        withAnimation(.easeInOut(duration: phase.pulseDuration)) {
            isPulsing.toggle()
        }
        try? await Task.sleep(for: .seconds(phase.pulseDuration))
    }
}

/// Runs independently of the visual pulse: Reduce Motion is a *visual* motion preference, not a
/// request to silence the alarm's escalating haptic urgency (spec §5.10: "escalating
/// sound/haptics"). This keeps that safety-relevant escalation intact even when `runPulseLoop()`
/// is skipped above.
private func runHapticEscalationLoop() async {
    while !Task.isCancelled {
        if phase != .waking {
            pulseHapticTick += 1
        }
        try? await Task.sleep(for: .seconds(phase.pulseDuration))
    }
}
```

and register the new task alongside the existing ones:

```swift
.task { await runPulseLoop() }
.task { await runHapticEscalationLoop() }
```

Because `isPulsing` never flips when `runPulseLoop()` is skipped, `.scaleEffect(isPulsing ? 1.04 :
1.0)` (`AlarmRingingView.swift:183`) and the background tint's opacity both automatically stay at
their resting values with no further change needed at those call sites — this is a case where
gating the *source* of the state change is enough, unlike the `.animation(...)`-level fixes in §1.

One thing to preserve deliberately: urgency information should not disappear entirely under
Reduce Motion, only the *oscillation*. Consider having the tint sit at a fixed, phase-appropriate
opacity instead of always resting at the low end:

```swift
phase.tint
    .opacity(reduceMotion ? 0.20 : (isPulsing ? 0.32 : 0.10))
    .ignoresSafeArea()
```

`0.20` is a fixed midpoint between the two animated extremes — a static reminder of "how urgent" is
still visible without any oscillation, so a Reduce-Motion user doesn't lose the escalation cue
entirely, just its motion.

### 5.2 Everything else in this file is correctly structured

Worth stating explicitly rather than only listing problems: the four dismiss variants' progress
rings all correctly reuse `GoalRing` (inheriting whatever fix lands from §2); the countdown-timer
math and haptic-decile bookkeeping in `beginEscapeHatchHold` mirror `PrimaryButton`'s pattern
faithfully (bug and all — see §3.2); `.interactiveDismissDisabled()` plus the always-rendered,
never-gated escape hatch is exactly the right HIG "wayfinding" balance (no accidental dismissal,
but a way out always exists); and `onDisappear { focusTask?.cancel(); holdTask?.cancel() }`
correctly tears down in-flight `Task`s. No further changes recommended beyond §1/§3.2/§5.1.

---

## 6. Remaining component-by-component notes

### 6.1 `Theme.swift`

- No drift found: every color/radius/spacing/typography token matches `docs/spec.md` §15
  verbatim, and — cross-checked against `Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift`,
  which necessarily keeps its own hardcoded copy since the widget extension can't yet depend on
  this file — every hex value in that independent copy matches byte-for-byte. No second accent
  color exists anywhere in the reviewed set.
- Add `springGesture` (§2) and the `standard(reduceMotion:)` helper (§1) as the two concrete
  additions this review recommends to `Theme.Motion`.
- No `Theme.Materials` tokens exist today (see §7 — recommend adding one, but scoped narrowly).
- No `Theme.Metrics` (or similar) token for the repeated "icon badge circle" diameter used by four
  different row-style components at two different hand-picked sizes — see §8.

### 6.2 `GoalRing.swift` / `RingCluster.swift`

Already covered in §2/§4. One additional, low-priority note: `RingCluster`'s `ForEach(items)` has
no `.animation(value: items)` at the cluster level, so if a caller mutates the `items` array
in-place (add/remove a ring) without itself wrapping that in `withAnimation`, rings will
appear/disappear with no transition. Recommend, for polish (not correctness):

```swift
// RingCluster.swift, on the ForEach's container
.animation(reduceMotion ? nil : Theme.Motion.springStandard, value: items)
```

with individual cells getting `.transition(.scale.combined(with: .opacity))` (reduce-motion
fallback: `.transition(.opacity)`) if per-item insert/remove animation is desired.

### 6.3 `LockStatusCard.swift` / `GoalRow.swift` / `GhostProgressBanner.swift` — missing press feedback

All three are conditionally a `Button(action:) { rowBody }.buttonStyle(.plain)`. `.buttonStyle(.plain)`
suppresses SwiftUI's default press-state visual almost entirely, so these rows currently give
**zero visible feedback on touch-down** — a direct miss against HIG's foundational "Response — kill
latency" principle ("the moment lag appears, the feeling of directness falls off a cliff... respond
on pointer-down, not on release"). `PrimaryButton`'s own `StandardPrimaryButtonStyle` already
solves this correctly (`scaleEffect(configuration.isPressed ? 0.97 : 1)` +
`opacity(configuration.isPressed ? 0.92 : 1)`); recommend the same pattern applied consistently to
these three row-style tappable components, reduce-motion gated per §1:

```swift
private struct RowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.springGesture, value: configuration.isPressed)
    }
}
```

(`0.98`/`springGesture` rather than `PrimaryButton`'s `0.97`/`springStandard`: these are smaller,
denser rows where a 3% scale reads as more pronounced than on a full-width CTA — a slightly
smaller press scale keeps the feedback proportional.) Consider promoting this to a small shared
internal `ButtonStyle` in `Core/UI` once the implementation phase touches more than one of these
three files, rather than hand-copying it three times (same reuse note as §3.2).

Separately, `GoalRow.swift:79`'s `.sensoryFeedback(.success, trigger: status == .complete)` is a
correctly-implemented, causally-tied haptic (HIG "Multimodal feedback" — fires on the real
completion event, not a proxy) — no change needed there. `GoalRow`'s `statusIndicator` icon swap
needs the `.contentTransition` fix from §4.

### 6.4 `TrophyCaseView.swift` / `CosmeticsShopView.swift` — the highest-value *missing* moment

Spec §15 explicitly calls out "unlock celebration ≤ 1.2s; haptics on every verified event," and
this screen is the one place in the safe set where an achievement literally unlocks in front of the
user (a `Badge` row appearing via the live `@Query` while the screen is open) — yet
`TrophyTile` has no animation and no haptic at all on that transition:

```swift
// TrophyCaseView.swift:251-260 — isEarned flips instantly, silently, with no motion
ZStack {
    Circle()
        .fill(isEarned ? Theme.Colors.accent.opacity(0.16) : Theme.Colors.surface2)
        .frame(width: 60, height: 60)
    Image(systemName: isEarned ? milestone.systemImage : "lock.fill")
        .font(.system(size: isEarned ? 24 : 18, weight: .semibold))
        .foregroundStyle(isEarned ? Theme.Colors.accent : Theme.Colors.muted)
}
```

Recommended fix — animate the reveal, add the `.contentTransition` from §4, and add the haptic spec
§15 asks for on every verified event (currently absent from this screen entirely):

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// inside TrophyTile.body, replace the ZStack above with:
ZStack {
    Circle()
        .fill(isEarned ? Theme.Colors.accent.opacity(0.16) : Theme.Colors.surface2)
        .frame(width: 60, height: 60)
    Image(systemName: isEarned ? milestone.systemImage : "lock.fill")
        .font(.system(size: isEarned ? 24 : 18, weight: .semibold))
        .foregroundStyle(isEarned ? Theme.Colors.accent : Theme.Colors.muted)
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
}
.animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.springCelebration, value: isEarned)
.sensoryFeedback(.success, trigger: isEarned)
```

`springCelebration` (not `springStandard`) is the right token here specifically because this *is*
one of the "celebratory/positive feedback" moments its own doc comment names.

Two smaller notes on the same pair of files:
- `CoinBalancePill`'s numeral needs the `.contentTransition(.numericText(value:))` fix from §4,
  applied **twice** (once in each file's own `private` copy — `TrophyCaseView.swift:288-306` and
  `CosmeticsShopView.swift:296-318` — since neither file can reach the other's `private` type).
  Worth a one-line note to whoever applies these fixes: this duplication already exists in the
  codebase today for non-animation reasons (per `CosmeticsShopView.swift`'s own header comment,
  matching `ProgressView.swift`'s established convention of small per-file private helpers) — this
  review is not recommending a refactor to de-duplicate it, only flagging that the same one-line
  animation fix needs to land in both places or they'll visibly drift from each other.
- `CosmeticItemCard.actionRow` (`CosmeticsShopView.swift:276-293`) swaps between a "Buy" and an
  "Equip" `PrimaryButton` via a bare `@ViewBuilder if/else` with no transition, right at the moment
  a purchase's `.sensoryFeedback(.success, trigger: purchaseSuccessTick)` haptic fires
  (`CosmeticsShopView.swift:102`). The haptic and the hard visual pop happen in the same frame but
  don't *feel* synchronized (HIG "Harmony": the visual should feel materialized, not swapped).
  Recommend wrapping the state that drives `isOwned` in an animation at the call site:
  `.animation(reduceMotion ? nil : Theme.Motion.springCelebration, value: isOwned)` on `actionRow`.

### 6.5 `LockedOutMomentView.swift` / `WeeklyRecapShareView.swift` — the spinner→share-button swap

Both files share an identical pattern (`LockedOutMomentView.swift:335-357`,
`WeeklyRecapShareView.swift:181-204`): while `renderedImage == nil`, show a `ProgressView` +
"Preparing…" pill; once the `@MainActor`-isolated `ShareCard.renderImage` `.task` resolves, hard-swap
to the real `ShareLink`. This is a bare `if/else` inside `@ViewBuilder` with no transition at all —
the button's entire content (icon, label, and implicitly its tap target becoming a real `ShareLink`)
pops the instant rendering finishes. Recommend:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

@ViewBuilder
private var actions: some View {
    VStack(spacing: Theme.Spacing.sm) {
        Group {
            if let renderedImage {
                ShareLink(/* ... unchanged ... */) { shareLabel }
                    .buttonStyle(.plain)
            } else {
                preparingShareLabel
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: renderedImage != nil)
        // ...
    }
}
```

Separately, both files' `ShareCard` preview (`LockedOutMomentView.swift:285`,
`WeeklyRecapShareView.swift:138`) appears fully-formed the instant the screen mounts, with no entry
motion — a materialize-in would match HIG's "materialize, don't just fade" guidance for a card the
user is specifically about to export/share (this is the moment they should feel is a little
special). Recommend a one-shot scale+opacity settle, gated:

```swift
@State private var hasAppeared = false
// ...
ShareCard(content: shareCardContent)
    .frame(maxWidth: 320)
    .scaleEffect(hasAppeared ? 1 : 0.94)
    .opacity(hasAppeared ? 1 : 0)
    .onAppear {
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
            hasAppeared = true
        }
    }
```

Both files' `xmark.circle.fill` dismiss button is also `.buttonStyle(.plain)` with no press
feedback — same §6.3 fix applies here too.

Layout note (no material needed): both screens lay out header / `ScrollView` / footer as VStack
siblings, not an overlay, so content never actually scrolls *underneath* the header or footer —
HIG's "scroll edge effect, not a hard divider" guidance doesn't apply here since there's no overlap
to mask in the first place. If a future revision makes either header sticky/overlaid on the
scrolling content, that's the moment to add a bottom-edge gradient fade — not before.

### 6.6 `ShieldPreview.swift` — correctly static, one opportunity

Currently has zero animation, which is largely *correct*: this is a full-bleed "block" screen, and
HIG's "dim to focus" model treats a screen like this as the focus itself rather than a layered
sheet needing a scrim/material — the flat `Theme.Colors.background` fill is the right call, no
translucency needed (see §7). One opportunity: since `ShieldPreview` is presented as a "preview my
shield" surface from onboarding/LockSetup callers (outside this review's file scope to wire up), a
materialize-in transition on first appearance would be consistent with §6.5's recommendation for
the same reason — a small `.scale(0.96).combined(with: .opacity)` entry, reduce-motion gated to
`.opacity` alone. Explicitly **do not** add a continuous/looping pulse to the lock badge — HIG's
"avoid slow looping oscillations" guidance (already invoked in §5.1) applies here too, and unlike
`AlarmRingingView`'s deliberately escalating urgency, a static preview screen has no reason to loop
motion at all; if any per-appearance motion is added, keep it strictly one-shot.

### 6.7 `RecapCard.swift` / `ShareCard.swift`

Both are correctly animation-free as authored: `RecapCard` is a passive data display (any
"smooth load" transition belongs to whichever screen embeds it and decides when its data is ready
— that's `ProgressView.swift`, outside this safe set, so this is a deferred integration note, not a
finding against `RecapCard` itself). `ShareCard` is frequently rendered off-screen for
`ImageRenderer` export (`ShareCard.renderImage`) as well as shown live — correctly has no animation
of its own, since baking motion into a view that's sometimes rasterized to a static PNG would be
either wasted or actively wrong. Its two live call sites' *entrance* motion is covered in §6.5.

### 6.8 `PreviewCatalog.swift`

Dev-only tool, no user-facing implication, but worth one addition once any of the reduce-motion
fixes above land: add a second preview trait so implementers (who cannot visually check anything in
this environment either, but a future session with a Mac can) get an easy side-by-side:

```swift
#Preview("PreviewCatalog — Reduced Motion") {
    PreviewCatalog()
        .environment(\.accessibilityReduceMotion, true)
        .preferredColorScheme(.dark)
}
```

### 6.9 `LockSetupView.swift` / `AppPickerView.swift` / `AlwaysAllowedWarningView.swift`

Almost entirely plain `Form`/`List`/`Toggle`/`swipeActions` — system-provided components that
already animate correctly and already respect Reduce Motion with zero custom code needed; no
findings against the motion in these three files as authored. Two minor, low-priority notes: (1)
`LockSetupView`'s `defaultToggle` flip and new-row insertion into the `@Query`-backed `List` rely
entirely on `List`'s own default animations — fine, no action needed. (2)
`AlwaysAllowedWarningView` is, by its own header comment, not yet wired into either
`LockSetupView`'s editor form or onboarding — when that integration happens (explicitly out of this
task's scope per that file's own comment), recommend the *caller* wrap the conditional
`if shouldWarn { AlwaysAllowedWarningView(...) }` in `withAnimation` +
`.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))` rather than
adding animation inside the banner view itself (the banner has no opinion on when it appears/
disappears — that's correctly the caller's job, per its own header's "dumb about when to show
itself" design).

### 6.10 `SunriseAlarmSetupView.swift` / `BedtimeGateSetupView.swift`

Both are otherwise clean, system-idiomatic `Form` screens. Only finding: `variantRow`'s
`withAnimation(Theme.Motion.springStandard) { settings.dismissVariant = variant }`
(`SunriseAlarmSetupView.swift:230`) needs the standard §1 reduce-motion gate. Nothing else to
report — no gesture surfaces, no materials concerns, no optical-alignment issues found.

### 6.11 `Extensions/ZANOWidgets/**`

Reviewed in full (`ZANOHomeWidget.swift`, `ZANOLockScreenWidget.swift`,
`ZANOWidgetComponents.swift`, `ZANOWidgetColor.swift`, and both Live Activities). **No findings** —
and that absence is itself the correct outcome, not a gap: WidgetKit timelines render discrete
static snapshots the system composites/transitions on its own terms, so the near-total absence of
`.animation()`/`.transition()` calls across every file in this directory is structurally correct,
not an oversight. Two things worth naming explicitly rather than passing over silently:

- `ZANOFocusLiveActivity.swift`'s countdown correctly uses `Text(timerInterval:countsDown:)`
  (`AlarmRingingView.swift`'s and any future in-app countdown should copy this technique rather than
  a manual per-second state update — it's system-ticked with zero extra content-state pushes, and
  it's the one place in the whole safe set already doing exactly what Apple's own guidance
  recommends for a live countdown).
- `ZANOGoalRingView` (the widget-local, dependency-free re-implementation of `GoalRing`'s trim-
  stroke logic) correctly has no `.animation()` — adding one would do nothing useful against a
  timeline snapshot and risks misbehaving across timeline reloads. No change recommended.
- Reduce Motion is effectively moot for this directory today: nothing here animates continuously,
  and the system's own Dynamic Island/Live Activity morph transitions (which this code doesn't
  control) already respect the system Reduce Motion setting on their own.

---

## 7. Materials & depth (docs/spec.md §15's background/surface/surface-2 hierarchy)

**Finding: zero uses of SwiftUI `Material` (`.ultraThinMaterial`, `.regularMaterial`, etc.) exist
anywhere in the safe set.** Every card/surface is built from `Theme.Colors.background` /
`.surface` / `.surface2` as flat, fully opaque fills layered via
`.background(_:in: RoundedRectangle(...))`. This is **not a violation to "fix" by adding blur
everywhere** — spec §15 gives literal opaque hex values for all three tokens, and every reviewed
screen in this safe set uses them correctly and consistently as a *flat-fill elevation hierarchy*
(surface2 nested inside surface, both distinct from background), which is a legitimate, common dark-
UI depth strategy in its own right, not a mistake. Two specific observations rather than a blanket
recommendation:

1. **No floating-chrome-over-scrolling-content pattern exists anywhere in this safe set today** —
   checked specifically because HIG's materials guidance is mostly about exactly that pattern
   (toolbars/sheets that show content scrolling underneath them). `LockedOutMomentView` and
   `WeeklyRecapShareView`'s header/`ScrollView`/footer are laid out as flow siblings in a `VStack`,
   not an overlay, so there is no actual content-under-chrome overlap to apply a material or a
   scroll-edge fade to (see §6.5's layout note). `ShieldPreview` is a single full-bleed screen with
   no floating chrome at all. Nothing in this safe set currently calls for a `Material` — this is a
   genuine "reviewed, nothing to fix" outcome, not an omission.
2. **If/when a future screen in this app (in or out of this safe set) introduces a sticky
   header/toolbar over scrolling content** — the natural first candidate being `TodayView`'s
   tab/nav chrome, which is out of scope for this task (see §9) — recommend adding a narrowly-scoped
   `Theme.Materials` token now so that future work has a spec-compliant primitive ready rather than
   inventing an ad hoc blur value at the call site (which CLAUDE.md's "no ad hoc hex literals or
   magic numbers outside Theme.swift" rule would otherwise flag):

   ```swift
   // Theme.swift — proposed addition, not yet needed by anything in this safe set
   public enum Materials {
       /// For floating chrome (sticky headers/toolbars) that should show scrolled content blurred
       /// underneath rather than sit as a hard-edged opaque bar (Apple HIG "Materials & depth").
       /// Layered ON TOP of a screen's own background tint — never a replacement for the flat
       /// `Colors.surface`/`.surface2` fills spec §15 mandates for cards/rows, which stay opaque.
       @Environment(\.accessibilityReduceTransparency) private static var _unused // (illustrative
       // only — a real implementation reads this via a view's own @Environment, not statically;
       // shown here to flag that `reduceTransparency`, not `reduceMotion`, is the correct signal
       // to gate this specific token on)
       public static func floatingChrome(reduceTransparency: Bool) -> AnyShapeStyle {
           reduceTransparency
               ? AnyShapeStyle(Theme.Colors.surface)
               : AnyShapeStyle(.ultraThinMaterial)
       }
   }
   ```

   (The commented-out `@Environment` line above is illustrative only, flagging the *correct* signal
   to gate on — `@Environment(\.accessibilityReduceTransparency)`, read from within an actual `View`,
   not a static property — not literal code to ship.) This is infrastructure for a screen outside
   this review's scope; no call site in the reviewed safe set needs it today.

---

## 8. Optical alignment

One genuine, verifiable finding and one pattern worth standardizing:

1. **`PrimaryButton.label` has no horizontal padding at all.** (`PrimaryButton.swift:74-86`):

   ```swift
   private var label: some View {
       HStack(spacing: Theme.Spacing.xs) {
           if let systemImage { Image(systemName: systemImage)... }
           Text(title)...
       }
       .frame(maxWidth: .infinity)
       .padding(.vertical, Theme.Spacing.sm)   // ← vertical only
   }
   ```

   Every other padded surface in this codebase (`LockStatusCard`, `GoalRow`, `RecapCard`,
   `ShieldPreview`, etc.) applies both axes. Because `label` is `frame(maxWidth: .infinity)` with
   no horizontal inset of its own, its title/icon will sit flush against the button's rounded-rect
   edge whenever a caller doesn't separately add outer horizontal padding — and the `.holdToCommit`
   variant additionally draws a 1.5pt stroke border right at that same edge
   (`PrimaryButton.swift:104-107`), making a flush-left/right label look especially tight against a
   visible border. Recommend:

   ```swift
   .frame(maxWidth: .infinity)
   .padding(.horizontal, Theme.Spacing.md)
   .padding(.vertical, Theme.Spacing.sm)
   ```

2. **Icon-badge-circle diameter is hand-picked inconsistently across four visually-identical row
   patterns.** `LockStatusCard` and `GhostProgressBanner` both use a 40×40 circle with a 17pt icon;
   `GoalRow` (no-progress branch) and `AlwaysAllowedWarningView` both use a 32×32 circle with a
   15–16pt icon — same "leading icon badge + text column + trailing indicator" row shape, two
   different hand-tuned sizes, with no shared token naming either number. Not a visible bug (each
   file is internally consistent), but exactly the kind of drift a design-system token exists to
   prevent. Recommend:

   ```swift
   // Theme.swift — proposed addition
   public enum Metrics {
       /// Leading icon-badge circle diameter for a compact row (`GoalRow`'s bare-icon variant,
       /// `AlwaysAllowedWarningView`).
       public static let iconBadgeSmall: CGFloat = 32
       /// Leading icon-badge circle diameter for a card-level row (`LockStatusCard`,
       /// `GhostProgressBanner`).
       public static let iconBadgeMedium: CGFloat = 40
   }
   ```

   and have all four call sites reference one of these two instead of a bare `32`/`40` literal —
   low priority, but worth doing the next time any of these four files is touched for another
   reason, so a fifth future row-style component doesn't add a third hand-picked size.

No other optical-alignment issues were found: chevron sizing (13pt semibold) is already consistent
between `LockStatusCard` and `GhostProgressBanner`; `GoalRow`'s status-indicator glyphs are
internally consistent at 20pt; `ShieldPreview`'s icon-badge/notification-dot overlay
(`ShieldPreview.swift:136-157`) is a standard, correctly-executed "badge overlapping a circle's
edge" composition with no alignment issue found.

---

## 9. Deferred — genuinely valuable but outside this run's safe working set

Per this task's scope boundary (two other background workflows own `TodayView.swift`, every
`Onboarding/*.swift`, `Core/Sources/Core/UI/Components/CelebrationBurst.swift`, and
`App/ZANO/Features/Celebration/*` this run), the following were **not read, not touched, and are
not evaluated above** — noted here only so the observation isn't lost:

- **`TodayView.swift`** is the natural home for wiring `LockStatusCard`'s lock/unlock transition and
  `GoalRing`'s fill motion into a live screen — this document's §1/§2/§4 recommendations for those
  two components are written so whichever wave owns `TodayView` can apply them directly once it
  touches that file. Not reviewed here.
- **`CelebrationBurst.swift` / `App/ZANO/Features/Celebration/*`** — `docs/design/animation-library-
  decision.md` (already on disk, written by a prior task) already scoped the native-SwiftUI
  approach for the unlock-celebration moment itself (`PhaseAnimator`/`KeyframeAnimator` +
  `Canvas`/`TimelineView` particle burst, capped at `Theme.Motion.unlockCelebrationMaxDuration`,
  reduce-motion gated to drop straight to end-state). §6.4 above (`TrophyCaseView`'s badge-earning
  moment) is a smaller, local version of the same idea, scoped to a component actually in this run's
  safe set — the two should read as a matching pair once both land, but `CelebrationBurst.swift`
  itself was not opened this run.
- **`Onboarding/*.swift`** — `PrimaryButton`'s `.holdToCommit` variant exists specifically for the
  onboarding plan-reveal flow (spec §16 P4 mockup: "a hold-to-commit button at the bottom with a
  progress outline"), so §3.1's interruption-bug fix directly benefits that flow, but no onboarding
  file itself was read or evaluated this run.

---

## 10. Priority-ranked action list

1. **`AlarmRingingView.swift` §5.1** — gate the full-screen pulse loop behind
   `accessibilityReduceMotion`, split haptic escalation into its own always-running loop. Highest
   priority: this is the one finding closest to a documented HIG anti-pattern, on the screen with
   the least ability for the user to look away.
2. **§3.1/§3.2** — fix the hold-to-commit re-press interruption bug in both `PrimaryButton.swift`
   and `AlarmRingingView.swift`'s escape hatch (same fix, two files; the escape hatch is the more
   safety-relevant of the two).
3. **§1** — add `@Environment(\.accessibilityReduceMotion)` gating to every call site in the table
   in §1 (roughly a one-line change per site once the `Theme.Motion.standard(reduceMotion:)` helper
   from §1 exists).
4. **§2** — propose the spec §15 amendment and land `Theme.Motion.ringFill` as a critically-damped
   spring; add `Theme.Motion.springGesture`. Highest-leverage single token change (drives `GoalRing`
   transitively through six other files).
5. **§6.4** — `TrophyCaseView`'s badge-earning animation + haptic (currently entirely silent/static
   for what spec §15 calls a scored "unlock celebration" moment).
6. **§4** — `.contentTransition` fixes (symbol replace / numeric text) across `LockStatusCard`,
   `StreakPill`, `GoalRow`, `GhostProgressBanner`, both `CoinBalancePill` copies.
7. **§6.3** — press-feedback `ButtonStyle` for `LockStatusCard`/`GoalRow`/`GhostProgressBanner`'s
   plain-style row buttons.
8. **§6.5** — share-card materialize-in + spinner→button transition in `LockedOutMomentView`/
   `WeeklyRecapShareView`.
9. **§8** — `PrimaryButton.label`'s missing horizontal padding (small, but a real optical-alignment
   miss on the app's single most-reused button).
10. **§6.9/§6.10/§8 Metrics token** — remaining low-priority polish items, safe to bundle with
    whichever other change next touches each file.

§7 (materials) is not on this list as an action item — its conclusion is "no call site in this
safe set needs it today," with a proposed `Theme.Materials` token to have ready for the next
screen (outside this safe set) that does.
