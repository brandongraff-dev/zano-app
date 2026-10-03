// NFCTagSticker.swift
// App / ZANO / Features / NFC
//
// Pass 2 (2026-10-03, "make it more playful"): "Your tags" as a sticker collection. Each tag is a
// round die-cut sticker in its action's colour (white rim, the action glyph, a hard printed
// shadow, a slight tilt that alternates through the grid), with its name, what a tap does and when
// it was last tapped under it, on a glass tile. Tap the tile to edit; the ellipsis menu and the
// context menu still offer edit and remove (NFCTagsView owns those actions).

import SwiftUI
import Core

/// The round sticker itself.
struct NFCTagStickerDisc: View {
    let symbol: String
    let tint: Color
    var diameter: CGFloat = 64
    var tilt: Double = -6

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Circle().strokeBorder(Color.white, lineWidth: max(2.5, diameter * 0.05))
            // A tiny ZANO star in the corner, like a maker's mark.
            ZanoMark(height: diameter * 0.12, style: .mono(Theme.Colors.onFill.opacity(0.55)))
                .offset(x: diameter * 0.2, y: diameter * 0.26)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.36, weight: .black))
                .foregroundStyle(Theme.Colors.onFill)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.45), radius: 0, x: 2, y: 4)
        .rotationEffect(.degrees(tilt))
        .accessibilityHidden(true)
    }
}

/// One tag in the collection grid.
struct NFCTagStickerTile<MenuContent: View>: View {
    let name: String
    let summary: String
    let lastTapped: String
    let symbol: String
    let tint: Color
    let tilt: Double
    let onEdit: () -> Void
    let menuAccessibilityLabel: String
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    NFCTagStickerDisc(symbol: symbol, tint: tint, tilt: tilt)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Text(summary)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lastTapped)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .lineLimit(1)
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .combine)

            Menu(content: menu) {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .minTapTarget()
            }
            .accessibilityLabel(menuAccessibilityLabel)
            .padding(Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(tint: tint)
        .contextMenu(menuItems: menu)
    }
}
