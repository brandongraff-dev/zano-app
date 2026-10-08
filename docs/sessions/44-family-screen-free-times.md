# Session 44 — Family screen-free times

- **Branch:** `claude/dazzling-hypatia-ed6q5d` (worktree)
- **Spec sections:** §5.31 (Household; screen-free times added), §5.24 (focus lock, the hand-off reused), §5.10 (Bedtime Gate, the night math reused), §6, §11 (extensions read App Group only), §24 (emergency unlock, no forced locks, privacy), §27 (DeviceActivity: 15-minute minimum, activity cap, no Simulator)
- **Status:** Scaffolded — Unverified (not compiled yet; hidden until Household is live: needs the Supabase project with 0009 applied and sign-in; DeviceActivity needs a real device)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder's request (2026-10-08): a household (session 28) can create shared screen-free windows ("Dinner 6–7 pm
daily", "Bedtime 10 pm–7 am school nights"). Every member who opts in gets their own ZANO lock on their own phone
during the window, parents included. Nobody can force a lock on anyone: opt in per window, opt out any time,
emergency unlock as always; Family Controls tokens never leave the device (each member picks their own lock set).

## Definition of done

- CI compiles; `HouseholdQuietTimeTests` pass.
- Live project + two signed-in phones: A adds "Dinner", B sees it after reopening; B joins; at the start B's apps
  shield (app closed), A's don't (A didn't join); B's 60-second emergency unlock ends it and nothing re-arms that
  evening; at the end the shield lifts by itself; a crossing-midnight window lifts the next morning.
- The notification and Today chip appear 10 minutes before a joined window.

## Log

### 2026-10-08 — Table + RPCs, client, App Group store, scheduling through the existing monitor, UI, docs

- **Files touched:**
  - new `backend/supabase/migrations/0009_household_quiet_times.sql`
  - new `Core/Sources/Core/Household/HouseholdQuietTimes.swift` (model, `HouseholdQuietTimeActivity` names, pure `HouseholdQuietTimePlanner`, `HouseholdQuietTimeStore` App Group state)
  - new `Core/Sources/Core/Household/HouseholdQuietTimeScheduler.swift` (registration, join/leave, reminders, stand-down)
  - new `Core/Tests/CoreTests/HouseholdQuietTimeTests.swift`
  - new `App/ZANO/Features/Household/{HouseholdQuietTimesSection,HouseholdQuietTimeEditor,HouseholdQuietTimeChip}.swift`
  - `Core/Sources/Core/Household/HouseholdClient.swift` (fetch/create/update/delete)
  - `Core/Sources/Core/LockEngine/LockScheduler.swift` (`PendingScheduledLock.Source.household`; `ScheduledLockMonitor.quietTimeDidStart/quietTimeDidEnd`; the `.focus` hand-off now also serves `.household`)
  - `Core/Sources/Core/Copy/HouseholdCopy.swift`
  - `App/ZANO/Features/Household/HouseholdView.swift` (section + fetch), `App/ZANO/Features/Today/TodayView.swift` (chip), `App/ZANO/ContentView.swift` (foreground refresh)
  - `docs/spec.md` §5.31, `docs/launch/privacy-policy.md` (Household row, inside its `[CONFIRM WHEN HOUSEHOLD IS LIVE]` marker), `docs/launch/supabase-setup.md` step 3
- **What changed:**
  - **Backend (0009).** `household_quiet_times` (household_id, name, start_minute, end_minute, weekdays int[], created_by, created_at, updated_at) with checks matching the app (name 1–40, minutes 0–1439, days ⊆ 1–7, at least 15 minutes wrapping midnight). RLS like 0007: members read; no direct writes; security-definer RPCs: any member creates (max 20 per household), creator or owner updates/deletes.
  - **Window math reused, not rewritten.** A screen-free time is turned into a `BedtimeGateSchedule` (start = "bedtime", end = "wake", days = "nights"), which already handles crossing midnight, weekly windows whose end lands on the next weekday, early/late callbacks and stray end callbacks.
  - **Scheduling reuses the lock path.** `HouseholdQuietTimeScheduler` registers repeating DeviceActivity windows under `com.zano.app.quiet.<id>[.d<weekday>]` (own prefix, so lock schedules/focus/bedtime never touch them), re-registering only when the joined set's signature changes or registrations are missing. In `ZANOMonitor`, `ScheduledLockMonitor.quietTimeDidStart` shields this phone's chosen lock set (or the default) via the existing `arm` with no goals and a `.household` pending record; `LockScheduler.convert` adopts it exactly like a focus window (session with no required goals, owned by the window); `quietTimeDidEnd` lifts it via `endScheduledLock`.
  - **Overlap.** Existing reconciliation: `arm` never stacks on an active or pending lock; the occurrence is then marked decided and the running lock carries on.
  - **One decision per occurrence** (`HouseholdQuietTimeStore.hasDecided/markDecided`), like the Bedtime Gate's per-night record: a repeated start callback or a re-registration never re-arms after an emergency unlock.
  - **Opt-in on device.** `HouseholdQuietTimeOptIn` (window id, lock set id or default, joined at) lives only in the App Group. Joining while a window is under way marks that occurrence decided, so it starts next time (no surprise lock). Leaving (or the window being deleted, or leaving the household) ends a lock that window is running, recorded as a manual end. When Household isn't live (signed out), every registration and reminder is stopped and any running screen-free lock ends; joins are kept for when they sign back in.
  - **Cap.** Joined windows may use 7 DeviceActivity registrations together (an every-day window uses 1, otherwise 1 per day); the Join switch is disabled with a note when a window wouldn't fit.
  - **Heads-up.** Local notifications 10 minutes before each joined window for the next 7 days (max 14, replaced on every sync, own `household.quiet.` identifiers), and a Today chip ("Dinner in 10 min · phones down together", then "Dinner · phones down until 7:00 PM").
  - **UI.** Household screen > "Screen-free times": list (name, hours, days, who added it), Join switch, lock set picker once joined, Edit for creator/owner; add/edit sheet with name, start, end ("Ends the next morning" when it crosses midnight), day buttons, Delete.
- **Decisions made and why:**
  - **No server record of who joined** (the brief left it optional). "4 of 5 joined" would tell the household who is and isn't locking their phone, which is exactly the kind of screen-time information §5.31 promised a household never sees, and it could turn opting in into pressure. Kept off; easy to add later as a boolean if the founder wants it.
  - **No goals to earn** during a window (like a focus window): it's a shared pause, not a goal gate. Mode `.full`.
  - **Opting out mid-window ends the lock.** "Opt out anytime" should mean the lock stops, not "after the window". Recorded as `.manual`, not `.emergency`, so it doesn't count against the person.
  - **School nights** label for Sunday–Thursday start days, since windows are keyed by the day they start.
- **Known issues / TODOs left behind:**
  - **Unverified API (same as session 38):** repeating `DeviceActivitySchedule`s whose end is earlier than the start, and weekly windows with different start/end weekdays. If the end never fires on a device, split into two windows.
  - Joined windows and the activity cap: lock schedules (up to 7 per lock set), the Bedtime Gate (up to 7), focus windows (up to 8) and these (up to 7) can together exceed Apple's believed limit of 20 (UNVERIFIED). Registration failures are logged, not surfaced.
  - No push: an added or edited window reaches other phones when they next open ZANO (foreground refresh). A deleted window keeps locking a phone until that phone next opens the app.
  - "Next lock" (`SharedDefaults.nextScheduledLockAt`) doesn't include screen-free times; the Lock tab won't list them.
  - A screen-free lock adopted while a Bedtime Gate night starts: the gate sees a running lock and skips that night (existing no-stack rule). Fine for dinner; for a household bedtime window that overlaps the person's own Bedtime Gate, the window's end lifts the lock and the gate doesn't re-arm that night.
  - Times are read in each phone's own time zone; a household split across zones gets the same wall-clock times.
  - PostgREST array params (`p_weekdays` as a JSON array into `integer[]`) are written from memory, like the rest of the Household client.
- **Needs verification on:** CI (compile + `HouseholdQuietTimeTests`); a live Supabase project with 0009 and two accounts; a **real device** for DeviceActivity start/end with the app closed, the crossing-midnight end, emergency unlock, and notifications.

## Founder steps

1. Apply `0009_household_quiet_times.sql` (`supabase db push`, docs/launch/supabase-setup.md step 3).
2. Nothing else: it appears with Household when Supabase keys and sign-in are live.
3. When Household goes live, resolve the privacy policy's `[CONFIRM WHEN HOUSEHOLD IS LIVE]` row (now also mentions screen-free times).

## Blockers

- No Mac or device here; CI is the compiler. DeviceActivity doesn't run in the Simulator (§27). Household needs the Supabase project and sign-in (session 34). Family Controls entitlement not filed.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinating session)
- [x] No secrets committed
