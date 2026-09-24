// Screen2SocialProof.swift
// App / Features / Onboarding
//
// docs/spec.md §7.2 (screen 2, Social proof strip): "3 rotating quotes (real ones once you have
// them; placeholder copy marked clearly until then)."
//
// CONTENT MODEL (read this before editing). `Copy.onboarding.socialProofQuotes` currently holds three
// plain product claims (facts about how ZANO works), NOT testimonials: the Copy owner removed the
// invented "early user" quotes as a ship risk. This screen therefore renders two formats from the same
// array, decided per entry:
//   - claim (today): no leading quote mark; a glyph badge + the sentence. Must never be dressed up as
//     a quote.
//   - quote (when real testimonials replace them): an entry shaped `"..." - Name` (starts with a quote
//     mark, has an em-dash attribution) gets a large accent quote mark and a muted attribution line.
// Either way this screen adds no star ratings, avatars, counts or other invented proof.
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered).
//   - One shared card (`zanoCard`, hero radius) whose height is set by the tallest entry, so it never
//     changes height mid-rotation at any Dynamic Type size; the active entry crossfades and drifts
//     inside it. A story-style segment bar (the active segment fills over the interval) makes the
//     pacing visible. Tap or swipe the card to step.
//   - The ring trio above the card is three real `GoalRing`s (workout / protein / focus, each partly
//     filled, each with its glyph), staggered in one after another. They teach the ring language, screen
//     3 lights them up per answer and screen 10 lists them, so the motif is introduced here first.
//     Decorative; hidden from VoiceOver.
//   - Nothing sits behind a timer for anyone who cannot use one: under Reduce Motion, VoiceOver / Voice
//     Control / Switch Control, or an accessibility Dynamic Type size (long text needs longer than a
//     fixed 4.5s), there is no auto-rotation and all entries are shown stacked and scrollable (HIG
//     Reduce Motion: "reduce automatic and repetitive animation").
//   - The interval is 4.5s, up from 3.5s: a ~12-word claim at 22pt bold needs about that to be read.
//     The timer restarts whenever the index changes, so a manual step always gets a full interval.
//   - The rotation is decorative pacing, never a gate: Continue is pinned and live from frame one.
//
// Product note for the spec owner: spec §7.2 asks for rotation, which is what this does. But today's
// three entries are facts, not quotes, and hiding two of three behind a timer costs ~9s of attention
// for nothing. If they stay claims, consider showing them stacked (this file's `staticItems` path
// already renders that) and reserving rotation for real testimonials.

import SwiftUI
import Core

/// Screen 2 of 15 (spec §7.2). Auto-rotating proof card with a manual Continue CTA.
struct Screen2SocialProof: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver and Switch Control each get their own flag: both step through elements at the
    /// user's pace, so a timer that moves the content under them is a trap.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlRunning
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var activeIndex = 0
    @State private var cycleStart = Date()
    /// Per-ring fill, staggered in by `fillRings()` (indices match `TrioSlot.all`).
    @State private var fills: [Double] = Array(repeating: 0, count: TrioSlot.all.count)

    private let rotationSeconds: Double = 4.5

    /// SF Symbol identifiers for claim-format entries, matched by position to today's three claims
    /// (locked until earned / verified by location + Health / works offline). Decorative only.
    private let claimSymbols = ["lock.fill", "location.fill", "wifi.slash"]

    private var items: [SocialProofItem] {
        Copy.onboarding.socialProofQuotes.map { SocialProofItem(raw: $0) }
    }

    /// No auto-rotation and no timed progress when motion is reduced, assistive tech is running, or
    /// the text is at an accessibility size.
    private var isStatic: Bool {
        reduceMotion || voiceOverRunning || switchControlRunning || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.md)

            ringTrio

            if isStatic {
                staticItems
            } else {
                rotatingItems
                progressSegments
            }

            Spacer(minLength: Theme.Spacing.md)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .task(id: RotationKey(index: activeIndex, isStatic: isStatic)) { await autoAdvance() }
        .task { await fillRings() }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "social_proof", "screen_number": 2]
            )
        }
    }

    // MARK: - Pieces

    private var ringTrio: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(Array(TrioSlot.all.enumerated()), id: \.offset) { index, slot in
                GoalRing(
                    // Reduce Motion: drawn filled from the first frame (no empty-ring flash).
                    progress: reduceMotion ? slot.target : fills[index],
                    color: Theme.Colors.Ring.color(for: slot.type),
                    size: .custom(64),
                    center: .icon(systemName: slot.icon)
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// One shared card surface; the entries crossfade inside it. Every entry is laid out (the
    /// inactive ones at opacity 0), so the card is always as tall as the tallest entry.
    private var rotatingItems: some View {
        surfaced {
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    SocialProofItemContent(item: item, symbol: claimSymbol(for: index))
                        .opacity(index == activeIndex ? 1 : 0)
                        .offset(x: slideOffset(for: index))
                        .accessibilityHidden(index != activeIndex)
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: activeIndex)
        .contentShape(Rectangle())
        .onTapGesture { step(1) }
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                // Horizontal intent only, so a slightly diagonal scroll never steps the card.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 {
                    step(1)
                } else if value.translation.width > 40 {
                    step(-1)
                }
            }
        )
    }

    private var staticItems: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    surfaced {
                        SocialProofItemContent(item: item, symbol: claimSymbol(for: index))
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Story-style progress: finished segments full, the active one filling over the rotation
    /// interval, upcoming ones empty. `TimelineView` derives the fill from the cycle's start time,
    /// so there is no animation state to reset when the index changes. 30fps is plenty for a 4pt bar.
    private var progressSegments: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(cycleStart)
            let fraction = min(1, max(0, elapsed / rotationSeconds))
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule()
                        .fill(Theme.Colors.track)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                // Chrome, not an earned state: white (decision 2026-09-24).
                                Capsule()
                                    .fill(Theme.Colors.interactive)
                                    .frame(width: proxy.size.width * segmentFill(index, active: fraction))
                            }
                        }
                        .frame(height: Theme.Spacing.xxs)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func surfaced<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .zanoCard(radius: Theme.Radius.large)
    }

    private func claimSymbol(for index: Int) -> String {
        claimSymbols[index % claimSymbols.count]
    }

    // MARK: - Rotation

    private func segmentFill(_ index: Int, active fraction: Double) -> Double {
        if index < activeIndex { return 1 }
        if index == activeIndex { return fraction }
        return 0
    }

    /// Inactive entries rest one small step to the side of the active one, so the crossfade also
    /// reads as a slide in the direction of travel.
    private func slideOffset(for index: Int) -> CGFloat {
        CGFloat(max(-1, min(1, index - activeIndex))) * Theme.Spacing.lg
    }

    /// Resets `cycleStart` in the same transaction as the index change, so the newly active
    /// segment starts empty on its very first frame instead of flashing full for one frame.
    private func step(_ delta: Int) {
        guard items.count > 1 else { return }
        activeIndex = (activeIndex + delta + items.count) % items.count
        cycleStart = Date()
    }

    /// One sleep, then advance. `.task(id:)` cancels and restarts this whenever `activeIndex`
    /// changes (auto or manual), which is what gives every entry a full interval on screen and
    /// removes the need for a long-lived loop. Cancelled automatically when the view disappears.
    @MainActor
    private func autoAdvance() async {
        guard !isStatic, items.count > 1 else { return }
        cycleStart = Date()
        try? await Task.sleep(for: .seconds(rotationSeconds))
        guard !Task.isCancelled else { return }
        step(1)
    }

    /// Fills the trio one ring after another (250ms lead-in, then 110ms apart). `GoalRing` animates
    /// each fill itself (`Theme.Motion.ringFill`), so this only sets the targets in sequence. Under
    /// Reduce Motion there is no sequence: `ringTrio` already draws the filled rings.
    @MainActor
    private func fillRings() async {
        guard !reduceMotion, fills.allSatisfy({ $0 == 0 }) else { return }
        for index in TrioSlot.all.indices {
            try? await Task.sleep(for: .milliseconds(index == 0 ? 250 : 110))
            guard !Task.isCancelled else { return }
            fills[index] = TrioSlot.all[index].target
        }
    }
}

private struct RotationKey: Equatable {
    let index: Int
    let isStatic: Bool
}

/// One ring of the decorative trio. Order matches Today (spec §16 P1) and screen 3's plan preview.
private struct TrioSlot {
    let type: GoalType
    let icon: String
    /// How far the ring fills: always partial (spec §8 rule 2), never a claim about the user.
    let target: Double

    static let all: [TrioSlot] = [
        TrioSlot(type: .workoutGym, icon: "dumbbell.fill", target: 0.78),
        TrioSlot(type: .protein, icon: "fork.knife", target: 0.50),
        TrioSlot(type: .focusSession, icon: "timer", target: 0.30),
    ]
}

/// Display-only reading of one `Copy.onboarding.socialProofQuotes` string. An entry is a *quote* only
/// if it starts with a quote mark and carries an em-dash attribution (`"..." - Name`, the shape the
/// Copy file documents for real testimonials). Anything else is a plain product claim, shown as-is.
private struct SocialProofItem {
    let body: String
    /// Non-nil only for a genuine quote-with-attribution entry.
    let attribution: String?

    init(raw: String) {
        let dash = " \u{2014} "
        let quoteMarks = CharacterSet(charactersIn: "\"\u{201C}\u{201D}")
        let parts = raw.components(separatedBy: dash)
        let startsWithQuote = raw.unicodeScalars.first.map { quoteMarks.contains($0) } ?? false

        if startsWithQuote, parts.count >= 2, let last = parts.last {
            body = parts.dropLast().joined(separator: dash).trimmingCharacters(in: quoteMarks)
            attribution = last
        } else {
            body = raw
            attribution = nil
        }
    }
}

private struct SocialProofItemContent: View {
    let item: SocialProofItem
    /// Leading glyph for claim-format entries; ignored for quotes.
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if item.attribution != nil {
                // A 56pt opening quote mark carries ~40pt of empty line box below its glyph; the
                // fixed-height, top-aligned frame keeps only the mark in layout.
                Text("\u{201C}")
                    .font(.system(size: 56, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(height: Theme.Spacing.lg, alignment: .top)
                    .accessibilityHidden(true)
            } else {
                // `text`, not accent: a claim is not an earned state (accent budget), and the badge
                // is decoration for a sentence that carries its own meaning.
                IconBadge(systemName: symbol, tint: Theme.Colors.text, size: .medium)
            }

            Text(item.body)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let attribution = item.attribution {
                Text(attribution)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Screen2SocialProof(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
