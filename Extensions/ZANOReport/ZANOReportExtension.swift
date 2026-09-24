import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI
import Core

// On-device screen-time report (docs/spec.md §5.15, §27): usage numbers can only be read inside
// this extension, never in the main app or backend, so this is where Today's "Screen time" section
// is computed and drawn. The main app embeds it with `DeviceActivityReport(.zanoToday, filter:)`.
//
// The view is Core's `ScreenTimeSummaryView` (shared so CI can screenshot it from demo data); this
// file only turns `DeviceActivityResults` into a `ScreenTimeSummary`. Locked apps are the ones in
// the default lock set, which the main app mirrors to `SharedDefaults.lockedSelectionData`; their
// usage is the red part of the chart.
//
// Unverified without a device (the Simulator has no Screen Time data): the exact shape of the
// DeviceActivityData async sequences below is from Apple's documentation and WWDC22 "What's new in
// Screen Time API", not from a run. The extension is memory-limited, so it keeps only per-app and
// per-hour totals, never raw segments.
@main
struct ZANOReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // The closure's return type is the scene's `content` type, so no modifiers here: the view
        // uses fixed dark Theme colors and needs none.
        TodayScreenTimeReport { summary in
            ScreenTimeSummaryView(summary: summary)
        }
    }
}

struct TodayScreenTimeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .zanoToday
    let content: (ScreenTimeSummary) -> ScreenTimeSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTimeSummary {
        let locked = LockedSelection.load()
        var total: TimeInterval = 0
        var lockedTotal: TimeInterval = 0
        var pickups = 0
        var perApp: [String: (name: String, token: ApplicationToken?, duration: TimeInterval, isLocked: Bool)] = [:]
        var perHour: [Int: (locked: Double, other: Double)] = [:]
        let calendar = Calendar.current

        for await deviceData in data {
            for await segment in deviceData.activitySegments {
                let hour = calendar.component(.hour, from: segment.dateInterval.start)
                total += segment.totalActivityDuration
                pickups += segment.totalPickupsWithoutApplicationActivity

                for await categoryActivity in segment.categories {
                    let categoryLocked = categoryActivity.category.token.map { locked.categories.contains($0) } ?? false
                    for await appActivity in categoryActivity.applications {
                        let app = appActivity.application
                        let duration = appActivity.totalActivityDuration
                        let isLocked = categoryLocked || (app.token.map { locked.applications.contains($0) } ?? false)
                        pickups += appActivity.numberOfPickups

                        let key = app.bundleIdentifier ?? app.localizedDisplayName ?? UUID().uuidString
                        var entry = perApp[key] ?? (app.localizedDisplayName ?? "App", app.token, 0, isLocked)
                        entry.duration += duration
                        perApp[key] = entry

                        var bucket = perHour[hour] ?? (0, 0)
                        if isLocked {
                            bucket.locked += duration / 60
                            lockedTotal += duration
                        } else {
                            bucket.other += duration / 60
                        }
                        perHour[hour] = bucket
                    }
                }
            }
        }

        let apps = perApp
            .map { ScreenTimeSummary.AppUsage(id: $0.key, name: $0.value.name, token: $0.value.token, duration: $0.value.duration, isLocked: $0.value.isLocked) }
            .sorted { $0.duration > $1.duration }
        let hours = perHour
            .map { ScreenTimeSummary.Hour(hour: $0.key, lockedMinutes: $0.value.locked, otherMinutes: $0.value.other) }
            .sorted { $0.id < $1.id }

        return ScreenTimeSummary(
            total: total,
            lockedTime: lockedTotal,
            pickups: pickups,
            apps: Array(apps.prefix(8)),
            hours: hours,
            asOf: .now
        )
    }
}

/// The default lock set's apps and categories, from the App Group mirror.
private struct LockedSelection {
    var applications: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []

    static func load() -> LockedSelection {
        guard let data = SharedDefaults.lockedSelectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return LockedSelection() }
        return LockedSelection(applications: selection.applicationTokens, categories: selection.categoryTokens)
    }
}
