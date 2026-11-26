import Foundation
import XCTest
@testable import MiraNoteKit

final class MomentsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let base = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC

    /// A unit vector at `angle` radians from the x axis.
    private func print(_ angle: Double) -> [Float] {
        [Float(cos(angle)), Float(sin(angle))]
    }

    private func photo(_ id: String, at offset: TimeInterval, vector: [Float], aesthetics: Double? = nil,
                       labels: [LabelScore] = [], location: GeoPoint? = nil) -> ThemePhoto {
        ThemePhoto(id: id, takenAt: base.addingTimeInterval(offset), location: location, labels: labels,
                   aesthetics: aesthetics, faces: 0, isTheme: true,
                   print: ThemePhoto.normalized(vector), printRevision: 1)
    }

    func testBurstOfTenBecomesOneMoment() {
        let photos = (0..<10).map { photo("p\($0)", at: Double($0) * 5, vector: print(Double($0) * 0.01)) }
        let moments = MomentBuilder.build(photos, calendar: calendar)
        XCTAssertEqual(moments.count, 1)
        XCTAssertEqual(moments[0].photoIds, (0..<10).map { "p\($0)" })
        XCTAssertEqual(moments[0].start, base)
        XCTAssertEqual(moments[0].day, "2027-01-15")
    }

    func testChainOfThirtyNotMergedIntoOne() {
        // Each step is a cosine distance of 0.15 from its neighbour.
        let step = acos(1 - 0.15)
        let vectors = (0..<30).map { print(Double($0) * step) }
        let photos = (0..<30).map { photo("p\($0)", at: Double($0) * 60, vector: vectors[$0]) }
        XCTAssertGreaterThanOrEqual(MomentBuilder.cosineDistance(vectors[0], vectors[4]), 0.2)
        let moments = MomentBuilder.build(photos, calendar: calendar)
        XCTAssertGreaterThan(moments.count, 1)
        let byId = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        for moment in moments {
            let first = byId[moment.photoIds[0]]!
            for id in moment.photoIds {
                XCTAssertLessThan(MomentBuilder.cosineDistance(first.vector, byId[id]!.vector), 0.2)
            }
        }
        XCTAssertEqual(moments.flatMap(\.photoIds).count, 30)
    }

    func testElevenMinutesApartStaysTwo() {
        let same = print(0)
        let moments = MomentBuilder.build([
            photo("a", at: 0, vector: same), photo("b", at: 660, vector: same)
        ], calendar: calendar)
        XCTAssertEqual(moments.map(\.photoIds), [["a"], ["b"]])
    }

    func testExactlyTenMinutesMerges() {
        let same = print(0)
        let moments = MomentBuilder.build([
            photo("a", at: 0, vector: same), photo("b", at: 600, vector: same)
        ], calendar: calendar)
        XCTAssertEqual(moments.count, 1)
    }

    func testDistanceAtPointTwoStaysTwoAndJustUnderMerges() {
        // Float cannot hit 0.2 exactly; first hair over must stay apart, first hair under merges.
        let first = photo("first", at: 0, vector: [1, 0])
        let over = photo("over", at: 10, vector: [0.79, 0.6])
        let overDistance = MomentBuilder.cosineDistance(first.vector, over.vector)
        XCTAssertGreaterThanOrEqual(overDistance, MomentBuilder.mergeDistance)
        XCTAssertEqual(MomentBuilder.build([first, over], calendar: calendar).count, 2)

        let under = photo("under", at: 10, vector: [0.81, 0.5863])
        XCTAssertLessThan(MomentBuilder.cosineDistance(first.vector, under.vector), MomentBuilder.mergeDistance)
        XCTAssertEqual(MomentBuilder.build([first, under], calendar: calendar).count, 1)
    }

    func testDifferentDaysNeverMerge() {
        let same = print(0)
        let midnight = Date(timeIntervalSince1970: 1_800_057_600) // 2027-01-16 00:00 UTC
        func shot(_ id: String, _ time: Date) -> ThemePhoto {
            ThemePhoto(id: id, takenAt: time, location: nil, labels: [], aesthetics: nil, faces: 0,
                       isTheme: true, print: ThemePhoto.normalized(same), printRevision: 1)
        }
        let moments = MomentBuilder.build([
            shot("late", midnight.addingTimeInterval(-300)), shot("early", midnight.addingTimeInterval(300))
        ], calendar: calendar)
        XCTAssertEqual(moments.map(\.day), ["2027-01-15", "2027-01-16"])
        XCTAssertEqual(moments.map(\.id), ["late", "early"])
    }

    func testRepresentativeIsHighestAesthetics() {
        let same = print(0)
        let moments = MomentBuilder.build([
            photo("a", at: 0, vector: same, aesthetics: 0.2),
            photo("b", at: 5, vector: same, aesthetics: 0.9),
            photo("c", at: 10, vector: same, aesthetics: 0.9),
            photo("d", at: 15, vector: same)
        ], calendar: calendar)
        XCTAssertEqual(moments.count, 1)
        XCTAssertEqual(moments[0].id, "b")
        XCTAssertEqual(moments[0].photoIds, ["a", "b", "c", "d"])
    }

    func testNilAestheticsEarliestWinsAllTie() {
        let same = print(0)
        let moments = MomentBuilder.build([
            photo("b", at: 5, vector: same), photo("a", at: 0, vector: same, aesthetics: 0)
        ], calendar: calendar)
        XCTAssertEqual(moments[0].id, "a")
    }

    func testLabelsTakeMaxConfidenceAndLocationFallsBack() {
        let same = print(0)
        let place = GeoPoint(lat: 1, lon: 2)
        let moments = MomentBuilder.build([
            photo("a", at: 0, vector: same, labels: [LabelScore(id: "sky", confidence: 0.4),
                                                      LabelScore(id: "sea", confidence: 0.4)],
                  location: place),
            photo("b", at: 5, vector: same, aesthetics: 0.5,
                  labels: [LabelScore(id: "sky", confidence: 0.9), LabelScore(id: "dog", confidence: 0.1)])
        ], calendar: calendar)
        XCTAssertEqual(moments[0].id, "b")
        XCTAssertEqual(moments[0].location, place)
        XCTAssertEqual(moments[0].labels.map(\.id), ["sky", "sea", "dog"])
        XCTAssertEqual(moments[0].labels.map(\.confidence), [0.9, 0.4, 0.1])
    }

    func testCosineDistanceNormalisesAndHandlesZero() {
        XCTAssertEqual(MomentBuilder.cosineDistance([2, 0], [5, 0]), 0, accuracy: 1e-6)
        XCTAssertEqual(MomentBuilder.cosineDistance([0, 0], [1, 0]), 1)
        XCTAssertEqual(MomentBuilder.cosineDistance([1, 0], [0, 1]), 1, accuracy: 1e-6)
    }

    func testMeanCenterIsUnitLengthAndSkipsOtherLengths() {
        let center = MomentBuilder.meanCenter([[3, 0], [0, 4], [1, 2, 3]])
        XCTAssertEqual(center.count, 2)
        XCTAssertEqual(center[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(center[1], 0.8, accuracy: 1e-6)
        XCTAssertEqual(MomentBuilder.meanCenter([]), [])
    }
}
