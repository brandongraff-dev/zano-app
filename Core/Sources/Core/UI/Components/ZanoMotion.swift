// ZanoMotion.swift
// Core / UI / Components
//
// Two navigation/scroll motions that make the app feel like Apple's own (design redo step 3,
// 2026-10-06 — docs/sessions/14-apple-native-surfaces.md):
//
//   * Zoom navigation. A tapped card grows into the screen it opens, and the screen shrinks back
//     into the card when dismissed (Photos, App Store, Fitness). `matchedTransitionSource` and
//     `.navigationTransition(.zoom)` are iOS 18+; on iOS 17 the push is the standard slide. The
//     system handles Reduce Motion for the zoom itself.
//   * Scroll edge settle. A top-level card eases down slightly in scale and opacity as it scrolls
//     off the top or bottom edge, so a scrolling screen reads as layered rather than a flat sheet
//     sliding under glass. Off under Reduce Motion. Apply to *top-level* cards in a vertical
//     `ScrollView` only — nested cards would compound the effect.

import SwiftUI

extension View {

    /// Marks this view as the card a zoom navigation grows out of. Pair with
    /// `zanoZoomDestination(id:in:)` on the pushed screen, using the same `id` and `namespace`.
    public func zanoZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZanoZoomSource(id: id, namespace: namespace))
    }

    /// Makes this pushed screen zoom out of the card marked with `zanoZoomSource(id:in:)`.
    public func zanoZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZanoZoomDestination(id: id, namespace: namespace))
    }

    /// The scroll edge settle described in the file header. For top-level cards in a vertical
    /// `ScrollView`.
    public func zanoScrollSettle() -> some View {
        modifier(ZanoScrollSettle())
    }
}

struct ZanoZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct ZanoZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

struct ZanoScrollSettle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Copied to a local: the transition closure is `@Sendable` and must not capture `self`.
        let settles = !reduceMotion
        return content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .scaleEffect(settles && !phase.isIdentity ? 0.96 : 1)
                .opacity(settles && !phase.isIdentity ? 0.65 : 1)
        }
    }
}
