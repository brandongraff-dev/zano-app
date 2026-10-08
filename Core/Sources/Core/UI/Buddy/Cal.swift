// Cal.swift
// Core / UI / Buddy
//
// Cal, the calendar character (session 29): a friendly page-a-day calendar with a face, in the same
// pixel family as the buddies. It lives wherever the calendar does: the Today header's calendar button
// and the Planner. The art is generated (`scripts/buddies/cal.py`, written into `BuddySprites.swift`).

import SwiftUI

/// Cal's mood.
public enum CalPose: String, Sendable, CaseIterable {
    /// A plain day.
    case idle
    /// Everything for the day is done: a check mark on the header.
    case happy
    /// Nothing planned: eyes closed, a little "z".
    case sleepy
    /// Something is overdue: worried eyes and a "!".
    case alarm
}

/// Cal, pixel-crisp. Decorative.
public struct CalSprite: View {
    let pose: CalPose
    let size: CGFloat

    public init(_ pose: CalPose = .idle, size: CGFloat = 40) {
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = pose.pixels.cgImage() {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A small buddy in the navigation bar's trailing corner, doing something that suits the page
    /// (guarding on Lock, eating on Fuel, analysing on Progress, tinkering on Settings). Decorative.
    public func pageBuddy(_ pose: BuddyPose) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                StoredBuddySprite(pose: pose, size: 34)
            }
        }
    }
}
