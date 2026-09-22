import Foundation
import SwiftData

/// A named, reusable set of apps/categories the user locks together (e.g. "Distractions",
/// "Social + Games"). A `LockSession` references one of these by id when a lock starts.
///
/// Mirrors `lock_sets` in `backend/supabase/migrations/0001_init.sql` field-for-field
/// (docs/spec.md §13):
/// ```sql
/// create table lock_sets (
///     id uuid primary key default gen_random_uuid(),
///     user_id uuid not null references users(id) on delete cascade,
///     name text not null,
///     app_tokens_blob bytea,
///     is_default boolean not null default false
/// );
/// ```
///
/// **`appTokensBlob` never leaves the device.** FamilyControls' opaque `ApplicationToken` /
/// `ActivityCategoryToken` / `WebDomainToken` values (as captured in a `FamilyActivitySelection`
/// and encoded via its `Codable` conformance) are meaningless outside the device that granted
/// them, and Apple's usage terms treat them as sensitive — they must not be transmitted. The
/// Postgres mirror of this table keeps an `app_tokens_blob bytea` column only for schema
/// completeness (see the migration's header comment and docs/spec.md §13/§24); the Sync
/// module's outbox (Session 7, `Core/Sources/Core/Sync`) MUST exclude this property from every
/// upload/download payload and only ever sync `id`, `name`, and `isDefault`. LockEngine owns
/// encoding/decoding a `FamilyActivitySelection` into/out of this blob — this type is storage
/// only and intentionally has no FamilyControls import.
@Model
public final class LockSet {
    /// Matches `lock_sets.id uuid primary key`.
    @Attribute(.unique) public var id: UUID

    /// Matches `lock_sets.user_id uuid not null`.
    public var userID: UUID

    /// Matches `lock_sets.name text not null`. User-facing label (e.g. "Distractions") — the
    /// only piece of this model that's safe, and useful, to show in copy or sync remotely.
    public var name: String

    /// Matches `lock_sets.app_tokens_blob bytea` (nullable in Postgres; also optional here
    /// because a freshly-created lock set may not have an app selection yet). Device-local
    /// only — see the type-level doc comment. Expected contents: a `FamilyActivitySelection`
    /// JSON-encoded by LockEngine (`try JSONEncoder().encode(selection)`), not raw tokens.
    public var appTokensBlob: Data?

    /// Matches `lock_sets.is_default boolean not null default false`. The lock set applied
    /// when the user hasn't chosen one explicitly (e.g. NFC tap with no tag mapping, or the
    /// end of onboarding's first-win flow).
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        userID: UUID,
        name: String,
        appTokensBlob: Data? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.appTokensBlob = appTokensBlob
        self.isDefault = isDefault
    }
}
