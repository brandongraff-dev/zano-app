// ZanoGlass.swift
// Core / UI / Components
//
// Chrome glass (visual direction v2, docs/design/visual-direction-v2.md §3 "Glass", level `.chrome`):
// the material for things that float over scrolling content — the tab bar, status capsules, toasts,
// quick-add controls, floating circular buttons. Unlike content cards (`zanoCard`, which is frost
// without blur), chrome is a real `.ultraThinMaterial` blur, because what scrolls beneath it is sharp.
//
//   * `.ultraThinMaterial` in the dark scheme, an ink tint over it (so it reads ink-frosted, not
//     system grey), a faint white sheen from the top, and the 1px specular rim.
//   * Reduce Transparency: an opaque `surface` fill with the same rim.
//   * Increase Contrast: the rim doubles.

import SwiftUI

/// Chrome glass in `shape`.
public struct ZanoGlass<S: InsettableShape>: View {
    private let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(_ shape: S) {
        self.shape = shape
    }

    public var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(Theme.Colors.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.Colors.glassChromeTint)
                shape.fill(
                    LinearGradient(
                        colors: [Theme.Colors.glassFillTop, Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            shape.strokeBorder(
                contrast == .increased ? Theme.Colors.glassEdgeIncreased : Theme.Colors.glassEdge,
                lineWidth: Theme.Metrics.edgeWidth
            )
        }
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Puts this view on chrome glass in `shape`.
    public func zanoGlass<S: InsettableShape>(in shape: S) -> some View {
        background(ZanoGlass(shape))
    }

    /// Puts this view on a chrome-glass capsule.
    public func zanoGlass() -> some View {
        background(ZanoGlass(Capsule(style: .continuous)))
    }
}

/// A status on a glass capsule: a glyph (or a coloured dot when no glyph is given), the text, and an
/// optional chevron when the capsule is tappable. One fact per capsule: compose two capsules rather
/// than joining facts with a middle dot.
public struct ZanoStatusCapsule: View {
    private let dotColor: Color
    private let text: String
    private let systemImage: String?
    private let showsChevron: Bool

    public init(dotColor: Color, text: String, systemImage: String? = nil, showsChevron: Bool = false) {
        self.dotColor = dotColor
        self.text = text
        self.systemImage = systemImage
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.small, weight: .bold))
                    .foregroundStyle(dotColor)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
            }
            Text(text)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .zanoGlass()
    }
}

/// A small chip on chrome glass: an optional glyph and a short fact ("72% charged", "since 7:00 AM").
/// Quieter than `ZanoStatusCapsule`: caption weight, `tint` on the glyph only.
public struct ZanoGlassChip: View {
    private let text: String
    private let systemImage: String?
    private let tint: Color

    public init(_ text: String, systemImage: String? = nil, tint: Color = Theme.Colors.textSecondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs + 2)
        .zanoGlass()
    }
}

/// An (i) button that shows `text` in a popover: the home for explanations removed from main screens
/// (visual direction v2: no explanatory paragraphs on the main surface).
public struct ZanoInfoButton: View {
    private let text: String
    private let accessibilityLabelText: String

    @State private var isShown = false

    /// - Parameters:
    ///   - text: The explanation (from `Copy`).
    ///   - accessibilityLabel: What the button is ("About borrowing", from `Copy`).
    public init(_ text: String, accessibilityLabel: String) {
        self.text = text
        self.accessibilityLabelText = accessibilityLabel
    }

    public var body: some View {
        Button {
            isShown = true
        } label: {
            Image(systemName: "info.circle")
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.muted)
                .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.9))
        .accessibilityLabel(accessibilityLabelText)
        .popover(isPresented: $isShown) {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(Theme.Spacing.md)
                .presentationCompactAdaptation(.popover)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("Chrome glass") {
    VStack(spacing: Theme.Spacing.md) {
        ZanoStatusCapsule(dotColor: Theme.Colors.textSecondary, text: "Social", systemImage: "lock.fill", showsChevron: true)
        ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: "Unlocked")
        ZanoGlassChip("72% charged", systemImage: "bolt.fill", tint: Theme.Colors.accent)
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .zanoAmbient(.progress(0.5))
    .preferredColorScheme(.dark)
}
