// Screen4AppSelection.swift
// App / Features / Onboarding
//
// docs/spec.md §7.4 (screen 4, Q2): "Which apps steal your time? - Native FamilyActivityPicker styled
// into the flow. (This is also the permission request; prime it with one sentence first.)" The
// one-sentence prime is `Copy.onboarding.q2Subtitle`, shown above the picker card.
//
// This screen deliberately does NOT reuse `App/ZANO/Features/LockSetup/AppPickerView.swift`: that view
// renders itself as a `Form` `Section` row for the LockSetup admin screen, while spec §7.4 wants this
// styled full-bleed as part of the onboarding flow with a one-sentence prime up front. Both use the
// same underlying FamilyControls APIs (`AuthorizationCenter`, `.familyActivityPicker`, `.individual`
// authorization - never `.child`, since ZANO only ever restricts the signed-in user's own device).
// The authorization logic below is unchanged from the previous revision.
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered). The picker is the
// screen's one focal object (layout audit 1.8: "the apps are the product, and only a count is shown"):
//   - Empty: a large dashed drop-zone card. Inside it, a row of three empty app-icon slots and a
//     fourth "add" slot: it previews exactly what the filled state looks like (icons in a row), so the
//     card reads as "your apps go here" before it is read. A dashed outline is the empty-slot idiom
//     (competitive-research §3.10).
//   - Filled: an overlapped row of the user's real app icons, then a check + the count summary, in a
//     `zanoCard` with a 2pt white selection edge (no glow: selection is not earned, 2026-09-24).
//     Icons are FamilyControls' own `Label(token).labelStyle(.iconOnly)`: the system renders them,
//     so the privacy rule holds (tokens are opaque; nothing here can read an app name or bundle id).
//     API verified against Apple's Developer Forums / sample code, not compiled.
//   - Icon-only on purpose: `Label(token)` titles ignore this app's forced-dark color scheme (they
//     follow the system setting) and cannot be restyled (Apple Developer Forums threads 726330 and
//     732567), so a title would render dark-on-dark for light-mode users. The count line below the
//     icons carries the text. Icons can also intermittently render as three dots (thread 723651), so
//     the icon row is additive and the summary never depends on it. Capped at 5 tiles + "+N" to keep
//     the number of live token views small (thread 727437 reports freezes with many).
//   - The card carries no *wash*: the icon tiles are cut out of each other
//     with a `surface`-colored ring, which only matches the card fill if nothing tints it.
//   - Real tokens: `hairlineStrong` dash, white add-slot, `PressableStyle` press state,
//     `chevron.forward` (mirrors in RTL), selection haptic, Reduce-Motion-gated transitions.
//
// Denied access is not a dead end (2026-09-24 audit, P0): the alert offers "Open Settings", and
// once access has been refused an inline card under the picker repeats the message with a
// "Try again" that re-runs the request and the picker. Continue stays gated on a real selection
// (screen 14's lock needs one), so this card is the way forward.
//
// Handoff idea (needs a Copy key, not editable here): one privacy line under the subtitle, e.g.
// "Your app list never leaves this phone." It is true (CLAUDE.md: tokens never leave the device) and
// it is the moment users are about to see a system permission prompt.

import SwiftUI
import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import Core

/// Screen 4 of 14 (spec §7.4) - Q2, the onboarding-embedded app picker. This is also v1's
/// FamilyControls authorization request (spec §7.4's parenthetical), primed with one sentence
/// (`Copy.onboarding.q2Subtitle`) before the system picker/permission sheet appears.
struct Screen4AppSelection: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var isPickerPresented = false
    @State private var authorizationAlert: Screen4AuthorizationAlert?
    /// Set when the last request ended without access; shows the inline "Try again" card.
    @State private var authorizationDenied = false
    /// Tracks a same-session dismiss of `AlwaysAllowedWarningView` below, so tapping its close
    /// button hides it immediately without waiting for `AlwaysAllowedCheck.hasAcknowledgedWarning`
    /// (a `UserDefaults`-backed value, not `@Observable`) to be re-read on the next render.
    @State private var alwaysAllowedWarningDismissed = false

    private let tileSize = Theme.Metrics.iconBadgeMedium
    private let maxIconTiles = 5

    private var selectedCount: Int {
        flowState.selectedApps.applicationTokens.count
            + flowState.selectedApps.categoryTokens.count
            + flowState.selectedApps.webDomainTokens.count
    }

    private var hasSelection: Bool { selectedCount > 0 }

    /// docs/spec.md §20.2's `dsadriel-pocs/screen-time-app-blocker-ios` row: "add an onboarding
    /// check for Always Allowed." This is that check's one call site - the moment the user is
    /// actually picking apps to lock is the moment the gotcha (apps in Settings > Screen Time >
    /// Always Allowed can never be shielded, no matter what ZANO configures) is most actionable.
    /// See `AlwaysAllowedCheck.swift` (Core/Sources/Core/LockEngine) for exactly what this can and
    /// can't detect.
    private var alwaysAllowedAssessment: AlwaysAllowedCheck.Assessment {
        AlwaysAllowedCheck.assessment(for: flowState.selectedApps)
    }

    private var shouldShowAlwaysAllowedWarning: Bool {
        hasSelection
            && !alwaysAllowedWarningDismissed
            && !AlwaysAllowedCheck.hasAcknowledgedWarning
            && alwaysAllowedAssessment.shouldWarn
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
    }

    /// A slot's corner: `Radius.small`, concentric with the card at a 16pt inset (20 - 16 = 4 would
    /// be exact; 12 keeps the tiles reading as app icons, which iOS draws at ~22% of their side).
    private var slotShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
    }

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q2Title, subtitle: Copy.onboarding.q2Subtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                pickerCard

                if authorizationDenied && !hasSelection {
                    deniedCard
                        .transition(.opacity)
                }

                // spec §20.2 / §27: surface the Always Allowed gotcha right where the user is
                // picking apps, not buried in a settings screen they may never visit.
                if shouldShowAlwaysAllowedWarning {
                    AlwaysAllowedWarningView(assessment: alwaysAllowedAssessment) {
                        AlwaysAllowedCheck.recordAcknowledged()
                        alwaysAllowedWarningDismissed = true
                    }
                }
            }
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel, isEnabled: hasSelection) {
            flowState.advance()
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $flowState.selectedApps)
        .alert(
            authorizationAlert?.title ?? "",
            isPresented: Binding(
                get: { authorizationAlert != nil },
                set: { isPresented in if !isPresented { authorizationAlert = nil } }
            ),
            presenting: authorizationAlert
        ) { _ in
            Button(Copy.onboarding.q2OpenSettingsButton) {
                authorizationAlert = nil
                openAppSettings()
            }
            Button(Copy.common.ok, role: .cancel) { authorizationAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "app_selection", "screen_number": 4]
            )
        }
    }

    // MARK: - Denied card

    /// Shown under the picker once access was refused: what happened, and a way to try again.
    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "hourglass")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(Copy.onboarding.q2AuthorizationErrorMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(
                title: Copy.onboarding.q2TryAgainButton,
                systemImage: "arrow.clockwise",
                style: .secondary
            ) {
                Task { await requestAuthorizationThenPresentPicker() }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - Picker card

    private var pickerCard: some View {
        Button {
            Task { await requestAuthorizationThenPresentPicker() }
        } label: {
            cardContent
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: hasSelection)
        .sensoryFeedback(.selection, trigger: selectedCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasSelection ? selectionSummary : Copy.onboarding.q2PickerButtonLabel)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var cardContent: some View {
        if hasSelection {
            selectedContent
        } else {
            emptyContent
        }
    }

    private var emptyContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<3, id: \.self) { _ in
                    slotShape
                        .strokeBorder(
                            Theme.Colors.hairlineStrong,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                        )
                        .frame(width: tileSize, height: tileSize)
                }
                // The one live slot: the action, on the ZANO Blue fill with a white glyph
                // (`onAccent`: near-black on blue read muddy).
                Image(systemName: "plus")
                    .font(Theme.Typography.icon(.large, weight: .bold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: tileSize, height: tileSize)
                    .background(Theme.Colors.interactive, in: slotShape)
            }
            .accessibilityHidden(true)

            Text(Copy.onboarding.q2PickerButtonLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Colors.surface.opacity(0.6), in: cardShape)
        .overlay {
            cardShape.strokeBorder(
                Theme.Colors.hairlineStrong,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
            )
        }
        .contentShape(cardShape)
    }

    private var selectedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                iconRow
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
            }

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.interactive)
                Text(selectionSummary)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Selected = the white selection edge (decision 2026-09-24). No glow: the glow is the
        // reward, and picking apps is not one.
        .zanoCard(radius: Theme.Radius.medium)
        .overlay { cardShape.strokeBorder(Theme.Colors.interactive, lineWidth: Theme.Metrics.selectedStroke) }
        .contentShape(cardShape)
    }

    // MARK: - Selected-app icons

    /// A token to preview. Web domains are counted in the summary but not drawn as tiles.
    private enum PreviewToken: Hashable, Identifiable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)

        var id: Self { self }
    }

    private var previewTokens: [PreviewToken] {
        let apps = flowState.selectedApps.applicationTokens.map(PreviewToken.app)
        let categories = flowState.selectedApps.categoryTokens.map(PreviewToken.category)
        return Array((apps + categories).prefix(maxIconTiles))
    }

    private var overflowCount: Int { max(0, selectedCount - previewTokens.count) }

    private var iconRow: some View {
        HStack(spacing: -Theme.Spacing.xs) {
            ForEach(previewTokens) { token in
                iconTile { tokenIcon(token) }
            }
            if overflowCount > 0 {
                iconTile {
                    Text("+\(overflowCount)")
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.text)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tokenIcon(_ token: PreviewToken) -> some View {
        switch token {
        case .app(let applicationToken):
            Label(applicationToken).labelStyle(.iconOnly)
        case .category(let categoryToken):
            Label(categoryToken).labelStyle(.iconOnly)
        }
    }

    /// One app-icon slot. The `surface`-colored ring cuts each tile out of its neighbour where they
    /// overlap, matching the card fill.
    private func iconTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: tileSize, height: tileSize)
            .background(Theme.Colors.surface2, in: slotShape)
            .overlay(slotShape.strokeBorder(Theme.Colors.surface, lineWidth: 2))
    }

    private var selectionSummary: String {
        Copy.onboarding.q2SelectionSummary(
            appCount: flowState.selectedApps.applicationTokens.count,
            categoryCount: flowState.selectedApps.categoryTokens.count,
            webDomainCount: flowState.selectedApps.webDomainTokens.count
        )
    }

    /// Same authorization dance as `AppPickerView.requestAuthorizationThenPresentPicker()`
    /// (`App/ZANO/Features/LockSetup/AppPickerView.swift`), duplicated per this file's header
    /// note. `.individual` (not `.child`): ZANO restricts the signed-in user's own device, it is
    /// never a parent managing a child's device.
    private func requestAuthorizationThenPresentPicker() async {
        let center = AuthorizationCenter.shared

        // Ask again after a refusal too: "Try again" must re-run the request, not just re-read a
        // stored `.denied`. (UNVERIFIED on device: whether `.individual` re-prompts after a denial
        // or throws straight away; either way the card and "Open Settings" remain.)
        if center.authorizationStatus != .approved {
            do {
                try await center.requestAuthorization(for: .individual)
            } catch {
                authorizationDenied = true
                authorizationAlert = Screen4AuthorizationAlert(
                    title: Copy.onboarding.q2AuthorizationErrorTitle,
                    message: Copy.onboarding.q2AuthorizationErrorMessage
                )
                return
            }
        }

        switch center.authorizationStatus {
        case .approved:
            authorizationDenied = false
            isPickerPresented = true
        case .denied, .notDetermined:
            authorizationDenied = true
            authorizationAlert = Screen4AuthorizationAlert(
                title: Copy.onboarding.q2AuthorizationDeniedTitle,
                message: Copy.onboarding.q2AuthorizationDeniedMessage
            )
        @unknown default:
            isPickerPresented = true
        }
    }
}

/// File-scoped alert payload - plain `Identifiable` glue for SwiftUI's `.alert(_:isPresented:
/// presenting:actions:message:)`, not a shared model.
private struct Screen4AuthorizationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    Screen4AppSelection(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
