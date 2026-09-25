// TagTapToast.swift
// App / ZANO / Features / NFC
//
// On-screen confirmation after a tag tap ("+25 g protein logged", "Lock started"). Before this, a
// tap that opened the app via `zano://tag/<uuid>` ran its intent with no visible result.
//
// `TagTapFeedback.shared` is the one place anything posts a toast; `.zanoTagTapToast()` (applied
// once, at the root) draws it. Main-actor `@Observable`, same pattern as `AppRouter`.

import SwiftUI
import Observation
import Core

/// Posts short tag-tap confirmations for `.zanoTagTapToast()` to show.
@MainActor
@Observable
final class TagTapFeedback {
    static let shared = TagTapFeedback()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let systemImage: String
        let isFailure: Bool
    }

    /// The toast on screen, if any.
    private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    /// How long a toast stays up.
    static let visibleDuration: Duration = .seconds(2.6)

    private init() {}

    /// Shows `text` (already resolved from `Copy`).
    func show(_ text: String, systemImage: String = "wave.3.right", isFailure: Bool = false) {
        current = Toast(text: text, systemImage: systemImage, isFailure: isFailure)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Shows the confirmation for what a handled tap did.
    func show(effect: NFCTagTapEffect) {
        show(effect.toastText, systemImage: effect.toastSymbol)
    }

    /// Shows a failure line for a tap whose intent threw.
    func showFailure(_ error: Error) {
        let text: String
        if case NFCTagMapperError.noConfirmedGym = error {
            text = Copy.nfc.toastNoConfirmedGym
        } else {
            text = Copy.nfc.toastTapFailed
        }
        show(text, systemImage: "exclamationmark.circle", isFailure: true)
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// The toast itself: a glass capsule with the action's glyph.
struct TagTapToastView: View {
    let toast: TagTapFeedback.Toast

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: toast.systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(toast.isFailure ? Theme.Colors.warning : Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(toast.text)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Capsule(style: .continuous).fill(Theme.Colors.surface.opacity(0.92)))
        .zanoGlass()
        .shadow(color: Theme.Colors.shadow, radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

private struct TagTapToastModifier: ViewModifier {
    @State private var feedback = TagTapFeedback.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = feedback.current {
                    TagTapToastView(toast: toast)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .id(toast.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .onTapGesture { feedback.dismiss() }
                        .onAppear {
                            AccessibilityNotification.Announcement(toast.text).post()
                        }
                }
            }
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion) ?? .default, value: feedback.current)
            .sensoryFeedback(trigger: feedback.current) { _, new -> SensoryFeedback? in
                guard let new else { return nil }
                return new.isFailure ? .warning : .success
            }
    }
}

extension View {
    /// Shows `TagTapFeedback.shared`'s toasts over this view. Apply once, at the app root.
    func zanoTagTapToast() -> some View {
        modifier(TagTapToastModifier())
    }
}
