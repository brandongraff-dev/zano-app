// UnlockCelebrationView.swift
// App / Features / Celebration
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
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
// Widget deep link, a Siri intent's completion) without this file needing a `ModelContext`, or
// needing to know which verifier/engine produced the unlock — the presenting screen resolves that
// once and hands this view plain values. This mirrors `RecapCard`/`ShareCard`
// (`Core/Sources/Core/UI/Components`, both read in full before writing this file), which each take
// plain data rather than their SwiftData model directly for the same reason.
//
// Composition, not duplication: reuses `Core/Sources/Core/UI/Components/TimeBankBar.swift` for the
// bar itself (per this task's brief: "reuse it, do not rebuild a second bar") and this task's other
// owned file, `Core/Sources/Core/UI/Components/CelebrationBurst.swift`, for the particle burst.
// Every other visual (headline, subline, badge pill, dismiss button) is built from `Theme` tokens
// directly, the same way `ShieldPreview.swift` (same Core/UI/Components directory, read in full for
// precedent) composes its own full-screen "moment" from tokens plus one reused button component.
//
// New Copy area: `Copy.celebration` (`Core/Sources/Core/Copy/CelebrationCopy.swift`, this task's
// own addition — see that file's header for why building it here, rather than just assuming it for
// a future session, is the right call for this batch).
//
// Presentation: this view reads `@Environment(\.dismiss)` for its own "Nice" button, which SwiftUI
// resolves correctly whether the presenting screen shows this in a `.sheet`, a `.fullScreenCover`,
// or pushes it — no `onDismiss` closure needed in the public init, keeping it to exactly the params
// this task's brief asks for ("goal name / Time Bank state / optional badge"). A `.fullScreenCover`
// has no system swipe-to-dismiss, so this button is the only way out of that presentation style —
// required, not decorative, the same reasoning `ShieldPreview`'s always-present emergency action
// uses (see that file), even though this screen is a celebration, not a lock.

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
    /// `"comeback"`-prefixed `Badge.key` — worth reusing verbatim for a caller passing that exact
    /// badge, though any SF Symbol name is accepted for any other badge.
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
    /// Minutes still available in today's Time Bank *after* this unlock — the value the bar
    /// animates to. Same meaning as `TimeBankBar.remainingMinutes`
    /// (`Core/Sources/Core/UI/Components/TimeBankBar.swift`).
    private let timeBankRemainingMinutes: Int
    /// Minutes earned today, total — same meaning as `TimeBankBar.totalMinutes`.
    private let timeBankTotalMinutes: Int
    /// The occasional bonus surprise (spec §8 rule 4). `nil` most of the time — see that type's
    /// own doc comment.
    private let badge: UnlockCelebrationBadge?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var burstTrigger = 0
    @State private var showHeadline = false
    @State private var animatedRemainingMinutes = 0
    @State private var showBadge = false
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

    public var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            ZStack {
                CelebrationBurst(trigger: burstTrigger)
                    .frame(width: 280, height: 280)

                headlineBlock
                    .opacity(showHeadline ? 1 : 0)
                    .scaleEffect(showHeadline ? 1 : 0.86)
            }

            timeBankSection
                .opacity(showHeadline ? 1 : 0)

            if let badge {
                badgePill(badge)
                    .opacity(showBadge ? 1 : 0)
                    .scaleEffect(showBadge ? 1 : 0.7)
            }

            Spacer(minLength: Theme.Spacing.xl)

            PrimaryButton(title: Copy.celebration.dismissButtonLabel) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .sensoryFeedback(.success, trigger: unlockHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: badgeHapticTick)
        .onAppear { play() }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: - Sections

    private var headlineBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Copy.celebration.headline)
                .font(Theme.Typography.numeralLarge())
                // `Theme.Colors.accent`'s own doc comment: "Reserve for primary CTAs, the workout
                // ring, and unlock/earned states" — this headline is exactly that third case.
                .foregroundStyle(Theme.Colors.accent)

            Text(Copy.celebration.subline(goalName: goalName, detail: verificationDetail))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var timeBankSection: some View {
        TimeBankBar(
            remainingMinutes: animatedRemainingMinutes,
            totalMinutes: timeBankTotalMinutes,
            label: Copy.celebration.timeBankUnlockedLabel(minutes: timeBankRemainingMinutes)
        )
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private func badgePill(_ badge: UnlockCelebrationBadge) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: badge.systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(badge.title)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(Theme.Colors.background)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.celebration.badgeRevealAccessibilityLabel(title: badge.title))
    }

    // MARK: - Choreography

    /// Stages burst → headline/Time-Bank fill → badge reveal so the "surprise" (when present)
    /// lands last, per spec §8 rule 4's "tasteful" framing, rather than dumping everything on
    /// screen at once. Skips the staggered delays under Reduce Motion (`stageDelay` below) so that
    /// preference speeds up *when* information appears, not just how it animates in.
    private func play() {
        playTask?.cancel()
        playTask = Task { @MainActor in
            burstTrigger += 1
            unlockHapticTick += 1

            withAnimation(Theme.Motion.springCelebration) {
                showHeadline = true
            }

            try? await stageDelay(milliseconds: 220)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.ringFill) {
                animatedRemainingMinutes = timeBankRemainingMinutes
            }

            guard badge != nil else { return }
            try? await stageDelay(milliseconds: 520)
            guard !Task.isCancelled else { return }
            badgeHapticTick += 1
            withAnimation(Theme.Motion.springCelebration) {
                showBadge = true
            }
        }
    }

    private func stageDelay(milliseconds: Int) async throws {
        guard !reduceMotion else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

#Preview("UnlockCelebrationView — with badge") {
    UnlockCelebrationView(
        goalName: "Workout",
        verificationDetail: "42 min at the gym",
        timeBankRemainingMinutes: 130,
        timeBankTotalMinutes: 180,
        badge: UnlockCelebrationBadge(title: "Comeback", systemImage: "arrow.uturn.forward.circle.fill")
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
