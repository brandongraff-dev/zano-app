// FamilyHub.swift
// Core / Household
//
// The Family page (session 47, docs/spec.md §5.31): one place for everything family, with each member shown as the
// buddy they picked ("the family portrait"). The rules here are pure and tested (`FamilyHubTests`): when the page
// exists at all, which plan wording applies, how the portrait is arranged, the compact chores list, the next
// screen-free time. `HouseholdBuddySync` keeps this person's buddy and outfit on their household rows
// (`0012_household_member_buddy.sql`), display only.

import Foundation

// MARK: - When the page exists

public enum FamilyHubAvailability {
    /// Shown when Household is live (backend + sign-in), or when this person has a family plan: Pro shared with
    /// them by their family, or Pro they bought once Family Sharing is switched on for the products
    /// (`PaywallFamilySharing.isEnabled`). Never otherwise, so nobody meets a page of controls that can't work.
    public static func isVisible(
        householdLive: Bool, entitlement: ProEntitlementInfo?, familySharingEnabled: Bool = PaywallFamilySharing.isEnabled
    ) -> Bool {
        if householdLive { return true }
        return planStatus(entitlement: entitlement, familySharingEnabled: familySharingEnabled).isFamilyPlan
    }

    @MainActor public static var isVisible: Bool {
        isVisible(householdLive: HouseholdAvailability.isLive, entitlement: RevenueCatManager.shared.lastProEntitlement)
    }

    public enum PlanStatus: Equatable, Sendable {
        /// Someone in the person's Apple family group bought it.
        case sharedWithYou
        /// The person bought it, and Family Sharing is on for the products.
        case sharingWithFamily
        /// The person bought it; Family Sharing isn't switched on (yet).
        case yours
        /// No active Pro entitlement known.
        case noPlan

        public var isFamilyPlan: Bool { self == .sharedWithYou || self == .sharingWithFamily }
    }

    public static func planStatus(
        entitlement: ProEntitlementInfo?, familySharingEnabled: Bool = PaywallFamilySharing.isEnabled
    ) -> PlanStatus {
        guard let entitlement, entitlement.isActive else { return .noPlan }
        if entitlement.ownership == .familyShared { return .sharedWithYou }
        return familySharingEnabled ? .sharingWithFamily : .yours
    }
}

// MARK: - The family portrait

public enum FamilyPortrait {
    /// Everyone stands in the order they joined (the founder of the household first), so the picture is stable.
    public static func ordered(_ members: [HouseholdMember]) -> [HouseholdMember] {
        members.sorted { a, b in
            switch (a.joinedAt, b.joinedAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.userId.uuidString < b.userId.uuidString
            }
        }
    }

    /// Up to four stand in one row; a bigger family stands in two, the rest a step behind (back row first).
    public static func rows(_ members: [HouseholdMember]) -> [[HouseholdMember]] {
        let ordered = ordered(members)
        guard ordered.count > 4 else { return ordered.isEmpty ? [] : [ordered] }
        let back = Array(ordered.prefix(ordered.count - 4))
        let front = Array(ordered.suffix(4))
        return [back, front]
    }

    /// The buddy size in points (multiples of 16 keep the pixels even): bigger for a small family.
    public static func spriteSize(count: Int, isBackRow: Bool = false) -> Double {
        if count > 4 { return isBackRow ? 48 : 64 }
        switch count {
        case ...2: return 96
        case 3: return 80
        default: return 64
        }
    }

    /// Calendar events I added that this member can see (the member card's "What you share").
    public static func eventsSharedWith(_ member: UUID, events: [HouseholdEvent], me: UUID?) -> Int {
        guard let me, member != me else { return 0 }
        return events.filter { $0.createdBy == me && ($0.visibility == .household || $0.audience.contains(member)) }.count
    }
}

// MARK: - Compact lists

public enum FamilyHubLists {
    /// Open chores for me, then ones nobody has taken, soonest due first, at most `limit`.
    public static func chores(tasks: [HouseholdTask], me: UUID?, limit: Int = 4, now: Date = .now) -> [HouseholdTask] {
        let sections = HouseholdBoard.sections(tasks: tasks, me: me, now: now)
        return Array((sections.mine + sections.unassigned).prefix(limit))
    }

    public struct NextQuietTime: Equatable, Sendable {
        public let window: HouseholdQuietTime
        public let occurrence: DateInterval
        /// This phone joined it (the choice never leaves the phone).
        public let isJoined: Bool
        public let isRunning: Bool
    }

    /// The screen-free time running now (the one ending first), or else the next to start.
    public static func nextQuietTime(
        windows: [HouseholdQuietTime], optIns: [HouseholdQuietTimeOptIn], now: Date, calendar: Calendar = .current
    ) -> NextQuietTime? {
        let joined = Set(optIns.map(\.windowID))
        let running = windows.compactMap { window in
            window.occurrence(containing: now, calendar: calendar).map { (window, $0) }
        }.min { $0.1.end < $1.1.end }
        if let running {
            return NextQuietTime(window: running.0, occurrence: running.1, isJoined: joined.contains(running.0.id), isRunning: true)
        }
        let next = windows.compactMap { window in
            window.nextOccurrence(after: now, calendar: calendar).map { (window, $0) }
        }.min { $0.1.start == $1.1.start ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1.start < $1.1.start }
        guard let next else { return nil }
        return NextQuietTime(window: next.0, occurrence: next.1, isJoined: joined.contains(next.0.id), isRunning: false)
    }
}

// MARK: - Sharing my buddy with the household

/// Keeps this person's buddy and outfit on their household rows, so the family portrait on everyone's phone
/// shows the buddy they picked. Display only; sent when it changes (and when a row doesn't match yet).
public enum HouseholdBuddySync {
    private static let lastSentKey = "household.buddySync.lastSent.v1"

    /// One string per buddy-and-outfit, stable across launches.
    public static func signature(buddy: Buddy, outfit: BuddyOutfit) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(outfit)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return buddy.rawValue + "|" + json
    }

    /// Whether my household row shows something other than what I'm wearing.
    public static func needsSync(member: HouseholdMember?, buddy: Buddy, outfit: BuddyOutfit) -> Bool {
        guard let member else { return false }
        if member.buddyChoice != buddy || member.buddy == nil { return true }
        return (member.outfit ?? BuddyOutfit()) != outfit
    }

    /// Sends my buddy and outfit if they changed since the last send (or `force`). Does nothing unless Household
    /// is live. Failures are retried on the next call.
    @MainActor
    public static func syncIfNeeded(force: Bool = false) async {
        guard HouseholdAvailability.isLive, await HouseholdClient.shared.isConfigured else { return }
        let buddy = Buddy.stored
        let outfit = BuddyOutfit.stored(for: buddy)
        let current = signature(buddy: buddy, outfit: outfit)
        guard force || UserDefaults.standard.string(forKey: lastSentKey) != current else { return }
        do {
            try await HouseholdClient.shared.setBuddy(buddy, outfit: outfit)
            UserDefaults.standard.set(current, forKey: lastSentKey)
        } catch {
            // Kept unsent; the next foreground tries again.
        }
    }
}
