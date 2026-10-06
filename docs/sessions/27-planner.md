# Session 27 — Planner: calendar, tasks, reminders

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.30 (new), §5.24 (Focus lock shares calendar access)
- **Status:** Scaffolded — Unverified (not yet compiled in CI)
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06 — Planner

- **Files touched:** new `Core/Sources/Core/Planner/{PlannerModels,PlannerAgenda,PlannerStore,PlannerCalendarSource,PlannerReminders}.swift`, `Core/Sources/Core/Copy/PlannerCopy.swift`, `Core/Tests/CoreTests/PlannerTests.swift`, `App/ZANO/Features/Planner/{PlannerView,PlannerTaskEditor,PlannerEventEditor,PlannerTodayCard,PlannerSettingsView}.swift`; edited `TodayView.swift` (calendar button, "Due today" card, sheet), `SettingsView.swift` (row), `ContentView.swift` (refresh reminders on foreground), `ScreenshotGallery.swift` + `ci.yml` (`planner` screen), `docs/spec.md`.
- **What changed:** an Apple-Calendar-style month grid and day agenda, tasks with optional date, time and reminder, a native event editor (EventKitUI), a Today card, task reminders and optional "starts in N minutes" event alerts. Pure rules (month grid, agenda, dots, reminder plan, task expiry) are in Core and unit tested.
- **Decisions:** tasks are JSON in the App Group (like Focus lock and Sleep), not SwiftData, to avoid a schema migration; events are read, never copied; one notification identifier set owned by the feature so it never touches others; "Anytime" tasks sit under the timeline like Reminders' "no time".
- **Known issues / not done:** `EKEventEditViewDelegate` main-actor isolation is written from memory and may need one CI pass; tapping an event does nothing yet (the iOS Calendar opens its detail); no recurring tasks, no week view, no subtasks or lists; event alerts only refresh while the app is opening; the deep link of a reminder opens Today, not the calendar.
- **Needs verification on:** CI compile and `PlannerTests`; Simulator screenshot `planner`; a device for notifications and the event editor.
