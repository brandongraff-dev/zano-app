# UI stress-test findings — Design System, LockSetup, Share, Trophy, Sunrise Alarm, Widgets

**Status:** Read-only survey. No Swift files were edited to produce this document — the only file
this task wrote is this one. **No Mac, Simulator, device, or Swift compiler exists in this
environment.** Nothing below was run, built, or visually observed. Every finding is a static read
of the SwiftUI/Swift source — view hierarchy, modifiers, computed properties, and how each
component's data flows at its real call sites — reasoned through against the stress-test axes
below (empty states, extreme values, Dynamic Type, VoiceOver labels, dark/light mode, RTL). Where
I write "would show/read/truncate," that is a prediction from reading the code, not an observation.

**Scope:** this task's safe working set — `Core/Sources/Core/UI/Theme.swift`;
`Core/Sources/Core/UI/Components/{GoalRing,RingCluster,LockStatusCard,StreakPill,TimeBankBar,
PrimaryButton,ShieldPreview,GoalRow,RecapCard,ShareCard,GhostProgressBanner}.swift`;
`Core/Sources/Core/UI/PreviewCatalog.swift`; `App/ZANO/Features/LockSetup/*.swift`;
`App/ZANO/Features/Share/*.swift`; `App/ZANO/Features/Trophy/*.swift`;
`App/ZANO/Features/SunriseAlarm/*.swift`; `Extensions/ZANOWidgets/**/*.swift` — every file read in
full. Plus every other screen under `App/ZANO/Features` (Today, Lock, Fuel, Progress, Settings,
Onboarding 1–14), read-only, for the stress-test axes below; nothing there was or will be edited,
and findings there are marked **deferred** in §8, not folded into the numbered/actionable list.

**Relationship to sibling docs already on disk in `docs/design/`:** `animation-library-decision.md`,
`animation-opportunities.md`, and `apple-design-review.md` already cover this exact safe set in
depth for *motion* — reduced-motion coverage, spring vs. linear curves, the hold-to-commit
VoiceOver gesture bug (§3.1/§3.2 of `apple-design-review.md`), content-transitions, and press
feedback. This document does not re-derive those; where a finding below overlaps (reduced motion,
the escape-hatch hold gesture), it's noted briefly with a cross-reference rather than repeated in
full. Everything else here — Dynamic Type scaling, VoiceOver *labels/grouping* (as opposed to
gesture activation), empty states, extreme values, dark/light-mode enforcement, and RTL layout — is
new ground those docs don't cover.

**Severity key:** Critical = user-facing break or a user gets stuck/blocked. High = a real class of
users (VoiceOver, RTL, non-English) hits broken or misleading UI in normal use. Medium = a visible
defect in a plausible but less common state. Low = polish/consistency, no functional break.

---

## 1. Critical

### 1.1 The Sunrise Alarm escape hatch is unreachable by VoiceOver
**File:** `App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:391-409` (`escapeHatchHoldControl`)

This is the exact control the task brief called out by name, and it fails the check. The escape
hatch is a hand-rolled `DragGesture(minimumDistance: 0)` hold (mirrors `PrimaryButton`'s
`.holdToCommit` internals) with `.accessibilityElement(children: .ignore)`,
`.accessibilityLabel(...)`, and `.accessibilityAddTraits(.isButton)` — but **no
`.accessibilityAction`**. Compare to `Core/Sources/Core/UI/Components/PrimaryButton.swift:120-136`,
which implements the identical hold-to-commit mechanic and explicitly adds
`.accessibilityAction { commitTick += 1; action() }` with a comment spelling out exactly why:
*"a sustained physical hold has no VoiceOver equivalent... unacceptable for anything safety-critical
(e.g. Emergency Unlock)."* `AlarmRingingView` reimplements the same gesture from scratch instead of
reusing `PrimaryButton(style: .holdToCommit)`, and drops that one safety-critical line in the
process.

**Impact:** a VoiceOver user cannot dismiss an escalating alarm via the "no one gets trapped"
escape hatch at all — a raw `DragGesture` does not respond to VoiceOver's double-tap activation,
and `.isButton` alone adds no activation path. At the `.critical` phase (60s+) this is a full-screen,
danger-tinted, continuously pulsing/haptic alarm (§1.2/§4.1 below) with the one required-by-spec
"no one gets trapped" affordance silently inert for this user. The squad-dismiss variant on the
same screen (`squadDismissContent`, line 306) *is* accessible, because it correctly calls
`PrimaryButton(style: .holdToCommit)` instead of reimplementing the gesture — that's the fix to
mirror here.

Also see `docs/design/apple-design-review.md` §3.1/§3.2, which independently reaches the same
conclusion from the gesture-interruptibility angle (confirms this isn't a one-off misreading).
**Corroborating duplicate outside the safe set (deferred, §8):** `App/ZANO/Features/Onboarding/
Screen14FirstWin.swift:538+` (`EmergencyHoldControl`) reimplements the same `DragGesture`
hold-to-commit for onboarding's own emergency-unlock exit, with the same missing
`.accessibilityAction`. Two independent copies of the same miss is a strong signal this needs a
shared, reusable `PrimaryButton`-style modifier in `Core/UI` rather than a per-screen fix.

### 1.2 `Theme.Typography` never scales with Dynamic Type — the whole app's text is fixed-size
**File:** `Core/Sources/Core/UI/Theme.swift:149-172`

Every font in the type ramp (`numeralLarge/Medium/Small`, `title`, `headline`, `body`, `caption`,
`captionEmphasized`) is built with `Font.system(size: <fixed pt>, weight:, design:)`. SwiftUI does
**not** scale a fixed-`size:` `Font.system` with the user's Dynamic Type / accessibility text-size
setting — only semantic text styles (`Font.system(.body)`, `.largeTitle`, etc.) or fonts built with
`relativeTo:`/`@ScaledMetric` do. A repo-wide search confirms neither is used anywhere: `grep -rn
"ScaledMetric\|relativeTo\|Font.system(\." Core App Extensions` returns nothing.

**Impact:** setting the system text size to any accessibility size (up to the largest,
"AX5") has **zero visual effect** on any `Theme.Typography`-based text — which is essentially every
label in every component and every screen that uses `Theme`, including every file in this safe set.
This defeats one of iOS's primary vision-accessibility features for the entire app, not just a
truncation risk at the largest size (the task's original framing — "does anything truncate/
overlap?" — actually undersells this: nothing even *attempts* to grow). This is worth flagging to
whoever owns `Theme.swift` next as the single highest-leverage accessibility fix available: swap the
fixed `size:` initializers for `Font.system(.title, design: .rounded)`-style relative constructors
(or `@ScaledMetric` where a specific pixel value must be preserved, e.g. the ring diameters
`GoalRing.Size` intentionally keeps fixed), ideally with `.dynamicTypeSize(...clamp)` on the
biggest numerals (a 44pt numeral scaled to AX5 could get very large in a ring) rather than leaving
type scaling off entirely.

### 1.3 `AlwaysAllowedWarningView`'s interactive buttons are unreachable by VoiceOver
**File:** `App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift:80-111`

The whole banner `HStack` — including the "Open Settings" text button (`openSettingsButton`,
lines 145-158, invoked at line 94) and the optional dismiss "×" button (`dismissButton`, lines
160-168, invoked at line 100) — is wrapped in a single `.accessibilityElement(children: .ignore)`
(line 109) with one `.accessibilityLabel` (line 110). `.ignore` removes the children from the
accessibility tree entirely; the container itself carries no `.isButton` trait or
`.accessibilityAction`, so it isn't activatable either.

**Impact:** with VoiceOver on, this banner is announced once as static text (title + message) and
neither embedded button can be reached or activated — a VoiceOver user cannot jump to Settings to
fix the "Always Allowed" gotcha this banner exists to warn about, and (when `onDismiss` is
supplied) cannot dismiss it via this control at all. Contrast with `GhostProgressBanner.swift`
(same directory family), which this file's own header cites as its style precedent: that component
also uses `.accessibilityElement(children: .ignore)`, but it only ever has **one** possible action
(the whole card is optionally one `Button`), so collapsing to one label is safe there. This file has
*two* independent actions nested inside the collapsed element, which is the actual bug. Fix: drop
`.accessibilityElement(children: .ignore)` from the outer `HStack` (let the two buttons expose
themselves normally, each already has its own visible label) or, if a single combined announcement
is wanted, add explicit `.accessibilityAction(named:)` entries for both "Open Settings" and
dismiss on the outer element.

---

## 2. High

### 2.1 No screen in this safe set forces dark mode on its real body — only in `#Preview`
**Files:** every screen in the safe set: `App/ZANO/Features/LockSetup/LockSetupView.swift`,
`AppPickerView.swift`, `AlwaysAllowedWarningView.swift`; `App/ZANO/Features/Share/
LockedOutMomentView.swift` (`.preferredColorScheme(.dark)` only at line 428, inside `#Preview`),
`WeeklyRecapShareView.swift` (only at line 336, `#Preview`); `App/ZANO/Features/Trophy/
TrophyCaseView.swift`, `CosmeticsShopView.swift`; `App/ZANO/Features/SunriseAlarm/
AlarmRingingView.swift` (only at line 639, `#Preview`), `BedtimeGateSetupView.swift` (only at line
146, `#Preview`), `SunriseAlarmSetupView.swift` (only at line 554, `#Preview`);
`Core/Sources/Core/UI/PreviewCatalog.swift` (lines 268/273, both `#Preview` only).

`Theme.swift`'s own header (lines 10-16) is explicit that the design system is a **fixed, dark-only
palette, not light/dark-adaptive**, and says "screens should still force
`.preferredColorScheme(.dark)` where appropriate at the App/Features layer." That pattern already
exists and works correctly elsewhere in this exact codebase — every one of `TodayView.swift:112`,
`LockStatusView.swift:71`, `FuelView.swift:136`, `ProgressView.swift:102`, `SettingsView.swift:124`,
`OnboardingContainerView.swift:147` (and 8 more Onboarding screens) calls
`.preferredColorScheme(.dark)` on their real production body, not just a preview. Every screen in
*this* safe set is the outlier that doesn't.

**Impact:** with the device's system appearance set to Light (or Automatic, during the day), these
screens still render `Theme`'s fixed near-black background/surfaces correctly (`Theme.Colors` are
hardcoded regardless), but everything the OS itself draws around that content — the status bar
(time/battery glyphs default to dark-on-light in Light mode, which is nearly invisible against
`#0A0A0B`), navigation bar chrome, sheet grab handles, and every native `.alert`/
`.confirmationDialog` these screens use heavily (`LockSetupView`'s delete confirmation and save
error alerts; `SunriseAlarmSetupView`'s forget-tag dialog; `CosmeticsShopView`'s purchase alerts) —
follows the *system* appearance, not the app's own dark design. The result is a same-screen mix of
a correctly-dark card and a light-styled system alert/status bar. Fix: add
`.preferredColorScheme(.dark)` to each screen's real body, matching the exact pattern the rest of
the app already establishes at the citations above.

### 2.2 `GoalRing`/`RingCluster`/`GoalRow` give VoiceOver no coherent reading — no label, no grouping
**Files:** `Core/Sources/Core/UI/Components/GoalRing.swift:98-101`, `RingCluster.swift:116-137`
(`RingClusterCell`), `GoalRow.swift` (whole body, no accessibility modifiers at all).

- `GoalRing` (lines 98-101) sets `.accessibilityElement(children: .ignore)` +
  `.accessibilityValue(Text("72%"))` but has **no `.accessibilityLabel`** and no label parameter in
  its `init` at all — there is no way for a caller to tell VoiceOver *what* the ring represents. A
  bare ring read in isolation announces only "72%."
- `RingClusterCell` (lines 116-137) stacks `GoalRing` + a title `Text` + an optional value `Text`
  with no `.accessibilityElement(children: .combine)` and no shared label — VoiceOver swipes
  through it as three disconnected stops: "72%," then "Workout," then "72/150g," in that order,
  never stated as one thing.
- `GoalRow.swift` has zero accessibility modifiers anywhere in the file — a VoiceOver user swiping
  a goal list hears the leading ring/icon, the title, the detail text, and the trailing status icon
  (whose SF Symbol name — "checkmark, circle" / "circle, dotted" / "circle" — carries no semantic
  "complete/in progress/pending" meaning on its own) as four separate, disconnected elements.

**Impact:** this is the app's single most-reused visual (every ring on every screen), and its
VoiceOver experience is uniformly fragmented. This is not hypothetical for out-of-safe-set screens
either — confirmed at real call sites in `TodayView.swift:167-195` (the 3 main goal rings),
`LockStatusView.swift:171-196`, `FuelView.swift:180-234`, and `ProgressView.swift` (via
`RecapCard`) — all reproduce the same gap, because the root cause is these two Core components.
Fixing `GoalRing`/`RingCluster`/`GoalRow` once in this safe set fixes VoiceOver for the whole app's
progress UI. Suggested fix: add an optional `label: String?` to `GoalRing.init`, wrap it plus
title/value in `.accessibilityElement(children: .combine)` (or an explicit composed
`.accessibilityLabel`) in `RingClusterCell`, and add the same combine + an explicit
status-aware label (e.g. "Leg day, 72 of 150 g, complete") to `GoalRow`.

### 2.3 Widget goal rings compare display *text* to a hardcoded English literal to pick an icon
**Files:** `Extensions/ZANOWidgets/LockScreenWidget/ZANOLockScreenWidget.swift:156`;
`Extensions/ZANOWidgets/Support/ZANOWidgetSnapshot.swift:221-223`

```swift
// ZANOLockScreenWidget.swift:156
Image(systemName: progress.title == "Protein" ? "fork.knife" : "drop.fill")
```
`progress.title` is populated from `ZANOWidgetSnapshot.swift:221-223` as the literal, hardcoded
English strings `"Protein"` / `"Water"` / `"Focus"` — not routed through `Copy`/localization at all.
This is two stacked problems: (a) every widget row/ring title is permanently English regardless of
the device's system language (there's no localization seam here at all), and (b) the circular
Lock Screen widget's icon-selection logic is a string-equality check against display text instead
of switching on the already-known `metric` case the caller has right there (`ring(for:
snapshot.protein, ...)` vs. `ring(for: snapshot.water, ...)` — the call site already knows which is
which). The moment (a) is fixed by localizing `title`, (b) silently breaks: every non-English
locale's protein ring would render the water icon (`"drop.fill"`, the `else` branch), since the
string would no longer equal the English literal `"Protein"`.

**Impact:** today, in English, this happens to work by coincidence. It's a landmine for the first
localization pass and worth fixing now while the cause is visible: switch on `metric` directly in
`ZANOLockScreenCircularView.body`'s existing `switch metric { case .protein: ... }` instead of
re-deriving it from `progress.title` inside `ring(for:unitLabel:)`.

### 2.4 `TrophyCaseView`'s disclosure chevron uses the non-mirroring SF Symbol name — breaks in RTL
**File:** `App/ZANO/Features/Trophy/TrophyCaseView.swift:141`

```swift
Image(systemName: "chevron.right")   // TrophyCaseView.swift:141 — "Open the Shop" row
```
Every other disclosure chevron in this exact safe set correctly uses the semantic, auto-mirroring
name: `Core/Sources/Core/UI/Components/GhostProgressBanner.swift:111` and
`LockStatusCard.swift:88` both use `"chevron.forward"`, which SwiftUI/SF Symbols automatically
flips to point left when the environment's layout direction is right-to-left (Arabic, Hebrew).
`"chevron.right"` is the literal, non-directional name and does **not** auto-mirror.

**Impact:** in an RTL locale, every other "tap to go further" chevron in the app correctly points
toward the start of the row's content (mirrored), while this one "Cosmetics Shop" row's chevron
keeps pointing to the physical right of the screen — i.e., backward, toward the reading direction's
end rather than its start. Small, but exactly the class of bug the RTL check exists to catch, with
an exact fix already established two files away in the same safe set: change `"chevron.right"` to
`"chevron.forward"`.

### 2.5 Reduced motion is unhandled everywhere in this safe set (cross-reference, not re-derived)
**Files:** whole safe set. `grep -rln "accessibilityReduceMotion" App Core Extensions Watch`
returns exactly two files in the *entire repository* — `App/ZANO/Features/Celebration/
UnlockCelebrationView.swift` and `Core/Sources/Core/UI/Components/CelebrationBurst.swift` — both
explicitly owned by the other concurrent wave, outside this safe set. Every spring/bounce/pulse
animation *inside* this safe set (`StreakPill.swift:37`'s `.symbolEffect(.bounce, value: count)`;
`PrimaryButton.swift`'s hold-to-commit scale/spring; `AlarmRingingView.swift`'s continuous
background-tint + clock-scale pulse loop, `runPulseLoop()` lines 431-441, which pulses every
0.45s–1.6s depending on escalation phase with **no** reduce-motion check anywhere in the file's 640
lines) ships with zero reduced-motion fallback, exactly the failure mode the task brief called out
by name ("never ship a spring/bounce/particle effect with no reduced-motion fallback").

This is already covered in exhaustive, per-file, per-line depth in `docs/design/
apple-design-review.md` §1 (cross-cutting) and §5.1 (the `AlarmRingingView` pulse specifically,
flagged there as "close to an explicit HIG anti-pattern" for its rapid full-screen opacity swings)
— see that document for the fix list rather than duplicating it here. Flagged in this document only
because the task brief explicitly asked for it and because `AlarmRingingView`'s pulse is also a
plausible mild photosensitivity/vestibular-discomfort concern on top of being a HIG motion miss
(continuous full-screen tint pulsing at up to ~1.1 pulses/sec on an alarm screen a user may be
staring at half-asleep).

---

## 3. Medium

### 3.1 `StreakPill`'s default VoiceOver label drops the "frozen" state entirely
**File:** `Core/Sources/Core/UI/Components/StreakPill.swift:26-47`

`accessibilityLabelOverride` defaults to `nil`, and the fallback (line 47) is just
`"\(count)"` — it never reads `isFrozen`. Visually, a frozen streak swaps the flame for a snowflake
and cools the tint (spec §8: "should feel protective, not fragile") — but a VoiceOver user gets
only the bare number either way unless every single caller remembers to pass a custom override that
separately encodes the frozen state. `ProgressView.swift:146` and `RecapCard.swift`'s `header`
(both real call sites, outside/adjacent to the safe set) call `StreakPill(count:)` with no override
at all, so today they get the silent version. Suggested fix: have the default fallback branch on
`isFrozen` itself (e.g. `isFrozen ? "\(count), frozen" : "\(count)"`) so the protective state is
never silently lost for VoiceOver users who don't get a hand-authored override.

### 3.2 `ZANOLockBadgeView` (widget) has no explicit accessibility label
**File:** `Extensions/ZANOWidgets/Support/ZANOWidgetComponents.swift:100-108`

```swift
struct ZANOLockBadgeView: View {
    let isLocked: Bool
    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isLocked ? ZANOWidgetColor.danger : ZANOWidgetColor.accent)
    }
}
```
No `.accessibilityLabel` anywhere. VoiceOver falls back to the SF Symbol's built-in glyph
description (something close to "padlock" / "unlocked padlock"), which is not guaranteed to convey
the app-semantic "Locked"/"Unlocked" state as clearly as the in-app `LockStatusCard` component does
(that one takes a fully caller-composed `statusLine` string specifically so the state is always
spelled out). Every Home Screen and Lock Screen widget family (`ZANOHomeWidget.swift`,
`ZANOLockScreenWidget.swift`) uses this badge. Fix: add
`.accessibilityLabel(isLocked ? WidgetCopy.controlLockedLabel : WidgetCopy.controlUnlockedLabel)`
(both keys already exist and are used elsewhere in `ZANOControls.swift`).

### 3.3 `CosmeticsShopView`'s 4-item segmented picker has long labels that won't fit standard widths
**File:** `App/ZANO/Features/Trophy/CosmeticsShopView.swift:143-151`

```swift
Picker(Copy.cosmetics.categoryPickerAccessibilityLabel, selection: $selectedCategory) {
    ForEach(CosmeticCategory.allCases, id: \.self) { category in
        Text(Copy.cosmetics.categoryTitle(category)).tag(category)
    }
}
.pickerStyle(.segmented)
```
Per the catalog-key checklist in this same file's header (lines 64-68), the four categories map to
labels like "Themes," "Ring Styles," "Shield Backgrounds," and "Coach Voice Packs." A
`.segmented` picker with 4 segments and labels that long is a known iOS layout squeeze even at
standard text size on a base iPhone width, and segmented controls don't wrap — they truncate or
visually compress. This is exactly the "does anything truncate/overlap" question the task asked,
answered from reading the label lengths against the control type, not from having rendered it.
Suggested fix: shorten the labels ("Shields" instead of "Shield Backgrounds," "Voice Packs" instead
of "Coach Voice Packs") or switch to a horizontally scrolling chip row (the same pattern
`FuelView.swift`'s `quickAddRow`/`quickRepeatSection` already use elsewhere in this codebase for an
open-ended, possibly-long set of options).

### 3.4 Selected-state pickers give VoiceOver no "selected" signal
**Files:** `App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:228-258` (`variantRow`);
same pattern in `App/ZANO/Features/Settings/SettingsView.swift`'s `coachVoiceSection` (deferred,
§8, same root cause).

Each dismiss-method row is a `Button` whose only visual indication of "this is the current choice"
is a conditionally-rendered `checkmark.circle.fill` icon (line 251-254) plus an accent tint on the
leading icon. Neither carries `.accessibilityAddTraits(.isSelected)` (or an equivalent label
addition), so a VoiceOver user swiping through the four Tag/Steps/Focus/Squad rows hears identical
"title, description, button" announcements for all four with no way to tell which one is currently
active. Fix: add `.accessibilityAddTraits(settings.dismissVariant == variant ? .isSelected : [])`
to `variantRow`.

### 3.5 `ShareCard` has no safeguard against long caller-supplied text overflowing its fixed export frame
**File:** `Core/Sources/Core/UI/Components/ShareCard.swift:78-121`

`ShareCard.renderImage` gives the card a **fixed** `.frame(width: 1080, height: 1920)` (default)
before handing it to `ImageRenderer`, and the view itself ends with `.clipShape(RoundedRectangle(...))`
— content that doesn't fit is silently clipped, not scrolled or truncated with an ellipsis.
`content.title` (line 87-89) and `content.statLine` (line 94, `.fixedSize(horizontal: false,
vertical: true)`, i.e. allowed to grow to as many lines as it needs) have no `lineLimit`. Real
callers pass caller-composed sentences here — `LockedOutMomentView.swift`'s title is
`Copy.lockedOut.headline(appName:blockingGoalSummary:)`, a full sentence built from a live app name
and goal summary; `WeeklyRecapShareView.swift`'s `statLine` embeds `Copy.share.weeklyRecapStatLine(...)`.
Neither this component's own file nor its two known callers cap those strings' length.

**Impact (extreme value): a long app name, a long localized sentence, or a long coach-voice line
pushed through `statLine`/`highlightLine`/`footerLabel` could grow the title/stat block tall enough
to push the footer wordmark, or even the day-ring strip, past the bottom of the fixed 1920pt frame
— and because the export is clipped, not scrolled, the overflow is silently cut off** rather than
degrading gracefully. This card is specifically built to be shared on social media (spec §5.14/
§5.16), so a silently truncated/cut-off export is a real user-facing failure mode, not just an
internal glitch. Suggested fix: cap `title`/`statLine` with an explicit `lineLimit` (matching the
truncation discipline `WeeklyRecapShareView.shortLabel(_:)` already applies to its own day-ring
labels for the same underlying reason — see that function's own comment), or give the whole card a
`ScrollView` for the on-screen preview path and only rely on the fixed frame for the actual
`ImageRenderer` export once content is known to fit.

### 3.6 "Preparing…" can get stuck forever if `ShareCard.renderImage` returns `nil`
**Files:** `App/ZANO/Features/Share/LockedOutMomentView.swift:302-310, 335-357`;
`WeeklyRecapShareView.swift:149-156, 181-204` (identical pattern in both)

```swift
.task {
    guard renderedImage == nil else { return }
    renderedImage = await ShareCard.renderImage(content: shareCardContent)
}
```
`ShareCard.renderImage`'s own doc comment states it returns `nil` "if `ImageRenderer` couldn't
produce one." Both callers only branch on `if let renderedImage` to decide between showing the real
`ShareLink` and a `preparingShareLabel` (a spinner + "Preparing…"); neither has an `else` for the
nil case. If rendering ever fails, `renderedImage` stays `nil` forever and the screen is stuck
showing an indefinite "Preparing…" spinner with the only way out being the separate small "dismiss"
text button underneath — a plausible extreme-condition trap (low memory, an unusual content size
from §3.5 above) with no retry and no error message. Suggested fix: treat `nil` as a terminal
failure state with its own message ("Couldn't prepare image — try again") rather than leaving
"Preparing…" indistinguishable from "still working."

### 3.7 Live Activities: unbounded numeric text has no width safeguard in the smallest regions
**Files:** `Extensions/ZANOWidgets/LiveActivities/ZANOEarnMeterLiveActivity.swift:68`;
`ZANOGymDwellLiveActivity.swift:53`; `ZANOLockScreenWidget.swift:163-171` (`streakGauge`)

`compactTrailing: Text("\(context.state.earnedMinutesRemaining)m")` (EarnMeter) and
`Text("\(context.state.elapsedMinutes)m")` (GymDwell) render into the Dynamic Island's compact
region, which is only comfortably wide enough for ~3 characters. `EarnMeterActivityAttributes`'s
own file header notes `TimeBank.earnedMin` is explicitly *unbounded* ("no fixed daily maximum...
this is unbounded"), and a long gym visit (`elapsedMinutes`) can just as easily run past 2 digits.
Neither `Text` has a `.minimumScaleFactor` or truncation safeguard, unlike the Home Widget's own
`ZANOGoalRingView` (`ZANOWidgetComponents.swift:31`, which does set `.minimumScaleFactor(0.7)` for
exactly this reason). Similarly, `ZANOLockScreenWidget.swift`'s `streakGauge` (extreme-value test
case from the brief: streak = 9999) renders `Text("\(snapshot.currentStreak)")` in a
`.accessoryCircular` widget (one of the smallest possible surfaces) with no scale/limit safeguard
either. Suggested fix: match the Home Widget's own precedent and add
`.minimumScaleFactor`/`.lineLimit(1)` to these three sites.

### 3.8 `GoalRow`'s success haptic also fires when a goal is *un*-completed, not only completed
**File:** `Core/Sources/Core/UI/Components/GoalRow.swift:79`

```swift
.sensoryFeedback(.success, trigger: status == .complete)
```
`sensoryFeedback(_:trigger:)` fires whenever the `Equatable` trigger value *changes*, in either
direction — not only when it becomes `true`. If a row's `status` ever flips from `.complete` back
to `.pending`/`.inProgress` (a plausible transition: a day rolls over and a recurring goal's status
resets while the same row identity persists, or a logged event is retracted/edited), this fires the
same `.success` haptic a second time on the way back down — a "you did it!" buzz for a goal that
just became un-done. Contrast with `TodayView.swift:113-118`, which handles the identical shape of
problem correctly: `.sensoryFeedback(.success, trigger: isLocked) { oldValue, newValue in oldValue
== true && newValue == false }`, an explicit direction-gated condition closure. Suggested fix: apply
the same pattern here — `trigger: status, condition: { old, new in old != .complete && new ==
.complete }` (or equivalent) — so the haptic only fires on the forward transition.

(One sibling document, `apple-design-review.md` §6.3, calls this line "correctly-implemented...
no change needed" from the causal-tie angle; that's true for the forward transition, but the
reverse-transition false-positive above is a distinct, narrower issue worth flagging alongside it.)

### 3.9 `ShieldPreview`'s Emergency affordance has a sub-44pt tap target
**File:** `Core/Sources/Core/UI/Components/ShieldPreview.swift:121-127`

```swift
Button(action: emergencyAction) {
    Text(emergencyActionTitle).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.muted).underline()
}
.buttonStyle(.plain)
```
No `.frame(minHeight:)`/`.contentShape` padding — the tappable area is exactly the rendered size of
a 13pt caption string. Apple HIG's minimum recommended touch target is 44×44pt. This file's own
header stresses that `emergencyActionTitle`/`emergencyAction` are non-optional by design
specifically so "it is impossible to construct a `ShieldPreview` without" an emergency path — the
structural guarantee is right, but the resulting control is one of the smallest tap targets in the
safe set, on the one button the safety rule (CLAUDE.md: "never trap the user") most depends on
being easy to hit. Suggested fix: add `.contentShape(Rectangle())` over a padded frame
(`.frame(minHeight: 44)`) around the emergency button, independent of its visual (intentionally
small/low-emphasis) text size.

### 3.10 `ZANOControls`' Lock toggle has no confirmation for turning the lock off
**File:** `Extensions/ZANOWidgets/Controls/ZANOControls.swift:28-46`

Spec §6 lists this control explicitly as "Toggle: Lock On/Off (**with confirmation for Off**)."
`ZANOLockToggleControl` wires a plain `ControlWidgetToggle` straight to `ZANOSetLockStateIntent()`
with no confirmation step of any kind — toggling off in Control Center (or from the Lock Screen/
Action Button, wherever this Control is assigned) unlocks immediately. `ControlWidget`'s toggle API
has no built-in confirmation-sheet mechanism, so this may be a genuine platform constraint rather
than an oversight — but as read, the shipped behavior doesn't match the spec-literal requirement,
and disabling a self-imposed discipline lock with one accidental long-press-menu tap (Controls sit
one swipe away in Control Center) is exactly the kind of low-friction bypass the whole product is
designed to prevent. Worth a decision (confirm intentional platform limitation, or find another way
to add friction — e.g. an `AppIntent` with `.confirmationTitle`) before shipping, not a definite
bug given the API surface.

---

## 4. Low

### 4.1 `ZANOWidgetColor.swift` is now a stale duplicate of `Theme.swift`
**File:** `Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift:7-11`

The file's own header says: *"If/when `Core/Sources/Core/UI/Theme.swift` ships with equivalent
tokens, this file should be deleted in favor of it."* `Theme.swift` now exists (it's in this same
safe set), its hex values match `ZANOWidgetColor` exactly, and every other file in
`Extensions/ZANOWidgets` already successfully `import Core` (confirmed via `grep -l "^import
Core"` across the extension — 9 of 10 widget files import it; only `ZANOWidgetColor.swift` itself
doesn't need to). Nothing is broken today since the two token sets are identical, but it's a
documented, self-flagged drift risk: a future retune of `Theme.Colors` (the whole reason `Theme`
exists as a single source of truth) would silently *not* propagate to widgets/Live Activities/
Controls unless someone remembers this second copy exists. Low severity only because nothing is
wrong *yet* — worth a follow-up to delete `ZANOWidgetColor` and reference `Theme.Colors.*` directly.

### 4.2 `PreviewCatalog` doesn't exercise `GhostProgressBanner`
**File:** `Core/Sources/Core/UI/PreviewCatalog.swift:22-40`

The catalog's section list (`themeTokensSection` through `shareCardSection`) covers 10 of the 11
named components in this safe set's Core UI list — `GhostProgressBanner` (added, per its own file
header, after the rest of the catalog existed) has no corresponding section. Not a functional bug
(nothing reachable from the app is affected), but it means this component is the one piece of the
design system nobody — human or a future static read — gets a side-by-side light/dark/empty/full
comparison of via the one tool built for exactly that. Suggested fix: add a
`ghostProgressBannerSection` alongside the others, including a `hasGhostWeek: false` sample (the
empty-state branch, §5's empty-state checklist) since that branch changes both the tint and hides
the scoreboard entirely.

### 4.3 No max-length validation on user-entered names anywhere in the safe set
**Files:** `App/ZANO/Features/LockSetup/LockSetupView.swift:323` (lock-set name `TextField`);
`App/ZANO/Features/Settings/SettingsView.swift:541` (gym name, deferred/adjacent);
`SunriseAlarmSetupView.swift` (NFC tag label, defaulted, not user-typed here)

None of these `TextField`s cap input length. Every consumer downstream that displays the resulting
string does apply a `lineLimit` (`LockStatusCard.statusLine` at `lineLimit(2)`, the Home Widget's
`Text(...).lineLimit(2)`, etc.), so a pathologically long name (the task's "very long user-entered
string" extreme-value case) degrades to a truncated string rather than a broken layout anywhere I
traced it — genuinely low severity — but there's no single place enforcing a sane ceiling (e.g. 40
characters) at the point of entry, so every new consumer has to independently remember to guard
against it rather than being able to trust the string is already bounded.

### 4.4 Widget-scale `StreakPill` equivalent uses a literal 🔥 emoji, not the tinted SF Symbol the in-app version deliberately chose
**Files:** `Extensions/ZANOWidgets/Support/ZANOWidgetComponents.swift:85-97`
(`ZANOStreakPillView`); `ZANOLockScreenWidget.swift:163-171` (`streakGauge`)

`Core/Sources/Core/UI/Components/StreakPill.swift`'s own header explains it deliberately renders an
SF Symbol flame "instead of the literal emoji so it inherits system dynamic type, tinting, and
dark-mode rendering correctly." Both widget-scale equivalents do the opposite —
`Text("🔥")` — which can't be tinted via `.foregroundStyle` (emoji ignore text color) and renders
as Apple's fixed-color emoji glyph rather than the app's single accent-tinted flame. Purely a
visual-consistency nit between the in-app and widget-scale takes on the same element, not a
functional defect (this is a widget-extension constraint call, not necessarily wrong — SF Symbol
flame.fill vs. 🔥 is a legitimate stylistic choice for glanceable widget chrome), flagged for
awareness in case it wasn't a deliberate divergence.

### 4.5 `NFCStepList`'s numbered badge is sized for one digit
**File:** `App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:515-541`

`Text("\(step.id)")` sits in a fixed `.frame(width: 18, height: 18)` circle at
`captionEmphasized` (13pt) size. `NFCTagSetupInstructions.shortcutsAutomationSteps`'s actual step
count isn't in this safe set to confirm, but if it ever reaches 10+ steps, the two-digit number
would be visually cramped inside an 18pt circle sized for one digit. Low severity / speculative —
flagged only because it's a concrete, checkable extreme-value seam if that step list ever grows.

---

## 5. Empty states — explicitly checked, mostly handled well

Answering the brief's specific empty-state prompts (0 goals, 0 streak, no lock sets, no squads)
directly, since most of this safe set handles them correctly and that's worth confirming rather
than only reporting defects:

- **0 goals / no rings supplied:** `RecapCard` (line 65: `if !ringItems.isEmpty { RingCluster(...) }`)
  and `ShareCard`'s `dayRingsStrip` (empty `ForEach` over `[]`) both degrade gracefully — no
  crash, no visible gap beyond the section simply not rendering.
- **No lock sets:** `LockSetupView.emptyState` (lines 162-172) uses a proper
  `ContentUnavailableView` with a "create one" CTA — correct pattern.
- **No mapped Sunrise Tags:** `SunriseAlarmSetupView.tagSection` (line 279) and
  `AlarmRingingView.tagDismissContent` both handle the zero-tags case with fallback copy rather
  than an empty list with no explanation.
- **No squads:** `SunriseAlarmSetupView.squadSection` (line 375, `squadsLoadFailed ||
  mySquads.isEmpty`) collapses network failure and "genuinely zero squads" into the same graceful
  empty-state text rather than surfacing a raw error — reasonable, though it does mean a real
  network failure is indistinguishable from "you have no squads" to the user; low-severity note,
  not filed as a separate finding.
- **0 badges (Trophy Case):** `TrophyCaseView`'s six canonical milestone tiles are a **static**
  list (line 161, explicitly not derived from `badges`), so a brand-new user with zero `Badge`
  rows still sees all six tiles, correctly locked/dimmed — this is the one place in the safe set
  that most deliberately designed for the true zero-state rather than just tolerating it.
- **Streak = 0 / no `Streak` row yet:** every safe-set caller of `StreakPill`/streak data uses
  `?? 0` fallbacks; `StreakPill(count: 0)` renders fine (no special-casing needed, a 0 is a valid
  number). No defect found here.
- **Time Bank empty (`totalMinutes == 0`):** `TimeBankBar.fraction` (line 34-37) explicitly guards
  `totalMinutes > 0` and returns 0 rather than dividing by zero — correct, and exercised directly
  in `PreviewCatalog`'s own "Time Bank empty" sample (line 142).

---

## 6. Extreme values — explicitly checked

- **Streak = 9999:** handled safely everywhere I traced it *except* the two Live Activity/Lock
  Screen widget circular-gauge sites flagged in §3.7 above (no scale/limit safeguard on very wide
  numerals in the smallest surfaces). Everywhere `Theme.Typography` renders a streak count inside
  an intrinsically-sized `HStack`/`Capsule` (in-app `StreakPill`, `RecapCard`, `TrophyCaseView`'s
  `CoinBalancePill` pattern), the container grows with the text — no truncation risk there.
- **100% vs. 0% progress:** `GoalRing.clampedProgress` (line 78-80) and `TimeBankBar.fraction`
  (line 34-37) both explicitly `min(1, max(0, ...))`-clamp, so out-of-range inputs (negative, or
  >1.0 from a caller's bad math) can't visually overflow the ring/bar. Correct defensive coding.
- **A very long user-entered string:** see §3.5 (`ShareCard`, the one place I found a real
  overflow/clipping risk) and §4.3 (no input-side length cap, but every consumer applies
  `lineLimit` downstream, so this degrades to truncation almost everywhere else rather than a
  broken layout).
- **`target == 0` / divide-by-zero:** every fraction computation in this safe set (`GoalRing`,
  `TimeBankBar`, and the widget-side `ZANORingProgress.fraction` in
  `ZANOWidgetSnapshot.swift:40-43`) explicitly guards `target > 0` before dividing — no NaN/crash
  risk found.

---

## 7. Dynamic Type, dark/light mode, RTL — summary answers to the brief's direct questions

- **"Does anything truncate/overlap at the largest accessibility size?"** The more important
  answer is §1.2: nothing *scales* at the largest accessibility size in the first place, because
  `Theme.Typography` fonts are fixed-`size:`. Once that's fixed, the specific truncation risks to
  re-check are: `LockStatusCard.statusLine` (`lineLimit(2)`, could genuinely truncate a long
  multi-app lock-set summary once text can grow), `RingClusterCell`'s title/value `Text`s (fixed
  cell width `max(size.diameter, 64)`, `lineLimit(1)`), and `TrophyTile`'s badge title
  (`lineLimit(2)` in a 96pt-min grid cell) — all three already have a `lineLimit`, so the risk is
  graceful truncation with ellipsis, not overlap/clipping, once scaling is enabled.
- **"Dark vs. light mode — Theme.swift should already handle this — confirm."** It does **not**,
  by design: `Theme.swift`'s own header (lines 10-16) states this is a single fixed dark palette,
  not an adaptive one, and delegates forcing dark mode to each screen. §2.1 above is the actual
  finding: every other screen in the app already does that correctly; every screen in this safe set
  currently doesn't.
- **RTL layout:** the one concrete break found is §2.4 (`chevron.right` vs. `chevron.forward` in
  `TrophyCaseView`). Everywhere else I checked — `.swipeActions(edge: .trailing)` in
  `LockSetupView`/`SunriseAlarmSetupView`, every `HStack`'s use of `.leading`/`.trailing` alignment
  rather than hardcoded left/right, `GoalRing`'s circular fill direction (a circle reads the same
  mirrored either way; not flagged as a defect) — uses SwiftUI's auto-mirroring primitives
  correctly.

---

## 8. Deferred — valuable findings outside this run's safe working set

Per this task's instructions, these are **not** implemented and the files below were **not**
edited — noted here only so they aren't lost, for whichever wave owns them.

- **`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:538+` (`EmergencyHoldControl`)** — a
  second, independent hand-rolled `DragGesture` hold-to-commit (onboarding's own emergency-unlock
  exit) with the same missing `.accessibilityAction` as §1.1. Two independent duplicates of the
  same miss is itself worth flagging to whoever eventually owns a shared fix.
- **`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:223,330`** — `.symbolEffect(.bounce,
  value: confettiBurstID)` and `.symbolEffect(.pulse, options: .repeating)` in the First Win
  celebration, and **`Screen9WakeUp.swift`'s `OnboardingAnimatedCount`** (count-up animation,
  lines 168-190) — neither respects `accessibilityReduceMotion`, corroborating how far the §2.5
  gap extends outside this safe set too.
- **`App/ZANO/Features/Lock/LockStatusView.swift:318`** — `Copy.timeBankFootnote` is
  `"Unused minutes expire at midnight — spec §5.2, no hoarding."` — an internal spec-section
  citation appears to have been left inside actual user-facing copy text. Worth a content pass
  before ship regardless of which wave owns it.
- **`App/ZANO/Features/Today/TodayView.swift:167-195`, `LockStatusView.swift:171-196`,
  `FuelView.swift:180-234`** — all three reproduce the §2.2 `GoalRing`/`RingCluster`/`GoalRow`
  VoiceOver-grouping gap at their own call sites; no new root cause, just confirms the Core-level
  fix (§2.2) is worth prioritizing since it fixes all of these at once.
- **`App/ZANO/Features/Settings/SettingsView.swift`'s `coachVoiceSection` (lines 142-171)** — same
  missing-`.isSelected`-trait pattern as §3.4.

---

## 9. What I did not, and could not, verify

- Nothing visual was rendered. Every claim above about wrapping, truncation, or overlap is inferred
  from `lineLimit`/`frame`/font-size values in the source, not from a screenshot.
- VoiceOver announcement text is described based on documented SwiftUI accessibility-tree behavior
  (`.accessibilityElement(children: .ignore)` removing children from the tree; SF Symbols carrying
  Apple-provided default descriptions), not from running VoiceOver.
- RTL mirroring behavior (`chevron.forward` auto-flipping) is stated per Apple's documented SF
  Symbols/SwiftUI layout-direction behavior, not observed on a device set to an RTL language.
- Whether `Copy.*`/`WidgetCopy.*` members referenced throughout this safe set actually exist with
  the assumed signatures is out of this document's scope — several files' own headers already flag
  their own "ASSUMED API" status for `Copy`; this survey took those assumptions as given rather than
  re-verifying them against `Core/Sources/Core/Copy`.
