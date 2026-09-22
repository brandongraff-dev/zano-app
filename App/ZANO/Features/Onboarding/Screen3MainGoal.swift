// Screen3MainGoal.swift
// App / Features / Onboarding
//
// Owned by this session (Onboarding screens 1-8; see OnboardingFlowState.swift's header for the
// full 14-screen map and this file list's ownership rules). docs/spec.md §7.3 (screen 3, Q1):
// "Main goal — Get consistent at the gym / Hit my protein / Stop doomscrolling / Lock in on
// work-school / All of it." Option labels below are spec-verbatim (`MainGoal.displayLabel`,
// `OnboardingFlowState.swift`, this session).
//
// ASSUMED API — this session's owned files do not include Core/Sources/Core/Copy or
// Core/Sources/Core/UI's component catalog (spec §15 names both as build targets for other
// sessions), so — following the same cross-session pattern already merged into this repo
// (`App/ZANO/Features/LockSetup/LockSetupView.swift`'s `Copy.lockSetup`/`LockSetManager`
// assumptions) — every screen in this session calls two things that don't exist on disk yet.
// This file carries the full note; every other screen in this session points back here.
//
// 1. `Copy.onboarding.*` / `Copy.common.continueButtonLabel` / `Copy.common.ok` — plain string
//    (or small formatting-function) members on the `Copy` namespace (`Core/Sources/Core/Copy`).
//    Full key list used across this session's 8 screens, for whoever builds that file next:
//      common: continueButtonLabel, ok
//      onboarding: hookHeadline, hookCTA, socialProofQuotes ([String], 3 placeholder testimonial
//        quotes per spec §7.2 — "marked clearly" as placeholder until real ones exist), q1Title,
//        q1Subtitle, q2Title, q2Subtitle, q2PickerButtonLabel, q2SelectionSummary(appCount:
//        categoryCount:webDomainCount:) -> String, q2AuthorizationErrorTitle,
//        q2AuthorizationErrorMessage, q2AuthorizationDeniedTitle, q2AuthorizationDeniedMessage,
//        q3Title, q3Subtitle, q3HoursValue(_ hours: Double) -> String, q3SliderMinLabel,
//        q3SliderMaxLabel, q4Title, q4Subtitle, q4CurrentLabel, q4TargetLabel,
//        q4WorkoutsPerWeekValue(_ count: Int) -> String, q5Title, q5Subtitle, q6Title, q6Subtitle.
//    `hookHeadline`/`hookCTA` are spec-verbatim (§7.1); every other key is this session's authored
//    copy (spec only gives each question's *subject*, e.g. "Q3: Daily phone time", not its
//    on-screen wording) — free to revise once a copy owner exists; nothing in these screens
//    depends on the exact wording, only that the keys exist and return non-empty strings.
//
// 2. Two Core/UI components (spec §15's component list): `OnboardingQuestion` and `PrimaryButton`.
//    Neither has a defined initializer in spec §15 (just named in the "build first" list), so this
//    session assumed the simplest shape that fits every screen that uses it:
//      struct OnboardingQuestion<Content: View>: View {
//          init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content)
//      }
//      struct PrimaryButton: View {
//          init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void)
//      }
//    CORRECTION (post-hoc cross-check against the real, shipped components): `OnboardingQuestion`'s
//    assumed shape above matched what was actually built. `PrimaryButton`'s did not — the real,
//    shipped `Core/Sources/Core/UI/Components/PrimaryButton.swift` requires a **labeled**
//    `title:` parameter (`init(title: String, systemImage: String? = nil, style: Style = .standard,
//    isEnabled: Bool = true, action: @escaping () -> Void)`), not the unlabeled `_ title:` guessed
//    here. Every call site in this session's screens (1, 2, 3, 4, 5, 6, 7, 8) has been updated to
//    pass `title:` explicitly to match the real component; this note is left in place, corrected,
//    rather than deleted, so the history of the assumption is still legible.
//    (`PrimaryButton` is also documented in spec §15 as having a "hold-to-commit variant" — see
//    `Theme.Motion.holdToCommitDuration` — used by screen 11's Commitment screen, not by this
//    session; the plain tap initializer above is all screens 1-8 need.)
//
// `MainGoal`'s display-label strings are a deliberate, narrow exception to "copy lives in
// Core/Copy" — see its doc comment in OnboardingFlowState.swift for why.

import SwiftUI
import Core

/// Screen 3 of 14 (spec §7.3) — Q1, single-select main goal.
struct Screen3MainGoal: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q1Title, subtitle: Copy.onboarding.q1Subtitle) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(MainGoal.allCases, id: \.self) { goal in
                    optionRow(goal)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.continueButtonLabel, isEnabled: flowState.mainGoal != nil) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }

    private func optionRow(_ goal: MainGoal) -> some View {
        let isSelected = flowState.mainGoal == goal
        return Button {
            flowState.mainGoal = goal
        } label: {
            HStack {
                Text(goal.displayLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.surface2 : Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent : Theme.Colors.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.springStandard, value: isSelected)
    }
}

#Preview {
    Screen3MainGoal(flowState: OnboardingFlowState())
}
