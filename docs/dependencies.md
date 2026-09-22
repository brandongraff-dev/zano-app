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
| Lottie | https://github.com/airbnb/lottie-ios | Session 5 or 9 (first celebration animation) | Unlock/milestone animations |

Optional, add only if/when actually used:

| Package | URL | Used for |
|---|---|---|
| swift-collections | https://github.com/apple/swift-collections | Gym-visit clustering (§9.4) |
| swift-algorithms | https://github.com/apple/swift-algorithms | Same |

After adding a package in Xcode, run `xcodegen generate` and check whether XcodeGen picked up the
resolved version in `project.yml` / `Package.resolved` — commit `Package.resolved` once one exists
so builds (including CI) are reproducible, but don't hand-write it.
