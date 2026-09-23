// OnboardingQuestion.swift
// Core / UI / Components
//
// The onboarding question shell from docs/spec.md §15's core component list ("Core components
// (build first, in Core/UI): ... OnboardingQuestion, PaywallCard"). Spec §15 names this component
// but defines no mockup/initializer for it — its shape is inferred from how every Q1-Q6 onboarding
// screen (docs/spec.md §7.3-§7.8, `App/ZANO/Features/Onboarding/Screen3MainGoal.swift` through
// `Screen8CoachVoice.swift`) already calls it: a title/subtitle header over caller-supplied
// content, scrollable so it never clips on smaller devices, with room left at the bottom for a
// pinned `PrimaryButton` via `.safeAreaInset(edge: .bottom)` (every call site chains that modifier
// directly onto this view). All text is caller-composed (from `Core/Sources/Core/Copy`), matching
// every other `Core/UI/Components` file's "no hardcoded copy" convention (see e.g. `GoalRow.swift`'s
// header note) — this file never imports `Copy` itself.
//
// Design-quality pass (docs/design/{typography-color T4,better-layout,better-interface}):
//
//   * The question is the screen. It was set in `title` (22pt bold) — the same tier as a card
//     heading — so on a screen whose entire job is one question the type had no more presence than
//     a settings row. It is `titleLarge` (28pt bold, -0.2 tracking) now, still well under the
//     `display` tier reserved for full-bleed hero screens (hook, celebration).
//   * The subtitle is paragraph copy, not a caption: 15pt in `textSecondary` (11.8:1 rather than
//     `muted`'s 6.1:1, since it is read, not scanned) with +3pt leading so a two-line subtitle does
//     not collide with the options beneath it.
//   * The title is a heading for VoiceOver, and the scroll view does not rubber-band when its content
//     already fits (a two-option question has nowhere to scroll to).

import SwiftUI

/// A single onboarding question's shell: eyebrow-free title + optional subtitle, then
/// caller-supplied content (option cards, a slider, steppers, etc.). Used by every Q1-Q6 screen in
/// the 14-screen onboarding flow (docs/spec.md §7).
public struct OnboardingQuestion<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    /// - Parameters:
    ///   - title: Caller-composed question headline (from `Copy.onboarding.*`).
    ///   - subtitle: Caller-composed supporting line. Defaults to `nil`.
    ///   - content: The question's own body (option list, slider, steppers, ...).
    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                content
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .zanoText(.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingQuestion(title: "What's your main goal?", subtitle: "We'll build your plan around this.") {
        VStack(spacing: Theme.Spacing.sm) {
            SelectableCard(title: "Get to the gym", subtitle: "Build a workout habit", icon: "dumbbell.fill", isSelected: true, action: {})
            SelectableCard(title: "Eat enough protein", icon: "fork.knife", isSelected: false, action: {})
            SelectableCard(title: "Focus without my phone", icon: "timer", isSelected: false, action: {})
        }
    }
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
