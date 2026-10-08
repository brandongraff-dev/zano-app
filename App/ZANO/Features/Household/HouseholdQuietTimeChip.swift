// HouseholdQuietTimeChip.swift
// App / ZANO / Features / Household
//
// The Today chip for a household screen-free time this phone joined (session 44; docs/spec.md §5.31):
// "Dinner in 10 min · phones down together" in the ten minutes before, then "Dinner · phones down until
// 7:00 PM" while it runs. Draws nothing when Household isn't live, nothing is joined, or nothing is near.
// The local notification at the same moment is planned by `HouseholdQuietTimeScheduler`.

import SwiftUI
import Core

struct HouseholdQuietTimeChip: View {
    var body: some View {
        if HouseholdAvailability.isLive {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let status = HouseholdQuietTimePlanner.status(joined: HouseholdQuietTimeStore.joinedWindows, now: context.date) {
                    ZanoGlassChip(text(for: status, now: context.date), systemImage: "moon.stars.fill", tint: Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func text(for status: HouseholdQuietTimePlanner.Status, now: Date) -> String {
        switch status {
        case .startingSoon(let window, let start):
            let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
            return Copy.household.quietChipSoon(name: window.name, minutes: minutes)
        case .running(let window, let end):
            return Copy.household.quietChipRunning(name: window.name, end: end)
        }
    }
}
