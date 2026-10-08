// ZanoAppearance.swift
// Core / UI
//
// Settings > Appearance (light mode, 2026-10-03): System / Light / Dark. Stored in the App Group's
// shared defaults (not `UserDefaults.standard`) so the widgets and the Screen Time report extension
// can match an explicit choice. The app applies it once at its root (`ZANOApp`); extensions apply it
// with `.zanoAppAppearance()`. Default: System.

import SwiftUI
import UIKit

/// The user's appearance choice.
public enum ZanoAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The App Group defaults key (`SharedDefaults.store`).
    public static let storageKey = "shared.appearance"

    /// The scheme to force, or nil to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The UIKit equivalent, for a window's `overrideUserInterfaceStyle`.
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// The stored choice (System when unset or unreadable).
    public static var stored: ZanoAppearance {
        SharedDefaults.store.string(forKey: storageKey).flatMap(ZanoAppearance.init(rawValue:)) ?? .system
    }
}

/// Applies the stored appearance to an extension's view tree (widgets, the Screen Time report),
/// which the app's root `preferredColorScheme` can't reach. System leaves the host's scheme alone.
struct ZanoAppAppearanceModifier: ViewModifier {
    @AppStorage(ZanoAppearance.storageKey, store: SharedDefaults.store)
    private var appearance: ZanoAppearance = .system
    @Environment(\.colorScheme) private var hostScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appearance.colorScheme ?? hostScheme)
    }
}

extension View {
    /// Resolves this view's colours in the user's Settings > Appearance choice (extensions only;
    /// the app sets it at its root).
    public func zanoAppAppearance() -> some View {
        modifier(ZanoAppAppearanceModifier())
    }
}
