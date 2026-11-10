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

    private func isWeekend(_ date: Date, _ cal: Calendar) -> Bool {
        let weekday = cal.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    func testWeekendIsSaturdaySundayWhateverTheLocale() {
        var cal = calendar("Asia/Riyadh")
        // ar_SA's CLDR weekend is Friday and Saturday (ar_AE's is already
        // Saturday and Sunday), so `isDateInWeekend` would get Fri and Sun wrong.
        cal.locale = Locale(identifier: "ar_SA")
        XCTAssertTrue(cal.isDateInWeekend(date(11, 6, 21, 0, cal)), "the locale's weekend includes Friday")
        // 2026-11-05 Thu .. 11-11 Wed: Fri 6th 21:00, Sat 7th and Sun 8th 20:30.
        let slots = PushSlots.make(now: date(11, 5, 9, 0, cal), calendar: cal)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(hm(slots[1], cal), [21, 0])
        XCTAssertEqual(cal.component(.weekday, from: slots[1]), 6)
        XCTAssertEqual(hm(slots[2], cal), [20, 30])
        XCTAssertEqual(hm(slots[3], cal), [20, 30])
        XCTAssertEqual(hm(slots[4], cal), [21, 0])
    }

    private func hm(_ date: Date, _ cal: Calendar) -> [Int] {
        [cal.component(.hour, from: date), cal.component(.minute, from: date)]
    }

    func testWeekdayAndWeekendTimes() {
        let cal = calendar("Asia/Shanghai")
        // 2026-11-04 is a Wednesday.
        let slots = PushSlots.make(now: date(11, 4, 9, 0, cal), calendar: cal)
        for slot in slots {
            let weekend = isWeekend(slot, cal)
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
            XCTAssertEqual(hm(slot, cal), isWeekend(slot, cal) ? [20, 30] : [21, 0])
        }
        let before = PushSlots.make(now: date(10, 31, 8, 0, cal), calendar: cal)
        XCTAssertEqual(before.count, 7)
        for slot in before { XCTAssertEqual(hm(slot, cal), isWeekend(slot, cal) ? [20, 30] : [21, 0]) }
    }

    func testSlotsFollowTheCalendarTimeZone() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let shanghai = calendar("Asia/Shanghai")
        let chicago = calendar("America/Chicago")
        let shanghaiSlots = PushSlots.make(now: now, calendar: shanghai)
        let chicagoSlots = PushSlots.make(now: now, calendar: chicago)
        XCTAssertNotEqual(shanghaiSlots, chicagoSlots)
        for slot in shanghaiSlots {
            XCTAssertEqual(hm(slot, shanghai), isWeekend(slot, shanghai) ? [20, 30] : [21, 0]) }
        for slot in chicagoSlots {
            XCTAssertEqual(hm(slot, chicago), isWeekend(slot, chicago) ? [20, 30] : [21, 0]) }
    }
}
