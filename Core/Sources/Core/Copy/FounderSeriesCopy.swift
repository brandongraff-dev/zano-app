// Core/Sources/Core/Copy/FounderSeriesCopy.swift
//
// docs/spec.md §5.22 Founder Series Inside the App: "A 'Building ZANO' feed card (optional)
// linking to your content. Founder-led brands win; make the founder visible without being
// annoying."
//
// `Core/Sources/Core/UI/Components/FounderSeriesCard.swift` (this same task) deliberately takes
// fully caller-composed strings, like every other file in `Core/UI/Components`
// (`PaywallCard`/`RecapCard`/`GhostProgressBanner` each document this same "views never compose
// their own sentence" discipline at their own declaration) — it does NOT read this enum directly.
// This file exists so whichever screen eventually wires the card in (explicitly flagged as a
// follow-up in `FounderSeriesCard.swift`'s own header — this task does not touch any
// `App/ZANO/Features` screen) has real, spec-sourced copy ready to pass in, rather than having to
// invent it ad hoc inline in a view file, which is exactly what CLAUDE.md's "no hardcoded
// user-facing strings in views" rule is meant to prevent.

import Foundation

extension Copy {
    public enum founderSeries {
        /// Matches spec §5.22's own example title verbatim: "A 'Building ZANO' feed card".
        public static let defaultHeadline = "Building ZANO"
        public static let defaultBody =
            "Follow along as we build ZANO — the wins, the bugs, and the hardware."
        /// "Watch", not "Follow" — spec's own product-catalog framing (§25) leans on video/UGC
        /// content (unboxing videos, gym-mirror content), so "Watch" reads as the more literal
        /// verb for "your content" than a generic "Follow". The label names its destination
        /// ("Watch the build log"), not a bare verb; caller can override entirely if the actual
        /// linked content (a specific video vs. a general profile) calls for different wording.
        public static let ctaLabel = "Watch the build log"
        public static let dismissAccessibilityLabel = "Dismiss"
    }
}
