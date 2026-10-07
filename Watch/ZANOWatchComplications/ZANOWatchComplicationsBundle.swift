// ZANOWatchComplicationsBundle.swift
// Watch/ZANOWatchComplications
//
// @main entry point of the watchOS WidgetKit extension that ZANOWatch embeds (project.yml,
// `ZANOWatchComplications`). Watch-face complications on watchOS 9+ are WidgetKit widgets in the
// accessory families. The rings complication still parked in the app target
// (`Watch/ZANOWatch/ComplicationPlaceholder.swift`) is not registered here; see that file.

import SwiftUI
import WidgetKit

@main
struct ZANOWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        StreakComplication()
    }
}
