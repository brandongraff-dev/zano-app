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
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)

                if let subline {
                    Text(subline)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer(minLength: Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.md) {
                if let primaryActionTitle, let primaryAction {
                    PrimaryButton(title: primaryActionTitle, action: primaryAction)
                }

                Button(action: emergencyAction) {
                    Text(emergencyActionTitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    private var iconBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Theme.Colors.surface2)
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: glyph.systemImage)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Theme.Colors.muted)
                )

            Circle()
                .fill(Theme.Colors.danger)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Colors.text)
                )
                .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 3))
        }
    }
}
