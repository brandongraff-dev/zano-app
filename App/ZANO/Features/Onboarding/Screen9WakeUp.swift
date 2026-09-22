// Screen9WakeUp.swift
// App / Features / Onboarding
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). Do not edit from
// another session — CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §7.9 "Wake-up moment": 'Compute: "At 5h/day, that's ~76 days a year on your
// phone." Then: "Earning even 2h back = 30 days a year." Animated counter.' This is the emotional
// pivot of the flow — the first screen that turns the user's own Q3 answer (`dailyPhoneTimeHours`)
// into a stake big enough to justify everything that follows (spec §8 rule 10, "loss aversion,
// ethically": show what's at stake before a lock, never as a threat after a miss).
//
// `flowState.estimatedDaysPerYearOnPhone` (`OnboardingFlowState.swift`, sibling-owned, read but
// never edited) already computes the exact `dailyPhoneTimeHours * 365 / 24` arithmetic spec §7.9
// asks for — that file's own doc comment says it exists precisely "so onboarding-2 doesn't have to
// re-derive the same arithmetic," so this screen uses it directly instead of recomputing it.
//
// ============================================================================================
// ASSUMED API — `Copy.onboarding.*` (Core/Sources/Core/Copy, not this session's file to create —
// see `OnboardingContainerView.swift`'s header for the full rationale, matching the
// `Copy.lockSetup`/`LockSetManager` precedent `LockSetupView.swift` set, and the parallel
// `Copy.onboarding.q1Title`-style precedent the sibling screens-1-8 session set in its own
// `Screen3MainGoal.swift`). Full key list needed by this session's six screen files, gathered here
// once instead of split six ways:
//
//   Screen 9  — wakeUpEyebrow, wakeUpHeadline(dailyHours:daysPerYear:), daysPerYearUnitLabel,
//               wakeUpReclaimLine(daysReclaimed:), wakeUpContinueButton
//   Screen 10 — planRevealEyebrow, planRevealHeadline, planBuiltInLabel,
//               planLockedAppsStatusLine(appCount:categoryCount:webDomainCount:),
//               planLockedAppsDetailLine, planGoalTitle(for: GoalType) [Core type, not the
//               App-only MainGoal — see Screen10PlanReveal.swift's header for why],
//               planGoalStartingDetail(current:target:unit:), planScheduleLine,
//               planScheduleFallOffNote(patternLabel: String) [a pre-resolved
//               FallOffPattern.displayLabel, same Core/App boundary reason], planContinueButton,
//               lockSetName [shared with Screen 14]
//   Screen 11 — commitEyebrow, commitHeadline, commitSubtitle, commitHoldButtonLabel,
//               commitHoldHint, commitRecapLine(goalCount:appCount:)
//   Screen 12 — permissionEyebrow, permissionHeadline, permissionSubtitle, permissionAllowButton,
//               permissionSkipButton
//   Screen 13 — see `Screen13Paywall.swift`'s own header: **superseded** by
//               `PaywallView.swift`/`Copy.paywall.*` (a different task this same batch); this
//               session's own Copy keys for screen 13 are listed there but unused by the wired
//               flow (`OnboardingContainerView.swift` routes screen 13 to `PaywallView`).
//   Screen 14 — firstWinEyebrow, firstWinHeadline, firstWinSubtitle, firstWinStartButton,
//               firstWinGoalTitle, firstWinRunningHeadline, firstWinRunningDetail,
//               firstWinEmergencyLabel, firstWinCelebrationTitle,
//               firstWinCelebrationSubtitle(streak: Int), firstWinNotVerifiedTitle,
//               firstWinNotVerifiedSubtitle, firstWinWidgetPromptHeadline,
//               firstWinWidgetPromptStep1, firstWinWidgetPromptStep2, firstWinWidgetPromptStep3,
//               firstWinDoneButton
//
// Plus container chrome (`OnboardingContainerView.swift`): backButtonAccessibilityLabel,
// progressAccessibilityLabel(screen:total:).
// ============================================================================================

import SwiftUI
import Core

/// docs/spec.md §7.9. Reads `flowState.dailyPhoneTimeHours`/`.estimatedDaysPerYearOnPhone` (Q3,
/// screen 5) and turns them into two stat lines with an animated count-up, per the spec's exact
/// worked example ("At 5h/day...").
@MainActor
struct Screen9WakeUp: View {
    @Bindable var flowState: OnboardingFlowState

    /// Spec's second line is anchored to "2h back" specifically, not a fraction of the user's own
    /// total — reclaiming 2h reads as a concrete, achievable target regardless of how many hours
    /// they start from, and never exceeds their own daily total, so someone who reported *less*
    /// than 2h/day doesn't see a reclaim number bigger than their whole day.
    private var reclaimHours: Double {
        min(flowState.dailyPhoneTimeHours, 2)
    }

    private var daysPerYearOnPhone: Int {
        Int(flowState.estimatedDaysPerYearOnPhone.rounded())
    }

    private var daysReclaimedPerYear: Int {
        Int((reclaimHours * 365 / 24).rounded())
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.lg)

            Text(Copy.onboarding.wakeUpEyebrow)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)

            Text(
                Copy.onboarding.wakeUpHeadline(
                    dailyHours: Int(flowState.dailyPhoneTimeHours.rounded()),
                    daysPerYear: daysPerYearOnPhone
                )
            )
            .font(Theme.Typography.title)
            .foregroundStyle(Theme.Colors.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.xxs) {
                OnboardingAnimatedCount(target: daysPerYearOnPhone, color: Theme.Colors.danger)
                Text(Copy.onboarding.daysPerYearUnitLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }

            Spacer(minLength: Theme.Spacing.md)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.wakeUpReclaimLine(daysReclaimed: daysReclaimedPerYear))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)

                OnboardingAnimatedCount(
                    target: daysReclaimedPerYear,
                    color: Theme.Colors.accent,
                    delay: 0.9,
                    size: .medium
                )
            }

            Spacer(minLength: Theme.Spacing.lg)

            PrimaryButton(title: Copy.onboarding.wakeUpContinueButton) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }
}

/// A big numeral that counts up from 0 to `target` once, on appear — the "animated counter" spec
/// §7.9 asks for. `internal`, not `private`, so `Screen10PlanReveal.swift` (elapsed "days a year"
/// callbacks aren't reused there, but the same visual language is) could reuse it too if a later
/// pass wants the same effect; today only this file uses it.
struct OnboardingAnimatedCount: View {
    enum Size {
        case large
        case medium

        var font: Font {
            switch self {
            case .large: Theme.Typography.numeralLarge()
            case .medium: Theme.Typography.numeralMedium()
            }
        }
    }

    let target: Int
    let color: Color
    var delay: TimeInterval = 0.2
    var size: Size = .large

    @State private var displayedValue = 0

    /// Total time the count-up animates over. Kept comfortably inside
    /// `Theme.Motion.unlockCelebrationMaxDuration` (spec §15: "unlock celebration <= 1.2s") even
    /// though this isn't an unlock celebration itself — the same "don't overstay the moment"
    /// motion budget reads right here too.
    private static let countDuration: TimeInterval = 0.9
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        Text("\(displayedValue)")
            .font(size.font)
            .foregroundStyle(color)
            .contentTransition(.numericText(countsDown: false))
            .task(id: target) {
                displayedValue = 0
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, target > 0 else {
                    displayedValue = target
                    return
                }
                let steps = max(1, Int(Self.countDuration / Self.frameInterval))
                for step in 1...steps {
                    try? await Task.sleep(for: .seconds(Self.frameInterval))
                    if Task.isCancelled { return }
                    let progress = Double(step) / Double(steps)
                    withAnimation(.linear(duration: Self.frameInterval)) {
                        displayedValue = Int((Double(target) * progress).rounded())
                    }
                }
                displayedValue = target
            }
            .accessibilityLabel("\(target)")
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen9WakeUp(flowState: flowState)
    }
}
