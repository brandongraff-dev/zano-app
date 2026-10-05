# Session 23 — Family Link (parent tasks with view-once photo proof)

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.23, §24
- **Status:** Scaffolded — Unverified. Blocked on Supabase project, Supabase Auth, Apple Developer enrollment
- **Started / Last updated:** 2026-10-05

## Log

### 2026-10-05

- **Files touched:** new `backend/supabase/migrations/0006_family_link.sql`, `functions/family-proof-{open,cleanup}`, `Core/Sources/Core/Family/*`, `Copy/FamilyCopy.swift`, `App/ZANO/Features/Family/FamilyLinkView.swift`, `FamilyTests.swift`; edited `SettingsView`
- **What changed:** Teen-consented link; parent sets tasks; teen hands in with an optional photo; parent approves or asks for a redo. The photo is private, opens once for the parent only (60 s signed URL), is deleted 10 min after the open or 24 h if unopened. Approved tasks can count toward a "Family tasks" goal. The screen says so and does nothing while no backend is configured.
- **Known issues / not done:** Nothing implements `SupabaseAuthTokenProviding`, so the feature is off. No screenshot notice to the teen (needs a server round trip). No push when a task is handed in. The cleanup cron is commented in the migration. Kids under 18 can still use ZANO alone.
- **Needs verification on:** Everything: a live Supabase project, migration, RLS, Edge Functions, and a two-device test

## Blockers

- No Mac or device here; CI is the compiler.
