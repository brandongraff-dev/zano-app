// Screen4AppSelection.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.4 (screen 4, Q2): "Which apps steal your time? — Native
// FamilyActivityPicker styled into the flow. (This is also the permission request; prime it with
// one sentence first.)"
//
// This screen deliberately does NOT reuse `App/ZANO/Features/LockSetup/AppPickerView.swift` (a
// different session's owned file, CLAUDE.md "never touch a file owned by another agent"): that
// view renders itself as a `Form` `Section` row for the LockSetup admin screen, while spec §7.4
// wants this styled full-bleed as part of the onboarding flow with a one-sentence prime up front.
// Both use the same underlying FamilyControls APIs (`AuthorizationCenter`, `.familyActivityPicker`
// modifier, `.individual` authorization — never `.child`, since ZANO only ever restricts the
// signed-in user's own device) — duplicated intentionally rather than shared.
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note (`Copy.onboarding`/
// `Copy.common`, `OnboardingQuestion`, `PrimaryButton`). New keys beyond that file's list: none —
// all of `q2Title`, `q2Subtitle`, `q2PickerButtonLabel`, `q2SelectionSummary`,
// `q2AuthorizationErrorTitle/Message`, `q2AuthorizationDeniedTitle/Message` are already listed
// there.

import SwiftUI
import FamilyControls
import Core

/// Screen 4 of 14 (spec §7.4) — Q2, the onboarding-embedded app picker. This is also v1's
/// FamilyControls authorization request (spec §7.4's parenthetical), primed with one sentence
/// (`Copy.onboarding.q2Subtitle`) before the system picker/permission sheet appears.
struct Screen4AppSelection: View {
    @Bindable var flowState: OnboardingFlowState

    @State private var isPickerPresented = false
    @State private var authorizationAlert: Screen4AuthorizationAlert?
    /// Tracks a same-session dismiss of `AlwaysAllowedWarningView` below, so tapping its close
    /// button hides it immediately without waiting for `AlwaysAllowedCheck.hasAcknowledgedWarning`
    /// (a `UserDefaults`-backed value, not `@Observable`) to be re-read on the next render.
    @State private var alwaysAllowedWarningDismissed = false

    private var hasSelection: Bool {
        !flowState.selectedApps.applicationTokens.isEmpty
            || !flowState.selectedApps.categoryTokens.isEmpty
            || !flowState.selectedApps.webDomainTokens.isEmpty
    }

    /// docs/spec.md §20.2's `dsadriel-pocs/screen-time-app-blocker-ios` row: "add an onboarding
    /// check for Always Allowed." This is that check's one call site — the moment the user is
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

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q2Title, subtitle: Copy.onboarding.q2Subtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Button {
                    Task { await requestAuthorizationThenPresentPicker() }
                } label: {
                    HStack {
                        Image(systemName: "apps.iphone")
                            .foregroundStyle(Theme.Colors.accent)
                        Text(hasSelection ? selectionSummary : Copy.onboarding.q2PickerButtonLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .strokeBorder(
                                hasSelection ? Theme.Colors.accent : Theme.Colors.hairline,
                                lineWidth: hasSelection ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)

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
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.continueButtonLabel, isEnabled: hasSelection) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
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

        if center.authorizationStatus == .notDetermined {
            do {
                try await center.requestAuthorization(for: .individual)
            } catch {
                authorizationAlert = Screen4AuthorizationAlert(
                    title: Copy.onboarding.q2AuthorizationErrorTitle,
                    message: Copy.onboarding.q2AuthorizationErrorMessage
                )
                return
            }
        }

        switch center.authorizationStatus {
        case .approved:
            isPickerPresented = true
        case .denied, .notDetermined:
            authorizationAlert = Screen4AuthorizationAlert(
                title: Copy.onboarding.q2AuthorizationDeniedTitle,
                message: Copy.onboarding.q2AuthorizationDeniedMessage
            )
        @unknown default:
            isPickerPresented = true
        }
    }
}

/// File-scoped alert payload — plain `Identifiable` glue for SwiftUI's `.alert(_:isPresented:
/// presenting:actions:message:)`, not a shared model.
private struct Screen4AuthorizationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    Screen4AppSelection(flowState: OnboardingFlowState())
}
