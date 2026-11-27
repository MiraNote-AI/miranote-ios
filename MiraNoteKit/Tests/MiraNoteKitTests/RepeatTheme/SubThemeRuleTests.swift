import Foundation
import XCTest
@testable import MiraNoteKit

// swiftlint:disable:next type_body_length
final class SubThemeRuleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2027-01-04, a Monday, 00:00 UTC.
    private var monday: Date { Date(timeIntervalSince1970: 1_799_020_800) }

    private let home = GeoPoint(lat: 31.2, lon: 121.5)

    /// A one-photo moment (moment id = photo id) unless `photos` names more.
    private func moment(_ id: String, dayOffset: Int = 0, hour: Int = 18, labels: [(String, Float)] = [],
                        location: GeoPoint? = nil, photos: [String]? = nil, vector: [Float] = [1, 0]) -> Moment {
        Moment(id: id, photoIds: photos ?? [id], day: "d\(dayOffset)",
               start: monday.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600),
               vector: vector, labels: labels.map { LabelScore(id: $0.0, confidence: $0.1) },
               location: location)
    }

    private func small(_ id: String, parent: String = "big", members: [String] = [], rule: SubRule,
                       center: [Float]? = nil, status: ThemeStatus = .active) -> ThemeRow {
        ThemeRow(id: id, kind: .small, parentId: parent, name: id, noun: id, samePart: "", split: nil,
                 status: status, center: center, rule: rule, members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
    }

    private func big(_ id: String = "big", center: [Float]?, members: [String] = []) -> ThemeRow {
        ThemeRow(id: id, kind: .big, parentId: nil, name: id, noun: id, samePart: "", split: "A",
                 status: .active, center: center, rule: nil, members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
    }

    private func lists(_ children: [ThemeRow], parent: ThemeRow, _ moments: [Moment],
                       photosById: [String: ThemePhoto] = [:], extra: [String] = []) -> [String: [String]] {
        SubThemeRule.lists(children: children, parent: parent, in: moments.flatMap(\.photoIds) + extra,
                           moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }),
                           photosById: photosById, calendar: calendar)
    }

    private let diagonal: [Float] = [Float(0.5).squareRoot(), Float(0.5).squareRoot()]

    private func members(_ rule: SubRule, _ moments: [Moment]) -> [String] {
        SubThemeRule.members(rule, in: moments.flatMap(\.photoIds),
                             moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }),
                             photosById: [:], calendar: calendar)
    }

    // MARK: - Content (C6)

    func testContentRuleNeedsConfidencePointThree() {
        let moments = [
            moment("soup30", labels: [("soup", 0.3)]),
            moment("soup29", labels: [("soup", 0.29)]),
            moment("noodle", labels: [("noodle", 0.9)]),
            moment("dumpling", labels: [("noodle", 0.9), ("dumpling", 0.5)]),
            moment("burst", labels: [("soup", 0.8)], photos: ["burst", "burst-2"])
        ]
        XCTAssertEqual(members(.content(evidence: ["soup", "dumpling"]), moments),
                       ["soup30", "dumpling", "burst", "burst-2"])
    }

    func testPhotoOutsideEveryMomentUsesItsOwnRecord() {
        let photo = ThemePhoto(id: "loose", takenAt: monday, location: nil,
                               labels: [LabelScore(id: "soup", confidence: 0.6)], aesthetics: nil,
                               faces: 0, isTheme: true, print: Data(), printRevision: 1)
        let result = SubThemeRule.members(.content(evidence: ["soup"]), in: ["loose", "gone"], moments: [:],
                                          photosById: ["loose": photo], calendar: calendar)
        XCTAssertEqual(result, ["loose"])
    }

    // MARK: - Occasion (C6)

    func testOccasionRule300m() {
        // 0.0022 degrees of latitude is about 245 m, 0.0032 about 356 m.
        let near = GeoPoint(lat: home.lat + 0.0022, lon: home.lon)
        let far = GeoPoint(lat: home.lat + 0.0032, lon: home.lon)
        let moments = [
            moment("home", location: home),
            moment("near", location: near),
            moment("far", location: far),
            moment("saturday", dayOffset: 5, location: home),
            moment("late", hour: 20, location: home),
            moment("nowhere")
        ]
        let rule = SubRule.occasion(keys: [OccasionKey(place: home, daypart: "evening", weekpart: "weekday")])
        XCTAssertEqual(members(rule, moments), ["home", "near"])
    }

    func testOccasionRuleWithoutPlaces() {
        let moments = [
            moment("lunch", hour: 12),
            moment("lunch-placed", hour: 12, location: home),
            moment("dinner", hour: 18),
            moment("sunday-lunch", dayOffset: 6, hour: 12),
            moment("evening-home", dayOffset: 1, hour: 18, location: home)
        ]
        let rule = SubRule.occasion(keys: [
            OccasionKey(place: nil, daypart: "noon", weekpart: "weekday"),
            OccasionKey(place: home, daypart: "evening", weekpart: "weekday")
        ])
        XCTAssertEqual(members(rule, moments), ["lunch", "evening-home"])
    }

    // MARK: - Frozen big themes (6.7)

    func testFrozenBigFreezesSmall() {
        let moments = [
            moment("r0", labels: [("soup", 0.9)]),
            moment("r1", labels: [("noodle", 0.9)]),
            moment("r2", labels: [("soup", 0.7)]),
            moment("s0", labels: [("sunset", 0.9)])
        ]
        let soup = small("soup", parent: "rice", members: ["r0"], rule: .content(evidence: ["soup"]))
        let sunset = small("sunset", parent: "sky", members: ["old-sky"], rule: .content(evidence: ["sunset"]))
        let claim = ClaimResult(follows: ["rice": 0], ratios: ["rice": 1, "sky": 0.1], flagged: [],
                                frozen: ["sky"], members: ["rice": ["r0", "r1", "r2"], "sky": ["old-sky"]],
                                newPiles: [1])
        let tonight = SubThemeRule.membersTonight(
            of: [big("rice", center: nil), soup, big("sky", center: nil), sunset], claim: claim,
            moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }), photosById: [:],
            calendar: calendar)
        XCTAssertEqual(tonight["soup"], ["r0", "r2"])
        // The sky is frozen: its small theme keeps its list, though "s0" would match.
        XCTAssertEqual(tonight["sunset"], ["old-sky"])
    }

    func testMissingParentRowKeepsTheOldList() {
        let moments = [moment("r0", labels: [("soup", 0.9)])]
        let soup = small("soup", parent: "rice", members: ["old"], rule: .content(evidence: ["soup"]))
        let claim = ClaimResult(follows: ["rice": 0], ratios: ["rice": 1], flagged: [], frozen: [],
                                members: ["rice": ["r0"]], newPiles: [])
        let tonight = SubThemeRule.membersTonight(
            of: [soup], claim: claim, moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }),
            photosById: [:], calendar: calendar)
        XCTAssertEqual(tonight["soup"], ["old"])
    }

    // MARK: - Content children by look (decision 2)

    func testContentChildrenSplitByLook() {
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [1, 0])
        let dog = small("dog", rule: .content(evidence: ["dog"]), center: [0, 1])
        let moments = [
            moment("c1", labels: [("cat", 0.9)], vector: [1, 0.1]),
            moment("c2", labels: [("cat", 0.3), ("dog", 0.9)], photos: ["c2", "c2-b"], vector: [0.9, 0.2]),
            moment("d1", labels: [("dog", 0.8)], vector: [0.1, 1]),
            moment("d2", labels: [("dog", 0.5), ("cat", 0.9)], vector: [0.2, 0.9]),
            moment("nocat", labels: [("dog", 0.9), ("cat", 0.29)], vector: [1, 0.1])
        ]
        let result = lists([cat, dog], parent: big(center: diagonal), moments)
        XCTAssertEqual(result["cat"], ["c1", "c2", "c2-b"])
        XCTAssertEqual(result["dog"], ["d1", "d2"])
    }

    func testPhotoNearerBigCenterJoinsNoChild() {
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [1, 0])
        let dog = small("dog", rule: .content(evidence: ["dog"]), center: [0, 1])
        let moments = [
            moment("middle", labels: [("cat", 0.9), ("dog", 0.9)], vector: [1, 0.8]),
            moment("c1", labels: [("cat", 0.9)], vector: [1, 0.1])
        ]
        let result = lists([cat, dog], parent: big(center: diagonal), moments)
        XCTAssertEqual(result["cat"], ["c1"])
        XCTAssertEqual(result["dog"], [])
        // A big theme without a look does not hold photos back.
        for parent in [big(center: nil), big(center: [])] {
            let loose = lists([cat, dog], parent: parent, moments)
            XCTAssertEqual(loose["cat"], ["middle", "c1"])
            XCTAssertEqual(loose["dog"], [])
        }
    }

    func testPhotoJoinsAtMostOneContentChild() {
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [1, 0])
        let kitten = small("kitten", rule: .content(evidence: ["kitten"]), center: [0.9, 0.3])
        let moments = [
            moment("c1", labels: [("cat", 0.9), ("kitten", 0.9)], vector: [1, 0]),
            moment("k1", labels: [("cat", 0.9), ("kitten", 0.9)], vector: [0.9, 0.35]),
            // Nearest is kitten, which it has no label of: it joins neither, not the next nearest.
            moment("k2", labels: [("cat", 0.9)], vector: [0.9, 0.35])
        ]
        let result = lists([cat, kitten], parent: big(center: [0, 1]), moments)
        XCTAssertEqual(result["cat"], ["c1"])
        XCTAssertEqual(result["kitten"], ["k1"])
        // The same center twice: the first child in order wins.
        let twin = small("twin", rule: .content(evidence: ["cat"]), center: [1, 0])
        let tied = lists([twin, cat], parent: big(center: [0, 1]), [moments[0]])
        XCTAssertEqual(tied["twin"], ["c1"])
        XCTAssertEqual(tied["cat"], [])
    }

    func testMomentWithoutVectorJoinsNoSmallTheme() {
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [1, 0])
        let moments = [
            moment("blank", labels: [("cat", 0.9)], vector: []),
            moment("short", labels: [("cat", 0.9)], vector: [1]),
            moment("c1", labels: [("cat", 0.9)], vector: [1, 0])
        ]
        let loose = ThemePhoto(id: "loose", takenAt: monday, location: nil,
                               labels: [LabelScore(id: "cat", confidence: 0.9)], aesthetics: nil,
                               faces: 0, isTheme: true, print: Data(), printRevision: 1)
        let result = lists([cat], parent: big(center: nil), moments, photosById: ["loose": loose],
                           extra: ["loose"])
        XCTAssertEqual(result["cat"], ["c1"])
    }

    func testOldSmallRowWithoutCenterKeepsLabelRule() {
        let oldCat = small("old-cat", rule: .content(evidence: ["cat"]))
        let emptyCenter = small("empty", rule: .content(evidence: ["cat"]), center: [])
        let dog = small("dog", rule: .content(evidence: ["dog"]), center: [0, 1])
        let moments = [
            moment("c1", labels: [("cat", 0.9)], vector: [1, 0]),
            moment("both", labels: [("cat", 0.9), ("dog", 0.9)], vector: [0, 1]),
            moment("d1", labels: [("dog", 0.9)], vector: [0, 1])
        ]
        let result = lists([oldCat, emptyCenter, dog], parent: big(center: diagonal), moments)
        XCTAssertEqual(result["old-cat"], ["c1", "both"])
        XCTAssertEqual(result["empty"], ["c1", "both"])
        XCTAssertEqual(result["dog"], ["both", "d1"])
    }

    func testOccasionChildrenUnchanged() {
        let moments = [
            moment("home", location: home),
            moment("saturday", dayOffset: 5, location: home, vector: [1, 0]),
            moment("cat", labels: [("cat", 0.9)], location: home, vector: [1, 0])
        ]
        let rule = SubRule.occasion(keys: [OccasionKey(place: home, daypart: "evening", weekpart: "weekday")])
        let evening = small("evening", rule: rule)
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [1, 0])
        let result = lists([evening, cat], parent: big(center: [0, 1]), moments)
        XCTAssertEqual(result["evening"], members(rule, moments))
        XCTAssertEqual(result["evening"], ["home", "cat"])
        XCTAssertEqual(result["cat"], ["cat"])
    }

    func testRetiredOrRulelessChildKeepsItsListAndTakesNoPhoto() {
        let retired = small("retired", members: ["old"], rule: .content(evidence: ["cat"]), center: [1, 0],
                            status: .retired)
        let ruleless = ThemeRow(id: "ruleless", kind: .small, parentId: "big", name: "r", noun: "r", samePart: "",
                                split: nil, status: .active, center: [1, 0], rule: nil, members: ["kept"],
                                lastAskedCount: 1, flagged: false, followRatio: nil, where: nil)
        let cat = small("cat", rule: .content(evidence: ["cat"]), center: [0.9, 0.1])
        let moments = [moment("c1", labels: [("cat", 0.9)], vector: [1, 0])]
        let result = lists([retired, ruleless, cat], parent: big(center: [0, 1]), moments)
        XCTAssertEqual(result["retired"], ["old"])
        XCTAssertEqual(result["ruleless"], ["kept"])
        XCTAssertEqual(result["cat"], ["c1"])
    }

    func testMembersTonightSplitsContentChildrenByLook() {
        let cat = small("cat", members: ["stale"], rule: .content(evidence: ["cat"]), center: [1, 0])
        let dog = small("dog", rule: .content(evidence: ["dog"]), center: [0, 1])
        let moments = [
            moment("c1", labels: [("cat", 0.9), ("dog", 0.9)], vector: [1, 0.1]),
            moment("d1", labels: [("cat", 0.9), ("dog", 0.9)], vector: [0.1, 1])
        ]
        let claim = ClaimResult(follows: ["big": 0], ratios: ["big": 1], flagged: [], frozen: [],
                                members: ["big": ["c1", "d1"]], newPiles: [])
        let tonight = SubThemeRule.membersTonight(
            of: [big(center: diagonal), cat, dog], claim: claim,
            moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }), photosById: [:],
            calendar: calendar)
        XCTAssertEqual(tonight, ["cat": ["c1"], "dog": ["d1"]])
    }

    // MARK: - Rows on disk

    func testThemeRowRoundTrips() throws {
        let row = ThemeRow(id: "x", kind: .small, parentId: "p", name: "n", noun: "n", samePart: "s",
                           split: nil, status: .frozen, center: nil,
                           rule: .occasion(keys: [OccasionKey(place: home, daypart: "night", weekpart: "weekend")]),
                           members: ["a"], lastAskedCount: 1, flagged: true, followRatio: 0.3, where: nil)
        let data = try JSONEncoder().encode(row)
        XCTAssertEqual(try JSONDecoder().decode(ThemeRow.self, from: data), row)
    }

    func testSubRuleJSONShapeIsPinned() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let content = SubRule.content(evidence: ["soup", "dumpling"])
        let occasion = SubRule.occasion(keys: [
            OccasionKey(place: GeoPoint(lat: 1.5, lon: 2.5), daypart: "evening", weekpart: "weekday"),
            OccasionKey(place: nil, daypart: "noon", weekpart: "weekend")
        ])
        XCTAssertEqual(String(bytes: try encoder.encode(content), encoding: .utf8),
                       #"{"content":{"evidence":["soup","dumpling"]}}"#)
        XCTAssertEqual(String(bytes: try encoder.encode(occasion), encoding: .utf8),
                       #"{"occasion":{"keys":[{"daypart":"evening","place":{"lat":1.5,"lon":2.5},"#
                           + #""weekpart":"weekday"},{"daypart":"noon","weekpart":"weekend"}]}}"#)
        for rule in [content, occasion] {
            XCTAssertEqual(try JSONDecoder().decode(SubRule.self, from: try encoder.encode(rule)), rule)
        }
    }
}
