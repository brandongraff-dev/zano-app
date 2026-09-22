import ManagedSettings
import ManagedSettingsUI
import UIKit
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

    private func configuration(shieldedName: String?) -> ShieldConfiguration {
        let content = ShieldCopy.content(for: Self.makeContext(shieldedName: shieldedName))

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            title: ShieldConfiguration.Label(text: content.title, color: .white),
            subtitle: ShieldConfiguration.Label(
                text: content.subtitle,
                color: UIColor(white: 1, alpha: 0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.showGoals, color: .black),
            primaryButtonBackgroundColor: Self.accentColor,
            secondaryButtonLabel: ShieldConfiguration.Label(text: ShieldCopy.Buttons.emergency, color: .white)
        )
    }

    /// spec §15 Design System token: "Accent (earned/unlock): `#B8FF3C` (acid green) — ONE accent
    /// only." Reused here rather than a plain white/system button so the shield's one visible
    /// call-to-action matches the rest of the app instead of introducing a second accent color.
    private static let accentColor = UIColor(
        red: CGFloat(0xB8) / 255,
        green: CGFloat(0xFF) / 255,
        blue: CGFloat(0x3C) / 255,
        alpha: 1
    )

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
