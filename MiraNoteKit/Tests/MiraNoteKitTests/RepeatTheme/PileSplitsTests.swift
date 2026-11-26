import Foundation
import XCTest
@testable import MiraNoteKit

final class PileSplitsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2027-01-04, a Monday, 00:00 UTC.
    private var monday: Date { Date(timeIntervalSince1970: 1_799_020_800) }

    private func moment(_ id: String, dayOffset: Int, hour: Int = 8, labels: [(String, Float)] = [],
                        location: GeoPoint? = nil) -> Moment {
        let start = monday.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        return Moment(id: id, photoIds: [id], day: day, start: start, vector: [1, 0],
                      labels: labels.map { LabelScore(id: $0.0, confidence: $0.1) }, location: location)
    }

    private func split(_ moments: [Moment]) -> (a: [SplitGroup], b: [SplitGroup]) {
        let pile = Pile(momentIds: moments.map(\.id), days: Set(moments.map(\.day)).count,
                        maxDayShare: 0.1, height: 0.3, center: [1, 0])
        return PileSplits.make(pile, moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }),
                               calendar: calendar)
    }

    // MARK: - Split A

    func testLabelInSixtyOnePercentIsDropped() {
        // "bowl" is on 61 of 100 moments: dropped, so the 30 with "side" fall to it.
        let moments = (0..<100).map {
            moment("m\($0)", dayOffset: 7 * $0,
                   labels: ($0 < 61 ? [("bowl", 0.9)] : []) + ($0 < 30 ? [("side", 0.4)] : []))
        }
        XCTAssertEqual(split(moments).a.map(\.key), ["side"])
        XCTAssertEqual(split(moments).a.first?.momentIds.count, 30)
    }

    func testLabelInSixtyPercentIsKept() {
        let moments = (0..<100).map {
            moment("m\($0)", dayOffset: 7 * $0,
                   labels: ($0 < 60 ? [("bowl", 0.9)] : []) + ($0 < 30 ? [("side", 0.4)] : []))
        }
        XCTAssertEqual(split(moments).a.map(\.key), ["bowl"])
        XCTAssertEqual(split(moments).a.first?.momentIds.count, 60)
    }

    func testLabelBelowPointThreeIsNotPresent() {
        let moments = (0..<5).map { moment("m\($0)", dayOffset: 7 * $0, labels: [("soup", 0.29)]) }
        XCTAssertTrue(split(moments).a.isEmpty)
    }

    func testGroupWithTwoDaysDropped() {
        let moments = (0..<2).map { moment("s\($0)", dayOffset: 7 * $0, labels: [("soup", 0.9)]) }
            + (0..<3).map { moment("n\($0)", dayOffset: 7 * ($0 + 2), labels: [("noodle", 0.9)]) }
        XCTAssertEqual(split(moments).a.map(\.key), ["noodle"])
        XCTAssertEqual(split(moments).a.first?.id, "A1")
    }

    func testAtMostSixGroups() {
        var moments: [Moment] = []
        for label in 0..<8 {
            for index in 0..<3 {
                moments.append(moment("l\(label)m\(index)", dayOffset: 7 * (label * 3 + index),
                                      labels: [("label\(label)", 0.9)]))
            }
        }
        let groups = split(moments).a
        XCTAssertEqual(groups.count, 6)
        XCTAssertEqual(groups.map(\.id), ["A1", "A2", "A3", "A4", "A5", "A6"])
        XCTAssertEqual(groups.map(\.key), (0..<6).map { "label\($0)" })
    }

    func testGroupsRankByDaysThenMoments() {
        var moments = (0..<3).map { moment("a\($0)", dayOffset: 7 * $0, labels: [("few", 0.9)]) }
        moments += (0..<5).map { moment("b\($0)", dayOffset: 7 * ($0 + 3), labels: [("many", 0.9)]) }
        moments += (0..<4).map { moment("c\($0)", dayOffset: 7 * ($0 + 8)) }
        XCTAssertEqual(split(moments).a.map(\.key), ["many", "few"])
        XCTAssertEqual(split(moments).a.map(\.days), [5, 3])
    }

    // MARK: - Split B

    private let home = GeoPoint(lat: 31.2, lon: 121.4)

    private func shifted(_ degrees: Double) -> GeoPoint { GeoPoint(lat: home.lat + degrees, lon: home.lon) }

    func testPlaceWithin300mJoins301mStartsNew() {
        // 0.0026 degrees is about 289 m; 0.00271 about 301 m.
        let near = (0..<3).map { moment("h\($0)", dayOffset: 7 * $0, location: home) }
            + (3..<6).map { moment("h\($0)", dayOffset: 7 * $0, location: shifted(0.0026)) }
        XCTAssertEqual(split(near).b.count, 1)
        XCTAssertEqual(split(near).b.first?.momentIds.count, 6)
        XCTAssertEqual(split(near).b.first?.where.places, 1)

        let far = (0..<3).map { moment("h\($0)", dayOffset: 7 * $0, location: home) }
            + (3..<6).map { moment("h\($0)", dayOffset: 7 * $0, location: shifted(0.00271)) }
        XCTAssertEqual(split(far).b.count, 2)
        XCTAssertEqual(split(far).b.map(\.key), ["0|morning|weekday", "1|morning|weekday"])
        XCTAssertNotNil(split(far).b.first?.placeCenter)
    }

    func testNoLocationGroupsByDaypartAndWeekpartOnly() {
        // Mondays at 08:00, Saturdays at 20:00; one far place apart changes nothing.
        let weekday = (0..<3).map { moment("w\($0)", dayOffset: 7 * $0) }
        let weekend = (0..<3).map { moment("e\($0)", dayOffset: 7 * $0 + 5, hour: 20) }
        let groups = split(weekday + weekend).b
        XCTAssertEqual(Set(groups.map(\.key)), ["unknown|morning|weekday", "unknown|night|weekend"])
        XCTAssertTrue(groups.allSatisfy { $0.where.places == nil && $0.placeCenter == nil })
    }

    func testMomentWithoutLocationDoesNotBorrowAPlace() {
        let located = (0..<3).map { moment("l\($0)", dayOffset: 7 * $0, location: home) }
        let unlocated = (0..<3).map { moment("u\($0)", dayOffset: 7 * ($0 + 3)) }
        XCTAssertEqual(Set(split(located + unlocated).b.map(\.key)), ["0|morning|weekday", "unknown|morning|weekday"])
    }

    // MARK: - Where facts

    /// One A group "x" from `members`, padded with unlabelled moments so "x" is not common.
    private func groupX(_ members: [Moment]) -> SplitGroup? {
        let padding = (0..<members.count + 1).map { moment("p\($0)", dayOffset: 7 * (100 + $0)) }
        return split(members + padding).a.first
    }

    private func oneGroup(weekdays: Int, weekends: Int) -> SplitGroup? {
        groupX((0..<weekdays).map { moment("d\($0)", dayOffset: 7 * $0, labels: [("x", 0.9)]) }
            + (0..<weekends).map { moment("e\($0)", dayOffset: 7 * $0 + 5, labels: [("x", 0.9)]) })
    }

    func testWhereFactsWeekdayAtSeventyPercent() {
        XCTAssertEqual(oneGroup(weekdays: 7, weekends: 3)?.where.weekpart, "weekday")
        XCTAssertEqual(oneGroup(weekdays: 3, weekends: 7)?.where.weekpart, "weekend")
        XCTAssertEqual(oneGroup(weekdays: 6, weekends: 4)?.where.weekpart, "mixed")
    }

    func testWhereFactsDaypartHoursAndPlaces() {
        let hours = [8, 8, 8, 9, 9, 12, 12, 12, 12, 18]
        let moments = hours.enumerated().map {
            moment("m\($0.offset)", dayOffset: 7 * $0.offset, hour: $0.element, labels: [("x", 0.9)],
                   location: $0.offset < 5 ? home : shifted(0.01))
        }
        let facts = groupX(moments)?.where
        XCTAssertEqual(facts?.daypart, "morning")
        XCTAssertEqual(facts?.daypartShare ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(facts?.hourFrom, 8)
        XCTAssertEqual(facts?.hourTo, 12)
        XCTAssertEqual(facts?.places, 2)
    }

    func testDaypartBoundaries() {
        let expected: [(Int, String)] = [(4, "night"), (5, "morning"), (10, "morning"), (11, "noon"), (13, "noon"),
                                         (14, "afternoon"), (16, "afternoon"), (17, "evening"), (18, "evening"),
                                         (19, "night"), (23, "night"), (0, "night")]
        for (hour, name) in expected {
            XCTAssertEqual(Daypart(hour: hour).rawValue, name, "hour \(hour)")
        }
    }

    func testWhereFactsEncodesBackendKeysWithNulls() throws {
        let facts = WhereFacts(daypart: "evening", daypartShare: 0.5, hourFrom: nil, hourTo: nil,
                               weekpart: "mixed", places: nil)
        let data = try JSONEncoder().encode(facts)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["daypart", "daypart_share", "hour_from", "hour_to", "weekpart", "places"])
        XCTAssertTrue(object["places"] is NSNull)
        XCTAssertTrue(object["hour_from"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(WhereFacts.self, from: data), facts)
    }

    func testTagSharesInsideAndOutside() {
        let moments = [moment("m1", dayOffset: 0, labels: [("cat", 0.9), ("animal", 0.8)]),
                       moment("m2", dayOffset: 1, labels: [("cat", 0.9), ("animal", 0.8)]),
                       moment("m3", dayOffset: 2, labels: [("dog", 0.9), ("animal", 0.8)]),
                       moment("m4", dayOffset: 3, labels: [("dog", 0.9), ("animal", 0.8), ("weak", 0.1)])]
        let pile = Pile(momentIds: moments.map(\.id), days: 4, maxDayShare: 0.25, height: 0.3, center: [1, 0])
        let byId = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        let shares = PileSplits.tagShares(of: ["m1", "m2"], pile: pile, moments: byId)
        XCTAssertEqual(shares, [PileSplits.TagShare(label: "animal", inside: 1, outside: 1),
                                PileSplits.TagShare(label: "cat", inside: 1, outside: 0)])
        XCTAssertFalse(PileSplits.isSharp(shares[0]))
        XCTAssertTrue(PileSplits.isSharp(shares[1]))
    }

    func testTagSharesCapAtEightAndOutsideIsZeroWithoutOthers() {
        let labels = (0..<10).map { ("l\($0)", Float(0.9)) }
        let only = moment("m1", dayOffset: 0, labels: labels)
        let pile = Pile(momentIds: ["m1"], days: 1, maxDayShare: 1, height: 0.3, center: [1, 0])
        let shares = PileSplits.tagShares(of: ["m1"], pile: pile, moments: ["m1": only])
        XCTAssertEqual(shares.map(\.label), (0..<8).map { "l\($0)" })
        XCTAssertTrue(shares.allSatisfy { $0.outside == 0 })
    }
}
