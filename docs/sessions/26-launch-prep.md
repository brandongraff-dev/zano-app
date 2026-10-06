# Session 26 — Launch preparation review

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §24, §5.23; `docs/launch/*`
- **Status:** Scaffolded — Unverified (code edits not yet through CI)
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06

- **Files touched:** `project.yml` (calendar permission text; `UIBackgroundModes: location` removed), `Core/Sources/Core/Copy/{FuelCopy,FamilyCopy}.swift`, `Core/Sources/Core/Family/FamilyModels.swift` (`FamilyLinkAvailability.isLive = false`), `App/ZANO/Features/Settings/SettingsView.swift` (Family Link row gated), `docs/launch/{privacy-policy,app-privacy-labels}.md`, new `docs/launch/{supabase-setup,final-checklist}.md`.
- **What changed:** found and fixed launch risks: the calendar permission and privacy policy denied reading event titles (Focus lock reads them, on device); "coming soon" wording; an unneeded background location mode; an unfinished feature (Family Link) visible in Settings. Wrote the Supabase setup guide and a founder checklist ordered by lead time.
- **Decisions:** recommend submitting 1.0 without Supabase (nothing can authenticate yet); Family Link stays hidden behind one constant until sign-in exists.
- **Known issues / not done:** `/privacy` and `/terms` pages do not exist on the landing site; sign-in with Apple is unwritten; CI uses the runner's Xcode (check Apple's current SDK requirement); removing the background location mode needs a device test.
- **Needs verification on:** CI (project.yml regeneration, tests); a real device for the geofence.
