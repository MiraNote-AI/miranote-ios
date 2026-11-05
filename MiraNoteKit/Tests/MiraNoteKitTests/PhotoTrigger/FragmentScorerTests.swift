import XCTest
@testable import MiraNoteKit

/// Scoring (acceptance B4): the weights in decisions.md / handoff 7.3, the
/// recency window, the 0.40 bar and each dimension's edge.
final class FragmentScorerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let place = GeoPoint(lat: 32.82, lon: -96.72)

    private func day(_ day: Int, _ hour: Int = 14, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// `count` photos on 2026-10-`on`, `spacing` minutes apart from 14:00.
    private func fragment(on date: Int = 10, count: Int = 4, spacing: Int = 30, gps: Bool = true,
                          representative: [String: String] = [:]) -> Fragment {
        let photos = (0..<count).map {
            GroupablePhoto(id: "p\($0)", takenAt: day(date, 14, 0).addingTimeInterval(Double($0 * spacing) * 60),
                           location: gps ? place : nil, burstId: nil)
        }
        return Fragment(photos: photos, uniqueCount: count - representative.count, representative: representative,
                        belongsTo: String(format: "2026-10-%02d", date))
    }

    private func library(_ fragment: Fragment, favorite: Set<String> = [], edited: Set<String> = [])
        -> [String: LibraryAsset] {
        Dictionary(uniqueKeysWithValues: fragment.photos.map {
            ($0.id, LibraryAsset(id: $0.id, takenAt: $0.takenAt, location: $0.location,
                                 isFavorite: favorite.contains($0.id), isEdited: edited.contains($0.id),
                                 isScreenshot: false, isHidden: false, isVideo: false,
                                 originalFilename: "IMG_1.HEIC", burstId: nil))
        })
    }

    private func analyses(_ fragment: Fragment, faces: [String: Int] = [:], aesthetics: [String: Double] = [:])
        -> [String: PhotoAnalysis] {
        Dictionary(uniqueKeysWithValues: fragment.photos.map {
            ($0.id, PhotoAnalysis(id: $0.id, labels: [], broad: [], faces: faces[$0.id] ?? 0,
                                  aesthetics: aesthetics[$0.id], isUtility: false, featurePrint: nil))
        })
    }

    private func score(_ fragment: Fragment, now: Date, favorite: Set<String> = [], faces: [String: Int] = [:],
                       aesthetics: [String: Double] = [:], past: [(day: String, point: GeoPoint)] = [],
                       multiplier: Double = 1.0)
        -> FragmentScore? {
        FragmentScorer.score(fragment, analyses: analyses(fragment, faces: faces, aesthetics: aesthetics),
                             library: library(fragment, favorite: favorite), at: now, calendar: calendar,
                             pastLocations: past.enumerated().map {
                                 PastLocation(id: "past-\($0.offset)", day: $0.element.day, point: $0.element.point)
                             },
                             bucket: .other, multiplier: multiplier)
    }

    func testWeightsSumAndMatchDecision() {
        let weights = FragmentScorer.weights
        XCTAssertEqual(weights.recency, 0.25)
        XCTAssertEqual(weights.story, 0.20)
        XCTAssertEqual(weights.people, 0.15)
        XCTAssertEqual(weights.novelty, 0.15)
        XCTAssertEqual(weights.user, 0.15)
        XCTAssertEqual(weights.aesthetics, 0.10)
        XCTAssertEqual(weights.recency + weights.story + weights.people + weights.novelty + weights.user
                       + weights.aesthetics, 1, accuracy: 1e-9)
    }

    func testElevenFiftyNineHoursIsOutTwelveIsIn() {
        // The fragment ends 15:30 on the 10th (4 photos, 30 min apart from 14:00).
        let frag = fragment(on: 10)
        XCTAssertNil(score(frag, now: day(11, 3, 29)), "11 h 59 min")
        XCTAssertNotNil(score(frag, now: day(11, 3, 30)), "12 h")
    }

    func testRecencyFlatToTenDays() {
        for days in [0, 1, 10] { XCTAssertEqual(FragmentScorer.recency(days: days), 1.0) }
    }

    func testRecencyLinearToSixtyDays() throws {
        XCTAssertEqual(try XCTUnwrap(FragmentScorer.recency(days: 35)), 0.65, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(FragmentScorer.recency(days: 60)), 0.3, accuracy: 1e-9)
    }

    func testOverSixtyDaysIsOut() {
        XCTAssertNil(FragmentScorer.recency(days: 61))
        // 2026-10-01 to 2026-11-30 is 60 days; to 2026-12-01 is 61.
        let old = fragment(on: 1)
        XCTAssertNotNil(score(old, now: day(30, 21, month: 11)), "60 days still counts")
        XCTAssertNil(score(old, now: day(1, 21, month: 12)))
    }

    func testMultiplierScalesTotal() throws {
        let frag = fragment(on: 10, count: 10, spacing: 25)
        let plain = try XCTUnwrap(score(frag, now: day(15), favorite: ["p3"], faces: ["p1": 2]))
        let fewer = try XCTUnwrap(score(frag, now: day(15), favorite: ["p3"], faces: ["p1": 2], multiplier: 0.6))
        XCTAssertEqual(fewer.base, plain.base, accuracy: 1e-9)
        XCTAssertEqual(fewer.total, plain.base * 0.6, accuracy: 1e-9)
        XCTAssertEqual(fewer.multiplier, 0.6)
        // Base 0.6 x 0.6 = 0.36 is under the bar.
        XCTAssertLessThan(0.6 * 0.6, FragmentScorer.bar)
    }

    func testBarIsInclusive() throws {
        let frag = fragment(on: 10, count: 10, spacing: 25)
        let base = try XCTUnwrap(score(frag, now: day(15))).base
        let exact = try XCTUnwrap(score(frag, now: day(15), multiplier: 0.40 / base))
        XCTAssertTrue(exact.pushable, "total \(exact.total)")
        let under = try XCTUnwrap(score(frag, now: day(15), multiplier: 0.399 / base))
        XCTAssertFalse(under.pushable)
    }

    func testBelowPointFourNotPushable() throws {
        // 59 days old, three photos close together, nothing marked, a place
        // visited often: well under 0.40.
        let plain = fragment(on: 1, count: 3, spacing: 5)
        let often = (2...20).map { (day: String(format: "2026-09-%02d", $0), point: place) }
        let low = try XCTUnwrap(score(plain, now: day(30, 12, month: 11), past: often))
        XCTAssertLessThan(low.total, 0.40)
        XCTAssertFalse(low.pushable)

        // Five days old, a long varied afternoon with faces and a favourite.
        let rich = fragment(on: 10, count: 10, spacing: 25)
        let high = try XCTUnwrap(score(rich, now: day(15), favorite: ["p3"], faces: ["p1": 2, "p2": 1]))
        XCTAssertTrue(high.pushable)
        XCTAssertEqual(high.base, 0.25 * high.r + 0.20 * high.s + 0.15 * high.p + 0.15 * high.n
                       + 0.15 * high.u + 0.10 * high.a, accuracy: 1e-9)
    }

    func testFirstVisitPlaceScoresOne() throws {
        let fragment = fragment()
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15))).n, 1.0)
        // The fragment's own day is not a past visit.
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15), past: [("2026-10-10", place)])).n, 1.0)
        let twice = [("2026-09-01", place), ("2026-09-02", place), ("2026-09-02", place)]
            .map { (day: $0.0, point: $0.1) }
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15), past: twice)).n, 0.7)
        let farAway = [(day: "2026-09-01", point: GeoPoint(lat: 33.5, lon: -96.72))]
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15), past: farAway)).n, 1.0)
        let tenDays = (1...10).map { (day: String(format: "2026-09-%02d", $0), point: place) }
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15), past: tenDays)).n, 0.4)
        let many = (1...11).map { (day: String(format: "2026-09-%02d", $0), point: place) }
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15), past: many)).n, 0.1)
    }

    /// A fragment that runs past 04:00 has photos on the next belongs-to
    /// day: they are its own, not a visit on another day.
    func testOwnPhotosAfterFourAreNotAnotherVisit() throws {
        let photos = (0..<8).map {
            GroupablePhoto(id: "n\($0)", takenAt: day(20, 2).addingTimeInterval(Double($0) * 30 * 60),
                           location: place, burstId: nil)
        }
        let fragment = try XCTUnwrap(
            FragmentGrouper.group(photos, threshold: 7200, calendar: calendar) { _, _ in nil }.fragments.first)
        XCTAssertEqual(fragment.belongsTo, "2026-10-19")
        let own = photos.map {
            PastLocation(id: $0.id, day: FragmentGrouper.belongsTo($0.takenAt, calendar: calendar), point: place)
        }
        XCTAssertEqual(Set(own.map(\.day)), ["2026-10-19", "2026-10-20"])
        XCTAssertEqual(FragmentScorer.novelty(fragment, pastLocations: own), 1.0)
        let another = own + [PastLocation(id: "other", day: "2026-10-20", point: place)]
        XCTAssertEqual(FragmentScorer.novelty(fragment, pastLocations: another), 0.7,
                       "another photo there on the next day is a visit")
    }

    func testNoGpsPlaceIsPointFour() throws {
        XCTAssertEqual(try XCTUnwrap(score(fragment(gps: false), now: day(15))).n, 0.4)
    }

    func testAestheticsMissingIsHalf() throws {
        let fragment = fragment()
        XCTAssertEqual(try XCTUnwrap(score(fragment, now: day(15))).a, 0.5)
        // Best three of (0.8, 0.6, 0.2, -1) -> mean of 0.9, 0.8, 0.6.
        let scored = try XCTUnwrap(score(fragment, now: day(15),
                                         aesthetics: ["p0": 0.8, "p1": 0.6, "p2": 0.2, "p3": -1]))
        XCTAssertEqual(scored.a, (0.9 + 0.8 + 0.6) / 3, accuracy: 1e-9)
    }

    func testStoryPeopleAndUserMarks() throws {
        // 4 photos 30 min apart: 4 moments, 1.5 h, 4 photos.
        let scored = try XCTUnwrap(score(fragment(), now: day(15), favorite: ["p0"], faces: ["p1": 3]))
        XCTAssertEqual(scored.s, 0.4 * 1 + 0.3 * 0.5 + 0.3 * 0.4, accuracy: 1e-9)
        XCTAssertEqual(scored.p, 0.6 * min(1, 2 * 0.25) + 0.4, accuracy: 1e-9)
        XCTAssertEqual(scored.u, 0.6, accuracy: 1e-9)
        // A near-duplicate cluster of three adds 0.3.
        let repeats = fragment(count: 5, spacing: 1, representative: ["p1": "p0", "p2": "p0"])
        XCTAssertEqual(try XCTUnwrap(score(repeats, now: day(15))).u, 0.3, accuracy: 1e-9)
    }

    func testUnderThreeUniqueIsNotScored() {
        XCTAssertNil(score(fragment(count: 4, spacing: 1, representative: ["p1": "p0", "p2": "p0"]), now: day(15)))
    }
}
