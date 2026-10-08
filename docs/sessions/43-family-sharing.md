# Session 43 — Family Sharing on the subscription

- **Branch:** `claude/dazzling-hypatia-ed6q5d` (worktree)
- **Spec sections:** §21 (Monetization & Paywall: tiers, "no dark patterns", restore visible), §24 (honest paywall claims)
- **Status:** Scaffolded — Unverified (not compiled yet; the claim is switched off until App Store Connect has Family Sharing on)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder's request (2026-10-08): one purchase covers up to 6 people through Apple Family Sharing for the
auto-renewable subscriptions. The paywall and Settings say so (only for products where it's on), a person whose
Pro is shared by their family sees "Shared with you by your family" instead of a "Manage subscription" button
that can't help them, and the launch docs carry the App Store Connect step.

## Definition of done

- CI compiles; `FamilySharingTests` pass.
- Sandbox, after the App Store Connect switch: the paywall shows the Family Sharing line only on shareable
  plans; a second Apple Account in the same family group sees "Shared with you by your family" in Settings.

## Log

### 2026-10-08 — Ownership, shareable flag, paywall line, Settings state, docs

- **Files touched:**
  - new `Core/Sources/Core/Monetization/PaywallFamilySharing.swift` (flag + pure decisions)
  - new `Core/Tests/CoreTests/FamilySharingTests.swift`
  - `Core/Sources/Core/Monetization/RevenueCatManager.swift`: `SubscriptionPackage.isFamilyShareable`
    (from `StoreProduct.isFamilyShareable`), new `SubscriptionOwnership`, `ProEntitlementInfo.ownership`
    (from `EntitlementInfo.ownershipType`); both new init parameters have defaults, so existing callers compile unchanged
  - `Core/Sources/Core/Copy/PaywallCopy.swift`, `Core/Sources/Core/Copy/SettingsCopy.swift`: new strings
  - `App/ZANO/Features/Onboarding/PaywallView.swift`: `familySharingLine` under the reassurance line
  - `App/ZANO/Features/Settings/SettingsView.swift`: plan card status, info note, and manage button follow ownership
  - `docs/launch/final-checklist.md` §D, `docs/launch/terms-of-use.md` §3 (`[CONFIRM: Family Sharing]` bullet)
- **What changed:**
  - **Paywall.** A small "Share it with your family through Family Sharing, up to 6 people." line appears under
    "No payment due now / Cancel anytime" when **both** `PaywallFamilySharing.isEnabled` is true **and** the
    selected package's product is family-shareable according to StoreKit. Switching between monthly and annual
    shows or hides it per product.
  - **Settings.** When RevenueCat reports the Pro entitlement as `.familyShared` (and active), the status capsule
    reads "Shared with you by your family", and the "Manage subscription" button is replaced by a note that the
    person who bought it manages billing. For the buyer, the plan's info note gains a Family Sharing sentence once
    the flag is on. The card refreshes the entitlement once if nothing has been fetched yet.
- **Decisions made and why:**
  - **`PaywallFamilySharing.isEnabled` defaults to `false`.** Nothing has been switched on in App Store Connect
    (the developer account isn't enrolled), and a paywall claim that isn't true is the kind of thing §21/§24 rule
    out. The per-product StoreKit check makes the paywall line safe even after the flag is flipped; the Settings
    sentence has no product to check, so the flag is its only guard.
  - **"Up to 6 people"** = the Family Sharing group limit (organizer plus five). Settings says "up to 5 other people"
    because it's addressed to the buyer.
  - **`.unknown` ownership is treated as the person's own plan** (button stays), so nobody loses the way to cancel.
  - No change to entitlement checks: a family-shared entitlement is an active `pro` entitlement, so `EntitlementGate`
    already lets that person in.
- **Verified against sources (2026-10-08):** purchases-ios `main`: `EntitlementInfo.ownershipType:
  PurchaseOwnershipType` (`.purchased = 0`, `.familyShared = 1`, `.unknown = 2`); `StoreProduct.isFamilyShareable:
  Bool` (iOS 14+). Apple's App Store Connect help: Family Sharing is turned on per product and **can't be turned off**
  once on. Not checked against the pinned 5.92.0 tag itself (GitHub tag path wasn't reachable from here); both
  members have existed since 4.x, so this is low risk.
- **Known issues / TODOs left behind:**
  - The `Subscription` row in SwiftData (synced from the webhook) doesn't know about ownership; the card's "Renews"
    date for a family member comes from whatever the local row holds. RevenueCat's webhook does send
    `is_family_share`; storing it is not done (would need a migration).
  - No analytics event for family-shared users.
- **Needs verification on:** CI (compile + `FamilySharingTests`); sandbox purchase with a family-group account once
  the products exist in App Store Connect.

## Founder steps

1. In App Store Connect, turn on Family Sharing for each subscription (and the lifetime product if wanted). Irreversible per product.
2. Set `PaywallFamilySharing.isEnabled = true`.
3. Resolve `[CONFIRM: Family Sharing]` in the terms of use.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinating session)
- [x] No secrets committed
