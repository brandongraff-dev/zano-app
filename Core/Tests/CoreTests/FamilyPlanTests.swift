// FamilyPlanTests.swift
// CoreTests
//
// docs/spec.md §21 (decision 2026-10-06): the Family annual plan never takes the individual annual
// plan's place as the default selection, and the paywall lays plans out as monthly, individual
// annual, anything else, then Family as the full-width bar at the bottom. Pure logic: nothing here touches RevenueCat.

import Testing
@testable import Core

@Suite("Family plan")
struct FamilyPlanTests {

    private func package(
        _ id: String,
        _ period: SubscriptionPackage.Period,
        family: Bool = false
    ) -> SubscriptionPackage {
        SubscriptionPackage(
            id: id,
            productIdentifier: "zano.\(id)",
            period: period,
            priceString: "$1",
            isFamilyShareable: family
        )
    }

    @MainActor @Test func defaultSelectionSkipsFamilyEvenWhenListedFirst() {
        let packages = [package("family", .annual, family: true), package("monthly", .monthly), package("annual", .annual)]
        #expect(PaywallViewModel.defaultSelection(in: packages) == "annual")
    }

    @MainActor @Test func defaultSelectionFallsBackToFamilyWhenItIsTheOnlyAnnual() {
        let packages = [package("monthly", .monthly), package("family", .annual, family: true)]
        #expect(PaywallViewModel.defaultSelection(in: packages) == "family")
    }

    @MainActor @Test func defaultSelectionFallsBackToFirstWithNoAnnual() {
        #expect(PaywallViewModel.defaultSelection(in: [package("monthly", .monthly)]) == "monthly")
        #expect(PaywallViewModel.defaultSelection(in: []) == nil)
    }

    @MainActor @Test func displayOrderIsMonthlyAnnualRestThenFamily() {
        let packages = [
            package("lifetime", .lifetime),
            package("family", .annual, family: true),
            package("annual", .annual),
            package("weekly", .weekly),
            package("monthly", .monthly),
        ]
        #expect(PaywallViewModel.displayOrder(packages).map(\.id) == ["monthly", "annual", "lifetime", "weekly", "family"])
    }

    @Test func packagesAreNotFamilyShareableByDefault() {
        let plain = SubscriptionPackage(id: "a", productIdentifier: "a", period: .annual, priceString: "$1")
        #expect(!plain.isFamilyShareable)
    }
}
