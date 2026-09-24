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
//
// Premium pass (2026-09-24): the preview is now a small lock screen — today's real date and time in
// the condensed numeral face, with the nudge arriving underneath it as an iOS banner looks (app icon,
// bold app name, "now", message) and two older banners stacked behind it. That fills the top half
// with the thing being asked about instead of a void, and puts the ask (headline, then the pinned
// Allow / Not now) in the bottom half. The mock app icon mirrors the real one (a "Z" on near-black).
// The redundant "Stay in the loop" eyebrow is gone: the headline already says it. This is screen 13
// in the flow order (after the paywall, decision 2026-09-23); the file keeps its old name.

import SwiftUI
import UserNotifications
import Core

@MainActor
struct Screen12PermissionPriming: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRequesting = false
    @State private var bannerShown = false
    /// Frozen when the screen opens so the mock clock doesn't tick under the user.
    @State private var openedAt = Date.now

    /// The mock app icon: a touch smaller than a list badge, as on a real banner.
    private static let appIconSide: CGFloat = 38
    /// The lock-screen clock: large and compressed, like the real one.
    private static let clockSize: CGFloat = 72

    /// Reduce Motion shows the banner in place from the first frame.
    private var isBannerVisible: Bool {
        reduceMotion || bannerShown
    }

    var body: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                lockScreenPreview

                VStack(spacing: Theme.Spacing.sm) {
                    OnboardingKit.DisplayTitle(text: Copy.onboarding.permissionHeadline)
                    Text(Copy.onboarding.permissionSubtitle)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .zanoAmbient(.neutral)
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
            try? await Task.sleep(for: .milliseconds(350))
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

    // MARK: - Mock lock screen

    /// Date, clock, and the notification stack: a lock screen in miniature. Decorative.
    private var lockScreenPreview: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: 0) {
                Text(openedAt, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(openedAt, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(Theme.Typography.numeral(size: Self.clockSize, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            notificationStack
        }
        .padding(.top, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .zanoHero()
        .accessibilityHidden(true)
    }

    /// The live banner with two older ones peeking out beneath it, as iOS stacks them.
    private var notificationStack: some View {
        ZStack(alignment: .top) {
            ghostBanner
                .scaleEffect(x: 0.86, y: 1, anchor: .bottom)
                .offset(y: Theme.Spacing.md)
                .opacity(0.35)
            ghostBanner
                .scaleEffect(x: 0.93, y: 1, anchor: .bottom)
                .offset(y: Theme.Spacing.xs)
                .opacity(0.6)
            banner
                .offset(y: isBannerVisible ? 0 : -Theme.Spacing.xl)
                .opacity(isBannerVisible ? 1 : 0)
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    /// A banner-shaped plate with no content, so it cannot say anything the live banner doesn't.
    /// Matches the live banner's height by holding the same content invisibly.
    private var ghostBanner: some View {
        bannerContent
            .hidden()
            .bannerPlate()
    }

    private var banner: some View {
        bannerContent
            .bannerPlate()
    }

    /// iOS's banner layout: app icon, then a bold title with the time on the trailing edge, then
    /// the message. The message is the line the voice picker promised on screen 8, verbatim.
    private var bannerContent: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            appIcon

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs / 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(Copy.onboardingReveal.notificationPreviewAppName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(Copy.onboardingReveal.notificationPreviewTime)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                Text(flowState.coachVoice.sampleLine)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The real app icon, drawn from the same vector as the asset (docs/brand/brand-kit.md): the
    /// silver mark on near-black, with the edge iOS draws around a dark icon.
    private var appIcon: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small * 0.75, style: .continuous)
        return ZanoMark(height: Self.appIconSide * 0.4)
            .frame(width: Self.appIconSide, height: Self.appIconSide)
            .background(Theme.Colors.background, in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
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

private extension View {
    /// The banner's plate: a lighter-than-card rounded rect with the shared top-lit edge, like the
    /// translucent grey of a real notification over a dark wallpaper.
    func bannerPlate() -> some View {
        zanoCard(radius: Theme.Radius.medium, fill: Theme.Colors.surface2)
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen12PermissionPriming(flowState: flowState)
    }
}
