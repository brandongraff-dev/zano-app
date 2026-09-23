// AlwaysAllowedWarningView.swift
// App / Features / LockSetup
//
// Owned by: this task (docs/spec.md §20.2 `dsadriel-pocs/screen-time-app-blocker-ios` row, §27).
//
// Renders `AlwaysAllowedCheck.Assessment` (Core/Sources/Core/LockEngine/AlwaysAllowedCheck.swift)
// as a small, reusable warning banner. See that file's header for exactly what is/isn't possible to
// detect automatically — short version: nothing. Apple gives no API to read Settings > Screen Time >
// Always Allowed, so this is an honest "go check yourself" nudge, not a real conflict detector, and
// this view never pretends otherwise. `LockSetEditorSheet` (LockSetupView.swift) shows it directly
// under the app picker whenever the picked apps could be exempted by that list.
//
// Style follows `GhostProgressBanner` (Core/UI/Components) — the closest precedent for a
// Theme-consistent, self-contained, drop-in banner that takes one already-computed value and an
// optional action/dismiss closure. It lives in App/ZANO (not Core/UI) because it is specific to the
// Screen Time / lock picking flow (imports `FamilyControls`), like `AppPickerView.swift`.
//
// `import UIKit` below is solely for `UIApplication.openSettingsURLString` (see
// `openSettingsButton`'s doc comment) — CLAUDE.md: "No UIKit unless an API requires it." SwiftUI
// has no equivalent constant; this is the one Apple-documented way to deep-link out to Settings.
//
// Visual pass (design wave 2026-09-23; docs/design/better-layout-findings.md row 1.9,
// better-ui-findings.md HIT-01/ICO-11): this message says a lock may silently not apply, yet its
// title was 13pt, its body 13pt muted, its only action a 13pt borderless text link, and its dismiss
// control an 11pt glyph with no hit padding (the smallest target in the app). Type now matches the
// severity (`headline` title, `textSecondary` paragraph), "Open Settings" is a real capsule button,
// and both controls reach 44pt without moving their visuals. The card is the shared `zanoCard` with a
// warning wash and a warning-hued edge, so it reads as an object with a severity, and the glyph is an
// `IconBadge` (the one badge recipe) instead of a hand-built disc.

import SwiftUI
import UIKit
import FamilyControls
import Core

/// A small, reusable warning banner explaining the "Always Allowed" gotcha (apps in Settings >
/// Screen Time > Always Allowed can never be shielded, no matter what ZANO configures) so a lock
/// setup / onboarding screen can drop it in next to a `FamilyActivityPicker`-driven selection.
///
/// Deliberately "dumb" about *when* to show itself — like `GhostProgressBanner`, the caller
/// decides (typically via `AlwaysAllowedCheck.shouldWarn(for:)`) whether to include this view in
/// its layout at all; this view only renders once asked to, and degrades to a generic-but-true
/// sentence (`Copy.alwaysAllowed.bannerMessageGeneral`) if shown for an assessment that shouldn't
/// have triggered it in the first place, rather than showing something specific but wrong.
///
/// This view also never reads or writes `AlwaysAllowedCheck.hasAcknowledgedWarning` itself — a
/// caller that wants "show once" behavior checks that flag before deciding whether to include this
/// view at all, and calls `AlwaysAllowedCheck.recordAcknowledged()` from `onDismiss` if it wants
/// the close button to count as acknowledging it. Keeping both of those decisions in the caller,
/// not this view, is what makes this genuinely reusable across onboarding's app-selection screen
/// and the LockSetup admin screen without this file needing to know which context it's in.
struct AlwaysAllowedWarningView: View {
    private let assessment: AlwaysAllowedCheck.Assessment
    /// Optional close/dismiss handler. `nil` (the default) renders no close button — a screen that
    /// wants "show once" behavior passes one that calls `AlwaysAllowedCheck.recordAcknowledged()`
    /// and removes this view from its layout.
    private let onDismiss: (() -> Void)?

    @Environment(\.openURL) private var openURL

    /// - Parameters:
    ///   - assessment: What to render, typically `AlwaysAllowedCheck.assessment(for: selection)`.
    ///     Callers that already computed one for some other reason (e.g. to also drive whether to
    ///     show this view at all) pass it straight through instead of recomputing it.
    ///   - onDismiss: Optional close-button handler. See the type doc comment.
    init(assessment: AlwaysAllowedCheck.Assessment, onDismiss: (() -> Void)? = nil) {
        self.assessment = assessment
        self.onDismiss = onDismiss
    }

    /// Convenience for a caller that has the raw `FamilyActivitySelection` and hasn't already
    /// computed an `Assessment` for some other reason. Equivalent to
    /// `AlwaysAllowedWarningView(assessment: AlwaysAllowedCheck.assessment(for: selection),
    /// onDismiss: onDismiss)`.
    init(selection: FamilyActivitySelection, onDismiss: (() -> Void)? = nil) {
        self.init(assessment: AlwaysAllowedCheck.assessment(for: selection), onDismiss: onDismiss)
    }

    var body: some View {
        // Only the non-interactive title + message collapse into one VoiceOver element; the "Open
        // Settings" and dismiss buttons stay individually reachable (collapsing the whole row under
        // `.accessibilityElement(children: .ignore)` used to make both unreachable for a
        // VoiceOver user, docs/design/ui-stress-test-findings.md §1.3).
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // A lock-with-warning glyph: this is specifically "your lock may not hold", which the
            // generic exclamation triangle did not say. SF Symbol name recalled from the catalog,
            // not confirmed on a Mac; a wrong name renders blank, never crashes.
            IconBadge(
                systemName: "lock.trianglebadge.exclamationmark.fill",
                tint: Theme.Colors.warning,
                size: .medium
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.alwaysAllowed.bannerTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)

                    // A five-line paragraph on a dark surface: the middle text tier and the
                    // paragraph leading (docs/design/typography-color-findings.md T5, C15).
                    Text(bannerMessage)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                openSettingsButton
            }

            Spacer(minLength: 0)

            if let onDismiss {
                dismissButton(action: onDismiss)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard(radius: Theme.Radius.medium, tint: Theme.Colors.warning)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.warning.opacity(0.4), lineWidth: Theme.Metrics.edgeWidth)
                .allowsHitTesting(false)
        }
    }

    /// Picks the specific-but-true variant when possible, falling back to the generic-but-true one
    /// otherwise — see the type doc comment on why this never shows a specific claim that doesn't
    /// match what `assessment` actually found.
    private var bannerMessage: String {
        if assessment.appCount > 0 {
            Copy.alwaysAllowed.bannerMessageAppsPicked
        } else if assessment.categoryCount > 0 {
            Copy.alwaysAllowed.bannerMessageCategoriesOnly
        } else {
            Copy.alwaysAllowed.bannerMessageGeneral
        }
    }

    /// Opens this app's own Settings page via `UIApplication.openSettingsURLString` — the only
    /// deep link Apple documents for jumping out to Settings from a third-party app. There is no
    /// public URL scheme into Settings > Screen Time > Always Allowed specifically (consistent
    /// with `AlwaysAllowedCheck.swift`'s header: Apple gives third-party apps no programmatic
    /// access to that screen at all, not even a one-way deep link), so the user still navigates
    /// Settings > Screen Time > Always Allowed by hand from here — this button only saves the
    /// first hop. `openSettingsURLString`'s exact current behavior (which page it lands on) isn't
    /// confirmed against a device in this environment (no Mac — CLAUDE.md rule 5).
    @ViewBuilder
    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            // A tinted capsule (~32pt visual) inside a 44pt frame: the fix for the previously
            // borderless 13pt text link is a visible edge plus a full-size target.
            Text(Copy.alwaysAllowed.openSettingsButtonLabel)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.warning)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.wash(Theme.Colors.warning), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.Colors.warning.opacity(0.35), lineWidth: Theme.Metrics.edgeWidth)
                }
                .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.96))
    }

    /// The glyph stays small and stays in the corner; only the tappable frame grows to 44pt. The
    /// negative padding hands the extra area back to the card's own padding so the visual position
    /// (and the text column's width) barely moves.
    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Theme.Typography.icon(.xsmall, weight: .bold))
                .foregroundStyle(Theme.Colors.muted)
                .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.9))
        .padding(.top, -Theme.Spacing.sm)
        .padding(.trailing, -Theme.Spacing.sm)
        .accessibilityLabel(Copy.alwaysAllowed.dismissAccessibilityLabel)
    }
}

#Preview("Apps picked") {
    AlwaysAllowedWarningView(
        assessment: AlwaysAllowedCheck.Assessment(appCount: 3, categoryCount: 1, webDomainCount: 0),
        onDismiss: {}
    )
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("Categories only") {
    AlwaysAllowedWarningView(
        assessment: AlwaysAllowedCheck.Assessment(appCount: 0, categoryCount: 2, webDomainCount: 0)
    )
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
