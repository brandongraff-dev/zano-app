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
    /// left, a softer pearl coach line, ONE ZANO Blue button with a white label, and the
    /// always-present "Emergency unlock" as the quiet secondary button (CLAUDE.md: never ship a
    /// lock with no way out — this label is never conditional on any state read below).
    private func configuration(shieldedName: String?) -> ShieldConfiguration {
        // spec §23: count every rendered shield on device; the app flushes it later.
        SharedDefaults.incrementShieldImpressionCount()

        let content = ShieldCopy.content(for: Self.makeContext(shieldedName: shieldedName))

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.background,
            icon: Self.starIcon,
            title: ShieldConfiguration.Label(text: content.title, color: Self.pearl),
            subtitle: ShieldConfiguration.Label(text: content.subtitle, color: Self.pearlSoft),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.showGoals, color: Self.onAccent),
            primaryButtonBackgroundColor: Self.accent,
            secondaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.emergency, color: Self.muted)
        )
    }

    // MARK: - Brand tokens (UIKit bridges of `Theme.Colors`; ShieldConfiguration takes UIColor)

    /// `Theme.Colors.background` (#050506) at 92% so the dark blur reads as depth, not grey.
    private static let background = UIColor(Theme.Colors.background).withAlphaComponent(0.92)
    /// `Theme.Colors.text`, pearl #F2F1ED.
    private static let pearl = UIColor(Theme.Colors.text)
    /// Pearl, softened for the coach line so the title stays the one thing read first.
    private static let pearlSoft = UIColor(Theme.Colors.text).withAlphaComponent(0.74)
    /// `Theme.Colors.muted`, #8E8E93: the emergency button is always there, never shouting.
    private static let muted = UIColor(Theme.Colors.muted)
    /// `Theme.Colors.accent`, ZANO Blue #3F7BFF — the one accent.
    private static let accent = UIColor(Theme.Colors.accent)
    /// `Theme.Colors.onAccent`: white labels on blue.
    private static let onAccent = UIColor(Theme.Colors.onAccent)

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
            earnedMinutesMirrorIsForToday: SharedDefaults.earnedMinutesMirrorIsForToday
            // `recentMiss` intentionally left at its default (`false`) — see the TODO on
            // `ShieldCopy.ShieldContext.recentMiss` for the still-missing SharedDefaults mirror
            // of `Streak.neverMissTwiceArmed` that would drive the after-a-miss moment for real.
        )
    }
}
