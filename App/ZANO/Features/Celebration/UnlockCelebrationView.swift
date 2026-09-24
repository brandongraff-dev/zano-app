// UnlockCelebrationView.swift
// App / Features / Celebration
//
// The unlock moment: the user finished their goals and their apps are back. docs/spec.md 16 P3
// (headline "Earned.", subline "Workout verified · 42 min at the gym", a Time Bank filling to
// "2h 10m unlocked", an occasional badge) and 8 rule 4 (the tasteful 1-in-6 surprise, the optional
// `badge` below).
//
// This is the *moment*, not a screen with its own navigation/data-fetching: every input is plain,
// already-resolved data, so it can be presented from anywhere (TodayView's and ContentView's
// full-screen covers, the screenshot gallery). The public `init` is unchanged by this redesign.
//
// DESIGN (brand wave, 2026-09-24). The brand's signature object is the living ZANO star, which
// "charges while you're off your phone". The unlock moment is the star reaching full charge:
//
//   stage       `UnlockStarStage`: the star charges 0.7 -> 1.0, then a flash of ZANO Blue blooms
//               from it with a brief white specular, a blue shockwave ring expands outward and a
//               blue particle burst fires. It settles in a soft bloom with three faint halo rings.
//   eyebrow     "Apps unlocked", small caps, in blue.
//   "Earned."   the headline, a big compressed numeral face filled with the logo's brushed silver.
//   figure      "2h 10m  in your Time Bank", the figure in blue, counting up.
//   subline     "Workout verified · 42 min at the gym".
//   Time Bank   the shared bar in a card.
//   badge       the occasional surprise, landing last.
//   Done        the blue CTA, tappable from the first frame.
//
// Timeline, from `onAppear`, all inside `Theme.Motion.unlockCelebrationMaxDuration` (1.2s):
//   0.00  charge 0.7 -> 1.0 (ease-in, 0.42s)
//   0.40  flash (0.75s linear, curves inside the stage), burst, one `.success` haptic
//   0.52  eyebrow, headline, figure and subline land on the celebration spring
//   0.66  figure/bar count up (0.5s), Time Bank card rises in, badge lands
// Reduce Motion: no delays, no burst, no shockwave; the resting frame appears with a short fade
// and the haptic still fires once.
//
// The resting frame is the full composition, so a still captured any time after ~1.2s (CI
// screenshots capture at ~5s) is the finished design.
//
// Presentation: `@Environment(\.dismiss)` for the Done button, which works for `.sheet`,
// `.fullScreenCover` or a push. A full-screen cover has no swipe-to-dismiss, so this button is the
// only way out and it never waits for the choreography.

import SwiftUI
import Core

/// The occasional bonus surprise this view can reveal alongside an unlock (docs/spec.md §8 rule 4:
/// "1 in ~6 unlocks... Keep it tasteful"). `title` should already be caller-resolved display copy
/// (e.g. via `Copy.badges.title(forKey:)` for a real `Badge.key` — `Core/Sources/Core/Copy/
/// TrophyCosmeticsCopy.swift`) — this type stores only what it needs to render, never a raw
/// `Badge.key` or the `Badge` model itself, so it carries no SwiftData dependency.
public struct UnlockCelebrationBadge: Equatable, Sendable {
    /// Caller-resolved display title, e.g. `"Comeback"`.
    public let title: String
    /// SF Symbol name. `"arrow.uturn.forward.circle.fill"` matches the icon
    /// `App/ZANO/Features/Progress/ProgressView.swift`'s `ProgressBadgeIconMap` already uses for a
    /// `"comeback"`-prefixed `Badge.key`, though any SF Symbol name is accepted for any other badge.
    /// Prefer the un-circled variant (`"arrow.uturn.forward"`): the badge is drawn inside its own
    /// capsule, so a circled glyph is a circle inside a pill.
    public let systemImage: String

    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}


/// The full unlock-celebration moment (docs/spec.md 16 P3). See the file header for the design,
/// the timeline and the presentation contract.
public struct UnlockCelebrationView: View {
    /// Caller-resolved display name for the goal that verified, e.g. `"Workout"`.
    private let goalName: String
    /// Caller-composed verification detail, e.g. `"42 min at the gym"`. Optional.
    private let verificationDetail: String?
    /// Minutes still available in today's Time Bank *after* this unlock. Same meaning as
    /// `TimeBankBar.remainingMinutes`.
    private let timeBankRemainingMinutes: Int
    /// Minutes earned today, total. Same meaning as `TimeBankBar.totalMinutes`.
    private let timeBankTotalMinutes: Int
    /// The occasional bonus surprise (spec 8 rule 4). `nil` most of the time.
    private let badge: UnlockCelebrationBadge?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The headline's size. Compressed heavy numeral face; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 76
    /// The Time Bank figure's size.
    @ScaledMetric(relativeTo: .title) private var figureSize: CGFloat = 40

    /// When the stage's timeline started; `nil` before `onAppear`.
    @State private var stageStart: Date?
    /// The stage has reached its resting frame; its timeline stops.
    @State private var stageSettled = false
    @State private var showBurst = false
    @State private var showHeadline = false
    @State private var showDetails = false
    @State private var showBadge = false
    @State private var animatedRemainingMinutes = 0
    @State private var unlockHapticTick = 0
    @State private var badgeHapticTick = 0
    @State private var hasPlayed = false
    @State private var playTask: Task<Void, Never>?

    /// - Parameters:
    ///   - goalName: Caller-resolved goal display name.
    ///   - verificationDetail: Caller-composed verification detail. Defaults to `nil`.
    ///   - timeBankRemainingMinutes: Today's Time Bank balance *after* this unlock.
    ///   - timeBankTotalMinutes: Today's Time Bank total earned (the bar's denominator).
    ///   - badge: An optional bonus badge reveal. Defaults to `nil`; pass one on roughly 1-in-6
    ///     unlocks per spec 8 rule 4, never on every unlock.
    public init(
        goalName: String,
        verificationDetail: String? = nil,
        timeBankRemainingMinutes: Int,
        timeBankTotalMinutes: Int,
        badge: UnlockCelebrationBadge? = nil
    ) {
        self.goalName = goalName
        self.verificationDetail = verificationDetail
        self.timeBankRemainingMinutes = timeBankRemainingMinutes
        self.timeBankTotalMinutes = timeBankTotalMinutes
        self.badge = badge
    }

    /// Full Mode has no Time Bank (spec 5.2), and callers pass `0`/`0` then. The figure and the
    /// bar are omitted rather than showing "0m" over an empty bar.
    private var hasTimeBank: Bool {
        timeBankTotalMinutes > 0 || timeBankRemainingMinutes > 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.md)

            stage

            textBlock
                .padding(.top, Theme.Spacing.sm)
                .opacity(showHeadline ? 1 : 0)
                .scaleEffect(showHeadline || reduceMotion ? 1 : 0.92)
                .offset(y: showHeadline || reduceMotion ? 0 : CelebrationLayout.riseOffset)

            if hasTimeBank {
                timeBankCard
                    .padding(.top, Theme.Spacing.lg)
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails || reduceMotion ? 0 : CelebrationLayout.riseOffset)
            }

            if let badge {
                badgePill(badge)
                    .padding(.top, Theme.Spacing.md)
                    .opacity(showBadge ? 1 : 0)
                    .scaleEffect(showBadge || reduceMotion ? 1 : 0.85)
            }

            Spacer(minLength: Theme.Spacing.lg)

            // Tappable from the first frame; never gated on the choreography.
            PrimaryButton(title: Copy.celebration.dismissButtonLabel, tint: .accent) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoAmbient(.earned)
        .sensoryFeedback(.success, trigger: unlockHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: badgeHapticTick)
        .onAppear { play() }
        .onDisappear { playTask?.cancel() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            if let stageStart, !stageSettled, !reduceMotion {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(stageStart)
                    UnlockStarStage(
                        charge: CelebrationTiming.charge(at: elapsed),
                        flash: CelebrationTiming.flash(at: elapsed)
                    )
                }
            } else {
                // Before the timeline starts: the star at its starting charge. After it settles,
                // or under Reduce Motion: the resting frame.
                let resting = stageSettled || reduceMotion
                UnlockStarStage(
                    charge: resting ? 1 : CelebrationTiming.startCharge,
                    flash: resting ? 1 : 0
                )
            }

            if showBurst && !reduceMotion {
                // Mounted at the flash so it fires once, from the star.
                CelebrationBurst(
                    trigger: 0,
                    colors: [Theme.Colors.accent, Theme.Colors.accent, Theme.Colors.text],
                    particleCount: 24
                )
                .frame(width: CelebrationLayout.burstFrame, height: CelebrationLayout.burstFrame)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: StageMetrics.stageHeight)
        .accessibilityHidden(true)
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(Copy.celebration.appsUnlockedEyebrow)
                .font(Theme.Typography.captionEmphasized)
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(Theme.Colors.accent)

            Text(Copy.celebration.headline)
                .font(Theme.Typography.numeral(size: headlineSize, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Theme.Colors.metallic)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)

            if hasTimeBank {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(
                        Duration.seconds(animatedRemainingMinutes * 60),
                        format: .units(allowed: [.hours, .minutes], width: .narrow)
                    )
                    .font(Theme.Typography.numeral(size: figureSize, weight: .heavy))
                    .foregroundStyle(Theme.Colors.accent)
                    .contentTransition(
                        reduceMotion ? .opacity : .numericText(value: Double(animatedRemainingMinutes))
                    )

                    Text(Copy.celebration.timeBankFigureCaption)
                        .font(Theme.Typography.unit)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // VoiceOver hears the final figure from the first frame, not the count-up.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.celebration.timeBankUnlockedLabel(minutes: timeBankRemainingMinutes))
            }

            Text(Copy.celebration.subline(goalName: goalName, detail: verificationDetail))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.xxs)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var timeBankCard: some View {
        TimeBankBar(
            remainingMinutes: animatedRemainingMinutes,
            totalMinutes: timeBankTotalMinutes,
            label: Copy.lockStatus.timeBankHeading
        )
        .padding(Theme.Spacing.md)
        .zanoCard()
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func badgePill(_ badge: UnlockCelebrationBadge) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: badge.systemImage)
                .font(Theme.Typography.icon(.small))
            Text(badge.title)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(Theme.Colors.onAccent)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.celebration.badgeRevealAccessibilityLabel(title: badge.title))
    }

    // MARK: - Choreography

    private func play() {
        // A cover that reappears (e.g. after a system alert) keeps its settled state.
        guard !hasPlayed else { return }
        hasPlayed = true

        if reduceMotion {
            playReduced()
            return
        }

        playTask?.cancel()
        stageStart = Date()
        playTask = Task { @MainActor in
            // 0.00: the stage's timeline charges the star (see `CelebrationTiming.charge(at:)`).

            // Flash: the stage's own timeline draws bloom, specular and shockwave; this adds the
            // burst and the haptic on the same beat.
            try? await Task.sleep(for: .milliseconds(CelebrationTiming.flashAtMs))
            guard !Task.isCancelled else { return }
            showBurst = true
            unlockHapticTick += 1

            // The words land.
            try? await Task.sleep(for: .milliseconds(CelebrationTiming.headlineAfterFlashMs))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.springCelebration) {
                showHeadline = true
            }

            // The figure counts up with the bar; the card and the badge follow.
            try? await Task.sleep(for: .milliseconds(CelebrationTiming.detailsAfterHeadlineMs))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: CelebrationTiming.countUpDuration)) {
                animatedRemainingMinutes = timeBankRemainingMinutes
            }
            withAnimation(Theme.Motion.springCelebration) {
                showDetails = true
                showBadge = badge != nil
            }
            if badge != nil { badgeHapticTick += 1 }

            // Stop the stage's timeline once the flash has finished; the resting frame is static.
            try? await Task.sleep(for: .milliseconds(CelebrationTiming.settleAfterDetailsMs))
            guard !Task.isCancelled else { return }
            stageSettled = true
        }
    }

    /// Reduce Motion: the resting frame, faded in. No burst, no shockwave, no scale.
    private func playReduced() {
        stageSettled = true
        unlockHapticTick += 1
        withAnimation(.easeOut(duration: 0.2)) {
            showHeadline = true
            showDetails = true
            showBadge = badge != nil
            animatedRemainingMinutes = timeBankRemainingMinutes
        }
    }
}

// MARK: - Local constants

/// The unlock timeline. Charge ends at 0.42s; the flash runs 0.40-1.15s; the words land at 0.52s;
/// the count-up runs 0.66-1.16s. All inside `Theme.Motion.unlockCelebrationMaxDuration` (1.2s).
private enum CelebrationTiming {
    static let startCharge: Double = 0.7
    static let chargeDuration: TimeInterval = 0.42
    static let flashAtMs = 400
    static let flashDuration: TimeInterval = 0.75
    static let headlineAfterFlashMs = 120
    static let detailsAfterHeadlineMs = 140
    static let countUpDuration: TimeInterval = 0.5
    /// 0.40 + 0.12 + 0.14 + 0.55 = 1.21s: just after the flash ends (1.15s).
    static let settleAfterDetailsMs = 550

    /// The star's charge `elapsed` seconds in: `startCharge` -> 1 on an ease-in, so it accelerates
    /// into the flash.
    static func charge(at elapsed: TimeInterval) -> Double {
        let p = min(1, max(0, elapsed / chargeDuration))
        return startCharge + (1 - startCharge) * p * p
    }

    /// Progress through the flash `elapsed` seconds in: 0 until `flashAtMs`, then linear to 1 over
    /// `flashDuration`. The stage shapes its own curves from it.
    static func flash(at elapsed: TimeInterval) -> Double {
        let start = Double(flashAtMs) / 1000
        return min(1, max(0, (elapsed - start) / flashDuration))
    }
}

private enum CelebrationLayout {
    /// The burst's frame, centred on the star so particles radiate from it.
    static let burstFrame: CGFloat = 320
    /// Upward travel of text and card as they land. Skipped under Reduce Motion.
    static let riseOffset: CGFloat = 18
}

#Preview("UnlockCelebrationView — with badge") {
    UnlockCelebrationView(
        goalName: "Workout",
        verificationDetail: "42 min at the gym",
        timeBankRemainingMinutes: 130,
        timeBankTotalMinutes: 180,
        badge: UnlockCelebrationBadge(title: "Comeback", systemImage: "arrow.uturn.forward")
    )
}

#Preview("UnlockCelebrationView — no badge") {
    UnlockCelebrationView(
        goalName: "Focus session",
        verificationDetail: "25 min focused",
        timeBankRemainingMinutes: 45,
        timeBankTotalMinutes: 60
    )
}

#Preview("UnlockCelebrationView — Full Mode (no Time Bank)") {
    UnlockCelebrationView(
        goalName: "Workout",
        verificationDetail: "42 min at the gym",
        timeBankRemainingMinutes: 0,
        timeBankTotalMinutes: 0
    )
}
