// Core/Sources/Core/Models/KitchenStaple.swift
//
// Mirrors the `kitchen_staples` table field-for-field.
// Source of truth: docs/spec.md §5.20 (Protein Gap Planner — "something in their saved kitchen
// staples"), §10 ("Kitchen staples: user saves 10–20 staples once; the gap planner uses them
// first.") and backend/supabase/migrations/0005_kitchen_staples.sql ("kitchen_staples"):
//
//   create table if not exists public.kitchen_staples (
//       id uuid primary key default gen_random_uuid(),
//       user_id uuid not null references public.users(id) on delete cascade,
//       name text not null,
//       protein_g numeric not null check (protein_g >= 0),
//       created_at timestamptz not null default now()
//   );
//
// This is the on-device (SwiftData, App Group–backed) mirror of that row, consumed by
// `Verification/ProteinGapPlanner.swift` (this same task) as Tier 1 of spec §5.20's ranked
// options — "always available", no network/vendor dependency, unlike Tier 2 (restaurant) and
// Tier 3 (quick snack), which that file stubs pending spec §28's open vendor question.
//
// `kitchen_staples` is not part of docs/spec.md §13's frozen Data Model table (that table
// predates §5.20/§10 being fleshed out) — same situation backend/supabase/migrations/0002-0004
// were already in for their own new tables (user_day_features, waitlist_signups): additive,
// not a §13 edit. §13's blanket "RLS = user_id = auth.uid() on everything" rule still applies
// (see the migration file).
//
// No relationship to `User` is wired up here, matching `Gym.swift`/`Meal.swift`'s own precedent
// for a simple, flat, user-owned row: `ProteinGapPlanner` looks staples up by `userID: UUID`
// from the shared `ModelContext`, not via a `User.kitchenStaples` inverse.
//
// *** INTEGRATION GAP — flagged, not fixed here (out of this task's owned file list) ***
// `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`'s `appGroupModelTypes` array is the
// fixed list of every `@Model` type the shared App Group `Schema` knows about; that file's own
// header comment is explicit that a type left off the list "compile[s] fine ... but silently
// drop[s] every ... row at runtime" the moment something fetches/inserts it via
// `ModelContainer.appGroup`. `KitchenStaple.self` is NOT yet added to that array — this task's
// own scope is exactly three files (this model, the migration, `ProteinGapPlanner.swift`) and
// does not include `Store/ModelContainer+AppGroup.swift`, so it is deliberately left untouched
// here rather than guessed at. Whoever next owns that file (or a dedicated follow-up task) must
// add `KitchenStaple.self` to `appGroupModelTypes` before any real on-device fetch/insert of this
// model will work; until then `ProteinGapPlanner`'s Tier 1 will silently see zero staples against
// the real App Group container. See this task's `knownIssues`.

import Foundation
import SwiftData

/// A single user-saved "kitchen staple" — a food the user always has on hand and already knows
/// the protein content of (e.g. "Greek yogurt tub", "Rotisserie chicken"), saved once (spec §10:
/// "user saves 10–20 staples once") and reused by the Protein Gap Planner (spec §5.20) as the
/// zero-friction, zero-network first option for closing today's protein gap.
///
/// The "10–20 staples" figure in spec §10 is a UX expectation for onboarding/Kitchen Staples
/// setup (how many the product nudges a user to save), not a hard cap enforced here or in the
/// migration's schema — same reasoning `Goal.swift`'s header gives for `goals.type` having no
/// Postgres check constraint despite the catalog being effectively fixed: keeping the data layer
/// unconstrained avoids a false ceiling turning into a support ticket. If a future session wants
/// a real UI-level guardrail (e.g. "you've saved 20 staples — remove one to add another"), that
/// belongs in the Kitchen Staples setup screen, not this model.
@Model
public final class KitchenStaple {
    /// Primary key. Matches `kitchen_staples.id` (`uuid primary key default gen_random_uuid()`).
    @Attribute(.unique)
    public var id: UUID

    /// Matches `kitchen_staples.user_id`. Owning user of this saved staple.
    public var userID: UUID

    /// Matches `kitchen_staples.name` (`text not null`) — user-facing label, e.g. "Greek yogurt
    /// tub", "2 hard-boiled eggs", "Rotisserie chicken (3 oz)". Free text: this is the user's own
    /// shorthand for something already sitting in their kitchen, not a catalog lookup.
    public var name: String

    /// Matches `kitchen_staples.protein_g` (`numeric not null check (protein_g >= 0)`). Grams of
    /// protein this staple provides — the figure `ProteinGapPlanner` ranks by proximity to the
    /// user's remaining gap for the day.
    public var proteinG: Double

    /// Matches `kitchen_staples.created_at`.
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        name: String,
        proteinG: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.proteinG = proteinG
        self.createdAt = createdAt
    }
}
