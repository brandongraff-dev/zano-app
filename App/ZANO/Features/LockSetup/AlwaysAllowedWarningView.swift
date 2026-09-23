// AlwaysAllowedWarningView.swift
// App / Features / LockSetup
//
// Owned by: this task (docs/spec.md §20.2 `dsadriel-pocs/screen-time-app-blocker-ios` row, §27).
// New, standalone file — does NOT edit `LockSetupView.swift` / `AppPickerView.swift` in this same
// directory. Those two are owned by a different, already-in-flight session (see each file's own
// "Owned by" header: "Do not edit from another session"); this view has no compile-time
// dependency on either of them and is not wired into them from here. Dropping it into
// `LockSetEditorSheet`'s `Form` in `LockSetupView.swift`, or into the onboarding Q2 app-selection
// screen, is a follow-up integration step outside this task's file list — flagged in
// knownIssues, not done here.
//
// Renders `AlwaysAllowedCheck.Assessment` (Core/Sources/Core/LockEngine/AlwaysAllowedCheck.swift,
// this same task's other owned file) as a small, reusable warning banner. See that file's header
// for exactly what is/isn't possible to detect automatically — short version: nothing. Apple gives
// no API to read Settings > Screen Time > Always Allowed, so this is an honest "go check
// yourself" nudge, not a real conflict detector, and this view never pretends otherwise.
//
// Style follows `GhostProgressBanner` (Core/Sources/Core/UI/Components/GhostProgressBanner.swift)
// — the closest existing precedent for a Theme-consistent, self-contained, drop-in banner that
// takes one already-computed value and an optional action/dismiss closure. This view lives in
// App/ZANO (not Core/Sources/Core/UI/Components) because it's specific to the Screen Time / lock
// picking flow (imports `FamilyControls`), not a generic reusable component another non-lock
// module would need — `AppPickerView.swift` (this same directory, not edited here) is the
// existing precedent for a FamilyControls-importing view living at this App/ZANO layer rather
// than in Core/UI.
//
// `import UIKit` below is solely for `UIApplication.openSettingsURLString` (see
// `openSettingsButton`'s doc comment) — CLAUDE.md: "No UIKit unless an API requires it." SwiftUI
// has no equivalent constant; this is the one Apple-documented way to deep-link out to Settings.

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
        // Previously this whole `HStack` — including `openSettingsButton` and the optional
        // `dismissButton`, both real, independently-actionable buttons — was collapsed under a
        // single `.accessibilityElement(children: .ignore)` + one label, which removes children
        // from the accessibility tree entirely: a VoiceOver user could not reach or activate
        // either button, only hear one static announcement. The fix scopes the "collapse to one
        // label" treatment (still appropriate for `GhostProgressBanner`'s single-action precedent
        // this file's header cites, which has only ever one possible action) to just the
        // non-interactive title+message text below, leaving both buttons exposed normally — each
        // already carries its own visible/explicit label. See
        // `docs/design/ui-stress-test-findings.md` §1.3.
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            iconBadge
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.alwaysAllowed.bannerTitle)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)

                    Text(bannerMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
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
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.warning.opacity(0.4), lineWidth: 1)
        )
    }

    private var iconBadge: some View {
        ZStack {
            Circle().fill(Theme.Colors.warning.opacity(0.16))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
        }
        .frame(width: 32, height: 32)
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
    /// confirmed against a device in this environment (no Mac — CLAUDE.md rule 5); flagged in
    /// knownIssues.
    @ViewBuilder
    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Text(Copy.alwaysAllowed.openSettingsButtonLabel)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.warning)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.muted)
        }
        .buttonStyle(.plain)
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
}

#Preview("Categories only") {
    AlwaysAllowedWarningView(
        assessment: AlwaysAllowedCheck.Assessment(appCount: 0, categoryCount: 2, webDomainCount: 0)
    )
    .padding()
    .background(Theme.Colors.background)
}
