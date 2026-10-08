// FamilyRewardTests.swift
//
// Parent reward minutes (session 45; docs/spec.md §5.23, §5.2): the caps the app mirrors from
// `0010_family_rewards.sql`, void rewards, claim -> deposit, and deposit-once (claiming twice deposits once).
// Every engine test uses its own in-memory store and its own UserDefaults suite, never the App Group ones.

import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor
private enum RewardFixture {
    static let day = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12))!

    static func engine() throws -> TimeBankEngine {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(User())
        try context.save()
        return TimeBankEngine(modelContainer: container)
    }

    static func defaults() -> UserDefaults {
        let name = "zano.tests.familyRewards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func link(status: FamilyLinkStatus = .active, teen: UUID = UUID()) -> FamilyLink {
        FamilyLink(id: UUID(), parentId: UUID(), teenId: teen, inviteCode: "ABCD2345", status: status)
    }

    static func reward(on link: FamilyLink, minutes: Int = 30, createdAt: Date = day, claimed: Bool = false, voided: Bool = false) -> FamilyReward {
        FamilyReward(
            id: UUID(), linkId: link.id, fromUser: link.parentId, toUser: link.teenId!, minutes: minutes,
            note: "nice work on the homework", createdAt: createdAt,
            claimedAt: claimed ? createdAt : nil, voidedAt: voided ? createdAt : nil
        )
    }
}

@Suite("Family reward rules")
struct FamilyRewardRulesTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("caps match the server: 120 per reward, 240 per rolling 24 hours")
    func caps() {
        #expect(FamilyRewardRules.isValidAmount(120))
        #expect(!FamilyRewardRules.isValidAmount(121))
        #expect(!FamilyRewardRules.isValidAmount(0))
        #expect(!FamilyRewardRules.isValidAmount(-10))
        #expect(FamilyRewardRules.chipMinutes.allSatisfy(FamilyRewardRules.isValidAmount))

        let link = RewardFixture.link()
        let sent = [
            RewardFixture.reward(on: link, minutes: 120, createdAt: now.addingTimeInterval(-3_600)),
            RewardFixture.reward(on: link, minutes: 60, createdAt: now.addingTimeInterval(-7_200)),
            // Older than 24 hours: no longer counts.
            RewardFixture.reward(on: link, minutes: 120, createdAt: now.addingTimeInterval(-90_000)),
            // Voided: doesn't count, like the server trigger.
            RewardFixture.reward(on: link, minutes: 60, createdAt: now.addingTimeInterval(-60), voided: true),
        ]
        #expect(FamilyRewardRules.sentInWindow(sent, now: now) == 180)
        #expect(FamilyRewardRules.remainingAllowance(sent, now: now) == 60)
        #expect(FamilyRewardRules.availableChips(sent, now: now) == [10, 15, 30, 60])

        let full = sent + [RewardFixture.reward(on: link, minutes: 60, createdAt: now.addingTimeInterval(-10))]
        #expect(FamilyRewardRules.remainingAllowance(full, now: now) == 0)
        #expect(FamilyRewardRules.availableChips(full, now: now).isEmpty)
    }

    @Test("the note is plain text: one line, trimmed, at most 80 characters, empty means none")
    func note() {
        #expect(FamilyRewardRules.sanitizedNote("  nice\nwork\t on it  ") == "nice work on it")
        #expect(FamilyRewardRules.sanitizedNote("   ") == nil)
        #expect(FamilyRewardRules.sanitizedNote(String(repeating: "a", count: 200))?.count == FamilyRewardRules.noteMaxLength)
    }

    @Test("a reward on a left link is void, and void rewards are never claimable")
    func void() {
        let teen = UUID()
        let active = RewardFixture.link(teen: teen)
        let reward = RewardFixture.reward(on: active)
        #expect(!FamilyRewardRules.isVoid(reward, link: active))

        let left = FamilyLink(id: active.id, parentId: active.parentId, teenId: teen, inviteCode: "ABCD2345", status: .left)
        #expect(FamilyRewardRules.isVoid(reward, link: left))
        #expect(FamilyRewardRules.isVoid(reward, link: nil))
        #expect(FamilyRewardRules.isVoid(RewardFixture.reward(on: active, voided: true), link: active))
        #expect(FamilyRewardRules.claimable([reward], link: left, teenID: teen).isEmpty)
    }

    @Test("only the teen's unclaimed rewards are claimable, oldest first")
    func claimable() {
        let teen = UUID()
        let link = RewardFixture.link(teen: teen)
        let newer = RewardFixture.reward(on: link, createdAt: now)
        let older = RewardFixture.reward(on: link, createdAt: now.addingTimeInterval(-60))
        let claimed = RewardFixture.reward(on: link, claimed: true)
        let list = FamilyRewardRules.claimable([newer, claimed, older], link: link, teenID: teen)
        #expect(list.map(\.id) == [older.id, newer.id])
        // The parent's device (a different user id) never sees a card.
        #expect(FamilyRewardRules.claimable([newer], link: link, teenID: link.parentId).isEmpty)
        #expect(FamilyRewardRules.claimable([newer], link: link, teenID: nil).isEmpty)
    }

    @Test("reward rows decode from PostgREST's snake_case")
    func decode() throws {
        let json = #"[{"id":"\#(UUID())","link_id":"\#(UUID())","from_user":"\#(UUID())","to_user":"\#(UUID())","minutes":30,"note":"nice","created_at":"2026-10-08T10:00:00.123456+00:00","claimed_at":null,"voided_at":null}]"#
        let rewards = try FamilyJSON.decoder.decode([FamilyReward].self, from: Data(json.utf8))
        #expect(rewards.first?.minutes == 30)
        #expect(rewards.first?.createdAt != nil)
        #expect(rewards.first?.claimedAt == nil)
    }

    @Test("the user id is read from the access token's sub claim")
    func jwtSubject() {
        let id = UUID()
        let payload = Data(#"{"sub":"\#(id.uuidString.lowercased())","role":"authenticated"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        #expect(FamilyLinkClient.userID(fromJWT: "eyJhbGciOiJIUzI1NiJ9.\(payload).sig") == id)
        #expect(FamilyLinkClient.userID(fromJWT: "not-a-token") == nil)
    }

    @Test("reward errors map to calm copy")
    func errors() {
        #expect(Copy.family.error(FamilyLinkError.server(code: "reward_daily_cap")) == Copy.family.rewardLimitReached)
        #expect(Copy.family.error(FamilyLinkError.server(code: "void")) == Copy.family.rewardVoid)
        #expect(Copy.family.error(FamilyLinkError.server(code: "already_claimed")) == Copy.family.rewardAlreadyAdded)
    }
}

@Suite("Family reward claim and deposit")
@MainActor
struct FamilyRewardDepositTests {
    @Test("claim -> deposit: the minutes land in that day's Time Bank and are recorded as from family")
    func claimDeposits() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        let link = RewardFixture.link()
        let reward = RewardFixture.reward(on: link, minutes: 30)

        let result = try await FamilyRewardClaim.claimAndDeposit(
            reward, link: link, engine: engine, now: RewardFixture.day, ledger: defaults
        ) { _ in 30 }

        #expect(result == .deposited(minutes: 30))
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == 30)
        #expect(FamilyRewardLedger.minutes(on: RewardFixture.day, defaults: defaults) == 30)
        #expect(FamilyRewardLedger.hasDeposited(reward.id, defaults: defaults))
    }

    @Test("claiming twice deposits once")
    func idempotent() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        let link = RewardFixture.link()
        let reward = RewardFixture.reward(on: link, minutes: 15)
        var serverCalls = 0
        let claim: (UUID) async throws -> Int = { _ in
            serverCalls += 1
            return 15
        }

        _ = try await FamilyRewardClaim.claimAndDeposit(reward, link: link, engine: engine, now: RewardFixture.day, ledger: defaults, claim: claim)
        let second = try await FamilyRewardClaim.claimAndDeposit(reward, link: link, engine: engine, now: RewardFixture.day, ledger: defaults, claim: claim)

        #expect(second == .alreadyDeposited)
        #expect(serverCalls == 1)
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == 15)
        #expect(FamilyRewardLedger.minutes(on: RewardFixture.day, defaults: defaults) == 15)

        // The engine itself refuses a second deposit of the same reward too.
        let direct = try await engine.depositFamilyReward(rewardID: reward.id, minutes: 15, on: RewardFixture.day, ledger: defaults)
        #expect(direct == .alreadyDeposited)
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == 15)
    }

    @Test("a reward the server says was already claimed deposits nothing")
    func alreadyClaimedOnServer() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        let link = RewardFixture.link()
        let reward = RewardFixture.reward(on: link)

        let result = try await FamilyRewardClaim.claimAndDeposit(reward, link: link, engine: engine, now: RewardFixture.day, ledger: defaults) { _ in
            throw FamilyLinkError.server(code: "already_claimed")
        }

        #expect(result == .alreadyDeposited)
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == 0)
    }

    @Test("a voided reward (link left) never reaches the server and deposits nothing")
    func voided() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        let active = RewardFixture.link()
        let reward = RewardFixture.reward(on: active)
        let left = FamilyLink(id: active.id, parentId: active.parentId, teenId: active.teenId, inviteCode: "ABCD2345", status: .left)
        var serverCalls = 0
        let countingClaim: (UUID) async throws -> Int = { _ in
            serverCalls += 1
            return 30
        }
        let voidingClaim: (UUID) async throws -> Int = { _ in throw FamilyLinkError.server(code: "void") }

        var firstError: FamilyLinkError?
        do {
            _ = try await FamilyRewardClaim.claimAndDeposit(reward, link: left, engine: engine, now: RewardFixture.day, ledger: defaults, claim: countingClaim)
        } catch {
            firstError = error as? FamilyLinkError
        }
        #expect(firstError == .server(code: "void"))

        // The server voids it too: a 'void' answer from the claim deposits nothing.
        var secondError: FamilyLinkError?
        do {
            _ = try await FamilyRewardClaim.claimAndDeposit(reward, link: active, engine: engine, now: RewardFixture.day, ledger: defaults, claim: voidingClaim)
        } catch {
            secondError = error as? FamilyLinkError
        }
        #expect(secondError == .server(code: "void"))
        #expect(serverCalls == 0)
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == 0)
        #expect(!FamilyRewardLedger.hasDeposited(reward.id, defaults: defaults))
    }

    @Test("family minutes expire at midnight like all Time Bank minutes, and are clamped to the per-reward cap")
    func expiresAndClamps() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: RewardFixture.day)!

        let result = try await engine.depositFamilyReward(rewardID: UUID(), minutes: 500, on: RewardFixture.day, ledger: defaults)

        #expect(result == .deposited(minutes: FamilyRewardRules.maxMinutesPerReward))
        #expect(await engine.remainingMinutes(for: RewardFixture.day) == FamilyRewardRules.maxMinutesPerReward)
        #expect(await engine.remainingMinutes(for: tomorrow) == 0)
        #expect(FamilyRewardLedger.minutes(on: tomorrow, defaults: defaults) == 0)
    }

    @Test("goal minutes and family minutes stay apart in the ledger")
    func separateFromGoals() async throws {
        let engine = try RewardFixture.engine()
        let defaults = RewardFixture.defaults()
        try await engine.deposit(minutes: TimeBankEarnRates.gymSessionMinutes, for: RewardFixture.day)
        try await engine.depositFamilyReward(rewardID: UUID(), minutes: 30, on: RewardFixture.day, ledger: defaults)

        #expect(await engine.remainingMinutes(for: RewardFixture.day) == TimeBankEarnRates.gymSessionMinutes + 30)
        #expect(FamilyRewardLedger.minutes(on: RewardFixture.day, defaults: defaults) == 30)
    }
}
