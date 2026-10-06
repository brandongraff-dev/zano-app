# Session 28 — Household and sharing

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.31 (new), §5.30 (Planner), §5.23 (Family Link, kept separate)
- **Status:** Compiles + Core unit tests pass in CI (run 124, 2026-10-06). Household cannot run: needs the Supabase project and sign-in
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06

- **Files touched:** new `backend/supabase/migrations/0007_household.sql`, `Core/Sources/Core/Household/{HouseholdModels,HouseholdClient}.swift`, `Core/Sources/Core/Planner/PlannerShare.swift`, `Core/Sources/Core/Copy/HouseholdCopy.swift`, `Core/Tests/CoreTests/HouseholdTests.swift`, `App/ZANO/Features/Household/{HouseholdView,HouseholdTaskEditor}.swift`; edited `PlannerStore` (mirror of my assigned shared tasks), `PlannerReminders` (plans them), `PlannerCopy`, `PlannerView` and `PlannerTaskEditor` (share buttons), `SettingsView` (gated row), `docs/spec.md`, privacy policy and label docs, Supabase setup guide.
- **What changed:** (1) works today: "Share this day" and "Share task" through the system share sheet; events can be shared with invitees through Apple's own editor. (2) Household: tables, RLS and RPCs; a client; a screen with start/join, the four-group board, add-task sheet with assignee, tick-off, invite code share, leave; assigned-to-me dated tasks become local reminders.
- **Decisions:** separate from Family Link (different shape and rules); no photos, locations or chat; members choose their displayed name; max 8 members and 5 households per person; the owner role passes on when the owner leaves; the user id is read from the token's `sub` so no extra endpoint is needed; same availability-flag pattern as Family Link, flipped in step 10 of the setup guide.
- **Known issues / not done:** no push (an assignment shows next time the app opens); no comments or recurring tasks; the shared list doesn't appear inside the Planner agenda yet; owner can't remove another member; nothing has run against a live project.
- **Needs verification on:** CI compile and `HouseholdTests`; a live Supabase project with two accounts for everything server-side.
