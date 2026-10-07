// StravaCopy.swift
// Core / Copy
//
// Display copy for the direct Strava link (session 40; docs/spec.md §3 "Workout (home/outdoor)", §9.8
// "never accuse — just don't count, and show 'not counted' transparently"). Plain and calm like the other
// Settings screens. "Connect with Strava" and "Powered by Strava" are Strava's own required wording (brand
// guidelines); keep them exactly.

import Foundation

extension Copy {
    public enum strava {
        public static let rowLabel = "Strava"
        public static let rowValueConnected = "Connected"
        public static let screenTitle = "Strava"
        public static let intro = "Connect Strava and a workout you record there counts toward your workout goal, even if it never reaches Apple Health."

        /// Strava's required button wording.
        public static let connectButton = "Connect with Strava"
        /// Strava's required attribution wording.
        public static let poweredBy = "Powered by Strava"

        public static let connectedTitle = "Connected to Strava"
        public static func connectedAs(_ firstName: String) -> String { "Connected as \(firstName)" }
        public static func lastChecked(_ relative: String) -> String { "Last checked \(relative)" }
        public static let neverChecked = "Not checked yet"
        public static let checkNow = "Check for new workouts"

        public static let howItCounts = "A recorded activity of 20 minutes or more counts, using its moving time. If the same workout is also in Apple Health, it counts once."
        public static let privacyNote = "ZANO reads when your activities started, how long they lasted and your heart rate. It never posts to Strava, and your activities aren't kept on ZANO's servers."

        /// The transparent "not counted" line (§9.8). Never an accusation.
        public static func notCountedEnteredByHand(_ count: Int) -> String {
            count == 1
                ? "1 workout typed in by hand on Strava wasn't counted. Workouts recorded with a watch or the Strava app count."
                : "\(count) workouts typed in by hand on Strava weren't counted. Workouts recorded with a watch or the Strava app count."
        }

        public static let disconnect = "Disconnect Strava"
        public static let disconnectConfirmTitle = "Disconnect Strava?"
        public static let disconnectConfirmMessage = "New Strava workouts stop counting. Workouts already counted stay counted."
        public static let disconnectConfirmButton = "Disconnect"

        // Errors
        public static let errorTitle = "Strava"
        public static let errorScopeMissing = "Strava didn't share your activities. Connect again and leave activity access ticked."
        public static let errorRateLimited = "Strava is busy right now. Try again in a few minutes."
        public static let errorFailed = "Couldn't reach Strava. Try again in a moment."
        public static let errorNotLinked = "Strava is no longer connected. Connect again to keep counting Strava workouts."
    }
}
