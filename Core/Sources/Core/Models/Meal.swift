// Core/Sources/Core/Models/Meal.swift
//
// Mirrors the `meals` table field-for-field, minus `embedding`.
// Source of truth: docs/spec.md §13 (Data Model), §5.19 (Quick Repeats & Food Memory),
// §9.5 (Meal Vision) and backend/supabase/migrations/0001_init.sql ("meals").
//
//   create table meals (
//       id uuid primary key default gen_random_uuid(),
//       user_id uuid not null references users(id) on delete cascade,
//       ts timestamptz not null default now(),
//       photo_path text,
//       items jsonb not null default '[]'::jsonb,
//       protein_g numeric,
//       confirmed boolean not null default false,
//       embedding vector(1536)   -- dimension is a placeholder, Session 8 picks the model
//   );
//
// `embedding` is deliberately NOT mirrored here: per this session's task, it exists only
// server-side to power Quick Repeats similarity search (pgvector cosine search, §5.19) and is
// computed/stored by the Session 8 (`feat/ai`) meal-vision Edge Function, not on-device. If a
// future session needs on-device Quick Repeats ranking without a network round trip, that's a new
// field/decision for that session, not an extension of this one.

import Foundation
import SwiftData

/// One vision-model item line inside a meal's `items` jsonb array (spec §9.5): the vision LLM
/// returns strict JSON shaped `{items:[{name, grams_protein_est, confidence}], total_protein,
/// notes}`; `Meal.items` mirrors that `items` array. `Meal.proteinG` mirrors the response's
/// `total_protein` after the user confirms/edits it with a slider — `notes` is not persisted
/// (it isn't a `meals` column).
///
/// Stored inline as part of `Meal.items`; SwiftData persists `Codable` value-type properties
/// (and arrays of them) directly, matching the `jsonb` column on the Postgres side.
public struct MealItem: Codable, Hashable, Sendable {
    enum CodingKeys: String, CodingKey {
        case name
        case proteinGramsEstimate = "grams_protein_est"
        case confidence
    }

    /// Vision model's label for this food item, e.g. "grilled chicken breast".
    public var name: String

    /// Vision model's estimated protein contribution of this item, in grams.
    public var proteinGramsEstimate: Double

    /// Vision model's confidence for this item's estimate, 0...1.
    public var confidence: Double

    public init(name: String, proteinGramsEstimate: Double, confidence: Double) {
        self.name = name
        self.proteinGramsEstimate = proteinGramsEstimate
        self.confidence = confidence
    }
}

/// A logged meal: a photo-derived (or manually entered) protein estimate, confirmed by the user,
/// and the basis for Quick Repeats ("Your usual chicken bowl (48g)?", spec §5.19). Tier B
/// verification source for the Protein goal (spec §3).
///
/// Only protein (and, per spec §5.19/§9.5, optionally calories as a soft, hidden-by-default
/// number that is NOT part of this schema) is tracked — additive framing only, never a calorie
/// ceiling or restrictive target (spec §24).
@Model
public final class Meal {
    /// Primary key. Matches `meals.id` (`uuid primary key default gen_random_uuid()`).
    @Attribute(.unique)
    public var id: UUID

    /// Matches `meals.user_id`. Owning user of this meal.
    public var userID: UUID

    /// Matches `meals.ts` (`timestamptz not null default now()`). When the meal was logged.
    public var ts: Date

    /// Matches `meals.photo_path` (`text`, nullable). Local path to the meal photo inside the
    /// `group.com.zano.app` App Group container (never a remote URL on-device); Sync (Session 7)
    /// owns uploading it to Supabase Storage and reconciling this field with the remote path.
    public var photoPath: String?

    /// Matches `meals.items` (`jsonb not null default '[]'::jsonb`). The vision model's
    /// item-level breakdown, or a single manually-entered item for non-photo logging paths (NFC
    /// tap, quick-repeat, barcode).
    public var items: [MealItem]

    /// Matches `meals.protein_g` (`numeric`, nullable). Total protein for this meal in grams,
    /// after user confirmation/edit.
    public var proteinG: Double?

    /// Matches `meals.confirmed` (`boolean not null default false`). True once the user has
    /// confirmed (or edited then confirmed) the vision estimate; unconfirmed meals are pending
    /// review and should not count toward the Protein goal.
    public var confirmed: Bool

    public init(
        id: UUID = UUID(),
        userID: UUID,
        ts: Date = Date(),
        photoPath: String? = nil,
        items: [MealItem] = [],
        proteinG: Double? = nil,
        confirmed: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.ts = ts
        self.photoPath = photoPath
        self.items = items
        self.proteinG = proteinG
        self.confirmed = confirmed
    }
}
