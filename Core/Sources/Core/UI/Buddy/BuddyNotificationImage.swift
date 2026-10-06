// BuddyNotificationImage.swift
// Core / UI / Buddy
//
// The buddy as a local notification's image (buddy everywhere, 2026-10-03). A nudge shows the
// user's buddy, happy; a streak-at-risk nudge shows it sad; the trial reminder shows it content;
// the bedtime wind-down shows it sleepy. Lives in Core (not the app target) because every local
// notification is scheduled from Core (`NudgeScheduler`, `TrialReminder` through
// `NotificationPermission.scheduleOneShot`, `OnboardingDripScheduler`, `BedtimeGateManager`).
//
// The 48px sprite is scaled up 3x with no interpolation (144px, crisp) and written once per
// buddy and pose as a PNG in the caches directory. `UNNotificationAttachment` MOVES the file it is
// given into the system's attachment store when the request is added, so every attachment gets
// its own copy of the cached PNG in the temporary directory; the cached master stays put.
//
// Failures are silent: any error returns `nil` and the notification goes out with no image. This
// never throws and never blocks scheduling. Plain file work, no actor, safe from any isolation.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UserNotifications

public enum BuddyNotificationImage {
    /// Pixel scale: 48px x 3 = 144px.
    static let scale = 3

    /// An attachment showing `buddy` (the stored choice by default) in `pose`, or `nil` if the
    /// image couldn't be made. Attach with `content.attachments = [attachment]`.
    public static func attachment(pose: BuddyPose, buddy: Buddy = Buddy.stored) -> UNNotificationAttachment? {
        guard let master = cachedPNG(buddy: buddy, pose: pose) else { return nil }
        let fileManager = FileManager.default
        let copy = fileManager.temporaryDirectory
            .appendingPathComponent("buddy-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try fileManager.copyItem(at: master, to: copy)
            return try UNNotificationAttachment(
                identifier: "buddy",
                url: copy,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
            )
        } catch {
            try? fileManager.removeItem(at: copy)
            return nil
        }
    }

    /// The cached PNG for this buddy and pose, written on first use.
    static func cachedPNG(buddy: Buddy, pose: BuddyPose) -> URL? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("BuddyNotificationImages", isDirectory: true)
        let url = folder.appendingPathComponent("\(buddy.rawValue)-\(pose.rawValue)@\(scale)x.png")
        if fileManager.fileExists(atPath: url.path) { return url }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        guard let image = scaledImage(buddy.pixels(pose), scale: scale) else { return nil }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// The sprite scaled up by a whole number with nearest-neighbour sampling.
    static func scaledImage(_ pixels: BuddyPixels, scale: Int) -> CGImage? {
        guard let source = pixels.cgImage() else { return nil }
        let side = BuddyPixels.size * scale
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
