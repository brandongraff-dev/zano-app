// Screen13Paywall.swift
// App / Features / Onboarding
//
// A THIN FORWARDER. Screen 13 (docs/spec.md §7.13 "Paywall") is `PaywallView`, backed by
// `Core/Sources/Core/Monetization/PaywallViewModel.swift` (real RevenueCat offerings, purchase and
// restore, the plan the user built, `Copy.paywall.*`). This file used to be a second, older
// placeholder paywall — its own plan cards, a hard-coded price table, a `PaywallPlan` enum and an
// unconditional "advance as if the trial started" — that `OnboardingContainerView` had stopped
// routing to. Two paywalls with diverging structure is the exact failure competitive-research §2.3
// calls out, and the placeholder's hard-coded prices and fake-success path would have been a
// liability the day somebody wired it back in, so it is gone: this type now only exists so any
// reference to `Screen13Paywall` (a preview, a UI-test note) keeps compiling and lands on the one
// real screen.
//
// The `paywall*` strings in `Copy.onboarding` that only the placeholder used are now unreferenced;
// deleting them is a Copy-owner change (`OnboardingCopy.swift` is not this file's to edit).

import SwiftUI
import Core

@MainActor
struct Screen13Paywall: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        PaywallView(flowState: flowState)
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen13Paywall(flowState: flowState)
    }
}
