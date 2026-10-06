import Testing
import Foundation
@testable import Core

@Suite("Break coach")
struct BreakCoachTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let noon = Date(timeIntervalSince1970: 1_790_000_000)

    private func block(minutesAgo: Double, length: Double = 25) -> BreakCoach.Block {
        BreakCoach.Block(endedAt: noon.addingTimeInterval(-minutesAgo * 60), minutes: length)
    }

    @Test func shortBlockGetsFiveMinutes() {
        let s = BreakCoach.suggestion(blocks: [block(minutesAgo: 2)], isFocusing: false, now: noon, calendar: calendar)
        #expect(s?.minutes == 5)
        #expect(s?.isLong == false)
    }

    @Test func longerBlocksGetLongerBreaks() {
        #expect(BreakCoach.suggestion(blocks: [block(minutesAgo: 1, length: 50)], isFocusing: false, now: noon, calendar: calendar)?.minutes == 10)
        #expect(BreakCoach.suggestion(blocks: [block(minutesAgo: 1, length: 90)], isFocusing: false, now: noon, calendar: calendar)?.minutes == 15)
    }

    @Test func everyFourthBlockIsLong() {
        let blocks = (0..<4).map { block(minutesAgo: 1 + Double(3 - $0) * 60) }
        let s = BreakCoach.suggestion(blocks: blocks, isFocusing: false, now: noon, calendar: calendar)
        #expect(s?.isLong == true)
        #expect(s?.minutes == 15)
    }

    @Test func nothingWhenOldFocusingOrNoBlocks() {
        #expect(BreakCoach.suggestion(blocks: [block(minutesAgo: 20)], isFocusing: false, now: noon, calendar: calendar) == nil)
        #expect(BreakCoach.suggestion(blocks: [block(minutesAgo: 2)], isFocusing: true, now: noon, calendar: calendar) == nil)
        #expect(BreakCoach.suggestion(blocks: [], isFocusing: false, now: noon, calendar: calendar) == nil)
    }

    @Test func activityRotates() {
        let one = BreakCoach.suggestion(blocks: [block(minutesAgo: 1)], isFocusing: false, now: noon, calendar: calendar)
        let two = BreakCoach.suggestion(blocks: [block(minutesAgo: 40), block(minutesAgo: 1)], isFocusing: false, now: noon, calendar: calendar)
        #expect(one?.activity != two?.activity)
    }
}
