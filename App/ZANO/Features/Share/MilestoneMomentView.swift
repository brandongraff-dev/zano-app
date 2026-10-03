// MilestoneMomentView.swift
// App / ZANO / Features / Share
//
// The full-screen milestone moment (`MilestoneEngine`, `Core/Sources/Core/Retention/Milestones.swift`):
// a short reveal (the star blooms, then the card rises into place), the 9:16 card, the coach's line
// in the user's voice, a Share action that hands the rendered 1080 x 1920 image (plus a short text
// that names ZANO) to the share sheet, and "Not now".
//
// Presented by `MilestonePresenter` (`.zanoMilestoneMoments()`), at most once per app session and
// never over onboarding or the unlock celebration. A `.monthlyStory` milestone is shown by
// `MonthlyStoryView` instead.
//
// Rendering follows `LockedOutMomentView`: the poster `SharePosterRenderer` rasterizes is a separate,
// untransformed instance, so the reveal animation can never be captured mid-flight; a render failure
// becomes a tap-to-retry state instead of an endless "Preparing…".
//
// Copy: `Copy.milestone.*`, `Copy.share.*`. No user-facing string is composed here.

import SwiftUI
import Core

struct MilestoneMomentView: View {
    let milestone: Milestone
    let onDismiss: () -> Void

    @State private var renderedImage: UIImage?
    @State private var shareRenderFailed = false
    @State private var renderAttempt = 0
    /// Reveal phases: the star burst, then the card.
    @State private var burstStarted = false
    @State private var cardAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    init(milestone: Milestone, onDismiss: @escaping () -> Void) {
        self.milestone = milestone
        self.onDismiss = onDismiss
    }

    private var content: MilestoneCardContent { MilestoneCardContent(milestone: milestone) }
    private var poster: MilestoneCardView { MilestoneCardView(content: content) }
    private var voice: CoachVoice { CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice) }

    var body: some View {
        VStack(spacing: 0) {
            ZanoGlassChip(Copy.milestone.momentHeadline, systemImage: "trophy.fill", tint: content.hue.color)
                .padding(.top, Theme.Spacing.md)
                .opacity(cardAppeared ? 1 : 0)
                .accessibilityAddTraits(.isHeader)

            ZStack {
                burst
                // Slapped on like a sticker: in big and tilted, landing square.
                SharePosterPreview(poster: poster)
                    .scaleEffect(reduceMotion || cardAppeared ? 1 : 1.15)
                    .rotationEffect(.degrees(reduceMotion || cardAppeared ? 0 : -8))
                    .opacity(cardAppeared ? 1 : 0)
                if cardAppeared && !reduceMotion {
                    // Confetti in the milestone's colours as the card lands; fires once on mount.
                    CelebrationBurst(trigger: 0, colors: content.hue.sprinkles, particleCount: 36)
                        .frame(width: 340, height: 340)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoBackdrop()
        .zanoActionBar {
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.milestone.coachLine(for: milestone, voice: voice))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                shareAction
                Button(action: onDismiss) {
                    Text(Copy.milestone.notNowLabel)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .task(id: renderAttempt) {
            guard renderedImage == nil else { return }
            shareRenderFailed = false
            if let image = await SharePosterRenderer.image(of: poster) {
                renderedImage = image
            } else {
                shareRenderFailed = true
            }
        }
        .onAppear(perform: reveal)
        .sensoryFeedback(.success, trigger: cardAppeared) { _, newValue in newValue }
        .preferredColorScheme(.dark)
    }

    // MARK: - Reveal

    /// The user's buddy (the star until 2026-10-03) blooms out of the dark and fades as the card
    /// rises into its place. Reduce Motion: no burst, the card simply fades in.
    @ViewBuilder
    private var burst: some View {
        if !reduceMotion {
            BuddySprite(buddy, pose: .ecstatic, size: 96)
                .background {
                    RadialGradient(
                        colors: [content.hue.color.opacity(0.8), content.hue.color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                    .frame(width: 320, height: 320)
                }
                .scaleEffect(burstStarted ? (cardAppeared ? 2.4 : 1.1) : 0.3)
                .opacity(burstStarted && !cardAppeared ? 1 : 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func reveal() {
        guard !cardAppeared else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { cardAppeared = true }
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { burstStarted = true }
        // A real beat, not `.delay`: `cardAppeared` also mounts the confetti, which must fire as
        // the card lands, not when the state flips.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) { cardAppeared = true }
        }
    }

    // MARK: - Share

    @ViewBuilder
    private var shareAction: some View {
        Group {
            switch shareRenderState {
            case .ready:
                if let renderedImage {
                    ShareLink(
                        item: Image(uiImage: renderedImage),
                        message: Text(Copy.milestone.shareMessage(for: milestone)),
                        preview: SharePreview(
                            Copy.milestone.sharePreviewTitle(for: milestone),
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        ShareActionLabel(state: .ready)
                    }
                    .buttonStyle(.pressable)
                    .simultaneousGesture(TapGesture().onEnded {
                        Analytics.shared.capture(event: "milestone_share_tapped", properties: ["milestone": milestone.id])
                    })
                    .transition(.opacity)
                }
            case .failed:
                Button {
                    renderedImage = nil
                    shareRenderFailed = false
                    renderAttempt += 1
                } label: {
                    ShareActionLabel(state: .failed)
                }
                .buttonStyle(.pressable)
                .transition(.opacity)
            case .preparing:
                ShareActionLabel(state: .preparing)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard, value: shareRenderState)
    }

    private var shareRenderState: ShareRenderState {
        if renderedImage != nil { return .ready }
        if shareRenderFailed { return .failed }
        return .preparing
    }
}

#Preview {
    MilestoneMomentView(milestone: .streak(days: 30), onDismiss: {})
}
