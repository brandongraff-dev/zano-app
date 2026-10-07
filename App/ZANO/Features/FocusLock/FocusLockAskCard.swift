// FocusLockAskCard.swift
// App / ZANO / Features / FocusLock
//
// The Today card for one open focus-lock question ("Lock your apps during 'Design review'?"), so the
// answer doesn't wait inside Settings (session 24; docs/spec.md §5.24). Draws nothing when the feature
// is off, nothing is waiting, or the meeting is already over. Yes and No are the same answers the
// Settings screen gives; the emergency unlock is untouched.

import SwiftUI
import Core

struct FocusLockAskCard: View {
    @State private var proposal = Self.current()

    var body: some View {
        Group {
            if let proposal {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Copy.focusLock.askTitle(eventTitle: proposal.window.title))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Copy.focusLock.windowLine(start: proposal.window.start, end: proposal.window.end))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    HStack(spacing: Theme.Spacing.xs) {
                        PrimaryButton(title: Copy.focusLock.yesButton) {
                            FocusLockScheduler.shared.accept(proposal)
                            self.proposal = Self.current()
                        }
                        PrimaryButton(title: Copy.focusLock.noButton, style: .secondary) {
                            FocusLockScheduler.shared.decline(proposal)
                            self.proposal = Self.current()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoCard()
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear { proposal = Self.current() }
    }

    /// The soonest question about a meeting that hasn't ended.
    private static func current(now: Date = .now) -> FocusLockProposal? {
        guard FocusLockStore.settings.isEnabled else { return nil }
        return FocusLockStore.pendingProposals
            .filter { $0.window.end > now }
            .min { $0.window.start < $1.window.start }
    }
}
