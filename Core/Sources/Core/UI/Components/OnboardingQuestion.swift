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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingQuestion(title: "What's your main goal?", subtitle: "We'll build your plan around this.") {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<3) { index in
                Text("Option \(index + 1)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }
        }
    }
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
