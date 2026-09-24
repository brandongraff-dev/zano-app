// UnlockCelebrationView.swift
// App / Features / Celebration
//
// Owned by: this session's task (orchestrator batch, 2026-09-22; redesigned in the design-quality
// wave, 2026-09-23). Do not edit from another session — see CLAUDE.md "Stay strictly inside your
// assigned file list."
//
// docs/spec.md §16 P3 mockup, read verbatim before writing this file: "iPhone screen at the moment
// of earning apps back: burst of acid-green particles, headline 'Earned.', subline 'Workout
// verified · 42 min at the gym', a Time Bank bar filling to '2h 10m unlocked', small badge
// 'Comeback' appearing." Also docs/spec.md §8 rule 4 (variable reward): "1 in ~6 unlocks triggers a
// surprise (badge, coin bonus, milestone animation, coach voice line). Keep it tasteful." — the
// optional `badge` parameter below is exactly that occasional surprise; most calls should pass
// `nil` (see `badge`'s own doc comment).
//
// This is the *moment*, not a screen with its own navigation/data-fetching: it takes every piece
// of state it needs as plain, already-resolved init params (a goal display name, a verification
// detail string, a Time Bank balance, an optional badge) rather than reading `Goal`/`TimeBank`/
// `Badge` SwiftData models itself. That keeps it trivially presentable from anywhere (a `.sheet`/
// `.fullScreenCover` after a verifier/lock-engine call succeeds, a Live Activity tap-through, a
// Widget deep link, a Siri intent's completion). The public `init` is unchanged by the redesign, so
// `TodayView`'s call site is untouched.
//
// Composition, not duplication: reuses `Core/Sources/Core/UI/Components/TimeBankBar.swift` for the
// bar itself and `CelebrationBurst.swift` for the particle burst. Everything else is built from
// `Theme` tokens.
//
// Copy: every string is an existing key — `Copy.celebration.*` for the moment itself and
// `Copy.lockStatus.timeBankHeading` ("Time Bank") for the bar's caption. The reward figure is
// formatted by the system's `Duration` style rather than a hard-coded "2h 10m", so it localizes.
//
// Presentation: this view reads `@Environment(\.dismiss)` for its own "Nice" button, which SwiftUI
// resolves correctly whether the presenting screen shows this in a `.sheet`, a `.fullScreenCover`,
// or pushes it. A `.fullScreenCover` has no system swipe-to-dismiss, so this button is the only way
// out of that presentation style — required, not decorative — and it is tappable from the first
// frame: it never waits for the choreography (docs/design/competitive-research.md §3.4).
//
// DESIGN (design-quality wave). The previous version put a 44pt word ("Earned.") on a flat black
// screen and buried the actual reward, "2h 10m unlocked", in a 13pt label. The reward is the point
// of the moment, so the structure is now:
//
//   seal        a lock inside a ring. It starts locked and muted; at the unlock beat the glyph swaps
//               to an open lock in accent, the ring closes, the burst fires from the seal, and a
//               soft accent glow rises behind it. The product's core mechanic, literally.
//   "Earned."   the eyebrow, in accent.
//   "2h 10m"    the reward as the hero numeral (76pt, Dynamic-Type scaled), counting up.
//   subline     "Workout verified · 42 min at the gym".
//   Time Bank   the shared bar, in a card, captioned "Time Bank".
//   badge       the occasional surprise, landing last.
//
// Timeline (from `onAppear`; the whole thing stays inside `Theme.Motion.unlockCelebrationMaxDuration`,
// 1.2s): 0.25s lock is seen while the full-screen cover finishes sliding up -> unlock (glyph swap,
// ring close over 0.6s, burst, glow, "Earned.", one `.success` haptic) -> +0.12s reward count-up and
// bar fill -> +0.32s badge (if any). Under Reduce Motion there are no delays, no springs, no
// bounce and no rise: everything shows its final state with a short fade.
//
// Not done here, on purpose: a separate, longer milestone tier for streak days 7/30/100/365 (a
// number tick, week row and share button). That needs a spec note because it exceeds the 1.2s cap
// by being user-paced (competitive-research §3.2), and this view has no streak input.

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

/// The full unlock-celebration moment (docs/spec.md §16 P3). See the file header for why every
/// parameter is already-resolved plain data, and for the presentation contract.
public struct UnlockCelebrationView: View {
    /// Caller-resolved display name for the goal that verified, e.g. `"Workout"`. Not a
    /// `GoalType` — resolving a type to a display name is each caller's own job (e.g. an
    /// already-existing per-screen resolver such as `Copy.onboarding.planGoalTitle(for:)`), so
    /// this view stays decoupled from any one such resolver and from `Core.Models` entirely.
    private let goalName: String
    /// Caller-composed verification detail, e.g. `"42 min at the gym"` — spec §16 P3's own
    /// example. Optional: not every goal type has a detail worth showing.
    private let verificationDetail: String?
    /// Minutes still available in today's Time Bank *after* this unlock — the value the hero and
    /// the bar animate to. Same meaning as `TimeBankBar.remainingMinutes`
    /// (`Core/Sources/Core/UI/Components/TimeBankBar.swift`).
    private let timeBankRemainingMinutes: Int
    /// Minutes earned today, total — same meaning as `TimeBankBar.totalMinutes`.
    private let timeBankTotalMinutes: Int
    /// The occasional bonus surprise (spec §8 rule 4). `nil` most of the time — see that type's
    /// own doc comment.
    private let badge: UnlockCelebrationBadge?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero reward size. The reward is the entire point of this screen (docs/design/
    /// competitive-research.md §3.4: "the number is the reward; the word is the label"), so it is a
    /// notch above `Theme.Typography.numeralHero` (72pt, a fixed size) and scales with Dynamic Type.
    /// The face is still the shared numeral face (`Theme.Typography.numeral(size:weight:)`).
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 76

    @State private var isOpen = false
    @State private var sealProgress: Double = 0
    @State private var showBurst = false
    @State private var showHeadline = false
    @State private var animatedRemainingMinutes = 0
    @State private var showBadge = false
    @State private var bounceTick = 0
    @State private var unlockHapticTick = 0
    @State private var badgeHapticTick = 0
    @State private var playTask: Task<Void, Never>?

    /// - Parameters:
    ///   - goalName: Caller-resolved goal display name (see the property doc above).
    ///   - verificationDetail: Caller-composed verification detail. Defaults to `nil`.
    ///   - timeBankRemainingMinutes: Today's Time Bank balance *after* this unlock.
    ///   - timeBankTotalMinutes: Today's Time Bank total earned (the bar's denominator).
    ///   - badge: An optional bonus badge reveal. Defaults to `nil` — pass one on roughly 1-in-6
    ///     unlocks per spec §8 rule 4, never on every unlock.
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

    /// Full Mode has no Time Bank (spec §5.2: the bank only exists in Earn Mode), and `TodayView`
    /// passes `0`/`0` when there is none. Showing "Earned. 0m" over an empty bar would be wrong, so
    /// the reward hero and the bar are simply omitted in that case.
    private var hasTimeBank: Bool {
        timeBankTotalMinutes > 0 || timeBankRemainingMinutes > 0
    }

    public var body: some View {
        // `lg` (24), not `xl`: on a 667pt-tall phone with a badge present the stack is ~670pt at
        // `xl` and would clip; `lg` keeps it inside the screen with room for the spacers.
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.md)

            sealStack

            rewardBlock
                .opacity(showHeadline ? 1 : 0)
                .offset(y: showHeadline || reduceMotion ? 0 : CelebrationMetrics.riseOffset)

            if hasTimeBank {
                timeBankCard
                    .opacity(showHeadline ? 1 : 0)
            }

            if let badge {
                badgePill(badge)
                    .opacity(showBadge ? 1 : 0)
                    .scaleEffect(showBadge || reduceMotion ? 1 : 0.9)
            }

            Spacer(minLength: Theme.Spacing.lg)

            // The one CTA in the app that is itself the reward moment, so it wears the accent.
            PrimaryButton(title: Copy.celebration.dismissButtonLabel, tint: .accent) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: unlockHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: badgeHapticTick)
        .onAppear { play() }
        .onDisappear { playTask?.cancel() }
        // Fixed, dark-only design system. This full-screen cover used to set the scheme only inside
        // `#Preview`, so it depended on the presenter's scheme (typography-color-findings C11).
        .preferredColorScheme(.dark)
    }

    // MARK: - Seal

    /// A lock inside a ring, with the burst and glow behind it. Everything the unlock moment does
    /// visually originates here.
    private var sealStack: some View {
        ZStack {
            if showBurst {
                // Mounted at the unlock beat (not at appear) so the burst fires exactly once, from
                // the moment the lock opens. It handles Reduce Motion itself (in-place cross-fade).
                CelebrationBurst(trigger: 0)
                    .frame(width: CelebrationMetrics.burstFrame, height: CelebrationMetrics.burstFrame)
            }

            seal
        }
        .background {
            // Static radial glow; only its opacity changes, once, at the unlock beat. No animated
            // blur or radius (HIG Reduce Motion guidance). Being a `background` it never affects
            // layout, so it can be far larger than the seal.
            RadialGradient(
                colors: [Theme.Colors.accent.opacity(0.18), Theme.Colors.accent.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: CelebrationMetrics.glowRadius
            )
            .frame(width: CelebrationMetrics.glowRadius * 2, height: CelebrationMetrics.glowRadius * 2)
            .opacity(isOpen ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: isOpen)
        }
        .accessibilityHidden(true)
    }

    private var seal: some View {
        ZStack {
            // The ring's own-hue track (`Ring.track(for:)`, accent at 30%), the same empty ring every
            // `GoalRing` draws, so the seal reads as a ring about to close and not a faint smudge.
            Circle()
                .stroke(Theme.Colors.Ring.track(for: Theme.Colors.accent), lineWidth: CelebrationMetrics.sealLine)

            Circle()
                .trim(from: 0, to: sealProgress)
                .stroke(
                    Theme.Colors.accent,
                    style: StrokeStyle(lineWidth: CelebrationMetrics.sealLine, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Theme.Colors.surface)
                .padding(CelebrationMetrics.sealLine + Theme.Spacing.xs)

            Image(systemName: isOpen ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(isOpen ? Theme.Colors.accent : Theme.Colors.muted)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounceTick)
        }
        .frame(width: CelebrationMetrics.sealDiameter, height: CelebrationMetrics.sealDiameter)
    }

    // MARK: - Reward

    private var rewardBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Copy.celebration.headline)
                // `Theme.Colors.accent`'s own doc comment: "Reserve for primary CTAs, the workout
                // ring, and unlock/earned states" — this eyebrow is exactly that third case. With a
                // time-bank hero above the fold it is the label; without one it is the headline.
                .font(hasTimeBank ? Theme.Typography.numeralMedium() : Theme.Typography.numeralLarge())
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityAddTraits(.isHeader)

            if hasTimeBank {
                Text(Duration.seconds(animatedRemainingMinutes * 60), format: .units(allowed: [.hours, .minutes], width: .narrow))
                    .font(Theme.Typography.numeral(size: heroSize, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(Theme.Colors.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(animatedRemainingMinutes)))
                    // VoiceOver hears the final figure ("2h 10m unlocked") from the first frame
                    // instead of every intermediate value of the count-up.
                    .accessibilityLabel(Copy.celebration.timeBankUnlockedLabel(minutes: timeBankRemainingMinutes))
            }

            Text(Copy.celebration.subline(goalName: goalName, detail: verificationDetail))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.xs)
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
                .font(.system(size: 12, weight: .semibold))
            Text(badge.title)
                .font(Theme.Typography.captionEmphasized)
        }
        // `onFill`: the one label color for anything drawn on an accent fill (16.4:1).
        .foregroundStyle(Theme.Colors.onFill)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.celebration.badgeRevealAccessibilityLabel(title: badge.title))
    }

    // MARK: - Choreography

    /// Stages the lock -> unlock beat -> reward -> badge so the "surprise" (when present) lands
    /// last, per spec §8 rule 4's "tasteful" framing, rather than dumping everything on screen at
    /// once. Skips the staggered delays under Reduce Motion (`stageDelay` below) so that preference
    /// speeds up *when* information appears, not just how it animates in, and swaps every spring for
    /// a short ease. Nothing here gates the dismiss button.
    private func play() {
        playTask?.cancel()
        playTask = Task { @MainActor in
            // The lock is on screen (locked, muted) while the full-screen cover finishes sliding
            // up, so the swap that follows is actually seen.
            try? await stageDelay(milliseconds: 250)
            guard !Task.isCancelled else { return }

            // Unlock beat: glyph swap, ring close, burst, glow, "Earned.", one haptic.
            showBurst = true
            unlockHapticTick += 1
            if !reduceMotion { bounceTick += 1 }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springCelebration) {
                isOpen = true
                showHeadline = true
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill) {
                sealProgress = 1
            }

            // Reward: the hero figure and the bar count up together.
            try? await stageDelay(milliseconds: 120)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill) {
                animatedRemainingMinutes = timeBankRemainingMinutes
            }

            guard badge != nil else { return }
            try? await stageDelay(milliseconds: 320)
            guard !Task.isCancelled else { return }
            badgeHapticTick += 1
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springCelebration) {
                showBadge = true
            }
        }
    }

    private func stageDelay(milliseconds: Int) async throws {
        guard !reduceMotion else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

// MARK: - Local design constants
//
// Sizes specific to this moment's artwork (the seal, the burst frame, the glow) with no
// `Theme.Metrics` home. The Time Bank card is the shared `zanoCard` (review pass: it used to be a
// private `CelebrationCardSurface` with its own edge recipe, written before `zanoCard` existed).

private enum CelebrationMetrics {
    static let sealDiameter: CGFloat = 132
    static let sealLine: CGFloat = 8
    /// The burst's frame, centred on the seal so particles radiate from it.
    static let burstFrame: CGFloat = 280
    static let glowRadius: CGFloat = 300
    /// Upward travel of the reward block as it fades in. Skipped under Reduce Motion.
    static let riseOffset: CGFloat = 12
}

#Preview("UnlockCelebrationView — with badge") {
    UnlockCelebrationView(
        goalName: "Workout",
        verificationDetail: "42 min at the gym",
        timeBankRemainingMinutes: 130,
        timeBankTotalMinutes: 180,
        badge: UnlockCelebrationBadge(title: "Comeback", systemImage: "arrow.uturn.forward")
    )
    .preferredColorScheme(.dark)
}

#Preview("UnlockCelebrationView — no badge") {
    UnlockCelebrationView(
        goalName: "Focus session",
        verificationDetail: "25 min focused",
        timeBankRemainingMinutes: 45,
        timeBankTotalMinutes: 60
    )
    .preferredColorScheme(.dark)
}

#Preview("UnlockCelebrationView — Full Mode (no Time Bank)") {
    UnlockCelebrationView(
        goalName: "Workout",
        verificationDetail: "42 min at the gym",
        timeBankRemainingMinutes: 0,
        timeBankTotalMinutes: 0
    )
    .preferredColorScheme(.dark)
}
