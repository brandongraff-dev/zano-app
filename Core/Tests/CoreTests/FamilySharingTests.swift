import Testing
import Foundation
@testable import Core

@Suite("Family Sharing on the subscription (session 43)")
struct FamilySharingTests {
    private func package(shareable: Bool) -> SubscriptionPackage {
        SubscriptionPackage(
            id: "$rc_annual", productIdentifier: "zano_pro_annual", period: .annual,
            priceString: "$39.99", isFamilyShareable: shareable
        )
    }

    @Test func claimIsOffByDefaultUntilTheFounderFlipsIt() {
        #expect(PaywallFamilySharing.isEnabled == false)
        #expect(PaywallFamilySharing.applies(to: package(shareable: true)) == false)
    }

    @Test func claimNeedsBothTheFlagAndAShareableProduct() {
        #expect(PaywallFamilySharing.applies(to: package(shareable: true), enabled: true))
        #expect(!PaywallFamilySharing.applies(to: package(shareable: false), enabled: true))
        #expect(!PaywallFamilySharing.applies(to: package(shareable: true), enabled: false))
        #expect(!PaywallFamilySharing.applies(to: nil, enabled: true))
    }

    @Test func packagesDefaultToNotShareable() {
        let plain = SubscriptionPackage(id: "m", productIdentifier: "p", period: .monthly, priceString: "$6.99")
        #expect(plain.isFamilyShareable == false)
    }

    @Test func sharedWithYouOnlyForAnActiveFamilySharedEntitlement() {
        let shared = ProEntitlementInfo(isActive: true, isTrial: false, expirationDate: nil, willRenew: true, ownership: .familyShared)
        let mine = ProEntitlementInfo(isActive: true, isTrial: false, expirationDate: nil, willRenew: true)
        let lapsedShared = ProEntitlementInfo(isActive: false, isTrial: false, expirationDate: nil, willRenew: false, ownership: .familyShared)
        let unknown = ProEntitlementInfo(isActive: true, isTrial: false, expirationDate: nil, willRenew: true, ownership: .unknown)
        #expect(PaywallFamilySharing.isSharedWithYou(shared))
        #expect(!PaywallFamilySharing.isSharedWithYou(mine))
        #expect(!PaywallFamilySharing.isSharedWithYou(lapsedShared))
        #expect(!PaywallFamilySharing.isSharedWithYou(unknown))
        #expect(!PaywallFamilySharing.isSharedWithYou(nil))
        #expect(mine.ownership == .purchased)
    }
}
