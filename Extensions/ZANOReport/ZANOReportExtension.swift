import DeviceActivity
import SwiftUI

// On-device Time Reclaimed / usage views (docs/spec.md §5.15, §27 — usage numbers can only be read
// inside this extension, never in the main app or backend) are Session 9/10+ scope. This
// placeholder confirms the extension point is wired correctly.
@main
struct ZANOReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        ZANOPlaceholderReportScene()
    }
}

struct ZANOPlaceholderReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "ZANOPlaceholder")
    let content: (String) -> ZANOPlaceholderReportView = { ZANOPlaceholderReportView(text: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        "ZANO"
    }
}

struct ZANOPlaceholderReportView: View {
    let text: String

    var body: some View {
        Text(text)
    }
}
