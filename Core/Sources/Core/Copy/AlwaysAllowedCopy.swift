// AlwaysAllowedCopy.swift
// Core / Copy
//
// `Copy.alwaysAllowed` — every user-facing string for `AlwaysAllowedWarningView`
// (App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift) and the check it renders
// (`Core/Sources/Core/LockEngine/AlwaysAllowedCheck.swift`) — both this same task's owned files.
// Follows the `Copy.<area>` umbrella pattern `Copy.swift` / `OnboardingCopy.swift` establish: a
// nested enum added via its own `extension Copy { ... }` in its own file, never a flat standalone
// enum. `Copy.swift`'s own header explains why: independent sessions must be able to add a new
// area without editing this file or any other area's file — this file only adds `Copy.
// alwaysAllowed`; it touches nothing else in this directory.
//
// Content here explains the Always Allowed gotcha itself (docs/spec.md §20.2
// `dsadriel-pocs/screen-time-app-blocker-ios` row, §27 Known Platform Gotchas) — plain, factual
// explainer copy, not persona-voiced (no `CoachVoice` parameter threaded through), matching
// `AutoFocusSetupInstructions`'s (Core/Sources/Core/Copy/AutoFocusSetupInstructions.swift) own
// precedent: "walking someone through Apple's own Settings app is a fixed technical fact, not a
// Hype/Tough Love/Chill/Data moment" (spec §5.13).
//
// Deliberately doesn't claim anything about Always Allowed's exact default contents (e.g. which
// system apps ship pre-listed, or which of those can/can't be removed) — this task's own honest-
// check brief (see `AlwaysAllowedCheck.swift`'s header) is about the mechanism, not Apple's
// current default list, and that list has shifted across iOS releases with no Mac/device here to
// confirm current specifics (CLAUDE.md rule 5). Keeping the copy to the mechanism itself (there is
// a list, it overrides every third-party shield, ZANO can't read or detect it) avoids stating a
// specific fact this session couldn't verify.

extension Copy {
    public enum alwaysAllowed {

        // MARK: - Banner (`AlwaysAllowedWarningView`)

        /// A title that states as fact what the body below only hedges ("If any of these apps are
        /// in..."). This one matches the hedge: check first, then rely on the lock.
        public static let bannerTitle = "Check Always Allowed before you rely on this lock"

        /// Shown when the selection includes at least one individually-picked app
        /// (`AlwaysAllowedCheck.Assessment.appCount > 0`).
        public static let bannerMessageAppsPicked =
            "If any of these apps are in Settings > Screen Time > Always Allowed, iOS will keep " +
            "letting them through no matter what ZANO locks. Worth a quick check."

        /// Shown when the selection is category-only (no individually-picked apps) — still worth
        /// the same warning, since a category shield can include an Always-Allowed app, just
        /// without implying the user hand-picked that specific app.
        public static let bannerMessageCategoriesOnly =
            "If any app inside these categories is in Settings > Screen Time > Always Allowed, " +
            "iOS will keep letting it through no matter what ZANO locks. Worth a quick check."

        /// Fallback for a selection that shouldn't trigger this banner at all
        /// (`AlwaysAllowedCheck.Assessment.shouldWarn == false` — e.g. web-domains-only, or
        /// empty). `AlwaysAllowedWarningView` is deliberately "dumb" about when to show itself
        /// (the caller decides via `shouldWarn`/`isWebDomainsOnly`), so this exists only so a
        /// misused call site degrades to a true, generic sentence instead of a specific but wrong
        /// one.
        public static let bannerMessageGeneral =
            "If anything here is in Settings > Screen Time > Always Allowed, iOS will keep " +
            "letting it through no matter what ZANO locks. Worth a quick check."

        public static let openSettingsButtonLabel = "Open Settings"
        public static let dismissAccessibilityLabel = "Dismiss"

        // MARK: - Full explainer (for a setup/help screen that wants more than the one-line banner)

        public static let explainerTitle = "Apps that ignore your lock"

        public static let explainer =
            "Apple's Screen Time has its own exception list — Settings > Screen Time > Always " +
            "Allowed — separate from anything ZANO controls. Any app on that list stays reachable " +
            "through every lock, from every app-blocking app, because iOS itself never hands it " +
            "to the shield in the first place. ZANO has no way to read that list or detect the " +
            "conflict automatically — Apple doesn't expose an API for it — so the only reliable " +
            "fix is checking it yourself, once, for any app you're locking."

        public static let explainerCheckStep =
            "Open Settings > Screen Time > Always Allowed and remove any app you actually want " +
            "ZANO to be able to lock."

        public static let explainerNote =
            "This is how Screen Time works for every app blocker."
    }
}
