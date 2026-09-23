// ExperimentFlagsTests.swift
// CoreTests
//
// `Core/Package.swift` does not depend on PostHog yet (see `Analytics.swift`'s own header: "The
// PostHog SPM package is not yet added to project.yml"), so `#if canImport(PostHog)` is false for
// every build of this test target today — `Analytics.shared.featureFlagVariant(key:)` is
// therefore always `nil` here, and every `ExperimentFlag.resolve()` call below is guaranteed to
// fall through to its `defaultVariant`. That makes this the right place to pin down each
// experiment's default with a real, deterministic test instead of a comment asserting what the
// default "should" be — once PostHog is linked (Session 1, per `docs/dependencies.md`) these still
// pass unchanged, since linking the SDK doesn't change what an *unconfigured* flag resolves to.

import Testing
@testable import Core

@Suite("ExperimentFlags")
struct ExperimentFlagsTests {

    // MARK: - Defaults (PostHog unlinked in this test target → always falls through)

    @Test func paywallPlacementDefaultsToAfterPlan() {
        #expect(ExperimentFlags.paywallPlacement.resolve() == .afterPlan)
    }

    @Test func trialLengthDefaultsToSevenDays() {
        #expect(ExperimentFlags.trialLength.resolve() == .sevenDay)
        #expect(ExperimentFlags.trialLength.resolve().days == 7)
    }

    @Test func startingDifficultyDefaultsToSeventyPercent() {
        #expect(ExperimentFlags.startingDifficulty.resolve() == .seventyPct)
        #expect(ExperimentFlags.startingDifficulty.resolve().fractionOfTarget == 0.70)
    }

    @Test func shieldCopyVoiceDefaultsToHype() {
        #expect(ExperimentFlags.shieldCopyVoice.resolve() == .hype)
        #expect(ExperimentFlags.shieldCopyVoice.resolve().coachVoice == .hype)
    }

    @Test func widgetPromptTimingDefaultsToAfterFirstUnlock() {
        #expect(ExperimentFlags.widgetPromptTiming.resolve() == .afterFirstUnlock)
    }

    @Test func earnModeDefaultsToOff() {
        #expect(ExperimentFlags.earnModeDefault.resolve() == .off)
        #expect(ExperimentFlags.earnModeDefault.resolve().isEnabledByDefault == false)
    }

    @Test func onboardingLengthDefaultsToFourteenScreens() {
        #expect(ExperimentFlags.onboardingLength.resolve() == .fourteen)
        #expect(ExperimentFlags.onboardingLength.resolve().screenCount == 14)
    }

    @Test func freezeCountDefaultsToOne() {
        #expect(ExperimentFlags.freezeCount.resolve() == .one)
        #expect(ExperimentFlags.freezeCount.resolve().freezesPerWeek == 1)
    }

    @Test func nudgeCapDefaultsToOne() {
        #expect(ExperimentFlags.nudgeCap.resolve() == .one)
        #expect(ExperimentFlags.nudgeCap.resolve().maxPerDay == 1)
    }

    @Test func planBOfferThresholdDefaultsToModerate() {
        #expect(ExperimentFlags.planBOfferThreshold.resolve() == .moderate)
        #expect(ExperimentFlags.planBOfferThreshold.resolve().riskThreshold == 0.5)
    }

    // MARK: - Keys are unique and snake_case (PostHog dashboard convention)

    @Test func everyExperimentKeyIsUnique() {
        let keys = [
            ExperimentFlags.paywallPlacement.key,
            ExperimentFlags.trialLength.key,
            ExperimentFlags.startingDifficulty.key,
            ExperimentFlags.shieldCopyVoice.key,
            ExperimentFlags.widgetPromptTiming.key,
            ExperimentFlags.earnModeDefault.key,
            ExperimentFlags.onboardingLength.key,
            ExperimentFlags.freezeCount.key,
            ExperimentFlags.nudgeCap.key,
            ExperimentFlags.planBOfferThreshold.key,
        ]
        #expect(keys.count == Set(keys).count)
        #expect(keys.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") })
    }

    // MARK: - currentAssignments()

    @Test func currentAssignmentsCoversAllTenKeyedByFlagKey() {
        let assignments = ExperimentFlags.currentAssignments()
        #expect(assignments.count == 10)
        #expect(assignments[ExperimentFlags.paywallPlacement.key] == "after_plan")
        #expect(assignments[ExperimentFlags.trialLength.key] == "7_day")
        #expect(assignments[ExperimentFlags.startingDifficulty.key] == "70_pct")
        #expect(assignments[ExperimentFlags.shieldCopyVoice.key] == "hype")
        #expect(assignments[ExperimentFlags.widgetPromptTiming.key] == "after_first_unlock")
        #expect(assignments[ExperimentFlags.earnModeDefault.key] == "off")
        #expect(assignments[ExperimentFlags.onboardingLength.key] == "14_screens")
        #expect(assignments[ExperimentFlags.freezeCount.key] == "one")
        #expect(assignments[ExperimentFlags.nudgeCap.key] == "one")
        #expect(assignments[ExperimentFlags.planBOfferThreshold.key] == "moderate")
    }

    // MARK: - Non-default variants still compute the right concrete values

    @Test func trialLengthThreeDayVariant() {
        #expect(TrialLengthExperiment.Variant.threeDay.days == 3)
    }

    @Test func startingDifficultyEightyFivePctVariant() {
        #expect(StartingDifficultyExperiment.Variant.eightyFivePct.fractionOfTarget == 0.85)
    }

    @Test func shieldCopyVoiceMapsEveryVariantToItsCoachVoiceLosslessly() {
        #expect(ShieldCopyVoiceExperiment.Variant.hype.coachVoice == .hype)
        #expect(ShieldCopyVoiceExperiment.Variant.toughLove.coachVoice == .toughLove)
        #expect(ShieldCopyVoiceExperiment.Variant.chill.coachVoice == .chill)
        #expect(ShieldCopyVoiceExperiment.Variant.data.coachVoice == .data)
        // Raw values must match `CoachVoice.rawValue` exactly (Core/Sources/Core/Models/User.swift)
        // since PostHog is configured with these literal strings.
        for variant in ShieldCopyVoiceExperiment.Variant.allCases {
            #expect(variant.rawValue == variant.coachVoice.rawValue)
        }
    }

    @Test func earnModeOnVariant() {
        #expect(EarnModeDefaultExperiment.Variant.on.isEnabledByDefault)
    }

    @Test func onboardingLengthTenScreensVariant() {
        #expect(OnboardingLengthExperiment.Variant.ten.screenCount == 10)
    }

    @Test func freezeCountTwoVariant() {
        #expect(FreezeCountExperiment.Variant.two.freezesPerWeek == 2)
    }

    @Test func nudgeCapTwoVariant() {
        #expect(NudgeCapExperiment.Variant.two.maxPerDay == 2)
    }

    @Test func planBOfferThresholdHighVariant() {
        #expect(PlanBOfferThresholdExperiment.Variant.high.riskThreshold == 0.7)
    }

    // MARK: - Analytics feature-flag primitives (PostHog unlinked → documented no-ops)

    @Test func analyticsFeatureFlagPrimitivesAreSafeNoOpsWithoutPostHog() {
        #expect(Analytics.shared.featureFlag(key: "any_key") == nil)
        #expect(Analytics.shared.featureFlagVariant(key: "any_key") == nil)
        #expect(Analytics.shared.isFeatureEnabled(key: "any_key") == false)
        // Must not crash/throw even though no PostHog SDK is linked and `setup` was never called.
        Analytics.shared.reloadFeatureFlags()
    }
}
