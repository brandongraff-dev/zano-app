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

        /// A plain "commit this edit" button label — `LockSetupView.swift`'s editor sheet,
        /// `FuelView.swift`'s Kitchen Staple add sheet, and `SettingsView.swift`'s Gym add sheet
        /// each already call `Copy.common.save` (repo-wide Copy sweep, 2026-09-22: referenced by
        /// three call sites, never declared anywhere in `Core/Sources/Core/Copy`).
        public static let save = "Save"

        /// A plain destructive "remove this row" button/label — `FuelView.swift`'s Kitchen Staple
        /// swipe-to-delete and `SettingsView.swift`'s Gym swipe-to-delete both already call
        /// `Copy.common.delete` (same 2026-09-22 sweep as `save` above).
        public static let delete = "Delete"
        /// Closes a sheet.
        public static let done = "Done"

        /// Generic failure alert title/message, for a screen that has nothing more specific to say
        /// about why an action failed (e.g. `CosmeticsShopView.swift`'s `.noSignedInUser`/
        /// `.unknownItem`/`.storeFailure` catch-all). Added here, not a one-off in that file, per
        /// this same rationale: a second screen with the same generic-failure need should reuse
        /// this rather than invent its own wording.
        ///
        /// A last-resort catch-all should still name that the action didn't complete and give one
        /// thing to try. It does not blame the network: ZANO is local-first, so most failures are
        /// not connection failures, and "check your connection" sends the user to fix the wrong
        /// thing. Prefer a per-cause string whenever the caller knows the cause.
        public static let somethingWentWrongTitle = "Couldn't complete that"
        public static let somethingWentWrongMessage = "Something went wrong on our side. Try again."

        /// Accessibility label for a row's overflow ("...") menu button: "More options for Protein".
        public static func moreOptions(for name: String) -> String { "More options for \(name)" }

        /// VoiceOver hint on a hold-to-commit control (`PrimaryButton.Style.holdToCommit`).
        /// VoiceOver can't perform a sustained hold, so the control fires on a double-tap; the hint
        /// says so.
        public static let holdControlHint = "Double-tap to confirm"

        /// VoiceOver value for a streak pill: "12 days" / "12 days, frozen" (a streak freeze is
        /// protecting it today).
        public static func streakSpoken(days: Int, frozen: Bool) -> String {
            let base = days == 1 ? "1 day" : "\(days) days"
            return frozen ? "\(base), frozen" : base
        }
    }
}
