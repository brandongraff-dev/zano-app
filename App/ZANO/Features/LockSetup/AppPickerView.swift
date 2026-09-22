// AppPickerView.swift
// App / Features / LockSetup
//
// Owned by: Session "LockSetup" (this file's task). Do not edit from another session — see
// CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §4 (v1 — Launch): "App picker (FamilyActivityPicker) with saved 'lock sets'
// (e.g., Social, Games, All)." §11 Architecture lists `FamilyControls, ManagedSettings,
// DeviceActivity` as the only frameworks that ever see real app identity, and both §11's data
// flow note and `Core/Sources/Core/Models/LockSet.swift`'s header comment are explicit that the
// resulting tokens "never leave the device." This view respects that boundary structurally: it
// only ever hands a `FamilyActivitySelection` value back to its caller through a `Binding` — it
// never encodes, persists, logs, or inspects the tokens inside it. Persisting a selection onto a
// named `LockSet` (encoding it into `LockSet.appTokensBlob`) is `LockSetManager`'s job, not this
// view's (see the assumed-API note on `LockSetManager` in `LockSetupView.swift`, this session's
// other owned file).

import SwiftUI
import FamilyControls
import Core

/// Reusable control for choosing which apps / activity categories / web domains belong to a
/// `LockSet`. Wraps FamilyControls' system `FamilyActivityPicker` behind a single summary row:
/// tapping it requests Screen Time authorization if needed (docs/spec.md §24: "Family Controls
/// entitlement... apply to Apple on day one"; until that's approved, the **Family Controls
/// (Development)** capability covers real-device testing per CLAUDE.md's environment-status
/// block), then presents the system picker sheet via SwiftUI's `.familyActivityPicker(
/// isPresented:selection:)` modifier — the same picker Apple's own Screen Time / parental
/// controls UI uses, so this app never builds its own app-icon/name lookup (Apple's usage terms
/// don't allow reading the human-readable identity behind a token off-picker anyway).
///
/// Used embedded inside a `Form`/`List` (see `LockSetEditorSheet` in `LockSetupView.swift`) —
/// its `body` is a `Section`, which SwiftUI supports composing into a parent `List`/`Form` from a
/// separate view type without losing section styling.
///
/// Visual treatment is intentionally plain SwiftUI defaults. Session 5 (docs/spec.md §15, §17
/// row 5) owns final visual polish across every screen; this session only owns picker behavior.
struct AppPickerView: View {
    /// The selection being built or edited. Owned by the caller so this view stays ignorant of
    /// persistence — the caller is typically about to hand this straight to `LockSetManager`.
    @Binding var selection: FamilyActivitySelection

    @State private var isPickerPresented = false
    @State private var authorizationAlert: AuthorizationAlert?

    var body: some View {
        Section {
            Button {
                Task { await requestAuthorizationThenPresentPicker() }
            } label: {
                LabeledContent {
                    Text(selectionSummaryText)
                        .foregroundStyle(.secondary)
                } label: {
                    Text(Copy.lockSetup.selectAppsButtonLabel)
                }
            }
        } footer: {
            Text(Copy.lockSetup.appPickerFooter)
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .alert(
            authorizationAlert?.title ?? "",
            isPresented: Binding(
                get: { authorizationAlert != nil },
                set: { isPresented in
                    if !isPresented { authorizationAlert = nil }
                }
            ),
            presenting: authorizationAlert
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { authorizationAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var selectionSummaryText: String {
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        let webDomainCount = selection.webDomainTokens.count
        guard appCount + categoryCount + webDomainCount > 0 else {
            return Copy.lockSetup.noAppsSelected
        }
        return Copy.lockSetup.selectionSummary(
            appCount: appCount,
            categoryCount: categoryCount,
            webDomainCount: webDomainCount
        )
    }

    /// FamilyControls authorization gates everything the picker can show: with no authorization
    /// (or a denied one) `FamilyActivityPicker` still opens but silently shows nothing selectable,
    /// which reads as a bug rather than a permissions problem — so this checks/requests first and
    /// only presents the system sheet once `.approved`, showing our own alert otherwise.
    ///
    /// `.individual` (not `.child`) is the correct `FamilyControlsMember` here: ZANO restricts the
    /// signed-in user's own device, it is never a parent managing a child's device.
    private func requestAuthorizationThenPresentPicker() async {
        let center = AuthorizationCenter.shared

        if center.authorizationStatus == .notDetermined {
            do {
                try await center.requestAuthorization(for: .individual)
            } catch {
                authorizationAlert = AuthorizationAlert(
                    title: Copy.lockSetup.authorizationErrorTitle,
                    message: Copy.lockSetup.authorizationErrorMessage
                )
                return
            }
        }

        switch center.authorizationStatus {
        case .approved:
            isPickerPresented = true
        case .denied, .notDetermined:
            authorizationAlert = AuthorizationAlert(
                title: Copy.lockSetup.authorizationDeniedTitle,
                message: Copy.lockSetup.authorizationDeniedMessage
            )
        @unknown default:
            isPickerPresented = true
        }
    }
}

/// File-scoped alert payload — plain `Identifiable` glue for SwiftUI's `.alert(_:isPresented:
/// presenting:actions:message:)`, not a shared model.
private struct AuthorizationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    AppPickerPreviewContainer()
}

private struct AppPickerPreviewContainer: View {
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        Form {
            AppPickerView(selection: $selection)
        }
    }
}
