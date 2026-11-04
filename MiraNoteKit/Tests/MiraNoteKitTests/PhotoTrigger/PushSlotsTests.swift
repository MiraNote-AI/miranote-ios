import XCTest
@testable import MiraNoteKit

final class PushSlotsTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ min: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: min))!
    }

    private func hm(_ date: Date, _ cal: Calendar) -> [Int] {
        [cal.component(.hour, from: date), cal.component(.minute, from: date)]
    }

    func testWeekdayAndWeekendTimes() {
        let cal = calendar("Asia/Shanghai")
        // 2026-11-04 is a Wednesday.
        let slots = PushSlots.make(now: date(11, 4, 9, 0, cal), calendar: cal)
        for slot in slots {
            let weekend = cal.isDateInWeekend(slot)
            XCTAssertEqual(hm(slot, cal), weekend ? [20, 30] : [21, 0])
        }
        XCTAssertTrue(slots.contains { cal.component(.weekday, from: $0) == 7 })
        XCTAssertTrue(slots.contains { cal.component(.weekday, from: $0) == 1 })
    }

    func testTonightWhenThirtyMinutesAhead() {
        let cal = calendar("Asia/Shanghai")
        let slots = PushSlots.make(now: date(11, 4, 20, 30, cal), calendar: cal)
        XCTAssertEqual(slots.first, date(11, 4, 21, 0, cal))
    }

    func testTomorrowWhenUnderThirtyMinutes() {
        let cal = calendar("Asia/Shanghai")
        let slots = PushSlots.make(now: date(11, 4, 20, 31, cal), calendar: cal)
        XCTAssertEqual(slots.first, date(11, 5, 21, 0, cal))
    }

    func testAlwaysSevenSlots() {
        let cal = calendar("America/Chicago")
        for hour in [0, 9, 20, 21, 23] {
            let slots = PushSlots.make(now: date(11, 4, hour, 0, cal), calendar: cal)
            XCTAssertEqual(slots.count, 7)
            XCTAssertEqual(slots, slots.sorted())
        }
    }

    func testNoSlotIsQuiet() {
        let cal = calendar("Europe/London")
        let slots = PushSlots.make(now: date(11, 4, 12, 0, cal), calendar: cal)
        XCTAssertFalse(slots.contains { PushSlots.isQuiet($0, calendar: cal) })
        XCTAssertTrue(PushSlots.isQuiet(date(11, 4, 23, 0, cal), calendar: cal))
        XCTAssertTrue(PushSlots.isQuiet(date(11, 4, 8, 59, cal), calendar: cal))
        XCTAssertFalse(PushSlots.isQuiet(date(11, 4, 9, 0, cal), calendar: cal))
    }

    func testSlotsOnDSTNightAreLocal2100() {
        let cal = calendar("America/Chicago")
        // DST ends 2026-11-01 (a Sunday): that day's slot is 20:30, all others stay local.
        let slots = PushSlots.make(now: date(11, 1, 8, 0, cal), calendar: cal)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(slots.first, date(11, 1, 20, 30, cal))
        for slot in slots {
            XCTAssertEqual(hm(slot, cal), cal.isDateInWeekend(slot) ? [20, 30] : [21, 0])
        }
        let before = PushSlots.make(now: date(10, 31, 8, 0, cal), calendar: cal)
        XCTAssertEqual(before.count, 7)
        for slot in before { XCTAssertEqual(hm(slot, cal), cal.isDateInWeekend(slot) ? [20, 30] : [21, 0]) }
    }

    func testSlotsFollowTheCalendarTimeZone() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let shanghai = calendar("Asia/Shanghai")
        let chicago = calendar("America/Chicago")
        let shanghaiSlots = PushSlots.make(now: now, calendar: shanghai)
        let chicagoSlots = PushSlots.make(now: now, calendar: chicago)
        XCTAssertNotEqual(shanghaiSlots, chicagoSlots)
        for slot in shanghaiSlots {
            XCTAssertEqual(hm(slot, shanghai), shanghai.isDateInWeekend(slot) ? [20, 30] : [21, 0]) }
        for slot in chicagoSlots {
            XCTAssertEqual(hm(slot, chicago), chicago.isDateInWeekend(slot) ? [20, 30] : [21, 0]) }
    }
}
