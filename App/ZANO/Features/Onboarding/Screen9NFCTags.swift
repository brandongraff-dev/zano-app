// Screen9NFCTags.swift
// App / Features / Onboarding
//
// Onboarding screen 9 of 15: ZANO tags ("Tap to prove it"). docs/spec.md §3 (protein, water and
// creatine are verified by an NFC tap on the shaker, bottle or tub), §5.10 (the Sunrise Tag turns off
// the alarm), §6 (NFC: each tag is a `zano://tag/<uuid>` URL mapped to an action in-app), §25.1
// (Tag Pack placements) and §25.5-§25.6 (the gear store, linked from Settings).
//
// Why a screen: the founder calls tags "a huge part" of ZANO, and the flow never mentioned them.
// It sits right after the six questions (the last one, coach voice, is screen 8) and before the
// wake-up math and the plan reveal, so the plan can already say how a protein goal gets verified
// ("Verified by: NFC tap", screen 11). It adds one screen: the flow is 15 steps, one over spec §7's
// "10-14 screens" target (flagged for the founder in the session doc).
//
// The screen:
//   1. An illustration drawn in SwiftUI: an iPhone, top edge first, comes down onto a round silver
//      ZANO tag; on contact blue NFC rings pulse out of the tag, the goal ring around it fills, and a
//      check lands. Three runs, then it rests on the finished state (nothing loops forever). Reduce
//      Motion: the finished state, drawn once, with two faint static rings.
//   2. Two short lines (where the tag goes; one tap logs and verifies, instantly, offline), a proof
//      line, and three use-case chips (shaker, water bottle, Sunrise alarm).
//   3. One question, "Do you have ZANO tags?": have tags / get tags / skip. Continue is gated on an
//      answer, like Q1 and Q5. The answer is kept in `OnboardingFlowState.nfcTagAnswer` (transient,
//      like every other onboarding answer) and sent as an `onboarding_nfc_choice` analytics event,
//      which is the only record of tag interest today: there is no persisted home for it and no
//      store to send anyone to.
//
// "Get tags" has no store to open: `SettingsReferenceData.gearStoreURL` (SettingsView.swift) is `nil`
// until a real store exists, so the answer's detail line says tags aren't on sale yet. When that URL
// is set, this screen shows a link to it under the answer with no other change.

import SwiftUI
import Core

/// How the user will log their tag-able goals, answered on screen 9.
enum NFCTagAnswer: String, CaseIterable, Sendable, Hashable {
    /// Already owns ZANO tags (they add them in Settings → NFC tags after onboarding).
    case haveTags = "have_tags"
    /// Wants tags. Records interest only until a store exists.
    case wantTags = "want_tags"
    /// Logs with widgets and buttons for now.
    case skip
}

@MainActor
struct Screen9NFCTags: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Scaled down so the question and all three answers fit above the fold, even on
                // an iPhone SE.
                NFCTapIllustration()
                    .scaleEffect(0.68)
                    .frame(height: NFCTapGeometry.size.height * 0.68)
                    .frame(maxWidth: .infinity)

                header
                useCaseChips
                choices
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onboardingPinnedContinue(
            title: Copy.common.continueButtonLabel,
            isEnabled: flowState.nfcTagAnswer != nil
        ) {
            if let answer = flowState.nfcTagAnswer {
                Analytics.shared.capture(event: "onboarding_nfc_choice", properties: ["choice": answer.rawValue])
            }
            flowState.advance()
        }
        .sensoryFeedback(.selection, trigger: flowState.nfcTagAnswer)
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "nfc_tags", "screen_number": 9]
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            OnboardingKit.Eyebrow(text: Copy.onboarding.nfcEyebrow, color: Theme.Colors.accent)

            OnboardingKit.DisplayTitle(text: Copy.onboarding.nfcTitle, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text(Copy.onboarding.nfcBody)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)

            Text(Copy.onboarding.nfcProofLine)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Use-case chips

    /// Three glass chips on one row; on a narrow phone (or large type) the third wraps below.
    private var useCaseChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                proteinChip
                waterChip
                sunriseChip
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    proteinChip
                    waterChip
                }
                sunriseChip
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.onboarding.nfcUseCasesAccessibilityLabel)
    }

    private var proteinChip: some View {
        useCaseChip(Copy.onboarding.nfcUseCaseProtein, systemImage: "fork.knife")
    }

    private var waterChip: some View {
        useCaseChip(Copy.onboarding.nfcUseCaseWater, systemImage: "drop.fill")
    }

    private var sunriseChip: some View {
        useCaseChip(Copy.onboarding.nfcUseCaseSunrise, systemImage: "sunrise.fill")
    }

    private func useCaseChip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .zanoGlass()
    }

    // MARK: - The choice

    private var choices: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.onboarding.nfcChoiceTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Theme.Spacing.xs)

            ForEach(NFCTagAnswer.allCases, id: \.self) { answer in
                SelectableCard(
                    title: title(for: answer),
                    subtitle: detail(for: answer),
                    icon: symbol(for: answer),
                    isSelected: flowState.nfcTagAnswer == answer
                ) {
                    flowState.nfcTagAnswer = answer
                }
            }

            // Only once a real store exists (see file header): never a placeholder link.
            if flowState.nfcTagAnswer == .wantTags, let gearStoreURL = SettingsReferenceData.gearStoreURL {
                Button {
                    openURL(gearStoreURL)
                } label: {
                    Label(Copy.onboarding.nfcGearStoreLinkLabel, systemImage: "arrow.up.right")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func title(for answer: NFCTagAnswer) -> String {
        switch answer {
        case .haveTags: Copy.onboarding.nfcChoiceHaveTagsTitle
        case .wantTags: Copy.onboarding.nfcChoiceGetTagsTitle
        case .skip: Copy.onboarding.nfcChoiceSkipTitle
        }
    }

    private func detail(for answer: NFCTagAnswer) -> String {
        switch answer {
        case .haveTags: Copy.onboarding.nfcChoiceHaveTagsDetail
        case .wantTags: Copy.onboarding.nfcChoiceGetTagsDetail
        case .skip: Copy.onboarding.nfcChoiceSkipDetail
        }
    }

    /// SF Symbol identifiers (not user-facing copy).
    private func symbol(for answer: NFCTagAnswer) -> String {
        switch answer {
        case .haveTags: "wave.3.right.circle.fill"
        case .wantTags: "shippingbox.fill"
        case .skip: "hand.tap.fill"
        }
    }
}

// MARK: - Illustration

/// Layout of the illustration, in points, inside its fixed frame. A caseless, nonisolated enum so
/// `NFCTapFrame` (a plain value type) can read it without touching the main actor.
private enum NFCTapGeometry {
    static let size = CGSize(width: 220, height: 246)
    static let tagCenter = CGPoint(x: 110, y: 176)
    static let tagDiameter: CGFloat = 80
    static let ringDiameter: CGFloat = 116
    static let ringWidth: CGFloat = 5
    /// Bottom-right of the ring, clear of the phone coming down from the top.
    static let checkCenter = CGPoint(x: 151, y: 217)
    static let checkDiameter: CGFloat = 28
    static let phoneSize = CGSize(width: 60, height: 112)
    /// Upside down with a slight tilt, so the phone's top edge (where the NFC reader is) leads.
    static let phoneRotation: Double = 166
    /// Phone center when touching the tag.
    static let phoneContact = CGPoint(x: 104, y: 84)
    /// How far the phone lifts away between taps.
    static let phoneLift: CGFloat = 24
    static let waveCount = 3
    /// A wave ring starts at the tag's size and grows to this multiple.
    static let waveMaxScale: CGFloat = 2.0
}

/// The illustration's clock, in seconds. Three runs of `cycle`; the last run stops at `hold`, the
/// finished state (phone down, ring full, check in).
private enum NFCTapTiming {
    static let cycle: Double = 3.2
    static let runs = 3
    static let contact: Double = 0.75
    static let waveDuration: Double = 0.9
    static let waveStagger: Double = 0.18
    static let liftStart: Double = 2.45
    static let hold: Double = 2.3

    static var total: Double { Double(runs - 1) * cycle + hold }
}

/// Everything the illustration draws at one instant, as 0...1 amounts.
private struct NFCTapFrame {
    /// 0 = phone lifted, 1 = touching the tag.
    var approach: Double
    /// Progress of the NFC wave burst since contact (`nil` = no burst on screen).
    var waves: Double?
    var ring: Double
    var checkScale: Double
    var checkOpacity: Double
    var glow: Double
    /// Reduce Motion: two faint rings drawn still, standing in for the pulse.
    var staticWaves = false

    /// The finished state. Also the whole illustration under Reduce Motion.
    static func settled(staticWaves: Bool) -> NFCTapFrame {
        NFCTapFrame(
            approach: 1,
            waves: nil,
            ring: 1,
            checkScale: 1,
            checkOpacity: 1,
            glow: 0.35,
            staticWaves: staticWaves
        )
    }

    init(approach: Double, waves: Double?, ring: Double, checkScale: Double, checkOpacity: Double, glow: Double, staticWaves: Bool = false) {
        self.approach = approach
        self.waves = waves
        self.ring = ring
        self.checkScale = checkScale
        self.checkOpacity = checkOpacity
        self.glow = glow
        self.staticWaves = staticWaves
    }

    /// The frame `elapsed` seconds after the illustration started.
    init(elapsed: Double) {
        let timing = NFCTapTiming.self
        let run = max(0, Int(elapsed / timing.cycle))
        let isLastRun = run >= timing.runs - 1
        let t = isLastRun
            ? min(max(0, elapsed - Double(timing.runs - 1) * timing.cycle), timing.hold)
            : elapsed - Double(run) * timing.cycle

        // Down onto the tag, then (except on the last run) back up.
        let down = Self.easeInOut(Self.clamp(t / timing.contact))
        let up = isLastRun ? 0 : Self.easeInOut(Self.clamp((t - timing.liftStart) / 0.5))
        approach = down * (1 - up)

        // The burst: long enough for the last staggered ring to finish.
        let burst = (t - timing.contact) / timing.waveDuration
        let burstEnd = 1 + Double(NFCTapGeometry.waveCount - 1) * timing.waveStagger / timing.waveDuration
        waves = (burst > 0 && burst < burstEnd) ? burst : nil

        // Ring and check clear away as the phone lifts, ready for the next tap.
        let clear = isLastRun ? 0 : Self.clamp((t - timing.liftStart - 0.1) / 0.4)
        ring = Self.easeOut(Self.clamp((t - timing.contact) / 0.75)) * (1 - clear)
        let check = Self.clamp((t - timing.contact - 0.15) / 0.4)
        checkScale = 0.5 + 0.5 * Self.backOut(check)
        checkOpacity = Self.clamp(check * 3) * (1 - clear)

        // A flash of blue light from the tag on contact; the last run keeps a little of it.
        let flash = Self.clamp(1 - abs(t - timing.contact - 0.15) / 0.7)
        glow = isLastRun && t > timing.contact + 0.15 ? max(flash, 0.35) : flash
        staticWaves = false
    }

    /// Scale and opacity of wave ring `index` in this frame.
    func wave(_ index: Int) -> (scale: Double, opacity: Double) {
        if staticWaves {
            switch index {
            case 0: return (1.45, 0.35)
            case 1: return (1.8, 0.16)
            default: return (1, 0)
            }
        }
        guard let waves else { return (1, 0) }
        let local = (waves * NFCTapTiming.waveDuration - Double(index) * NFCTapTiming.waveStagger)
            / NFCTapTiming.waveDuration
        guard local > 0, local < 1 else { return (1, 0) }
        let grown = 1 + (Double(NFCTapGeometry.waveMaxScale) - 1) * Self.easeOut(local)
        return (grown, 0.85 * (1 - local))
    }

    // MARK: Easing

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// Overshoots a little and settles: the check "lands".
    static func backOut(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

/// An iPhone, top edge first, tapping a round silver ZANO tag: blue NFC rings pulse out, the goal
/// ring around the tag fills and a check lands. Plays three times, then rests on the finished state.
/// Reduce Motion: the finished state only. Decorative: the text beside it says the same thing.
@MainActor
private struct NFCTapIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var finished = false
    /// Flips once, on the first contact, for a single soft haptic (not one per loop).
    @State private var touched = false

    var body: some View {
        Group {
            if reduceMotion {
                scene(.settled(staticWaves: true))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { context in
                    scene(NFCTapFrame(elapsed: context.date.timeIntervalSince(start)))
                }
            }
        }
        .frame(width: NFCTapGeometry.size.width, height: NFCTapGeometry.size.height)
        .task {
            await play()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: touched) { _, newValue in
            newValue
        }
        .accessibilityHidden(true)
    }

    private func play() async {
        guard !reduceMotion else { return }
        start = .now
        try? await Task.sleep(for: .seconds(NFCTapTiming.contact))
        guard !Task.isCancelled else { return }
        touched = true
        try? await Task.sleep(for: .seconds(NFCTapTiming.total - NFCTapTiming.contact + 0.1))
        guard !Task.isCancelled else { return }
        finished = true
    }

    private func scene(_ frame: NFCTapFrame) -> some View {
        let g = NFCTapGeometry.self
        return ZStack {
            // NFC waves, under everything else.
            ForEach(0..<g.waveCount, id: \.self) { index in
                let wave = frame.wave(index)
                Circle()
                    .stroke(Theme.Colors.accent, lineWidth: 1.5)
                    .frame(width: g.tagDiameter, height: g.tagDiameter)
                    .scaleEffect(wave.scale)
                    .opacity(wave.opacity)
                    .position(g.tagCenter)
            }

            // The goal ring the tap fills.
            Circle()
                .stroke(Theme.Colors.accent.opacity(0.18), lineWidth: g.ringWidth)
                .frame(width: g.ringDiameter, height: g.ringDiameter)
                .position(g.tagCenter)
            Circle()
                .trim(from: 0, to: CGFloat(frame.ring))
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: g.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: g.ringDiameter, height: g.ringDiameter)
                .shadow(color: Theme.Colors.accent.opacity(0.5 * frame.ring), radius: 6)
                .position(g.tagCenter)

            NFCTagDisc(glow: frame.glow)
                .frame(width: g.tagDiameter, height: g.tagDiameter)
                .position(g.tagCenter)

            checkBadge
                .scaleEffect(frame.checkScale)
                .opacity(frame.checkOpacity)
                .position(g.checkCenter)

            PhoneSilhouette()
                .frame(width: g.phoneSize.width, height: g.phoneSize.height)
                .rotationEffect(.degrees(g.phoneRotation))
                .position(
                    x: g.phoneContact.x,
                    y: g.phoneContact.y - g.phoneLift * CGFloat(1 - frame.approach)
                )
        }
        .frame(width: g.size.width, height: g.size.height)
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(Theme.Typography.icon(.xsmall, weight: .bold))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(width: NFCTapGeometry.checkDiameter, height: NFCTapGeometry.checkDiameter)
            .background(Theme.Colors.accentFill, in: Circle())
            .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 2))
    }
}

/// The tag: a brushed-silver disc (the logo's metal) with the ZANO star printed on it. `glow` is the
/// blue light it gives off when read.
private struct NFCTagDisc: View {
    let glow: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.metallic)
            // The printed rim of a sticker tag.
            Circle()
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                .padding(5)
            ZanoMark(height: 26, style: .mono(Theme.Colors.background.opacity(0.82)))
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.75))
        .shadow(color: Theme.Colors.accent.opacity(0.65 * glow), radius: 16)
        .shadow(color: Theme.Colors.shadow, radius: 8, y: 4)
    }
}

/// A plain iPhone silhouette: graphite frame, dark screen with a hint of navy, Dynamic Island.
private struct PhoneSilhouette: View {
    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let screen = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return ZStack(alignment: .top) {
            outer
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.32), Color(white: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            screen
                .fill(
                    LinearGradient(
                        colors: [Theme.Colors.lockedAmbient, Theme.Colors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(3)
            Capsule()
                .fill(Color.black)
                .frame(width: 18, height: 5)
                .padding(.top, 8)
        }
        .overlay(outer.strokeBorder(Theme.Colors.edgeGradient(), lineWidth: 1))
        .shadow(color: Theme.Colors.shadow, radius: 10, y: 6)
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    flowState.currentScreen = 9
    return OnboardingScaffold(flowState: flowState) {
        Screen9NFCTags(flowState: flowState)
    }
}
