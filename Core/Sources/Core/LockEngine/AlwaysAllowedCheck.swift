// AlwaysAllowedCheck.swift
// Core / LockEngine
//
// docs/spec.md §20.2 reference-repo table, `dsadriel-pocs/screen-time-app-blocker-ios` row: that
// POC's README documents the "Always Allowed" immunity gotcha — apps a user has placed in
// Settings > Screen Time > Always Allowed can never be shielded, no matter what ZANO configures —
// and the table's own "Maps to" column calls for exactly this: "add an onboarding check for
// Always Allowed." Spec §27 Known Platform Gotchas is the list this same category of fact
// belongs alongside (shield buttons can't open the app, DeviceActivity's 15-minute minimum
// interval, etc.); this file is Core-owned *code* for that gotcha, not an edit to spec.md itself
// (spec.md is out of this task's owned-file list).
//
// === The platform limitation, stated exactly (read before changing anything below) ===
//
// There is no public API, anywhere in FamilyControls / ManagedSettings / DeviceActivity, that
// lets a third-party app read the current contents of Settings > Screen Time > Always Allowed.
// Apple exposes that list only as first-party Settings UI the user edits by hand; nothing in
// `AuthorizationCenter`, `ManagedSettingsStore`, or `DeviceActivityCenter` returns it, and every
// reference repo docs/spec.md §20.2 points at — including the one that names this gotcha — ships
// the same "tell the user to go check" advice this file encodes, because there is nothing else to
// build against. This is a deliberate Apple privacy boundary, not a gap this task failed to find
// an API for.
//
// A second, compounding limitation: even *if* Always Allowed were readable, this app has no way
// to compare it against the user's `FamilyActivitySelection` app-for-app. `ApplicationToken` is
// opaque by design (Apple's Screen Time privacy model — a token round-trips through
// `FamilyActivityPicker` / `ManagedSettingsStore` but never decodes to a bundle identifier or
// display name for a third-party app to inspect; see `LockSet.swift`'s header: "FamilyControls'
// opaque ApplicationToken / ActivityCategoryToken / WebDomainToken values... are meaningless
// outside the device that granted them"), so ZANO cannot ask "is *this specific* token the same
// app as *that* Always-Allowed entry" even with two lists in hand. No client-side cleverness
// closes that gap — it is enforced by the token type itself.
//
// === What this file does instead (the honest, available check) ===
//
// Given those two limitations, "check" here does not mean "detect the conflict" — it means
// "reliably notice when the gotcha is *possible* and say so before the user is surprised by a
// shield that silently doesn't apply." `assessment(for:)` below is a pure function of the
// `FamilyActivitySelection` the user just picked to lock: it cannot know whether any of those
// apps are on the user's Always Allowed list, so it flags the warning as relevant whenever the
// selection contains anything Always Allowed could plausibly cover (individual apps, or a
// category — Always Allowed is Apple's own "Allowed Apps" list, so it exempts apps, including
// apps only reached through a category shield) and marks it not relevant for a selection that is
// web-domains-only (Always Allowed has no bearing on Safari/web-domain shields — it is an apps
// list, not a websites list). That apps-vs-websites distinction is the one factual claim this
// file makes about how Always Allowed and category shields interact, rather than pure hedging; it
// is this session's best-available understanding from the cited reference repo and Apple's own
// Screen Time settings UI, not confirmed against current API docs or a device (no Mac in this
// environment — CLAUDE.md rule 5). Flagged in this task's knownIssues.
//
// `AlwaysAllowedWarningView` (App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift, this
// same task's other owned file) is the view that renders whatever this file computes; this file
// stays SwiftUI/UIKit-free, matching `EmergencyUnlock.swift` / `AutoFocusIntegration.swift`'s
// state-lives-in-Core split (this same directory).
//
// Not part of any predefined SYSTEM CONTRACTS list — like `EmergencyUnlock.swift` and
// `AutoFocusIntegration.swift` (this directory), this file's shape is this task's own design,
// built from its own brief: "given a FamilyActivitySelection the user picked to lock... build the
// most honest available check... and a simple copy-based warning."

import Foundation
import FamilyControls

/// The Always-Allowed onboarding check (docs/spec.md §20.2, §27): an honest, best-effort warning
/// for a `FamilyActivitySelection` the user is about to lock, plus a small "don't nag forever"
/// acknowledgement flag so an onboarding / lock-setup screen can show it once per relevant
/// selection rather than on every render. See this file's header for exactly what is and isn't
/// possible here — there is no way to *detect* the conflict, only to *warn* that it's possible.
public enum AlwaysAllowedCheck {

    /// What `assessment(for:)` found in one `FamilyActivitySelection` — everything a view needs
    /// to decide what to render, computed once so `AlwaysAllowedWarningView` doesn't re-derive
    /// token counts itself.
    public struct Assessment: Sendable, Equatable {
        /// Individually-picked apps in the selection
        /// (`FamilyActivitySelection.applicationTokens.count`).
        public let appCount: Int
        /// Activity categories in the selection (`.categoryTokens.count`).
        public let categoryCount: Int
        /// Web domains in the selection (`.webDomainTokens.count`) — see this file's header:
        /// Always Allowed does not apply to these.
        public let webDomainCount: Int

        /// `true` when this selection contains anything Always Allowed could plausibly exempt
        /// (any app or category pick). See this file's header for why this is "could plausibly,"
        /// never "does" — there is no way to make this precise.
        public var shouldWarn: Bool { appCount > 0 || categoryCount > 0 }

        /// `true` when the selection is web-domains-only — nothing here is an app, so Always
        /// Allowed (an apps list) has no bearing on it. Kept distinct from `!shouldWarn` reading
        /// as "nothing selected"; `AlwaysAllowedWarningView` uses this the same way `shouldWarn`
        /// is used — callers gate on it, the view itself never reads it.
        public var isWebDomainsOnly: Bool {
            webDomainCount > 0 && appCount == 0 && categoryCount == 0
        }

        public init(appCount: Int, categoryCount: Int, webDomainCount: Int) {
            self.appCount = appCount
            self.categoryCount = categoryCount
            self.webDomainCount = webDomainCount
        }
    }

    /// The one entry point: turns a picked `FamilyActivitySelection` into an `Assessment`. Pure
    /// and synchronous — reads only the three token counts already in memory on `selection`, no
    /// authorization check, no I/O, no persistence. Safe to call on every `body`
    /// re-evaluation (mirrors the same three-count read `AppPickerView.selectionSummaryText` and
    /// `LockSetupView.appSummary(for:)` already do off a `FamilyActivitySelection` — those files
    /// belong to a different, already-in-flight session, so this function isn't called from
    /// either; it's shaped to match so a future integration reads naturally alongside them).
    public static func assessment(for selection: FamilyActivitySelection) -> Assessment {
        Assessment(
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    /// Convenience for a call site that only needs the yes/no, not the full breakdown.
    public static func shouldWarn(for selection: FamilyActivitySelection) -> Bool {
        assessment(for: selection).shouldWarn
    }

    // MARK: - Acknowledgement (the "don't nag forever" cadence)

    /// `UserDefaults` is documented thread-safe by Apple but not yet marked `Sendable` by the SDK
    /// as of this writing; see `SharedDefaults.defaults`'s identical note
    /// (Core/Sources/Core/Store/SharedDefaults.swift) for why `nonisolated(unsafe)` is the right
    /// annotation here under Swift 6 strict concurrency.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let hasAcknowledged = "alwaysAllowedCheck.hasAcknowledged"
    }

    /// `true` once the user has dismissed/acknowledged `AlwaysAllowedWarningView` at least once.
    /// Defaults to `false`. This is a "don't repeat the same warning forever" flag, the same trust
    /// model `AutoFocusIntegration.isSetUp` documents for itself — it never gates or hides the
    /// underlying gotcha (Always Allowed keeps working, or not, regardless of whether the user has
    /// acknowledged reading about it), only whether a screen chooses to keep showing the banner. A
    /// screen is always free to ignore this and show the banner unconditionally —
    /// `AlwaysAllowedWarningView` never reads this flag itself (see that file's header).
    public static var hasAcknowledgedWarning: Bool {
        get { defaults.bool(forKey: Keys.hasAcknowledged) }
        set { defaults.set(newValue, forKey: Keys.hasAcknowledged) }
    }

    /// Marks the warning acknowledged. Call when the user dismisses `AlwaysAllowedWarningView`
    /// (an "I understand" / "Got it" / close-button tap) — prefer this over setting
    /// ``hasAcknowledgedWarning`` directly, same rationale `AutoFocusIntegration.
    /// recordSetupCompleted()` documents for itself.
    public static func recordAcknowledged() {
        hasAcknowledgedWarning = true
    }

    /// Undoes ``recordAcknowledged()`` — e.g. a "show me that again" Settings row, or resetting
    /// local state for a new signed-in user on the same device.
    /// `AutoFocusIntegration.recordSetupRemoved()`'s counterpart.
    public static func resetAcknowledgement() {
        hasAcknowledgedWarning = false
    }
}
