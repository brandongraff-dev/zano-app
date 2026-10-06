// EarnedItClipView.swift
// App / ZANO / Features / Share
//
// The sheet behind "Make my Earned It clip" (session 21; docs/spec.md §5.27): makes the 5-second clip
// on the phone (a progress bar while it renders), plays it back on a loop, and offers the share sheet.
// Nothing is uploaded; the file lives in the temp folder.

import SwiftUI
import AVKit
import Core

struct EarnedItClipView: View {
    let goalName: String
    let doneGoal: GoalType?

    @State private var phase: Phase = .making(0)
    @State private var player: AVQueuePlayer?
    /// Kept alive so the clip keeps looping.
    @State private var looper: AVPlayerLooper?
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case making(Double)
        case ready(URL)
        case failed
    }

    private var buddy: Buddy { Buddy.stored }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(Copy.clip.sheetTitle)
                .zanoText(.display)
                .foregroundStyle(Theme.Colors.text)
            content
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoBackdrop(glow: buddy.color)
        .task(id: attempt) { await make() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .making(let progress):
            VStack(spacing: Theme.Spacing.sm) {
                StoredBuddySprite(pose: .excited, size: 96)
                SwiftUI.ProgressView(value: progress)
                    .tint(buddy.color)
                Text(Copy.clip.making)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .padding(.top, Theme.Spacing.xl)
        case .ready(let url):
            VStack(spacing: Theme.Spacing.md) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                        .frame(maxHeight: 460)
                }
                ShareLink(item: url, message: Text(Copy.clip.shareMessage), preview: SharePreview(Copy.clip.previewTitle)) {
                    Label(Copy.clip.shareButton, systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                        .background(Capsule().fill(Theme.Colors.accentFill))
                }
                .buttonStyle(.pressable)
                Button(Copy.clip.doneButton) { dismiss() }
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.muted)
            }
        case .failed:
            VStack(spacing: Theme.Spacing.sm) {
                StoredBuddySprite(pose: .sad, size: 96)
                Text(Copy.clip.failed)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                PrimaryButton(title: Copy.clip.retry) { phase = .making(0); attempt += 1 }
            }
            .padding(.top, Theme.Spacing.xl)
        }
    }

    private func make() async {
        let buddy = self.buddy
        let streak = SharedDefaults.currentStreak
        do {
            let url = try await EarnedItClipRenderer.render(
                scene: { progress in
                    EarnedItClipScene(buddy: buddy, goalName: goalName, streak: streak, doneGoal: doneGoal, progress: progress)
                },
                onProgress: { phase = .making($0) }
            )
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            phase = .ready(url)
            queue.play()
        } catch {
            phase = .failed
        }
    }
}

#Preview {
    EarnedItClipView(goalName: "Gym session", doneGoal: .workoutGym)
        .preferredColorScheme(.dark)
}
