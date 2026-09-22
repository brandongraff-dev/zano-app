import ManagedSettings
import UIKit

// Real behavior (primary button → local notification that opens the app to the goals screen,
// since shields can't open the host app directly — docs/spec.md §27; "Emergency" → 60-second hold
// flow) is Session 2 scope. This placeholder just closes the shield so the extension point can be
// verified end-to-end first.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }
}
