// UndoToast.swift
// App / ZANO / Features / Today
//
// "Logged 25g of Protein · Undo": the few seconds after a one-tap quick-log in which a mis-tap can
// be taken back. Shown in Today's bottom bar; `TodayView` owns the timer and the delete.

import SwiftUI
import Core

struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text(Copy.today.undoTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.94))
            .accessibilityHint(Copy.today.undoHint)
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xxs)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
        .zanoGlass(in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
