import ManagedSettings
import ManagedSettingsUI
import UIKit

// The Living Shield (docs/spec.md §5.1 — dynamic copy per coach voice, goals remaining, streak,
// tone shifts after a miss) is Session 2 scope. This placeholder returns a static configuration so
// the extension point, entitlement, and App Group wiring can be verified before real content lands.
// NOTE: extensions read the App Group only — no networking, no heavy work (docs/spec.md §11, §27).
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        placeholderConfiguration
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        placeholderConfiguration
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        placeholderConfiguration
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        placeholderConfiguration
    }

    private var placeholderConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            title: ShieldConfiguration.Label(text: "Locked by ZANO", color: .white),
            subtitle: ShieldConfiguration.Label(text: "Finish your goals to unlock this app.", color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Show my goals", color: .black),
            primaryButtonBackgroundColor: .white
        )
    }
}
