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
}
