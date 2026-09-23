// StickyActionBar.swift
// Core / UI / Components
//
// The action that matters must never depend on scroll distance. Today's primary button was the only
// pinned CTA, on a full-width `.ultraThinMaterial` strip — the app's single `Material`, a grey slab
// on a flat black screen that also stacks a second translucent panel over iOS 26's floating glass
// tab bar. Meanwhile the paywall's purchase button and its "continue free" path, the alarm's escape
// hatch, the Lock screen's emergency unlock and onboarding's plan-reveal CTA all scrolled with their
// content, below the fold on real phones (docs/design/better-layout-findings.md §7, composition-audit
// offenders 1/5/8).
//
// One component instead: a bottom inset on the screen's own scroll view that fades the content into
// the background rather than drawing a panel, so it never competes with system chrome
// (composition-audit.md: "a LinearGradient fade rather than .ultraThinMaterial"). Deliberately not
// `safeAreaBar` (iOS 26 only, and this target is iOS 17): `safeAreaInset` works everywhere and the
// fade is the same idea.

import SwiftUI

/// The chrome behind a pinned action: `Spacing.md` gutters, room above for a fade, and a gradient
/// from clear to `Theme.Colors.background` that also extends under the home indicator.
public struct StickyActionBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Theme.Colors.background.opacity(0), location: 0),
                        Gradient.Stop(color: Theme.Colors.background.opacity(0.94), location: 0.35),
                        Gradient.Stop(color: Theme.Colors.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    /// Pins `bar` to the bottom of the screen in a `StickyActionBar`, as an inset on this view's
    /// own scroll content so the scroll view's bottom inset is adjusted automatically. Put the
    /// primary action (and, on the paywall, the trial note and the "continue free" link; on the
    /// Lock screen, the emergency unlock) in `bar`.
    ///
    ///     ScrollView { … }
    ///         .zanoActionBar {
    ///             PrimaryButton(title: Copy.today.startFocusTitle, action: start)
    ///         }
    public func zanoActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let built = StickyActionBar(content: { bar() })
        return safeAreaInset(edge: .bottom, spacing: 0) { built }
    }
}

#Preview("StickyActionBar") {
    ScrollView {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(0..<12) { index in
                Text("Row \(index + 1)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .zanoCard()
            }
        }
        .padding(Theme.Spacing.md)
    }
    .background(Theme.Colors.background)
    .zanoActionBar {
        PrimaryButton(title: "Start focus", systemImage: "timer", action: {})
    }
    .preferredColorScheme(.dark)
}
