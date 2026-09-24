// OnboardingPaywallFirstWinCopy.swift
// Core / Copy
//
// Three strings the onboarding/paywall design pass (screens 13-14, docs/design/
// {competitive-research,composition-audit,better-layout-findings}.md) needed that no existing
// `Copy.<area>` had. They are added as `extension`s of the two areas they belong to
// (`Copy.paywallTimeline`, `Copy.onboardingReveal`, both in `OnboardingRevealCopy.swift`) from
// their own file, so this pass could add wording without editing files another workflow may be
// touching. A copy owner is free to fold these into the home files; every call site names the
// enum, so moving a member is a one-line change per site.
//
// Wording rules (same as `OnboardingRevealCopy.swift`): calm, no urgency, no countdown, nothing a
// paywall could be accused of pressuring with (spec §21 "no dark patterns", §8 rule 9 "no shame").

import Foundation

extension Copy.paywallTimeline {

    /// The small heading over the dated trial timeline (Today / reminder / trial ends). The
    /// timeline only renders when the selected plan has a free trial.
    public static let timelineHeading = "How your trial works"

    /// Title of the plan-loading failure state. Names what failed, so the message under it (the
    /// cause) and the "Try again" button read as one thought. Replaces a bare error string.
    public static let plansLoadFailedTitle = "Couldn't load plans"

    /// One line under `plansLoadFailedTitle`: what happened and what to do, not a raw StoreKit error.
    public static let plansLoadFailedDetail = "The App Store didn't answer. Check your connection, then try again."
}

extension Copy.onboardingReveal {

    /// The unit on the first-win intro ring ("2" over "min"): the ring the user is about to fill.
    public static let firstWinRingUnit = "min"
}
