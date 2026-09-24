// ShieldPreview.swift
// Core / UI / Components
//
// A stylized, in-app mockup of what a ZANO shield screen looks like — per docs/spec.md §15's core
// component list and the P2 mockup in §16 ("Full-screen iPhone block screen shown when the user
// tries to open TikTok... headline 'TikTok unlocks after your workout', subline '1 goal left ·
// Streak 14', two buttons 'Show my goals' and a small text 'Emergency'"). Used wherever the app
// wants to *show* a shield preview inline (onboarding's plan reveal, Lock Set setup, Settings'
// "preview my shield"), as distinct from the real system shield.
//
// This is deliberately NOT the real ManagedSettingsUI `ShieldConfiguration` the system renders
// when an app is actually blocked — that lives in `Extensions/ZANOShieldConfig` (a separate
// extension target, per CLAUDE.md's "Extension-only code in Extensions/<Name>/") and is built
// from `ShieldConfiguration.Configuration`/`ShieldConfiguration.Label`, which the system renders
// itself rather than exposing as an embeddable SwiftUI view. Rendering a *real* `ApplicationToken`
// here would also require importing FamilyControls/ManagedSettingsUI into Core/UI and couldn't be
// previewed in `PreviewCatalog`/SwiftUI Previews without a live, entitled selection. So this
// component takes a neutral `AppGlyph` (an SF Symbol standing in for the shielded app's icon)
// instead of a real app token — flagged as an assumption in this task's decisions.
//
// Safety (CLAUDE.md, docs/spec.md §24): "Any lock/shield feature must always keep an emergency-
// unlock path. Never trap the user." `emergencyActionTitle`/`emergencyAction` are non-optional by
// design below, so it is impossible to construct a `ShieldPreview` without one — the compiler
// enforces the safety rule, not just a convention.
//
// Design-quality pass (docs/design/{better-ui DEP-06,typography-color T10/C,composition-audit 5.6,
// competitive-research 3.3}). This is the app's most-seen surface (every blocked-app attempt), and
// it was a flat black rectangle with a 96pt grey circle and a 22pt title:
//
//   * It has a backdrop: a static navy `lockedAmbient` glow from the top (`zanoBackdrop`), the
//     same cool "locked" light the real shield and Today's locked state sit in. It used to be a red
//     `danger` glow; red now means only time spent in locked apps, not "you are locked" (a lock is
//     a choice the user made, not an error). Static — no animated blur or radius.
//   * The headline is a focal message (`titleLarge`, 28pt), and it wraps instead of truncating. A
//     subline that opens with a number ("1 goal left · Streak 14") leads with that number as a
//     numeral — the one sec finding is that the *count* is what changes behaviour, not persuasive
//     prose (competitive-research 3.3) — with the rest as a quiet unit line.
//   * The lock badge is a brushed-silver `metallic` disc (the logo's metal) with an `onFill`
//     near-black glyph (at least 7:1 across the gradient); it was a red `danger` disc. The glyph
//     disc has a lit edge instead of a bare 1.08:1 fill.
//   * The Emergency affordance is the control the "never trap the user" rule most depends on, and
//     it was the smallest, dimmest text on the screen (13pt `muted`). It is `body` in
//     `textSecondary` (still low-emphasis, per the P2 mockup's "small text"), with a full 44x44pt
//     target and a press state.

import SwiftUI

/// A visual stand-in for the shielded app's icon, since this component never has access to a real
/// `ApplicationToken` (see the file header for why).
public struct ShieldPreviewGlyph: Equatable, Sendable {
    /// SF Symbol name rendered in place of the app's real icon.
    public let systemImage: String
    /// Optional short label under the icon (e.g. an app's display name, when the caller has one
    /// to show — still caller-composed, never invented here).
    public let caption: String?

    public init(systemImage: String, caption: String? = nil) {
        self.systemImage = systemImage
        self.caption = caption
    }
}

/// An in-app preview of a ZANO shield/block screen. See the file header for the full rationale and
/// the safety guarantee `emergencyActionTitle`/`emergencyAction` provide.
public struct ShieldPreview: View {
    private let glyph: ShieldPreviewGlyph
    /// Fully-composed headline, e.g. `"TikTok unlocks after your workout"`.
    private let headline: String
    /// Fully-composed subline, e.g. `"1 goal left · Streak 14"`. Optional.
    private let subline: String?
    private let primaryActionTitle: String?
    private let primaryAction: (() -> Void)?
    /// Required — see the file header's safety note. Rendered as small, low-emphasis text per the
    /// P2 mockup ("a small text 'Emergency'"), never hidden behind another screen.
    private let emergencyActionTitle: String
    private let emergencyAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives a single-beat hero reveal on first appearance — this is the onboarding plan-reveal
    /// screen, the highest-emotion moment in the P2 mockup (spec §16), so it's worth a restrained,
    /// one-shot "materialize" rather than the fully-static render every other admin surface in
    /// this safe set correctly uses (docs/design/animation-opportunities.md row 8). Deliberately
    /// *not* a looping/repeating animation — HIG's "avoid slow looping oscillations" guidance
    /// applies here exactly as it does to `AlarmRingingView`'s pulse; this fires once and stops.
    @State private var hasAppeared = false

    /// - Parameters:
    ///   - glyph: Stand-in icon for the shielded app.
    ///   - headline: Caller-composed headline.
    ///   - subline: Caller-composed subline. Defaults to `nil`.
    ///   - primaryActionTitle: Label for the primary button (e.g. "Show my goals"). When `nil`
    ///     (with `primaryAction` also `nil`), no primary button is shown.
    ///   - primaryAction: Handler for the primary button.
    ///   - emergencyActionTitle: Label for the always-present emergency-unlock affordance.
    ///   - emergencyAction: Handler for the always-present emergency-unlock affordance. Required —
    ///     see the file header.
    public init(
        glyph: ShieldPreviewGlyph,
        headline: String,
        subline: String? = nil,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        emergencyActionTitle: String,
        emergencyAction: @escaping () -> Void
    ) {
        self.glyph = glyph
        self.headline = headline
        self.subline = subline
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.emergencyActionTitle = emergencyActionTitle
        self.emergencyAction = emergencyAction
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                iconBadge
                if let caption = glyph.caption {
                    Text(caption)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(headline)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    // Wrap, never truncate: the headline is the message.
                    .fixedSize(horizontal: false, vertical: true)

                if let subline {
                    sublineView(subline)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: reduceMotion || hasAppeared ? 0 : 8)
            .animation(reduceMotion ? reducedMotionReveal : .easeOut(duration: 0.3).delay(0.25), value: hasAppeared)

            Spacer(minLength: Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.xs) {
                if let primaryActionTitle, let primaryAction {
                    PrimaryButton(title: primaryActionTitle, action: primaryAction)
                }

                Button(action: emergencyAction) {
                    Text(emergencyActionTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .underline()
                        // The visual (intentionally low-emphasis text) stays exactly as designed;
                        // the tappable area is a full 44x44pt — this is the one button the "never
                        // trap the user" safety rule (file header) most depends on being easy to
                        // hit. See `docs/design/ui-stress-test-findings.md` §3.9.
                        .minTapTarget()
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `lockedAmbient` is itself a dark navy, so it needs a much higher peak than a bright hue.
        .zanoBackdrop(glow: Theme.Colors.lockedAmbient, intensity: 0.7)
        .onAppear { hasAppeared = true }
    }

    /// A subline that opens with a number leads with it as a numeral ("1" big, "goal left · Streak
    /// 14" quiet); any other subline is plain paragraph text.
    @ViewBuilder
    private func sublineView(_ subline: String) -> some View {
        if NumeralText.hasNumeral(subline) {
            NumeralText(subline, size: .medium)
        } else {
            Text(subline)
                .zanoText(.paragraph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Under Reduce Motion, every element below fades on the *same* short curve with no delay —
    /// one uniform 150ms cross-fade for the whole card, not a staggered sequence with scale/rise
    /// (docs/design/apple-design-review.md §6.6 / animation-opportunities row 8's reduced-motion
    /// note).
    private var reducedMotionReveal: Animation { .easeInOut(duration: 0.15) }

    private var iconBadge: some View {
        let diameter = Theme.Metrics.iconBadgeLarge
        let lockDiameter = diameter * 0.38

        return ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Theme.Colors.surface2)
                .overlay(
                    Circle().strokeBorder(Theme.Colors.edgeGradient(), lineWidth: Theme.Metrics.edgeWidth)
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Image(systemName: glyph.systemImage)
                        .font(.system(size: diameter * 0.4, weight: .medium))
                        .foregroundStyle(Theme.Colors.muted)
                )
                .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.8)
                .opacity(hasAppeared ? 1 : 0)
                .animation(reduceMotion ? reducedMotionReveal : .spring(response: 0.45, dampingFraction: 0.7), value: hasAppeared)

            Circle()
                .fill(Theme.Colors.metallic)
                .frame(width: lockDiameter, height: lockDiameter)
                .overlay(
                    // `onFill` (near-black) on the silver disc: pearl-to-silver is light, so a
                    // light glyph would vanish.
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockDiameter * 0.44, weight: .bold))
                        .foregroundStyle(Theme.Colors.onFill)
                )
                // A cut-out ring in the page colour separates the badge from the disc behind it.
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: Theme.Spacing.xxs))
                // The lock "lands" on the badge a beat after it — delayed by 150ms under normal
                // motion; under Reduce Motion this collapses to the same un-delayed cross-fade as
                // everything else, not a staggered arrival.
                .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.8)
                .opacity(hasAppeared ? 1 : 0)
                .animation(
                    reduceMotion ? reducedMotionReveal : .spring(response: 0.45, dampingFraction: 0.7).delay(0.15),
                    value: hasAppeared
                )
        }
        .accessibilityHidden(true)
    }
}

#Preview("ShieldPreview") {
    ShieldPreview(
        glyph: ShieldPreviewGlyph(systemImage: "play.tv.fill", caption: "TikTok"),
        headline: "TikTok unlocks after your workout",
        subline: "1 goal left · Streak 14",
        primaryActionTitle: ShieldCopy.Buttons.showGoals,
        primaryAction: {},
        emergencyActionTitle: ShieldCopy.Buttons.emergency,
        emergencyAction: {}
    )
    .preferredColorScheme(.dark)
}
