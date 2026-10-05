// EarnedItClip.swift
// App / ZANO / Features / Share
//
// The "Earned It" clip (session 21, 2026-10-05; docs/spec.md §5.27): a 5-second vertical video of the
// shield opening after a verified goal, starring the user's own buddy, with the ZANO name on it, made
// on the phone and shared like any video. Built to be posted: the win is visible.
//
// Two parts:
//   * `EarnedItClipScene`: one 360 x 640 scene that is a pure function of `progress` (0...1), so any
//     frame can be drawn on its own. Three beats: LOCKED (the lock shakes, the buddy sleeps, the goal
//     fills), the burst (the lock opens, a ring and confetti fly out, the buddy lights up), and the
//     payoff (EARNED IT, the goal and day, the buddy celebrating, the wordmark).
//   * `EarnedItClipRenderer`: draws the scene frame by frame with `ImageRenderer` into an H.264 file
//     (720 x 1280, 24 fps) with AVAssetWriter. Nothing is uploaded; the file sits in the temp folder
//     until the share sheet is done with it.
//
// The scene has no timers or animations of its own, only `progress`, so a frame can't be caught
// mid-flight. Reduce Motion doesn't apply to a video the person chose to make.
//
// UNVERIFIED (no Mac/device): the AVAssetWriter and pixel-buffer path is the standard recipe written
// from memory; a real frame time (about 120 renders) and the H.264 output need a device.

import SwiftUI
import AVFoundation
import Core

// MARK: - Scene

struct EarnedItClipScene: View {
    let buddy: Buddy
    let goalName: String
    let streak: Int
    /// The goal's emotion once it is done (flexing for a workout, proud for water...); ecstatic when unknown.
    let doneGoal: GoalType?
    /// 0...1 over the whole clip.
    let progress: Double

    // Beat boundaries.
    private let burstStart = 0.30
    private let payoffStart = 0.45

    private var buddyColor: Color { buddy.color }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.14)
            glow
            if progress < payoffStart { lockedBeat }
            if progress >= burstStart - 0.02, progress < 0.70 { burst }
            if progress >= payoffStart { payoff }
            watermark
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    // MARK: Background

    private var glow: some View {
        let pulse = progress >= burstStart ? 1.0 : 0.55
        return RadialGradient(
            colors: [buddyColor.opacity(0.45 * pulse), buddyColor.opacity(0)],
            center: .center, startRadius: 10, endRadius: 280
        )
    }

    // MARK: Beat 1: locked

    private var lockedBeat: some View {
        let fill = min(1, max(0, (progress - 0.04) / (burstStart - 0.04)))
        let shake = sin(progress * 90) * 3 * (progress > 0.12 ? 1 : 0.4)
        return VStack(spacing: 22) {
            Text(Copy.clip.locked)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.9))
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 150, height: 150)
                Image(systemName: "lock.fill")
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(x: shake)
            BuddySprite(buddy, pose: .sleepy, size: 144, gear: nil)
            goalBar(fill: fill)
        }
        .offset(y: -10)
    }

    private func goalBar(fill: Double) -> some View {
        VStack(spacing: 8) {
            Text(goalName)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 220, height: 10)
                Capsule().fill(buddyColor).frame(width: 220 * fill, height: 10)
            }
        }
    }

    // MARK: Beat 2: burst

    private var burst: some View {
        let t = min(1, max(0, (progress - (burstStart - 0.02)) / 0.30))
        return ZStack {
            // The lock opens, pops and fades.
            Image(systemName: "lock.open.fill")
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(1 + 0.9 * t)
                .opacity(1 - t)
                .offset(y: -150)
            // A ring flies out.
            Circle()
                .strokeBorder(buddyColor, lineWidth: 10 * (1 - t) + 1)
                .frame(width: 60 + 560 * t, height: 60 + 560 * t)
                .opacity(1 - t)
            confetti(t: t)
        }
    }

    private func confetti(t: Double) -> some View {
        let colors: [Color] = [buddyColor, .white, Color(red: 1, green: 0.83, blue: 0.28), Color(red: 0.36, green: 0.78, blue: 0.96)]
        return ZStack {
            ForEach(0..<28, id: \.self) { index in
                let angle = Double(index) / 28 * 2 * .pi + Double(index % 5) * 0.21
                let speed = 140.0 + Double((index * 37) % 120)
                let distance = speed * t * 1.6
                let drop = 90.0 * t * t
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[index % colors.count])
                    .frame(width: 8, height: 14)
                    .rotationEffect(.degrees(Double(index) * 31 + t * 360))
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance + drop)
                    .opacity(1 - t * 0.9)
            }
        }
    }

    // MARK: Beat 3: payoff

    private var payoff: some View {
        let t = min(1, (progress - payoffStart) / 0.20)
        // A springy pop: overshoot, then settle.
        let pop = 1 + 0.18 * sin(t * .pi) * (1 - t) * 3 - (1 - t) * 0.4
        let hop = abs(sin(progress * 28)) * 14 * min(1, t * 2)
        return VStack(spacing: 18) {
            Text(Copy.clip.earnedIt)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(max(0.2, pop))
                .shadow(color: buddyColor.opacity(0.6), radius: 14)
            BuddySprite(buddy, pose: payoffPose, size: 192, gear: nil)
                .offset(y: -hop)
            VStack(spacing: 6) {
                Text(goalName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if streak > 0 {
                    Text(Copy.clip.streakLine(days: streak))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(buddyColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            .opacity(min(1, max(0, (t - 0.3) / 0.4)))
        }
        .offset(y: -20)
    }

    private var payoffPose: BuddyPose {
        // Big and happy first, then the goal's own emotion.
        guard progress > 0.62, let doneGoal else { return .ecstatic }
        return BuddyPose(goal: doneGoal, moment: .done)
    }

    // MARK: Watermark

    private var watermark: some View {
        VStack {
            Spacer()
            VStack(spacing: 2) {
                Text("zano")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(Copy.clip.tagline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            // Clear of the bottom band the Stories and Reels interfaces cover.
            .padding(.bottom, 96)
        }
    }
}

// MARK: - Renderer

enum EarnedItClipError: Error {
    case cannotStart
    case frameFailed
    case writeFailed
}

@MainActor
enum EarnedItClipRenderer {
    static let width = 720
    static let height = 1280
    static let framesPerSecond = 24
    static let seconds = 5

    /// Renders `scene(progress)` for every frame into an MP4 in the temp folder and returns its URL.
    /// `onProgress` gets 0...1. Throws if the file can't be written.
    static func render<Scene: View>(
        scene: (Double) -> Scene,
        onProgress: (Double) -> Void
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zano-earned-it-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(input) else { throw EarnedItClipError.cannotStart }
        writer.add(input)
        guard writer.startWriting() else { throw EarnedItClipError.cannotStart }
        writer.startSession(atSourceTime: .zero)

        let frames = framesPerSecond * seconds
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let progress = Double(index) / Double(frames - 1)
            let renderer = ImageRenderer(content: scene(progress).environment(\.colorScheme, .dark))
            renderer.scale = CGFloat(width) / 360
            guard let image = renderer.cgImage, let buffer = pixelBuffer(from: image) else {
                throw EarnedItClipError.frameFailed
            }
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond))
            guard adaptor.append(buffer, withPresentationTime: time) else { throw EarnedItClipError.writeFailed }
            onProgress(Double(index + 1) / Double(frames))
            await Task.yield()
        }
        input.markAsFinished()
        // The completion-handler form: the async overload "sends" the non-Sendable writer.
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed else { throw EarnedItClipError.writeFailed }
        return url
    }

    /// A BGRA pixel buffer holding `image`, scaled to the clip size.
    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
