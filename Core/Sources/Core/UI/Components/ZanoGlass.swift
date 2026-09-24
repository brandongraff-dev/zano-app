// ZanoGlass.swift
// Core / UI / Components
//
// The dark glass the floating tab bar introduced, as one component so capsules, quick-add controls
// and status pills all sit on the same material instead of per-screen copies.

import SwiftUI

/// A faint white fill with a top-lit hairline, in `shape`.
public struct ZanoGlass<S: InsettableShape>: View {
    private let shape: S

    public init(_ shape: S) {
        self.shape = shape
    }

    public var body: some View {
        shape
            .fill(Theme.Colors.glassFill)
            .overlay(shape.strokeBorder(Theme.Colors.glassEdge, lineWidth: 0.75))
    }
}

extension View {
    /// Puts this view on dark glass in `shape` (a capsule by default).
    public func zanoGlass<S: InsettableShape>(in shape: S) -> some View {
        background(ZanoGlass(shape))
    }

    public func zanoGlass() -> some View {
        background(ZanoGlass(Capsule(style: .continuous)))
    }
}

/// "● Locked · Social · since 7:00 AM": a status line on a glass capsule, with an optional chevron
/// when the capsule is tappable.
public struct ZanoStatusCapsule: View {
    private let dotColor: Color
    private let text: String
    private let showsChevron: Bool

    public init(dotColor: Color, text: String, showsChevron: Bool = false) {
        self.dotColor = dotColor
        self.text = text
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(text)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.xsmall))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .zanoGlass()
    }
}
