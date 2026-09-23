# Animation library decision: unlock celebration & milestone moments

**Status:** Research + recommendation only — not yet adopted. `docs/spec.md` §12/§20 and
`docs/dependencies.md` still list Lottie as of this writing; this doc argues for changing that,
but per this task's scope a separate harden pass reconciles those files, not this one.

**Question:** `docs/spec.md` §12 names Lottie (`airbnb/lottie-ios`) for "Unlock celebration,
milestone animations," and `docs/dependencies.md` schedules adding it in Session 5 or 9. Is that
still the right call for a small/mid-size iOS team building this in 2026, or has native SwiftUI
motion (PhaseAnimator, KeyframeAnimator, SF Symbol effects, TimelineView/Canvas particle work)
caught up enough to cover this specific use case without the extra dependency? Separately: does
`lottie-ios` have any Swift 6 strict-concurrency issues worth flagging before adoption?

**Bottom line: don't add Lottie for this. Build the unlock-celebration and milestone moments as
native SwiftUI (PhaseAnimator/KeyframeAnimator for the sequence, Canvas+TimelineView for the
particle burst, symbolEffect for badge/icon beats), driven entirely by `Theme.Motion`'s existing
tokens. Keep Lottie off the dependency list for now; revisit only if a real need for
designer-authored, After-Effects-sourced illustration work shows up later (e.g. a complex
onboarding mascot sequence), and even then scope it to the main app target only.**

---

## 1. What's actually being animated

Per spec §15 and the P3 mockup prompt (§16), the unlock celebration is: a burst of acid-green
particles, a headline ("Earned."), a subline, a Time Bank bar filling, and a small badge
appearing — all inside `Theme.Motion.unlockCelebrationMaxDuration` (1.2s). Milestones (streak
freezes, badges, "Comeback") are shorter variants of the same idea: a burst + a badge/icon beat.

This is a **procedural, code-tunable effect built from primitives already in the design system**
(accent color, radii, spacing, the two motion curves already defined in `Theme.swift`) — not a
piece of pre-rendered illustration a designer hands off as a finished asset. That distinction is
the crux of the recommendation below: Lottie's whole value proposition is shipping an
After-Effects-authored `.json`/`.lottie` file exactly as a designer drew it; a particle burst +
text + bar-fill + badge sequence, in ZANO's own accent color, over your own numeric progress
state, is not that kind of asset — it's easier to *build* than to *export and keep in sync*.

## 2. Native SwiftUI is no longer the weaker option for this

As of iOS 17+ (ZANO's min target per spec §12) and especially iOS 26 (current as of this
research, SF Symbols 7):

- **`PhaseAnimator`** (iOS 17+) drives a multi-step sequence where properties move together
  between discrete phases — exactly the "burst → settle → badge" shape of an unlock celebration.
- **`KeyframeAnimator`** (iOS 17+) choreographs independently-timed properties (e.g. particles
  scaling/fading on a different curve than the badge scaling in) — useful if the burst and the
  badge reveal shouldn't feel perfectly synced.
- **SF Symbol effects** (`symbolEffect(.bounce)`, `.pulse`, `.variableColor`, `.wiggle`,
  `.breathe`, plus `.appear`/`.disappear`/`.replace` transitions) cover badge/icon "pop" beats for
  free — no asset, no designer round-trip, and (per Apple's own WWDC23 "Animate symbols in your
  app" session) these are the same animation vocabulary Apple's own apps use, so they read as
  native by construction. SF Symbols 7 (iOS 26) adds finer-grained variable-color tiers and new
  draw-on animations, extending this vocabulary further this year.
- **`Canvas` + `TimelineView`** is the correct native tool for the actual particle burst itself —
  it's an immediate-mode drawing surface driven by a time schedule, built for exactly this kind of
  effect (particle systems, not expressible as a tween between two view states), and it composes
  with `.drawingGroup()` for Metal-backed compositing so a few dozen particles over 1.2s is cheap.

None of this requires a new SPM dependency, a design tool most small/mid teams don't have anyone
fluent in (After Effects + Bodymovin/LottieFiles), or an asset pipeline to keep in sync as the
design token (`Theme.Colors.accent`) evolves. It's also directly tunable against the tokens that
already exist in `Theme.Motion` (`springCelebration`, `unlockCelebrationMaxDuration`) instead of
baking timing into an opaque exported file.

## 3. Reduced-motion is a first-class, low-effort concern either way

Both paths support it, but differently:

- **Native:** `@Environment(\.accessibilityReduceMotion)` is read directly in the view and gates
  which animation runs — this is exactly the pattern this task (and every animation in this
  codebase) is already required to follow. Full control: e.g. keep the badge/haptic/text payoff
  but skip the particle burst and bar-fill spring, landing straight on end state.
- **Lottie:** since 4.3.0, Lottie supports "reduced motion" *markers* authored into the animation
  file itself — if Reduce Motion is on, it jumps to the last frame instead of playing. That's
  convenient, but it means the fallback behavior lives inside a binary-ish asset file authored in
  After Effects, not in reviewable Swift alongside the rest of the app's reduced-motion logic —
  a worse fit for a codebase where "every animation must respect
  `@Environment(\.accessibilityReduceMotion)`" is a stated, auditable rule (this task's brief, and
  implicitly spec §15's motion row). Native code makes this rule mechanically checkable; a Lottie
  marker makes it something you have to trust the asset was authored correctly.

Either way, whoever implements `CelebrationBurst.swift` (a concurrent wave's file — not touched by
this research) needs an explicit reduced-motion fallback path; this doc's recommendation just
means that fallback is plain Swift instead of an asset-authoring convention.

## 4. `lottie-ios` current state, and the Swift 6 concurrency issues worth flagging

Checked directly against the upstream repo (not from training-data memory, since dependency
versions and concurrency posture drift fast — CLAUDE.md's own working rule):

- **Current releases:** 4.6.0 (published 2026-01-06, changelog: "Lottie now requires Xcode 16 /
  Swift 6.0 or later") and 4.6.1 (2026-06-13, no concurrency-relevant changes). Requiring the
  Swift 6.0 *toolchain* is not the same claim as being strict-concurrency-checked — see below.
- **The package explicitly opts its own target out of Swift 6 strict checking.** `Package.swift`
  on `master` declares `swift-tools-version: 6.0` but sets `swiftLanguageMode(.v5)` on the Lottie
  target itself. In plain terms: Lottie *builds* under an Xcode-16-class toolchain, but the
  library's own source is not compiled with Swift 6's complete concurrency checking turned on —
  it's still Swift 5 mode internally. "Requires Swift 6.0" in their changelog is a toolchain-
  minimum claim, not a "we're strict-concurrency clean" claim, and conflating the two is a common
  and understandable misread of that changelog line.
- **A specific, named, still-live gap: `LottieConfiguration.shared`.** Issue #2483 ("LottieConfiguration
  shared instance in Swift 6," filed 2024-09-19) reports that accessing the shared static instance
  triggers a "not concurrency-safe" warning under complete concurrency checking in Swift 5 mode,
  and would be a hard error under Swift 6 language mode in a consuming app. That issue was closed
  same-day as "completed," which in context reads as redirected into Discussion #2484 rather than
  fixed — the discussion is where the maintainer (`calda`) is on record: making Lottie compatible
  with Swift 6 strict concurrency "will probably require breaking API changes," with no committed
  timeline. Net effect for ZANO: if the app target itself builds under Swift 6 language mode with
  complete concurrency checking (which CLAUDE.md and this task both require — "Swift 6 strict
  concurrency" is stated as a hard convention), touching `LottieConfiguration.shared`, or passing a
  `LottieAnimationView`/`LottieAnimation` across an actor boundary (e.g. decoding a `.lottie` file
  off the main actor, which is the recommended pattern to avoid janking the celebration screen on
  first load), is exactly the kind of call site likely to surface warnings-now/errors-under-Swift-6
  until Lottie ships that breaking API pass. This is a real, current, and non-cosmetic cost to
  budget for, not a hypothetical one.
- **Sendable coverage is partial, not systemic.** Prior releases show incremental, targeted fixes
  (`DotLottieCache` marked `Sendable` in 4.4.0; "fix warnings for types that inherit
  `@unchecked Sendable`" in 4.5.1) rather than a full audit of the public API surface. That pattern
  — patching specific reported warnings rather than a top-down Sendable pass — is consistent with
  "no committed Swift 6 concurrency timeline" above.
- **Extension/widget relevance is low but worth naming explicitly**, since this task's safe
  working set includes `Extensions/ZANOWidgets/**`: third-party rendering engines like Lottie are
  fine in a full app target but carry real overhead inside WidgetKit's restricted process, and
  ZANO's own spec (§11/CLAUDE.md) already says extensions "must be tiny" and read App Group state
  only. Spec §12's Lottie row only ever named "Unlock celebration, milestone animations," which are
  main-app-only surfaces — so this was never actually a widget/extension question, but it's worth
  stating outright so nobody later reaches for Lottie inside a widget or Shield extension by
  analogy: don't.

**Checked and ruled out as an alternative to airbnb/lottie-ios:** LottieFiles' own
`dotlottie-ios` (Rust-cored, "official" `.lottie`/`.json` player, API-compatible-ish with
`LottieAnimationView`/`LottieView`). Its README documents no Swift 6 / strict-concurrency posture
at all, so it doesn't resolve the concurrency question — it just moves it somewhere less
documented. Given the native path already wins on its own merits for this specific use case, there
was no reason to chase this further; noting it here only so a future session doesn't have to
re-discover it and re-ask the same question.

## 5. Recommendation

1. **Do not add `airbnb/lottie-ios` (or `dotlottie-ios`) to `docs/dependencies.md` / `project.yml`
   for the unlock-celebration/milestone use case.** Build it native.
2. **Composition sketch for whoever implements `CelebrationBurst.swift`** (a concurrent wave's
   file — this is a note for them, not an instruction this task is implementing): a `PhaseAnimator`
   or `KeyframeAnimator` driving overall sequence timing against `Theme.Motion.springCelebration`
   and capped at `Theme.Motion.unlockCelebrationMaxDuration`; a `Canvas`+`TimelineView` particle
   layer for the acid-green burst (`Theme.Colors.accent`), gated entirely off when
   `accessibilityReduceMotion` is true (drop straight to end-state: badge, headline, filled bar);
   `symbolEffect(.bounce)` or `.pulse` (skipped/replaced with a static appearance under reduced
   motion) for any badge/icon beat. All values sourced from `Theme`, per this codebase's existing
   "no ad hoc hex literals or magic numbers outside Theme.swift" rule — nothing here needs a value
   Theme doesn't already define.
3. **Revisit only if the need changes**, not if the tech changes: if a future session needs
   genuinely designer-authored illustration (a complex onboarding mascot, a multi-character story
   beat) that's cheaper to get from an After-Effects export than to hand-build, that's a real
   reason to reconsider Lottie — and by then the upstream Swift 6 situation may well have resolved
   (the maintainer thread signals intent, just no committed date as of this research). That's a
   different call than the unlock-celebration/milestone question this doc answers, and shouldn't
   be pre-decided here.
4. **For the harden pass reconciling `docs/dependencies.md` and `docs/spec.md`:** this is a
   reversal of a named §12 tech-stack choice, which `docs/decisions/README.md`'s own stated
   criteria says warrants a `docs/decisions/NNNN-*.md` entry (not written by this task — out of
   its scope and it was told not to touch `docs/dependencies.md` itself). Suggested edits for that
   pass: drop the Lottie row from spec §12's tech-stack table, drop the two Lottie bullets in §20
   ("Just use (libraries)" and the "borrow" line), and drop or footnote the Lottie row in
   `docs/dependencies.md` pointing at this doc.

## 6. Known issues / honesty about verification

- **Nothing in this doc was run, built, or visually checked.** Per this environment's constraints
  (no Mac, no Simulator, no device, no Swift compiler available here), the SwiftUI APIs discussed
  above (`PhaseAnimator`, `KeyframeAnimator`, `symbolEffect`, `Canvas`/`TimelineView`) are cited
  from Apple's own current documentation/WWDC material and third-party technical write-ups, not
  from having compiled or rendered anything in this repo. No code was written or changed by this
  task — it's research + recommendation only, as scoped.
- **The lottie-ios findings are read from the live GitHub repo** (release list, `Package.swift` on
  `master`, issue #2483, discussion #2484) as of this research date (2026-09-22), not from
  pretrained memory, per CLAUDE.md's working rule 5 about unverified/shifting API surfaces. Version
  numbers and issue states can move; re-check before actually deciding to adopt Lottie later.
  Repository conventions on GitHub (issues page rendering, search endpoints returning empty against
  a JS-rendered results page) meant a couple of secondary lookups were noisier than the primary
  ones cited; the load-bearing facts above (Package.swift's `swiftLanguageMode(.v5)`, issue
  #2483's close-same-day-as-completed with no linked fix PR, discussion #2484's maintainer comment)
  each came from a direct fetch of that specific page/API endpoint, not an aggregated search
  summary.
- **Deferred, out of this task's safe working set:** while researching the celebration moment, it
  was clear `TodayView` and the actual `CelebrationBurst.swift` implementation are where this
  recommendation gets applied — both are owned by a concurrent wave this run and were not read or
  touched. This doc is written so that wave (or whichever session next touches
  `docs/dependencies.md`) has the research already done.

## Sources

- [LottieConfiguration shared instance in Swift 6 — airbnb/lottie-ios Discussion #2484](https://github.com/airbnb/lottie-ios/discussions/2484)
- [Issue #2483 — LottieConfiguration shared instance in Swift 6](https://github.com/airbnb/lottie-ios/issues/2483)
- [airbnb/lottie-ios — `Package.swift` (master)](https://github.com/airbnb/lottie-ios/blob/master/Package.swift)
- [airbnb/lottie-ios — Releases](https://github.com/airbnb/lottie-ios/releases)
- [airbnb/lottie-ios — repository root](https://github.com/airbnb/lottie-ios/)
- [LottieFiles/dotlottie-ios — repository root](https://github.com/LottieFiles/dotlottie-ios)
- [Animate symbols in your app — WWDC23, Apple Developer](https://developer.apple.com/videos/play/wwdc2023/10258/)
- [`phaseAnimator(_:content:animation:)` — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/phaseanimator(_:content:animation:))
- [Using KeyframeAnimator in SwiftUI to Create Advanced Animations](https://medium.com/appcoda-tutorials/using-keyframeanimator-in-swiftui-to-create-advanced-animations-e33e240a435e)
- [Symbol Effects: SwiftUI's Built-In Animation Vocabulary For Every Icon](https://blakecrosley.com/blog/symbol-effects-vocabulary)
- [Animate SF Symbols with symbolEffect — Sarunw](https://sarunw.com/posts/animate-sf-symbols-with-symboleffect/)
- [SwiftUI Canvas & TimelineView Guide (2026) — Swift Crafted](https://swiftcrafted.dev/article/swiftui-canvas-timelineview-custom-drawings-animated-graphics-ios-26)
- [A "Native" Debate Over SwiftUI Animation — Fatbobman's Swift Weekly #154](https://weekly.fatbobman.com/p/fatbobmans-swift-weekly-154)
- [Breaking the WidgetKit Refresh Limit: Continuous Native Animation in Pure SwiftUI](https://dev.to/limooonik/breaking-the-widgetkit-refresh-limit-continuous-native-animation-in-pure-swiftui-35c2)
- [Lottie Animations and Accessibility: prefers-reduced-motion, ARIA, and Best Practices](https://dev.to/fazalshah/lottie-animations-and-accessibility-prefers-reduced-motion-aria-and-best-practices-51fo)
- [Lottie 4.3.0 now available, with official support for SwiftUI — Discussion #2189](https://github.com/airbnb/lottie-ios/discussions/2189)
