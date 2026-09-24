// Screen12PermissionPriming.swift
// App / Features / Onboarding
//
// docs/spec.md §7.12 "Permission priming": 'Notifications (one screen: "We'll only nudge when it
// matters"). Location and Health are requested later, at gym setup, not here.' This file
// deliberately requests ONLY notifications — no `CLLocationManager`/`HKHealthStore` calls belong
// here, matching that line exactly. (Family Controls authorization is Screen 4's job, priming Q2's
// app picker — also not this file's concern.)
//
// `UserNotifications` is a first-party framework, not UIKit, so this stays within CLAUDE.md's
// "No UIKit unless an Apple API requires it."
//
// Design pass (composition-audit scorecard for screen 12 — "Generic; show a mock notification
// instead of a bell", better-layout 3.2/6.2, better-ui HIT-02/MOT-08, typography-color C7): a
// bell glyph in a circle asks the user to trust an abstraction. Now the screen shows the thing
// itself: a stack of notification banners, the top one in the coach voice the user just picked on
// screen 8 (`CoachVoice.sampleLine`, the exact line the picker promised — so the priming previews
// a real nudge, not a placeholder). The banner drops in with a spring (static under Reduce
// Motion). "Not now" is a real 44pt target with room around it, the CTA sits in the shared pinned
// action bar, and the decorative accent icon is gone (accent stays for the CTA and the app tile).
// The preview is decorative, so VoiceOver skips it; the headline and subtitle carry the meaning.

import SwiftUI
import UserNotifications
import Core

@MainActor
struct Screen12PermissionPriming: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRequesting = false
    @State private var bannerShown = false

    /// Roughly the height of the live banner (icon row plus a two-line coach quote), so the
    /// ghosts behind it line up with its edges instead of peeking out at a different scale.
    private static let ghostBannerHeight: CGFloat = 76

    /// Reduce Motion shows the banner in place from the first frame.
    private var isBannerVisible: Bool {
        reduceMotion || bannerShown
    }

    var body: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                notificationPreview

                VStack(spacing: Theme.Spacing.sm) {
                    OnboardingKit.Eyebrow(text: Copy.onboarding.permissionEyebrow)
                    OnboardingKit.DisplayTitle(text: Copy.onboarding.permissionHeadline)
                    Text(Copy.onboarding.permissionSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background {
            OnboardingKit.Glow(tint: Theme.Colors.accent, opacity: 0.08)
        }
        .onboardingKitActionBar {
            PrimaryButton(
                title: Copy.onboarding.permissionAllowButton,
                isEnabled: !isRequesting
            ) {
                requestNotificationAuthorization()
            }

            Button {
                flowState.advance()
            } label: {
                Text(Copy.onboarding.permissionSkipButton)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.96))
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.springCelebration) { bannerShown = true }
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "permission_priming", "screen_number": 13]
            )
        }
    }

    // MARK: - Mock notification

    /// Two ghost banners behind the live one imply a stack of nudges without promising a number.
    private var notificationPreview: some View {
        ZStack(alignment: .top) {
            ghostBanner
                .scaleEffect(0.88)
                .offset(y: Theme.Spacing.lg)
                .opacity(0.35)
            ghostBanner
                .scaleEffect(0.94)
                .offset(y: Theme.Spacing.sm)
                .opacity(0.6)
            banner
                .offset(y: isBannerVisible ? 0 : -Theme.Spacing.xl)
                .opacity(isBannerVisible ? 1 : 0)
        }
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityHidden(true)
    }

    /// The edge of a notification banner peeking from behind the live one: an empty card, same
    /// recipe (`zanoCard`), no content, so it cannot say anything the live banner doesn't.
    private var ghostBanner: some View {
        Color.clear
            .frame(height: Self.ghostBannerHeight)
            .zanoCard()
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Stand-in for the app icon (the real one lives in the asset catalog, which this
            // screen doesn't own): an accent tile with a lock, `onFill` glyph on the accent (16:1).
            // A rounded square, not an `IconBadge` circle: it is impersonating an app icon.
            Image(systemName: "lock.fill")
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.onFill)
                .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                .background(
                    Theme.Colors.accent,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: OnboardingKit.icon(for: flowState.coachVoice))
                        .font(Theme.Typography.icon(.xsmall))
                        .foregroundStyle(Theme.Colors.muted)
                    Text(Copy.onboardingReveal.notificationPreviewAppName)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                }
                // The line the voice picker promised on screen 8, verbatim.
                Text(flowState.coachVoice.sampleLine)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(fill: Theme.Colors.surface2)
    }

    // MARK: - Authorization

    /// Advances the flow regardless of the system prompt's outcome (granted, denied, or already
    /// determined from a previous install): spec §8 rule 12 ("friction is the feature, but only
    /// where the user asked for it") — a denied notification permission is not a lock, so
    /// onboarding must never stall on it. `.badge`/`.sound`/`.alert` cover every nudge format spec
    /// §9.3's Nudge Optimizer can eventually send (push, one of its three delivery `NudgeFormat`s).
    private func requestNotificationAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isRequesting = false
            flowState.advance()
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen12PermissionPriming(flowState: flowState)
    }
}
