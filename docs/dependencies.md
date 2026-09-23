# External dependencies (SPM)

None are added to `project.yml` yet — Session 0's scope is deliberately dependency-free (just the
local `Core` package). Add each package in the session that first needs it, via Xcode's
"Add Package Dependency" (which resolves the actual current latest version — don't hand-guess a
version number in `project.yml`, dependency versions drift fast enough that a stale pin here would
likely be wrong by the time someone builds this).

| Package | URL | Add in | Used for |
|---|---|---|---|
| PostHog | https://github.com/PostHog/posthog-ios | Session 1 | Analytics |
| Sentry | https://github.com/getsentry/sentry-cocoa | Session 1 | Crash reporting |
| Supabase Swift | https://github.com/supabase/supabase-swift | Session 7 | Backend client, auth, sync |
| RevenueCat | https://github.com/RevenueCat/purchases-ios | Session 6 | Subscriptions/paywall |
| Lottie | https://github.com/airbnb/lottie-ios | Deferred — not currently planned, see note | Unlock/milestone animations *(research recommends against — see below)* |

**Lottie note (2026-09-22):** `docs/design/animation-library-decision.md` researched this row and
recommends *not* adding `airbnb/lottie-ios` for the unlock-celebration and milestone moments spec
§12/§20 currently name it for — build those as native SwiftUI (`PhaseAnimator`/`KeyframeAnimator`
for sequencing, `Canvas`+`TimelineView` for the particle burst, `symbolEffect` for badge beats)
instead, both because that's a procedural/code-tunable effect rather than designer-authored
illustration and because `lottie-ios` still has open Swift 6 strict-concurrency gaps
(`LottieConfiguration.shared`, partial `Sendable` coverage). This is a recommendation for *this*
row's two named use cases specifically, not a blanket "never use Lottie" — a genuinely
designer-authored, After-Effects-sourced sequence (e.g. a complex onboarding mascot) would still be
a real reason to reconsider it. The row above is left in place (not deleted) since spec §12/§20
still name Lottie broadly; reconciling those references is a separate harden-pass task, not this
edit.

Optional, add only if/when actually used:

| Package | URL | Used for |
|---|---|---|
| swift-collections | https://github.com/apple/swift-collections | Gym-visit clustering (§9.4) |
| swift-algorithms | https://github.com/apple/swift-algorithms | Same |

After adding a package in Xcode, run `xcodegen generate` and check whether XcodeGen picked up the
resolved version in `project.yml` / `Package.resolved` — commit `Package.resolved` once one exists
so builds (including CI) are reproducible, but don't hand-write it.
