// UnmappedTagView.swift
// App / ZANO / Features / NFC
//
// What a tap on a ZANO tag with no saved mapping opens (the router parks its id in
// `AppRouter.pendingUnmappedTagID`). Before this, an unmapped tap just switched to the Settings tab
// and nothing else happened. Now: "This tag isn't set up yet" → Set up this tag → `NFCMapTagSheet`.
//
// Present as a sheet; it owns its NavigationStack (and swaps to the map sheet's).

import SwiftUI
import Core

struct UnmappedTagView: View {
    let tagID: UUID
    /// Called once: with the saved mapping, or `nil` for "Not now".
    var onFinished: (NFCTagMapping?) -> Void = { _ in }

    init(tagID: UUID, onFinished: @escaping (NFCTagMapping?) -> Void = { _ in }) {
        self.tagID = tagID
        self.onFinished = onFinished
    }

    @State private var isMapping = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isMapping {
                NFCMapTagSheet(
                    tagID: tagID,
                    onSaved: { mapping in
                        TagTapFeedback.shared.show(
                            Copy.nfc.summary(action: mapping.nfcDisplayName, detail: mapping.action.nfcSummary()),
                            systemImage: NFCActionChoice(mapping.action).symbol
                        )
                        finish(mapping)
                    },
                    onCancel: { isMapping = false }
                )
                .transition(.opacity)
            } else {
                NavigationStack {
                    prompt
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Copy.common.cancel) { finish(nil) }
                            }
                        }
                }
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
            }
        }
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isMapping)
        .onAppear {
            Analytics.shared.capture(event: "nfc_unmapped_tag_prompt_shown")
        }
    }

    private var prompt: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.md)
            TagTapScene(phase: .idle)
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.nfc.unmappedEyebrow)
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.accent)
                Text(Copy.nfc.unmappedTitle)
                    .zanoText(.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.nfc.unmappedMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            VStack(spacing: Theme.Spacing.xs) {
                PrimaryButton(title: Copy.nfc.unmappedSetUpButton, systemImage: "wave.3.right") {
                    isMapping = true
                }
                PrimaryButton(title: Copy.nfc.unmappedNotNowButton, style: .secondary) {
                    finish(nil)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoBackdrop(glow: Theme.Colors.accent, intensity: 0.16)
    }

    private func finish(_ mapping: NFCTagMapping?) {
        onFinished(mapping)
        dismiss()
    }
}

/// `.sheet(item:)` payload for presenting `UnmappedTagView` from a bare `UUID`.
struct UnmappedTagPrompt: Identifiable, Equatable {
    let tagID: UUID
    var id: UUID { tagID }
}
