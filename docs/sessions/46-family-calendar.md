# Session 46 — Family calendar with privacy per event

- **Branch:** worktree branch, based on `origin/claude/dazzling-hypatia-ed6q5d` at `6dc5dd3`
- **Spec sections:** §5.30 (Planner: events, "Who can see this", merge, alerts), §5.31 (Household: family calendar), §24 (privacy: "Only me" never uploaded)
- **Status:** Scaffolded — Unverified (not compiled yet; the shared half is hidden until Household is live: needs the Supabase project with 0011 applied and sign-in. Private "Only me" events work offline in any build)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder (2026-10-08): "the calendar should be shared but also the option to add a private calendar or make it
private to yourself only or share with a certain family member."

1. Household events in Supabase (`0011_household_events.sql`) with per-event visibility (`household` or
   `members` + `audience`). RLS is the privacy boundary; creator-only writes; owner may delete; audience checked
   against the household; cap 500 upcoming per household.
2. "Only me" events never uploaded: kept on the iPhone (Planner's App Group store), or the person's own iOS
   calendars through Apple's editor. Said plainly in the form.
3. Planner: "Who can see this" (Only me / Everyone in <household> / Choose people), merged month grid and day
   agenda with owner/visibility marks, Calendars filter, edit/delete own, read-only "Added by <name>" for others.
4. Alerts for shared events follow the planner's existing reminder rule, locally.
5. Household parts hidden when `HouseholdAvailability.isLive` is false; private events always work.

## Definition of done

- CI compiles; `HouseholdEventTests` (and the existing `PlannerTests`, `HouseholdTests`) pass.
- Any build, offline: "New event" > Only me saves an event that shows with a lock on the grid and agenda, edits,
  deletes, and alerts (when event alerts are on).
- Live project + two signed-in phones in one household: A adds "Soccer" for everyone; B sees it after reopening
  with "Added by A", read only. A adds "Surprise" for C only; B never receives the row (check the network
  response, not just the screen). A moves an event from Only me to Everyone and back. B leaves; B's events
  disappear for A.

## Log

### 2026-10-08 — Migration, Core model/rules/cache, client, Planner UI, docs

- **Files touched:**
  - new `backend/supabase/migrations/0011_household_events.sql`
  - new `Core/Sources/Core/Household/HouseholdEvents.swift` (`HouseholdEvent`, `HouseholdEventVisibility`,
    `PlannerEventSharing`, pure `HouseholdEventRules`, `PlannerEventTimes`, App Group `HouseholdEventStore` + `refresh()`)
  - `Core/Sources/Core/Household/HouseholdClient.swift` (`events`, `createEvent`, `updateEvent`, `deleteEvent`, private `send`)
  - `Core/Sources/Core/Planner/PlannerModels.swift` (`PlannerEventOrigin`, `PlannerEvent.origin/notes`, `PlannerPrivateEvent`, `PlannerCalendarFilter`)
  - `Core/Sources/Core/Planner/PlannerAgenda.swift` (`merge`)
  - `Core/Sources/Core/Planner/PlannerStore.swift` (`privateEvents`, `calendarFilter`, upsert/delete, prune)
  - `Core/Sources/Core/Planner/PlannerReminders.swift` (`refresh` plans alerts for the merged list)
  - `Core/Sources/Core/Copy/PlannerCopy.swift`, `Core/Sources/Core/Copy/HouseholdCopy.swift`
  - new `Core/Tests/CoreTests/HouseholdEventTests.swift`
  - new `App/ZANO/Features/Planner/PlannerZanoEventEditor.swift` (form with "Who can see this")
  - new `App/ZANO/Features/Planner/PlannerEventDetailView.swift` (read-only sheet + `PlannerEventOwnership` wording/glyphs)
  - `App/ZANO/Features/Planner/PlannerView.swift` (merge, marks, tap to open, Calendars menu, family refresh)
  - `App/ZANO/Features/Household/HouseholdView.swift` (keeps the calendar cache's household/members in step; clears it when there's no household)
  - `App/ZANO/ContentView.swift` (foreground refresh of the cache, then reminders)
  - `App/ZANO/ScreenshotGallery.swift` (planner shot seeds one "Only me" event; other shots clear them)
  - `docs/spec.md` §5.30, §5.31; `docs/launch/privacy-policy.md` (Household row, inside its `[CONFIRM WHEN HOUSEHOLD IS LIVE]` marker); `docs/launch/supabase-setup.md` step 3
- **What changed:**
  - **Backend (0011).** `household_events` with checks (title 1–120, notes ≤ 500, end ≥ start, ≤ 31 days,
    `household` ⇒ empty audience, `members` ⇒ ≤ 7). Policies: SELECT = member AND (creator OR household-wide OR
    `auth.uid() = any(audience)`); INSERT/UPDATE = creator, member; DELETE = creator or owner (Postgres also
    applies SELECT to a DELETE's rows, so an owner can't delete or even see an event they aren't in). A security-
    definer `before insert or update` trigger stamps `created_by`/timestamps, refuses changing household or
    creator, dedupes the audience, drops the creator from it, requires someone (`empty_audience`), checks every id
    is a member (`bad_audience`), and caps 500 upcoming per household (`too_many_events`, advisory-locked per
    household). An `after delete` trigger on `household_members` deletes the leaver's own events and removes
    them from audiences (an audience emptied this way leaves the event to its creator only; the trigger-depth
    check allows exactly that). Optional `clear_old_household_events()` for 90-day cleanup.
  - **"Only me" is a different storage, not a visibility value.** There is no `private` value in the table, so
    a private event can't be uploaded by a bug in a picker. `PlannerPrivateEvent` lives in `PlannerStore`
    (App Group JSON, ≤ 500, ended > 90 days dropped).
  - **Merge.** `PlannerAgenda.merge` returns one sorted `[PlannerEvent]` with an `origin` (`device`, `onlyMe`,
    `household(createdBy, visibility, audience)`); household rows pass `HouseholdEventRules.visible` again (the
    client-side mirror of the policy) and are left out unless Household is live and the family calendar is shown.
    Month grid dots, the day agenda, Cal's mood and the day share all use it unchanged.
  - **UI.** "New event" opens the ZANO form; "Add to my iPhone calendar instead" hands over to Apple's editor
    (opened after the form's sheet is gone). Agenda rows: a lock for only me, people for shared; subtitle "Only
    you" / "Everyone in Home" / "You, Sam and Alex" for mine, "Added by Sam" for others'; VoiceOver value says
    who can see it. Tap opens the form (mine) or a read-only sheet (others'). Toolbar "Calendars" menu: Family
    calendar (live only), iPhone calendars (with access only).
  - **Moving between private and shared.** Shared → only me deletes the server copy first, then saves locally
    (a failure leaves no duplicate); only me → shared creates on the server, then drops the local copy.
  - **Cache + alerts.** `HouseholdEventStore` keeps household, members, me and visible events in the App Group;
    refreshed when the Planner opens and on every foreground. `PlannerReminders.refresh` plans "starts soon"
    alerts for the merged list under the existing `eventAlerts` setting (40-notification cap unchanged).
- **Decisions made and why:**
  - **Table writes through RLS, not RPCs** (unlike 0007/0009): the founder named RLS as the boundary and the
    rules are expressible as policies; the trigger covers what policies can't. Reads are plain selects.
  - **Device calendar filter is all-or-nothing.** The Planner never had per-calendar selection; adding a source
    picker was out of scope. Private ZANO events can't be hidden (they're the person's own).
  - **Hidden calendars don't alert.** Hiding the family calendar now also stops its alerts; seemed the expected
    meaning of "hide".
  - **Creator buddy avatar on rows** is left to session 47, which adds the member `buddy` column.
- **Known issues / TODOs left behind:**
  - No push: other members see a new or changed event the next time they open ZANO.
  - All-day events are stored at the creator's local midnight; members in another time zone see them shifted.
  - No repeats, invitees, locations or per-event alerts on ZANO events (Apple's editor still covers those for
    the iPhone's own calendars).
  - Fetch window: events ending in the last 62 days and later, max 600 rows; months further back show no
    family events.
  - PostgREST details written from memory: `Prefer: return=representation` on PATCH/DELETE returning the rows
    (used to tell "not yours" from success), array body for `uuid[]`, `ends_at=gte.<ISO>` filter.
  - The Starts/Ends pickers switch between date-only and date-and-time with All-day; they carry an `.id` per mode
    so SwiftUI rebuilds them (UNVERIFIED on a device).
- **Needs verification on:** CI (compile + `HouseholdEventTests`); a live Supabase project with 0011 and two or
  three accounts (RLS is the thing to test: a row not meant for B must not be in B's response); Simulator for the
  form and agenda marks.

## Founder steps

1. Apply `0011_household_events.sql` (`supabase db push`, docs/launch/supabase-setup.md step 3).
2. Optional: schedule `select public.clear_old_household_events();` daily next to the existing cleanup job.
3. When Household goes live, resolve the privacy policy's `[CONFIRM WHEN HOUSEHOLD IS LIVE]` row (now mentions
   shared calendar events) and the privacy labels' Household line (Other User Content covers event text).

## Blockers

- No Mac or device here; CI is the compiler. Household needs the Supabase project and sign-in (session 34).

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinating session)
- [x] No secrets committed
