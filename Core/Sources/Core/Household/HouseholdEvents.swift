// HouseholdEvents.swift
// Core / Household
//
// The family calendar (session 46, docs/spec.md §5.30 / §5.31): calendar events a household shares, each with
// its own "who can see this". Mirrors `backend/supabase/migrations/0011_household_events.sql` (snake_case on the
// wire, decoded with `FamilyJSON.decoder`).
//
// Three kinds of "who can see this", and only two of them ever reach the server:
//   - Only me:        a `PlannerPrivateEvent` in the Planner's App Group store. Never uploaded.
//   - Everyone:       `visibility = household`.
//   - Chosen people:  `visibility = members` with `audience` = their user ids.
//
// Row-level security is the privacy boundary; `HouseholdEventRules.visible` applies the same rule again on the
// device after every fetch, so a server mistake still can't put someone else's private event on this screen.
// The rules are pure and tested in `HouseholdEventTests`.

import Foundation

// MARK: - Model

public enum HouseholdEventVisibility: String, Codable, Sendable, Equatable {
    /// Everyone in the household.
    case household
    /// Only the creator and the members in `audience`.
    case members
}

/// One shared event. Mirrors a `household_events` row.
public struct HouseholdEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let householdId: UUID
    public let createdBy: UUID?
    public var title: String
    public var notes: String
    public var startsAt: Date
    public var endsAt: Date
    public var allDay: Bool
    public var visibility: HouseholdEventVisibility
    /// Member user ids who can see a `.members` event (the creator always can). Empty for `.household`.
    public var audience: [UUID]
    public let updatedAt: Date?

    public init(
        id: UUID = UUID(), householdId: UUID, createdBy: UUID?, title: String, notes: String = "",
        startsAt: Date, endsAt: Date, allDay: Bool = false, visibility: HouseholdEventVisibility = .household,
        audience: [UUID] = [], updatedAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.createdBy = createdBy
        self.title = title
        self.notes = notes
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.visibility = visibility
        self.audience = audience
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, householdId, createdBy, title, notes, startsAt, endsAt, allDay, visibility, audience, updatedAt
    }

    /// Lenient where the server could send `null` (an older row, a column added later).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        // An unknown visibility is treated as the narrowest one, never as household-wide.
        visibility = (try? c.decodeIfPresent(HouseholdEventVisibility.self, forKey: .visibility)) ?? .members
        audience = try c.decodeIfPresent([UUID].self, forKey: .audience) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// Who an event is for, as the editor's "Who can see this" picker offers it.
public enum PlannerEventSharing: Equatable, Sendable {
    /// Stays on this iPhone. Never uploaded.
    case onlyMe
    /// Everyone in the household.
    case household
    /// The creator and these members.
    case members([UUID])

    public var isShared: Bool { self != .onlyMe }
}

// MARK: - Rules (pure)

public enum HouseholdEventRules {
    public static let titleMaxLength = 120
    public static let notesMaxLength = 500
    /// A household has at most 8 people, so a members-only event can name at most 7 others.
    public static let maxAudience = 7
    /// Upcoming (not ended) events per household; the server enforces the same number.
    public static let maxUpcoming = 500
    /// How far back the app fetches (ended events older than this aren't drawn or kept).
    public static let fetchLookback: TimeInterval = 62 * 86_400

    /// The same rule as the table's SELECT policy: mine, household-wide, or I'm in the audience.
    public static func canSee(_ event: HouseholdEvent, me: UUID?) -> Bool {
        if let me, event.createdBy == me { return true }
        switch event.visibility {
        case .household: return true
        case .members:
            guard let me else { return false }
            return event.audience.contains(me)
        }
    }

    /// The events this person may see. Applied after every fetch, on top of row-level security.
    public static func visible(_ events: [HouseholdEvent], me: UUID?) -> [HouseholdEvent] {
        events.filter { canSee($0, me: me) }
    }

    /// Only the creator edits an event.
    public static func canEdit(_ event: HouseholdEvent, me: UUID?) -> Bool {
        guard let me else { return false }
        return event.createdBy == me
    }

    public enum AudienceError: Error, Equatable, Sendable {
        /// "Choose people" with nobody chosen.
        case empty
        /// Someone who isn't in the household.
        case notAMember
        case tooMany
    }

    /// The audience as it will be stored: without repeats, without the creator, sorted; every id a member of
    /// the household; at least one person. Same rules as the server's trigger.
    public static func normalizedAudience(
        _ audience: [UUID], creator: UUID?, members: [HouseholdMember]
    ) -> Result<[UUID], AudienceError> {
        let memberIDs = Set(members.map(\.userId))
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in audience where id != creator && !seen.contains(id) {
            guard memberIDs.contains(id) else { return .failure(.notAMember) }
            seen.insert(id)
            result.append(id)
        }
        if result.isEmpty { return .failure(.empty) }
        if result.count > maxAudience { return .failure(.tooMany) }
        return .success(result.sorted { $0.uuidString < $1.uuidString })
    }

    /// What "Who can see this" shows for an existing shared event.
    public static func sharing(of event: HouseholdEvent) -> PlannerEventSharing {
        switch event.visibility {
        case .household: return .household
        case .members: return .members(event.audience)
        }
    }

    /// The next `limit` household events still to come (or under way), soonest first. The Family page's
    /// "Coming up".
    public static func upcoming(_ events: [HouseholdEvent], me: UUID?, now: Date, limit: Int = 3) -> [HouseholdEvent] {
        Array(
            visible(events, me: me)
                .filter { $0.endsAt > now }
                .sorted { $0.startsAt == $1.startsAt ? $0.id.uuidString < $1.id.uuidString : $0.startsAt < $1.startsAt }
                .prefix(limit)
        )
    }
}

// MARK: - Times

public enum PlannerEventTimes {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyTitle
        case titleTooLong
        case endsBeforeStart
    }

    /// An all-day event runs from the start of its first day to the last second of its last day (the way
    /// EventKit stores one, so `PlannerAgenda.events(on:)` treats both alike). A timed event is left as is.
    public static func normalized(start: Date, end: Date, allDay: Bool, calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard allDay else { return (start, end) }
        let first = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: max(start, end))
        let next = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        return (first, next.addingTimeInterval(-1))
    }

    public static func validate(title: String, start: Date, end: Date) -> ValidationError? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyTitle }
        if trimmed.count > HouseholdEventRules.titleMaxLength { return .titleTooLong }
        if end < start { return .endsBeforeStart }
        return nil
    }
}

// MARK: - App Group cache

/// The last fetched household, members and visible events, so the Planner draws the family calendar offline and
/// reminders cover shared events. Small JSON in App Group `UserDefaults`, like `HouseholdQuietTimeStore`.
/// `DeviceDataReset` clears every App Group key.
public enum HouseholdEventStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let household = "household.cache.household.v1"
        static let members = "household.cache.members.v1"
        static let me = "household.cache.me.v1"
        static let events = "household.events.v1"
    }

    public static var household: Household? {
        get { read(Household.self, key: Keys.household) }
        set { write(newValue, key: Keys.household) }
    }

    public static var members: [HouseholdMember] {
        get { read([HouseholdMember].self, key: Keys.members) ?? [] }
        set { write(newValue, key: Keys.members) }
    }

    /// The signed-in person's user id as of the last fetch.
    public static var me: UUID? {
        get { defaults.string(forKey: Keys.me).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Keys.me) }
    }

    /// Only events this person may see (filtered again on the way in).
    public static var events: [HouseholdEvent] {
        get { read([HouseholdEvent].self, key: Keys.events) ?? [] }
        set { write(Array(newValue.prefix(HouseholdEventRules.maxUpcoming + 100)), key: Keys.events) }
    }

    /// Saves a fresh fetch. `household == nil` (left, or never joined) clears everything.
    public static func save(household: Household?, members: [HouseholdMember], me: UUID?, events: [HouseholdEvent]) {
        guard let household else {
            resetAll()
            return
        }
        self.household = household
        self.members = members
        self.me = me
        self.events = HouseholdEventRules.visible(events.filter { $0.householdId == household.id }, me: me)
    }

    public static func resetAll() {
        for key in [Keys.household, Keys.members, Keys.me, Keys.events] { defaults.removeObject(forKey: key) }
    }

    /// Fetches the person's household (the first, as the Household screen does), its members and the events
    /// they may see, into the cache. Returns `false` (cache kept) when Household isn't live or the network fails.
    @MainActor
    @discardableResult
    public static func refresh(now: Date = .now) async -> Bool {
        guard HouseholdAvailability.isLive, await HouseholdClient.shared.isConfigured else { return false }
        do {
            let me = try? await HouseholdClient.shared.currentUserID()
            guard let household = try await HouseholdClient.shared.households().first else {
                save(household: nil, members: [], me: me, events: [])
                return true
            }
            let members = try await HouseholdClient.shared.members(householdID: household.id)
            // Separate from the members call so a project without 0011 still caches the household.
            let events = (try? await HouseholdClient.shared.events(
                householdID: household.id, endingAfter: now.addingTimeInterval(-HouseholdEventRules.fetchLookback)
            )) ?? self.events
            save(household: household, members: members, me: me, events: events)
            return true
        } catch {
            return false
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
