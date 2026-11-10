import XCTest
@testable import MiraNoteKit

final class SchedulePlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int = 21, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func candidate(_ day: Int, _ bucket: PushBucket, _ total: Double, key: String? = nil) -> PushCandidate {
        let belongs = String(format: "2026-10-%02d", day)
        let score = FragmentScore(r: 1, s: 1, p: 1, n: 1, u: 1, a: 1, base: total, multiplier: 1, bucket: bucket,
                                  total: total, days: 3, pushable: true)
        let fragment = Fragment(photos: [], uniqueCount: 3, representative: [:], belongsTo: belongs)
        return PushCandidate(fragment: fragment, groupKey: key ?? "\(belongs)_\(bucket.rawValue)",
                             belongsTo: belongs, bucket: bucket, score: score, aiPhotoIds: [], cacheKey: "k")
    }

    private func queue(_ ranked: [PushCandidate], previous: PushBucket?, groups: Set<String> = [],
                       days: Set<String> = []) -> [PushCandidate] {
        SchedulePlanner.queue(ranked: ranked, previousBucket: previous, takenGroups: groups, takenDays: days)
    }

    func testDifferentBucketPreferred() {
        let food = candidate(5, .food, 0.8), scenery = candidate(6, .scenery, 0.6)
        XCTAssertEqual(queue([food, scenery], previous: .food).map(\.bucket), [.scenery, .food])
    }

    func testSameBucketWhenNoOther() {
        let food = candidate(5, .food, 0.8)
        XCTAssertEqual(queue([food], previous: .food).map(\.bucket), [.food])
    }

    func testOtherIsExemptFromDiversity() {
        let first = candidate(5, .food, 0.8), second = candidate(6, .scenery, 0.6)
        XCTAssertEqual(queue([first, second], previous: .other).map(\.bucket), [.food, .scenery])
        XCTAssertEqual(queue([first, second], previous: nil).map(\.bucket), [.food, .scenery])
        let other = candidate(7, .other, 0.5)
        XCTAssertEqual(queue([first, other], previous: .food).map(\.bucket), [.other, .food])
    }

    func testTakenGroupsAndDaysDropped() {
        let first = candidate(5, .food, 0.8), second = candidate(6, .scenery, 0.6)
        XCTAssertEqual(queue([first, second], previous: nil, groups: [first.groupKey]), [second])
        XCTAssertEqual(queue([first, second], previous: nil, days: ["2026-10-06"]), [first])
    }

    private func plan(_ ranked: [PushCandidate], slots: Int = 7, active: [LedgerEntry] = [],
                      last: PushBucket? = nil, now: Date? = nil) -> [DayPlan] {
        SchedulePlanner.plan(slots: (0..<slots).map { at(5 + $0) }, rankedFor: { _ in ranked }, active: active,
                             lastDeliveredBucket: last, now: now ?? at(4, 12), calendar: calendar)
    }

    func testAtMostOnePerDayAndEmptyWhenShort() {
        let plans = plan([candidate(1, .food, 0.8), candidate(2, .scenery, 0.7)])
        XCTAssertEqual(plans.map { $0.queue.first?.groupKey }.compactMap { $0 }.count, 2)
        XCTAssertEqual(plans.filter { $0.queue.isEmpty }.count, 5)
        XCTAssertEqual(plans[0].queue.first?.belongsTo, "2026-10-01")
        XCTAssertEqual(plans[0].slotDay, "2026-11-05")
    }

    func testSameBelongsToDayNotOnTwoNights() {
        let first = candidate(1, .food, 0.8, key: "a"), second = candidate(1, .scenery, 0.7, key: "b")
        let plans = plan([first, second])
        XCTAssertEqual(plans.filter { !$0.queue.isEmpty }.count, 1)
    }

    func testFiresWithinAnHourIsLocked() {
        let soon = PushLedgerTests.entry("S", day: "2026-10-01", at: at(5, 21))
        let plans = plan([candidate(2, .scenery, 0.7)], active: [soon], now: at(5, 20, 30))
        XCTAssertTrue(plans[0].locked)
        XCTAssertEqual(plans[0].existing?.pushId, "S")
        XCTAssertTrue(plans[0].queue.isEmpty)
        let far = plan([candidate(2, .scenery, 0.7)], active: [soon], now: at(5, 12))
        XCTAssertFalse(far[0].locked)
        XCTAssertFalse(far[0].queue.isEmpty)
    }

    func testLockedGroupIsTakenForLaterDays() {
        let locked = PushLedgerTests.entry("S", day: "2026-10-01", at: at(5, 21))
        let same = candidate(1, .scenery, 0.9, key: locked.groupKey)
        let other = candidate(2, .food, 0.5)
        let plans = plan([same, other], active: [locked], now: at(5, 20, 30))
        XCTAssertEqual(plans[1].queue.first, other)
    }

    func testPlanStartsFromLastDeliveredBucket() {
        let food = candidate(1, .food, 0.8), scenery = candidate(2, .scenery, 0.6)
        XCTAssertEqual(plan([food, scenery], last: .food)[0].queue.first?.bucket, .scenery)
        XCTAssertEqual(plan([food, scenery], last: nil)[0].queue.first?.bucket, .food)
    }

    func testHeadSteersNextDay() {
        let plans = plan([candidate(1, .food, 0.9), candidate(2, .food, 0.8), candidate(3, .city, 0.5)])
        XCTAssertEqual(plans[0].queue.first?.bucket, .food)
        XCTAssertEqual(plans[1].queue.first?.bucket, .city)
        XCTAssertEqual(plans[2].queue.first?.bucket, .food)
    }
}
