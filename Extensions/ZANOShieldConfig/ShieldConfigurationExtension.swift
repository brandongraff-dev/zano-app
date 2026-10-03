import ManagedSettings
import ManagedSettingsUI
import UIKit
import SwiftUI
import Core

// The Living Shield (docs/spec.md §5.1): "The block screen isn't static. It reflects state and
// personality." Title/subtitle vary by the user's coach voice (Hype / Tough Love / Chill / Data,
// spec §5.13) and by state (mid-lock / near-completion / after-a-miss) — all of that decision
// logic lives in `ShieldCopy` (`Core/Sources/Core/Copy/ShieldCopy.swift`); this file only reads
// state from the App Group and renders whatever `ShieldCopy` returns.
//
// NOTE: extensions read the App Group only — no networking, no heavy work (docs/spec.md §11,
// §27: "Extensions must be tiny. No network in Shield extensions. Read state from the App Group
// only."). Every value below comes from `SharedDefaults`
// (`Core/Sources/Core/Store/SharedDefaults.swift`), which other engines (`StreakEngine`,
// `LockEngineManager`, `TimeBankEngine`) keep current as a cheap mirror of SwiftData — this file
// never opens `ModelContainer.appGroup` itself, to stay well inside a shield extension's tight
// memory/time budget.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(shieldedName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in _: ActivityCategory) -> ShieldConfiguration {
        // The category token has no reliable localized name of its own to read here;
        // `application` already gives us the one specific app being opened even though the
        // *shield* was configured at category granularity, so we use that.
        configuration(shieldedName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(shieldedName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in _: ActivityCategory) -> ShieldConfiguration {
        configuration(shieldedName: webDomain.domain)
    }

    // MARK: - Shared build

    /// Look (shield redesign, brand tokens from `Core/Sources/Core/UI/Theme.swift`): near-black
    /// base over a dark blur, the silver ZANO star as the icon, a pearl title that states what's
    /// left, a softer pearl coach line, ONE ZANO Blue button with a white label, and a quiet
    /// secondary button.
    ///
    /// One sec-style shield (2026-10-02, research item 3 in
    /// docs/design/growth-and-ml-research.md): the primary button is "Close app", the easy and
    /// rewarding choice (each tap counts as a reclaimed open), and the secondary is "Use Time
    /// Bank", which opens ZANO's Lock tab through the notification hand-off. That tab holds the
    /// Time Bank card AND the emergency unlock, and the notification says so, so the way out is
    /// still one tap from the shield (CLAUDE.md: never ship a lock with no way out). The labels are
    /// never conditional on any state read below.
    ///
    /// Not possible here: a timed pause before the buttons work. `ShieldConfiguration` is a static
    /// value (labels, colours, icon) with no animation or delay, so the one sec "breath" can't be
    /// reproduced on the shield itself (unverified for iOS 26+; true for the iOS 18.5 SDK).
    private func configuration(shieldedName: String?) -> ShieldConfiguration {
        // spec §23: count every rendered shield on device; the app flushes it later. Read after
        // the increment, it also rotates the coach line per view.
        SharedDefaults.incrementShieldImpressionCount()
        let rotation = SharedDefaults.shieldImpressionCount
        // spec §5.16: one attempt for the locked-out moment (display name only, never a token).
        LockedOutAttemptTracker.recordAttempt(appName: shieldedName)

        let content = ShieldCopy.content(for: Self.makeContext(shieldedName: shieldedName), rotation: rotation)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.background,
            icon: Self.starIcon,
            title: ShieldConfiguration.Label(text: content.title, color: Self.pearl),
            subtitle: ShieldConfiguration.Label(text: content.subtitle, color: Self.pearlSoft),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.closeApp, color: Self.onAccent),
            primaryButtonBackgroundColor: Self.accent,
            secondaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.useTimeBank, color: Self.muted)
        )
    }

    // MARK: - Brand tokens (UIKit bridges of `Theme.Tones`; ShieldConfiguration takes UIColor)
    //
    // Light mode (2026-10-03): the shield stays DARK in both appearances, on purpose. The
    // configuration is a static value handed to the system, which draws it in another process; a
    // dynamic `UIColor` provider is not guaranteed to survive that hand-off, and the blur style is
    // fixed per value (`.systemUltraThinMaterialDark`). So every colour is the dark tone resolved
    // explicitly (`uiColor(for: .dark)`, never the adaptive `Theme.Colors` value, which would
    // resolve light in a light-mode process). A dark blocked-app screen reads correctly over any
    // app in either appearance, and the pre-rendered silver `ShieldMark` icon is drawn for dark.
    // Unverified: whether iOS would honour a dynamic UIColor here (no device to test).

    /// `Theme.Tones.background` (dark ink) at 92% so the dark blur reads as depth, not grey.
    private static let background = Theme.Tones.background.uiColor(for: .dark).withAlphaComponent(0.92)
    /// `Theme.Tones.text` (dark): pearl.
    private static let pearl = Theme.Tones.text.uiColor(for: .dark)
    /// Pearl, softened for the coach line so the title stays the one thing read first.
    private static let pearlSoft = Theme.Tones.text.uiColor(for: .dark).withAlphaComponent(0.74)
    /// `Theme.Tones.muted` (dark): the emergency button is always there, never shouting.
    private static let muted = Theme.Tones.muted.uiColor(for: .dark)
    /// ZANO Blue (dark tone, `#3F7BFF`) — the one accent.
    private static let accent = Theme.Tones.accent.uiColor(for: .dark)
    /// White labels on blue.
    private static let onAccent = UIColor.white

    /// The silver swoosh-star, pre-rendered from `docs/brand/zano-mark.svg` into this
    /// extension's own `Assets.xcassets` (`ShieldMark`, 90pt square canvas @1x/2x/3x,
    /// original rendering). A bundled PNG is the cheapest possible icon for an extension with a
    /// tight memory/time budget (spec §27) — no drawing at render time. Computed rather than a
    /// stored `static let` so Swift 6 never has to reason about `UIImage`'s Sendability;
    /// `UIImage(named:)` keeps its own system cache, so repeat lookups are cheap. `nil` only if
    /// the asset is missing from the build, in which case the shield shows no icon.
    private static var starIcon: UIImage? { UIImage(named: "ShieldMark") }

    /// Builds a `ShieldCopy.ShieldContext` from `SharedDefaults` — the one place this extension
    /// touches the App Group.
    private static func makeContext(shieldedName: String?) -> ShieldCopy.ShieldContext {
        ShieldCopy.ShieldContext(
            voice: CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice),
            shieldedName: shieldedName,
            currentStreak: SharedDefaults.currentStreak,
            goalsRemaining: SharedDefaults.goalsRemainingForActiveLock,
            mode: SharedDefaults.activeLockMode,
            earnedMinutesRemainingToday: SharedDefaults.earnedMinutesRemainingToday,
            earnedMinutesMirrorIsForToday: SharedDefaults.earnedMinutesMirrorIsForToday,
            // Mirrored by `StreakEngine` on every streak write (spec §5.6 after-a-miss moment).
            recentMiss: SharedDefaults.neverMissTwiceArmed,
            // One small App Group dictionary read (`ShieldActionExtension` writes it).
            reclaimedThisWeek: ReclaimedOpens.countThisWeek()
        )
    }
}
