import Foundation
import SwiftData

/// A user's subscription state as last reported by the RevenueCat webhook (spec §21). One row per
/// user; the app reads this to gate Pro features (unlimited goals & lock sets, schedules, adaptive
/// plan, Earn Mode, protein photo AI, recaps, squads/duels, 3 streak freezes, cosmetics) versus Free
/// (1 goal, 1 lock set, manual/NFC lock, basic widget, 1 streak freeze/week).
///
/// Mirrors the Supabase `subscriptions` table (`backend/supabase/migrations/0001_init.sql`)
/// field-for-field. Postgres has no surrogate id there — its primary key is `user_id` itself.
/// SwiftData still needs its own stored identity property, so `id` below is a local-only SwiftData
/// identity; the Sync outbox (Session 7) reconciles rows against the server by `userID`, not `id`.
///
/// `status` and `product` are kept as raw strings rather than enums: the Postgres migration leaves
/// them unconstrained (no `check`) because they pass through whatever RevenueCat's webhook sends,
/// and that taxonomy (subscriber status strings, App Store Connect product identifiers) is owned by
/// RevenueCat/App Store Connect config, not this spec — constraining it here risks silently
/// dropping a legitimate webhook value this file's author didn't anticipate.
@Model
public final class Subscription {
    /// Local SwiftData identity only — no Postgres counterpart (see type doc comment above).
    @Attribute(.unique) public var id: UUID

    /// Mirrors `subscriptions.user_id`, the remote table's actual primary key.
    public var userID: UUID

    /// Mirrors `subscriptions.rc_customer_id` — RevenueCat's `app_user_id` / customer id.
    public var rcCustomerID: String?

    /// Mirrors `subscriptions.status` — RevenueCat subscriber status passthrough (e.g. `"active"`,
    /// `"expired"`, `"in_grace_period"`, `"in_billing_retry_period"`, `"cancelled"`, `"paused"`).
    /// Best-effort set, not enforced — see type doc comment.
    public var status: String?

    /// Mirrors `subscriptions.product` — the App Store Connect / RevenueCat product identifier the
    /// subscription is on (spec §21 price tests: monthly $6.99, annual $39.99 highlighted, lifetime
    /// $59.99 test-only).
    public var product: String?

    /// Mirrors `subscriptions.renews_at`.
    public var renewsAt: Date?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        rcCustomerID: String? = nil,
        status: String? = nil,
        product: String? = nil,
        renewsAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.rcCustomerID = rcCustomerID
        self.status = status
        self.product = product
        self.renewsAt = renewsAt
    }
}
