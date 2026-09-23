// FounderSeriesCard.swift
// Core / UI / Components
//
// docs/spec.md §5.22 Founder Series Inside the App: "A 'Building ZANO' feed card (optional)
// linking to your content. Founder-led brands win; make the founder visible without being
// annoying."
//
// A simple, standalone, dismissible card — this task's own brief is explicit that this is "logic
// + a standalone component only" and that wiring it into an actual feed/screen (Today, Progress,
// wherever "Settings → Gear"-adjacent content ends up living) is a follow-up, not this task's job;
// no `App/ZANO/Features/**` file is touched here. Every string is caller-composed, never read from
// `Core/Sources/Core/Copy` internally — same "views never compose their own sentence" discipline
// `PaywallCard.swift`/`RecapCard.swift`/`GhostProgressBanner.swift` each document at their own
// declaration (`PaywallCard.swift`'s header: "All text is caller-composed... `SubscriptionPackage`/
// pricing types never appear here; the caller resolves them to plain strings first"). A ready-made
// default set of that copy — "Building ZANO", matching spec §5.22's own example title verbatim —
// lives in `Copy/FounderSeriesCopy.swift` (`Copy.founderSeries`) for whichever future caller wires
// this in, exactly the same "component takes strings, Copy supplies them, the two files don't
// import each other" split this codebase already uses everywhere else.
//
// "Optional" (spec §5.22) and "without being annoying" are read as: this component is always
// dismissible (`onDismiss` is required, not optional) and is entirely stateless about *whether* to
// keep showing itself — it has no `@AppStorage`/`UserDefaults` of its own. A real "stay dismissed"
// promise needs to survive this view being destroyed and recreated (a fresh feed row, a relaunch),
// which only a caller with a persistence story of its own (or, if a shared/synced "seen this" flag
// is ever wanted, `GearOffersEngine`'s own `UserDefaults`-backed dismissal log in this same task —
// `Monetization/GearOffersEngine.swift` — is the closest existing precedent to extend, not this
// file) can actually provide. Flagged as the honest scope boundary, not silently assumed away.
//
// Naming note: the caller-composed paragraph copy is named `bodyText` throughout (parameter,
// stored property, doc comments), never plain `body` — `View`'s own required `var body: some
// View` already owns that exact name on this type, and a second, differently-typed member called
// `body` is an invalid redeclaration, not just a style nit.
//
// Design-quality pass (docs/design/{better-ui HIT-01,better-layout 3.2,typography-color C7}): both
// of this card's controls were below the 44pt target — the dismiss × was ~23pt (a bare 11pt glyph
// with 6pt of padding) and the CTA was 13pt accent text with no shape (~16pt). The × keeps its small
// visual and grows only its target; the CTA is a bordered secondary capsule, 44pt tall. The card is
// a `zanoCard` (real edge, not a 1.06:1 hairline), the video badge is a neutral `IconBadge` (accent
// means earned/CTA, not decoration), and the container is `.contain` rather than `.combine` so
// VoiceOver can reach the two buttons instead of reading one merged label with no actions.

import SwiftUI

/// A dismissible "Building ZANO" feed card (docs/spec.md §5.22) — founder-visibility content, kept
/// visually consistent with every other `Core/UI/Components` card via `Theme` tokens only.
public struct FounderSeriesCard: View {
    /// Caller-composed headline, e.g. `Copy.founderSeries.defaultHeadline` ("Building ZANO").
    private let headline: String
    /// Caller-composed paragraph copy, e.g. `Copy.founderSeries.defaultBody`. Named `bodyText`,
    /// not `body` — see this file's header naming note.
    private let bodyText: String
    /// Caller-composed CTA label (e.g. "Watch"). `nil` alongside a `nil` `onTapCTA` renders the
    /// card as a plain, non-interactive announcement with no button — still dismissible.
    private let ctaLabel: String?
    /// Tap handler for the CTA (e.g. open the founder's linked content). Only rendered when both
    /// this and `ctaLabel` are non-`nil`.
    private let onTapCTA: (() -> Void)?
    /// Caller-composed VoiceOver label for the dismiss (×) button, e.g.
    /// `Copy.founderSeries.dismissAccessibilityLabel`. Required, not defaulted to a bare literal
    /// here — see this file's header note on why this component never falls back to inline copy.
    private let dismissAccessibilityLabel: String
    /// Called when the person dismisses the card. Required (not optional) — spec §5.22 frames this
    /// card as "optional" from the *product's* point of view, which this component reads as: it
    /// must always be dismissible, never a caller-optional afterthought.
    private let onDismiss: () -> Void

    /// - Parameters:
    ///   - headline: Caller-composed headline (from `Copy.founderSeries.*` or an override).
    ///   - bodyText: Caller-composed paragraph copy.
    ///   - ctaLabel: Caller-composed CTA label. Defaults to `nil` (no CTA button).
    ///   - onTapCTA: CTA tap handler. Defaults to `nil`. Only rendered alongside a non-`nil`
    ///     `ctaLabel`.
    ///   - dismissAccessibilityLabel: Caller-composed VoiceOver label for the dismiss control.
    ///   - onDismiss: Dismiss handler — always called from the visible × button.
    public init(
        headline: String,
        bodyText: String,
        ctaLabel: String? = nil,
        onTapCTA: (() -> Void)? = nil,
        dismissAccessibilityLabel: String,
        onDismiss: @escaping () -> Void
    ) {
        self.headline = headline
        self.bodyText = bodyText
        self.ctaLabel = ctaLabel
        self.onTapCTA = onTapCTA
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            iconBadge

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(headline)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.leading)

                    Text(bodyText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }

                if let ctaLabel, let onTapCTA {
                    ctaButton(label: ctaLabel, action: onTapCTA)
                }
            }

            Spacer(minLength: 0)

            dismissButton
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
        // `.contain`, not `.combine`: this card holds two real controls (the CTA and the dismiss ×),
        // and `.combine` would merge them into one static element, leaving VoiceOver no way to
        // reach either.
        .accessibilityElement(children: .contain)
    }

    /// A video/camera glyph — "founder content" in this product's own framing (§25's
    /// unboxing/UGC/gym-mirror-video language) leans on video, not a literal headshot photo this
    /// component has no image asset for. `Image(systemName:)` degrades to a blank glyph (never a
    /// crash) if the symbol name is ever wrong on a given OS version — same acknowledged-but-
    /// nonfatal risk `GhostProgressBanner.swift`'s own `iconBadge` flags for its own SF Symbol. A
    /// neutral (`text`) badge, not accent: the glyph carries no state, and accent means earned.
    private var iconBadge: some View {
        IconBadge(systemName: "video.fill", tint: Theme.Colors.text, size: .medium)
    }

    /// The card's one action, as a real (secondary) control instead of 13pt accent text with a
    /// ~16pt target: a bordered `surface2` capsule, 44pt tall (better-layout 3.2).
    private func ctaButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: Theme.Metrics.minTapTarget)
                .background(Theme.Colors.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }

    /// A small × that keeps its small visual but has a full 44x44pt target (it was ~23pt). The glyph
    /// stays where it was: the target grows around it and is pulled back with a matching negative
    /// padding, so the card's layout does not change.
    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(Theme.Typography.icon(.xsmall, weight: .bold))
                .foregroundStyle(Theme.Colors.muted)
                .frame(width: Theme.Spacing.lg, height: Theme.Spacing.lg)
                .background(Theme.Colors.surface2, in: Circle())
                .minTapTarget()
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        // 44pt target around a 24pt visual: pull the 10pt of extra target back out of the layout.
        .padding(-(Theme.Metrics.minTapTarget - Theme.Spacing.lg) / 2)
        .accessibilityLabel(dismissAccessibilityLabel)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.sm) {
        FounderSeriesCard(
            headline: "Building ZANO",
            bodyText: "Follow along as we build ZANO in public — the wins, the bugs, and the hardware.",
            ctaLabel: "Watch",
            onTapCTA: {},
            dismissAccessibilityLabel: "Dismiss",
            onDismiss: {}
        )
        FounderSeriesCard(
            headline: "Building ZANO",
            bodyText: "New this week: sampling the first Lock Card run.",
            dismissAccessibilityLabel: "Dismiss",
            onDismiss: {}
        )
    }
    .padding()
    .background(Theme.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
