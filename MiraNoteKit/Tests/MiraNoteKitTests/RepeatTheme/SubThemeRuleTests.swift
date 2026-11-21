import Foundation
import XCTest
@testable import MiraNoteKit

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
                        location: GeoPoint? = nil, photos: [String]? = nil) -> Moment {
        Moment(id: id, photoIds: photos ?? [id], day: "d\(dayOffset)",
               start: monday.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600),
               vector: [1, 0], labels: labels.map { LabelScore(id: $0.0, confidence: $0.1) },
               location: location)
    }

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
        func small(_ id: String, parent: String, members: [String], evidence: [String]) -> ThemeRow {
            ThemeRow(id: id, kind: .small, parentId: parent, name: id, noun: id, samePart: "", split: nil,
                     status: .active, center: nil, rule: .content(evidence: evidence), members: members,
                     lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
        }
        let soup = small("soup", parent: "rice", members: ["r0"], evidence: ["soup"])
        let sunset = small("sunset", parent: "sky", members: ["old-sky"], evidence: ["sunset"])
        let claim = ClaimResult(follows: ["rice": 0], ratios: ["rice": 1, "sky": 0.1], flagged: [],
                                frozen: ["sky"], members: ["rice": ["r0", "r1", "r2"], "sky": ["old-sky"]],
                                newPiles: [1])
        let tonight = SubThemeRule.membersTonight(
            of: [soup, sunset], claim: claim,
            moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }), photosById: [:],
            calendar: calendar)
        XCTAssertEqual(tonight["soup"], ["r0", "r2"])
        // The sky is frozen: its small theme keeps its list, though "s0" would match.
        XCTAssertEqual(tonight["sunset"], ["old-sky"])
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
