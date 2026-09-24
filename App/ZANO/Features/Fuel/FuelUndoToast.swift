// FuelUndoToast.swift
// App / Features / Fuel
//
// The "Logged 25 g of protein · Undo" toast a quick-add chip leaves behind. One tap on a chip logs
// straight away (no confirm step), so a mis-tap needs a cheap way back: the toast offers Undo for a
// few seconds, then goes. It sits on the same dark glass as the chips (`ZanoGlass`). `FuelView`
// owns the timing and what Undo deletes; this file only draws the toast.

import SwiftUI
import Core

/// What the toast is about: the message, and the id of the `GoalEvent` the quick-add inserted
/// (what Undo deletes).
struct FuelUndoItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let eventID: UUID
}

struct FuelUndoToast: View {
    let message: String
    let undoLabel: String
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
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onUndo) {
                Text(undoLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.96))
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xxs)
        .padding(.vertical, Theme.Spacing.xxs)
        // Glass over a dark backing: the toast floats over scrolling cards, so the backing keeps the
        // text legible whatever passes underneath.
        // (`zanoGlass` first, so the backing draws beneath the glass.)
        .zanoGlass()
        .background(Theme.Colors.surface.opacity(0.92), in: Capsule(style: .continuous))
        .shadow(color: Theme.Colors.shadow, radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}
