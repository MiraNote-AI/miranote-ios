import Foundation
import XCTest
@testable import MiraNoteKit

final class ThemeSamplerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let home = GeoPoint(lat: 31.2, lon: 121.4)
    private let work = GeoPoint(lat: 31.3, lon: 121.5)

    /// 2027-01-04 (a Monday) 00:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_799_020_800)

    private func moment(_ id: String, dayOffset: Int, hour: Int, labels: [(String, Float)],
                        location: GeoPoint?, vector: [Float] = [1, 0]) -> Moment {
        let start = monday.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        return Moment(id: id, photoIds: [id], day: day, start: start, vector: vector,
                      labels: labels.map { LabelScore(id: $0.0, confidence: $0.1) }, location: location)
    }

    /// 40 moments on 40 days (Mondays): four labels of 10 days each, two
    /// places; labels and places cross.
    private func fortyMoments() -> [Moment] {
        (0..<40).map { index in
            moment("m\(index)", dayOffset: 7 * index, hour: index % 2 == 0 ? 8 : 20,
                   labels: [("label\(index % 4)", 0.9)], location: index % 2 == 0 ? home : work)
        }
    }

    private struct Outcome {
        let photos: [SampledPhoto]
        let groupsA: [SplitGroup]
        let groupsB: [SplitGroup]
    }

    private func run(_ moments: [Moment], aesthetics: [String: Double] = [:], max: Int = 20) -> Outcome {
        let pile = Pile(momentIds: moments.map(\.id), days: Set(moments.map(\.day)).count,
                        maxDayShare: 0.1, height: 0.3, center: [1, 0])
        let byId = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        let (groupsA, groupsB) = PileSplits.make(pile, moments: byId, calendar: calendar)
        let photos = ThemeSampler.pick(pile, moments: byId, a: groupsA, b: groupsB, aesthetics: aesthetics, max: max)
        return Outcome(photos: photos, groupsA: groupsA, groupsB: groupsB)
    }

    func testEveryGroupGetsTwo() {
        let result = run(fortyMoments())
        XCTAssertFalse(result.groupsA.isEmpty)
        XCTAssertFalse(result.groupsB.isEmpty)
        for group in result.groupsA {
            XCTAssertGreaterThanOrEqual(result.photos.filter { $0.a == group.id }.count, 2, group.id)
        }
        for group in result.groupsB {
            XCTAssertGreaterThanOrEqual(result.photos.filter { $0.b == group.id }.count, 2, group.id)
        }
    }

    func testAtMostOnePerDay() {
        // Two moments per day.
        let moments = (0..<60).map { index in
            moment("m\(index)", dayOffset: 7 * (index / 2), hour: index % 2 == 0 ? 8 : 20,
                   labels: [("label\((index / 2) % 3)", 0.9)], location: home)
        }
        let result = run(moments)
        let byId = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        let days = result.photos.compactMap { byId[$0.momentId]?.day }
        XCTAssertEqual(days.count, Set(days).count)
        XCTAssertEqual(result.photos.count, 20)
    }

    func testTotalTwentyWhenEnough() {
        let result = run(fortyMoments())
        XCTAssertEqual(result.photos.count, 20)
        XCTAssertEqual(Set(result.photos.map(\.momentId)).count, 20)
    }

    func testMaxIsRespected() {
        XCTAssertEqual(run(fortyMoments(), max: 12).photos.count, 12)
    }

    func testFewerThanTwentyGivesAll() {
        let moments = Array(fortyMoments().prefix(7))
        XCTAssertEqual(Set(run(moments).photos.map(\.momentId)), Set(moments.map(\.id)))
    }

    func testFewMomentsOnOneDayGiveTheBestMoment() {
        let first = moment("low", dayOffset: 0, hour: 8, labels: [], location: nil)
        let second = moment("high", dayOffset: 0, hour: 9, labels: [], location: nil)
        let result = run([first, second], aesthetics: ["low": 0.2, "high": 0.9])
        XCTAssertEqual(result.photos.map(\.momentId), ["high"])
    }

    func testHigherAestheticsWinsTheSlot() {
        // Everything fills the same slots; the best-looking moments go first.
        let moments = fortyMoments()
        var aesthetics: [String: Double] = [:]
        for (index, item) in moments.enumerated() { aesthetics[item.id] = Double(index) }
        let chosen = Set(run(moments, aesthetics: aesthetics).photos.map(\.momentId))
        XCTAssertTrue(chosen.contains("m39"))
        XCTAssertTrue(chosen.contains("m38"))
    }

    func testOtherRoundAddsUnusedDays() {
        // 30 grouped moments, plus 10 on their own: no label, a place of their own each.
        var moments = (0..<30).map { index in
            moment("g\(index)", dayOffset: 7 * index, hour: 8, labels: [("label\(index % 3)", 0.9)], location: home)
        }
        moments += (0..<10).map { index in
            moment("o\(index)", dayOffset: 7 * (30 + index), hour: 8, labels: [],
                   location: GeoPoint(lat: 40 + Double(index), lon: 10), vector: [0.6, 0.8])
        }
        let result = run(moments)
        XCTAssertEqual(result.photos.count, 20)
        let others = result.photos.filter { $0.a == "A0" && $0.b == "B0" }
        XCTAssertGreaterThanOrEqual(others.count, 1)
        XCTAssertTrue(others.allSatisfy { $0.momentId.hasPrefix("o") })
    }

    // MARK: Hand-built groups, so the sampler's rounds can be counted exactly.

    private let dims = 11

    /// Grouped moments point at the pile's center; ungrouped ones each get their
    /// own axis, so MMR (round 3) always prefers them over the grouped ones.
    private func centerVector() -> [Float] { [1] + [Float](repeating: 0, count: dims - 1) }

    private func axisVector(_ axis: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: dims)
        vector[axis] = 1
        return vector
    }

    private func group(_ id: String, _ members: [Moment]) -> SplitGroup {
        let facts = WhereFacts(daypart: nil, daypartShare: 0, hourFrom: nil, hourTo: nil,
                               weekpart: "mixed", places: nil)
        return SplitGroup(id: id, key: id, momentIds: members.map(\.id), days: Set(members.map(\.day)).count,
                          where: facts, placeCenter: nil)
    }

    private func pick(_ moments: [Moment], groupsA: [SplitGroup], groupsB: [SplitGroup]) -> [SampledPhoto] {
        let pile = Pile(momentIds: moments.map(\.id), days: moments.count, maxDayShare: 0.1, height: 0.3,
                        center: centerVector())
        let byId = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        return ThemeSampler.pick(pile, moments: byId, a: groupsA, b: groupsB, aesthetics: [:], max: 20)
    }

    private func grouped(_ count: Int) -> [Moment] {
        (0..<count).map { index in
            moment("g\(index)", dayOffset: 7 * index, hour: 8, labels: [], location: nil, vector: centerVector())
        }
    }

    private func ungrouped(_ count: Int, firstDay: Int) -> [Moment] {
        (0..<count).map { index in
            moment("o\(index)", dayOffset: 7 * (firstDay + index), hour: 8, labels: [], location: nil,
                   vector: axisVector(index + 1))
        }
    }

    func testBiggerGroupGetsMoreByDays() {
        // A1 has 30 days and A2 has 10; one B group holds them all. 10 ungrouped
        // moments fill round 3, so the grouped counts are exactly rounds 1 + 2.
        let moments = grouped(40)
        let big = Array(moments.prefix(30)), small = Array(moments.suffix(10))
        let groupsA = [group("A1", big), group("A2", small)]
        let groupsB = [group("B1", moments)]
        let photos = pick(moments + ungrouped(10, firstDay: 40), groupsA: groupsA, groupsB: groupsB)
        XCTAssertEqual(photos.count, 20)

        // Round 2 adds `extra` over the groups by days (largest remainder).
        let other = Int((20 * ThemeSampler.otherShare).rounded())
        let wanted = Int((20 * ThemeSampler.sizeShare).rounded())
        let floors = ThemeSampler.floorPerGroup * 2   // A1 + A2; B1 shares the same picks.
        let extra = min(wanted, 20 - floors - other)
        let exactBig = Double(extra * 30) / 40
        var bigExtra = Int(exactBig), smallExtra = Int(Double(extra * 10) / 40)
        if bigExtra + smallExtra < extra {   // The leftover goes to the larger remainder; a tie goes to A1.
            let smallRest = Double(extra * 10) / 40 - Double(smallExtra)
            if smallRest > exactBig - Double(bigExtra) { smallExtra += 1 } else { bigExtra += 1 }
        }
        let bigCount = photos.filter { $0.a == "A1" }.count
        let smallCount = photos.filter { $0.a == "A2" }.count
        XCTAssertEqual(bigCount, ThemeSampler.floorPerGroup + bigExtra)
        XCTAssertEqual(smallCount, ThemeSampler.floorPerGroup + smallExtra)
        XCTAssertGreaterThan(bigCount, smallCount)
        XCTAssertGreaterThan(smallCount, ThemeSampler.floorPerGroup)
    }

    func testOtherShareIsKeptForTheLastRound() {
        // Six A groups and six B groups of 5 days each, the same members, so
        // the floor (12) and the extra could fill 18 of the 20 slots; 10
        // ungrouped moments stand by for round 3.
        let moments = grouped(30)
        let parts = (0..<6).map { part in moments.enumerated().filter { $0.offset % 6 == part }.map(\.element) }
        let groupsA = parts.enumerated().map { group("A\($0.offset + 1)", $0.element) }
        let groupsB = parts.enumerated().map { group("B\($0.offset + 1)", $0.element) }
        let photos = pick(moments + ungrouped(10, firstDay: 30), groupsA: groupsA, groupsB: groupsB)
        XCTAssertEqual(photos.count, 20)

        // Rounds 1 + 2 stop 20% of the slots short, so round 3 picks those from "other".
        let other = Int((20 * ThemeSampler.otherShare).rounded())
        XCTAssertEqual(other, 4)
        let others = photos.filter { $0.a == "A0" && $0.b == "B0" }
        XCTAssertEqual(others.count, other)
        XCTAssertTrue(others.allSatisfy { $0.momentId.hasPrefix("o") })
        // The grouped rest keeps the floor in every group.
        for index in 1...6 {
            XCTAssertGreaterThanOrEqual(photos.filter { $0.a == "A\(index)" }.count, ThemeSampler.floorPerGroup)
        }
    }
}
