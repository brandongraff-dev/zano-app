// CommonCopy.swift
// Core / Copy
//
// `Copy.common` — small, generic strings reused across more than one feature area (a plain
// "Continue" button, a plain "OK" alert dismissal), so they're defined once instead of duplicated
// under every feature namespace that happens to need one. Kept deliberately tiny: only what's
// actually referenced today (CLAUDE.md: "don't add abstractions... beyond what the current
// session's scope requires") — `Copy.onboarding`/`Copy.paywall` (this same directory) each own
// every string that's specific to their own screens, even a "Continue"-shaped button, once its
// wording needs to differ from this generic one.

extension Copy {
    public enum common {
        /// A plain, generic "advance to the next step" button label. Used by every onboarding
        /// question screen that has no more specific verb for what "Continue" does.
        public static let continueButtonLabel = "Continue"

        /// A plain alert-dismissal button label.
        public static let ok = "OK"

        /// A plain alert/sheet cancel button label. Not referenced by the onboarding cluster
        /// itself, but `App/ZANO/Features/LockSetup/LockSetupView.swift` (a sibling session's
        /// owned file, not edited here) documents needing `Copy.common.cancel` alongside
        /// `Copy.common.ok` — added here too so that file's own gap closes for free once this one
        /// does, without a second `extension Copy { enum common { ... } }` declaration colliding
        /// with this one later.
        public static let cancel = "Cancel"

        /// Generic failure alert title/message, for a screen that has nothing more specific to say
        /// about why an action failed (e.g. `CosmeticsShopView.swift`'s `.noSignedInUser`/
        /// `.unknownItem`/`.storeFailure` catch-all). Added here, not a one-off in that file, per
        /// this same rationale: a second screen with the same generic-failure need should reuse
        /// this rather than invent its own wording.
        public static let somethingWentWrongTitle = "Something went wrong"
        public static let somethingWentWrongMessage = "Please try again."
    }
}
