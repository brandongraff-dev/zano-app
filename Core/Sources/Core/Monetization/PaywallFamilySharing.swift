// PaywallFamilySharing.swift
// Core / Monetization
//
// Session 43: one ZANO Pro purchase can cover a whole Apple Family Sharing group (the organizer plus up to
// five others, six people in all). Apple turns this on per product in App Store Connect, and once it is on
// for a product it can't be turned off again (Apple, "Turn on Family Sharing for in-app purchases").
//
// Two switches have to agree before the paywall says anything about it:
//   1. `PaywallFamilySharing.isEnabled`, flipped by the founder in code once the box is ticked in App Store
//      Connect (docs/launch/final-checklist.md §D). It is the only switch for the Settings line, which has no
//      product to check against.
//   2. The selected package's `isFamilyShareable` (StoreKit's own answer, via RevenueCat), so a product
//      that was missed in App Store Connect is never advertised as shareable.
//
// Default `false`: nothing has been ticked in App Store Connect yet (the developer account isn't enrolled),
// and saying "share with your family" before it's true would be a false claim on a paywall.
//
// The ownership side needs no flag: if RevenueCat reports the entitlement as family-shared, it is.

import Foundation

public enum PaywallFamilySharing {
    /// Flip to `true` after Family Sharing is turned on for the subscription products in App Store Connect.
    public static let isEnabled = false

    /// Whether the paywall should mention Family Sharing for `package`.
    public static func applies(to package: SubscriptionPackage?, enabled: Bool = isEnabled) -> Bool {
        guard enabled, let package else { return false }
        return package.isFamilyShareable
    }

    /// Whether this person's Pro came from someone else in their family (so they can't manage its billing).
    public static func isSharedWithYou(_ entitlement: ProEntitlementInfo?) -> Bool {
        guard let entitlement, entitlement.isActive else { return false }
        return entitlement.ownership == .familyShared
    }
}
