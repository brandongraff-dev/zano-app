import DeviceActivity
import Core

// ZANOMonitor — the DeviceActivity monitor extension (docs/spec.md §2 "Lock triggers: Schedule",
// §5.2 Earn Mode spend windows, §5.10 Bedtime Gate, §11, §27).
//
// A thin shim: every decision lives in Core's `ScheduledLockMonitor`
// (Core/Sources/Core/LockEngine/LockScheduler.swift) so it sits next to the engine it hands off to.
// What happens here, all from App Group state (no SwiftData, no networking — extensions are
// short-lived and memory-limited, spec §27):
//   - intervalDidStart of a lock schedule / the Bedtime Gate → shield the lock set's apps and leave
//     a pending record the app turns into a real LockSession on its next foreground
//     (`LockScheduler.reconcile`), so emergency unlock, goals and the Earn Meter all work.
//   - intervalDidEnd of a lock schedule → lift that schedule's lock; the app records `.scheduleEnd`.
//   - intervalDidEnd / intervalWillEndWarning of an Earn Mode spend window → shield back on.
// Bedtime pickups (`eventDidReachThreshold`) are not wired: BedtimeGateManager defines no
// DeviceActivityEvent yet.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        ScheduledLockMonitor.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ScheduledLockMonitor.intervalDidEnd(for: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        ScheduledLockMonitor.intervalWillEndWarning(for: activity)
    }
}
