// Copy.swift
// Core / Copy
//
// `Copy` is a pure namespace — every user-facing string this app shows lives under it, grouped by
// feature area, so a view never composes its own sentence (CLAUDE.md: "User-facing copy lives in
// Core/Sources/Core/Copy - no hardcoded UI strings elsewhere"). This file only declares the empty
// namespace; each feature area adds its own nested type via an `extension Copy { ... }` in its own
// file (e.g. `CommonCopy.swift` adds `Copy.common`, `OnboardingCopy.swift` adds `Copy.onboarding`,
// `PaywallCopy.swift` adds `Copy.paywall`), matching this same directory's existing per-file
// convention (`ShieldCopy.swift`, `WidgetCopy.swift` are each a single top-level type). Splitting
// `Copy` itself into a bare namespace plus per-area extensions — rather than one flat `Copy` type —
// lets independent sessions add a new area (e.g. a future `Copy.lockSetup` for
// `App/ZANO/Features/LockSetup/LockSetupView.swift`'s own already-flagged `Copy.lockSetup.*` gap)
// in its own file without any of them editing this one or each other's.
//
// This file was added while cross-checking the onboarding cluster (docs/spec.md §7): every
// onboarding/paywall screen already called `Copy.onboarding.*` / `Copy.common.*` / `Copy.paywall.*`
// against this exact assumed shape (see e.g. `App/ZANO/Features/Onboarding/Screen3MainGoal.swift`'s
// and `PaywallView.swift`'s own header comments, which each document the full key list they expect)
// — nothing about those call sites needed to change to make them real; only this namespace and its
// two sibling files (`CommonCopy.swift`, `OnboardingCopy.swift`, `PaywallCopy.swift`) were missing.

/// The root namespace every feature's user-facing copy nests under. Never instantiated.
public enum Copy {}
