// LocationPermissionPrimer.swift
// App / ZANO / Features / GymSetup
//
// spec §24 "Location: request 'When in Use' first; 'Always' only at gym setup with a clear
// explanation. Provide a manual check-in fallback." One card, four faces, picked from the live
// authorization level so it can never ask for something already granted:
//
//   * `.whenInUse` primer — shown in the Add Gym sheet before the first location ask: why (drop
//     the pin where you stand). Search and tap-to-drop work without it.
//   * `.always` primer — shown right after the first gym is saved (the "before the first auto
//     check-in" moment): why (arrival verifies without opening the app) and the privacy terms
//     (checked on the phone, no location history, manual fallback exists).
//   * "limited" — While Using granted and the one Always prompt already spent: explain, offer
//     Settings.
//   * "denied" — explain, offer Settings, point at the manual fallback.
//
// `import UIKit` is solely for `UIApplication.openSettingsURLString` (same as
// `AlwaysAllowedWarningView.swift`).

import SwiftUI
import UIKit
import Core

struct LocationPermissionPrimer: View {
    enum Kind {
        /// The While Using ask (Add Gym sheet).
        case whenInUse
        /// The Always ask (after saving a gym; Gym setup and check-in screens).
        case always
    }

    let kind: Kind
    let authorization: GymLocationAuthorization
    /// Shows a quiet "Not now" under the button when set (the post-save sheet).
    var onNotNow: (() -> Void)?

    @Environment(\.openURL) private var openURL

    private enum Face {
        case whenInUse, always, limited, denied
    }

    private var face: Face? {
        switch (kind, authorization.level) {
        case (_, .always): nil
        case (_, .denied): .denied
        case (.whenInUse, .notDetermined): .whenInUse
        case (.whenInUse, .whenInUse): nil
        case (.always, .notDetermined): .always
        case (.always, .whenInUse): authorization.hasRequestedAlways ? .limited : .always
        }
    }

    var body: some View {
        if let face {
            card(face)
        }
    }

    private func card(_ face: Face) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: glyph(face), tint: tint(face), size: .medium)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title(face))
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message(face))
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if face == .always {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    privacyPoint("iphone", Copy.gym.privacyPointOnDevice)
                    privacyPoint("scope", Copy.gym.privacyPointGymOnly)
                    privacyPoint("hand.raised", Copy.gym.privacyPointFallback)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoWell()
            }

            button(face)

            if let onNotNow, face == .always {
                Button(Copy.gym.alwaysNotNow, action: onNotNow)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(tint: face == .denied || face == .limited ? Theme.Colors.warning : nil)
    }

    @ViewBuilder
    private func button(_ face: Face) -> some View {
        switch face {
        case .whenInUse:
            PrimaryButton(title: Copy.gym.whenInUseButton, systemImage: "location.fill") {
                authorization.requestWhenInUse()
            }
        case .always:
            PrimaryButton(title: Copy.gym.alwaysButton, systemImage: "location.fill") {
                authorization.requestAlways()
            }
        case .limited, .denied:
            PrimaryButton(title: Copy.gym.openSettingsButton, systemImage: "gearshape", style: .secondary) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    private func privacyPoint(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glyph(_ face: Face) -> String {
        switch face {
        case .whenInUse: "location.fill"
        case .always: "figure.walk.arrival"
        case .limited: "location"
        case .denied: "location.slash"
        }
    }

    private func tint(_ face: Face) -> Color {
        switch face {
        case .whenInUse, .always: Theme.Colors.accent
        case .limited, .denied: Theme.Colors.warning
        }
    }

    private func title(_ face: Face) -> String {
        switch face {
        case .whenInUse: Copy.gym.whenInUseTitle
        case .always: Copy.gym.alwaysTitle
        case .limited: Copy.gym.whenInUseOnlyTitle
        case .denied: Copy.gym.deniedTitle
        }
    }

    private func message(_ face: Face) -> String {
        switch face {
        case .whenInUse: Copy.gym.whenInUseMessage
        case .always: Copy.gym.alwaysMessage
        case .limited: Copy.gym.whenInUseOnlyMessage
        case .denied: Copy.gym.deniedMessage
        }
    }
}

/// The post-save "Always" explainer, as a sheet. Closes itself once the level changes to Always
/// (or the person picks "Not now").
struct AlwaysLocationPrimerSheet: View {
    let authorization: GymLocationAuthorization
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            LocationPermissionPrimer(kind: .always, authorization: authorization, onNotNow: onClose)
                .padding(Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
        }
        .zanoBackdrop(glow: Theme.Colors.accent)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: authorization.level) { _, level in
            if level == .always || (level == .whenInUse && authorization.hasRequestedAlways) {
                onClose()
            }
        }
    }
}
